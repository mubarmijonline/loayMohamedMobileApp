import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error/failures.dart';
import '../../core/logging/app_logger.dart';
import '../../core/providers.dart';
import '../../core/security/playback_gate.dart';
import '../../core/storage/kv_cache.dart';
import '../_shared/models.dart';
import '../auth/presentation/auth_controller.dart';
import '../providers.dart';
import '../student_repository.dart';
import 'secure_native_player.dart';
import 'secure_web_player.dart';

/// Plays remote video via the secure embed URL.
/// - Uses the embed's own player UI (best UX with cross-origin iframes).
/// - Minimal Flutter chrome: back, fullscreen, watermark.
/// - Auto-rotates to landscape, restores on exit.
/// - Screenshot/recording protection via SecureApplication (Android FLAG_SECURE)
///   plus a user watermark to deter sharing on iOS where blocking isn't possible.
class ContentPlayerScreen extends ConsumerStatefulWidget {
  const ContentPlayerScreen({
    super.key,
    required this.contentId,
    required this.subjectId,
    this.lessonId,
    this.title,
  });

  final String contentId;
  final String subjectId;
  final String? lessonId;
  final String? title;

  @override
  ConsumerState<ContentPlayerScreen> createState() =>
      _ContentPlayerScreenState();
}

class _ContentPlayerScreenState extends ConsumerState<ContentPlayerScreen>
    with WidgetsBindingObserver {
  bool _fullscreen = false;
  Timer? _showChromeTimer;
  bool _chromeVisible = true;

  // ── Resume / heartbeat state ─────────────────────────────────────────────
  int _positionSeconds = 0;
  int _durationSeconds = 0;
  Timer? _heartbeatTimer;
  // Watched-time tracking: backend wants `delta = seconds watched since last
  // heartbeat` (clamped 0–60), not a position delta.
  bool _playing = false;
  DateTime _lastTick = DateTime.now();
  // Playhead position at the previous heartbeat. We derive watched `delta`
  // from how far the playhead actually advanced — this is robust even when
  // the embed's play/pause events never reach us (the `timeupdate` events
  // still do), so the backend keeps advancing the resume point.
  int _lastHeartbeatPosition = 0;

  // Cached repository so dispose-time flushes don't touch `ref` after the
  // widget has been unmounted (Riverpod throws if you do).
  StudentRepository? _repo;

  // Local resume cache. The backend resume point isn't always reliable, so we
  // also persist the last position on-device keyed by user + content. This
  // guarantees resume works on the same device for the same user, while
  // staying per-user isolated (User B never inherits User A's position).
  KvCache? _kv;
  String? _resumeKey;

  /// `Bearer <access_token>`, for the Drive proxy only.
  ///
  /// Loaded once into state because the player is built synchronously and the
  /// token store is async. Never passed to a WebView — the proxy is on our own
  /// origin, a third-party iframe is not.
  String? _authHeader;

  String? _buildResumeKey() {
    final uid = ref.read(authControllerProvider).user?.id ?? 'anon';
    return 'resume.$uid.${widget.contentId}';
  }

  void _saveLocalResume(int seconds) {
    final kv = _kv;
    final key = _resumeKey;
    if (kv == null || key == null || seconds <= 0) return;
    // Don't persist a position essentially at the start.
    if (seconds <= 3) return;
    kv.setInt(key, seconds);
  }

  int _readLocalResume() {
    final kv = _kv;
    final key = _resumeKey;
    if (kv == null || key == null) return 0;
    return kv.getInt(key) ?? 0;
  }

  @override
  void initState() {
    super.initState();
    // Cache the repository immediately so dispose() can still flush the
    // final position even after the ConsumerElement has been torn down.
    _repo = ref.read(studentRepositoryProvider);
    _kv = ref.read(kvCacheProvider);
    _resumeKey = _buildResumeKey();
    WidgetsBinding.instance.addObserver(this);
    _loadAuthHeader();
    WidgetsBinding.instance.addPostFrameCallback((_) => _enableProtection());
    _scheduleChromeHide();
    // Mark as seen the moment the player opens — we don't track minutes.
    WidgetsBinding.instance.addPostFrameCallback((_) => _markSeen());
    // Periodic upload of current position to backend (every 15s, per spec).
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _sendHeartbeat(),
    );
  }

  Future<void> _loadAuthHeader() async {
    final tokens = await ref.read(tokenStoreProvider).read();
    if (!mounted || tokens == null) return;
    setState(() => _authHeader = 'Bearer ${tokens.accessToken}');
  }

  Future<void> _markSeen() async {
    final StudentRepository repo = _repo ?? ref.read(studentRepositoryProvider);
    _repo ??= repo;
    try {
      // A 1-second heartbeat is enough for the backend to flag this content
      // as watched. We don't actually care about minute totals.
      await repo.sendHeartbeat(
        contentId: widget.contentId,
        deltaSeconds: 1,
        currentPositionSeconds: 1,
        tabVisible: true,
      );
      // Refresh providers so the "Videos seen" counters update everywhere.
      if (mounted) {
        ref.invalidate(contentsProvider);
        ref.invalidate(contentProvider(widget.contentId));
        ref.invalidate(dashboardProvider);
        ref.invalidate(subjectWorkloadProvider);
      }
    } catch (_) {
      // Best-effort — next heartbeat tick will retry.
    }
  }

  @override
  void dispose() {
    // Persist the last position locally + flush to backend so the next
    // session (even after a full app restart) can resume.
    _saveLocalResume(_positionSeconds);
    _sendHeartbeat(force: true);
    _heartbeatTimer?.cancel();
    // The WebView is owned by SecureWebPlayer, which tears the page down in
    // its own dispose() — no audio survives the route pop.
    WidgetsBinding.instance.removeObserver(this);
    _showChromeTimer?.cancel();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveLocalResume(_positionSeconds);
      _sendHeartbeat(force: true);
    }
  }

  Future<void> _sendHeartbeat({bool force = false}) async {
    // Backend semantics: `delta` = seconds **watched** since the last
    // heartbeat (clamped 0–60). We derive it from how far the playhead
    // actually advanced rather than relying on the embed's play/pause
    // events (which don't always reach us). The `timeupdate` position events
    // do arrive, so position-advance is the reliable signal that the user is
    // genuinely watching — and it keeps the backend's resume point moving.
    final now = DateTime.now();
    final wall = now.difference(_lastTick).inSeconds.clamp(0, 60);
    _lastTick = now;
    final advanced = _positionSeconds - _lastHeartbeatPosition;
    int delta;
    if (advanced > 0) {
      // Normal forward playback (or a forward seek). Count the seconds the
      // playhead moved, capped at 60 so a big jump can't inflate watch time.
      delta = advanced.clamp(0, 60);
    } else if ((_playing || force) && advanced == 0 && _positionSeconds > 0) {
      // Playhead didn't report movement but we believe we're playing — fall
      // back to wall-clock so a stalled `timeupdate` doesn't zero out watch
      // time.
      delta = wall;
    } else {
      // Paused, seeked backward, or not started: no watched time.
      delta = 0;
    }
    _lastHeartbeatPosition = _positionSeconds;
    if (!force && delta == 0 && _positionSeconds <= 0) return;
    // Use cached repo if available (e.g. during dispose) — `ref.read` throws
    // once the ConsumerStatefulElement has been disposed.
    final repo = _repo;
    if (repo == null) return;
    try {
      await repo.sendHeartbeat(
        contentId: widget.contentId,
        deltaSeconds: delta,
        currentPositionSeconds: _positionSeconds,
        tabVisible: !force,
      );
    } catch (_) {
      // Silent — next tick will retry.
    }
  }

  /// Arms capture protection for this screen.
  ///
  /// Android's FLAG_SECURE is already applied app-wide in MainActivity.onCreate
  /// and is not toggled here — a per-screen toggle leaves a window where the
  /// flag is off, and that window is exactly when someone screenshots. This
  /// starts the observers and confirms protection is genuinely live; the
  /// player will not render if it is not (see playbackPermissionProvider).
  void _enableProtection() {
    ref.read(screenGuardProvider).enable();
  }

  void _scheduleChromeHide() {
    _showChromeTimer?.cancel();
    // Give the user enough time to find the exit button.
    _showChromeTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _chromeVisible = false);
    });
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
    if (_chromeVisible) _scheduleChromeHide();
  }

  Future<void> _enterFullscreen() async {
    setState(() => _fullscreen = true);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setState(() => _chromeVisible = true);
    _scheduleChromeHide();
  }

  Future<void> _exitFullscreen() async {
    await _sendHeartbeat(force: true);
    setState(() => _fullscreen = false);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    setState(() => _chromeVisible = true);
    _scheduleChromeHide();
  }

  /// Re-mints the embed and rebuilds the player.
  ///
  /// The WebView itself is owned by [SecureWebPlayer]; invalidating the embed
  /// provider gives it a fresh URL and a new widget key, which is what
  /// actually reloads the page. There is deliberately no second WebView
  /// construction path in this file — one locked-down configuration, one
  /// navigation allowlist, no way to accidentally render an unhardened player.
  Future<void> _reload() async {
    ref.invalidate(contentEmbedProvider(widget.contentId));
  }

  static String _fmt(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final embed = ref.watch(contentEmbedProvider(widget.contentId));
    final orientation = MediaQuery.of(context).orientation;
    // Sync internal _fullscreen flag with real orientation.
    final isLandscape = orientation == Orientation.landscape;
    if (isLandscape != _fullscreen) {
      // Don't call setState during build — schedule a microtask.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_fullscreen != isLandscape) {
          setState(() => _fullscreen = isLandscape);
        }
      });
    }

    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _fullscreen) _exitFullscreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          top: !_fullscreen,
          // Respect the bottom inset in portrait so the embedded player's
          // timeline / play / fullscreen controls don't sit under the home
          // indicator. In fullscreen we want true full-bleed video.
          bottom: !_fullscreen,
          child: embed.when(
            loading: () => const _Loading(),
            error: (e, _) => _ErrorView(
              message: e is AppFailure ? e.message : e.toString(),
              onRetry: () =>
                  ref.invalidate(contentEmbedProvider(widget.contentId)),
            ),
            data: (data) {
              if (!data.hasVideo) {
                return const _ErrorView(
                  message: 'Video unavailable for this lesson.',
                );
              }

              // Runtime protection gate. Video is not rendered at all unless
              // the platform confirms capture protection is genuinely active
              // and the device is not rooted/jailbroken. Showing video under
              // a protection that silently failed is the failure mode this
              // whole subsystem exists to prevent.
              final permission = ref.watch(playbackPermissionProvider);
              return permission.when(
                loading: () => const _Loading(),
                error: (e, _) => const _ErrorView(
                  message: 'Could not verify screen protection on this device.',
                ),
                data: (perm) {
                  if (!perm.isAllowed) {
                    return _BlockedView(permission: perm);
                  }

                  // Prefer whichever resume source has progressed further. The
                  // local value covers cases where the backend has not
                  // persisted the position yet.
                  final resume = ref
                      .watch(contentResumeProvider(widget.contentId))
                      .valueOrNull;
                  final resumeFrom = math.max(
                    resume?.resumeFromSeconds ?? 0,
                    _readLocalResume(),
                  );

                  // Tag any capture event with the lesson being watched, so a
                  // queued screenshot is attributable to content rather than
                  // just a timestamp.
                  ref.read(screenGuardProvider).bindContent(widget.contentId);

                  return _stage(
                    embed: data,
                    watermark: _watermarkFor(data),
                    resumeFrom: resumeFrom,
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  /// The identity string drawn over every frame.
  ///
  /// The backend only returns `watermark` for Bunny (API_BRIEF §6), so for
  /// Drive and Cloudflare the client builds the same `full name · phone ·
  /// user id` string itself from the signed-in user. Falling back to a brand
  /// string would defeat the point — an unattributable watermark deters
  /// nobody.
  String _watermarkFor(ContentEmbed embed) {
    final serverSide = embed.watermark;
    if (serverSide != null && serverSide.trim().isNotEmpty) return serverSide;
    final u = ref.read(authControllerProvider).user;
    if (u == null) return '';
    return SecureWebPlayer.buildWatermark(
      fullName: u.name,
      phone: u.phone,
      userId: u.id,
    );
  }

  /// Position/playback callbacks shared by both player implementations.
  void _onPlayingChanged(bool playing) {
    _playing = playing;
    if (playing) {
      _lastTick = DateTime.now();
    } else {
      _sendHeartbeat(force: true);
    }
  }

  void _onPositionChanged(int pos, int? dur) {
    if (pos > 0) {
      _positionSeconds = pos;
      _saveLocalResume(pos);
    }
    if (dur != null && dur > 0) _durationSeconds = dur;
  }

  Widget _buildPlayer({
    required ContentEmbed embed,
    required String watermark,
    required int resumeFrom,
  }) {
    final guard = ref.read(screenGuardProvider);

    // Diagnostic only. Never logs the URL itself — that is a video credential
    // — but records which branch was taken and whether the backend supplied a
    // stream_url, which is the difference between the native proxy player and
    // the legacy iframe.
    AppLogger.I.i(
      'Player: provider=${embed.provider.name} '
      'hasStreamUrl=${embed.streamUrl != null} '
      'path=${embed.needsWebView ? "webview" : "native"} '
      'auth=${_authHeader != null} '
      'watermark=${watermark.isNotEmpty}',
    );

    if (!embed.needsWebView) {
      // The proxy 401s without the bearer token, and the token store is async.
      // Hold the loader rather than starting a request that is certain to
      // fail and then showing the user a spurious error.
      if (_authHeader == null) {
        return const ColoredBox(
          color: Colors.black,
          child: Center(
            child: CircularProgressIndicator(color: Colors.white70),
          ),
        );
      }
      return SecureNativePlayer(
        key: ValueKey(embed.playbackUrl),
        embed: embed,
        watermark: watermark,
        // The proxy is on our own origin and requires the bearer token. A
        // third-party iframe must never receive this, which is why it is
        // passed only on this branch.
        authHeader: _authHeader,
        screenGuard: guard,
        startAtSeconds: resumeFrom,
        onPlayingChanged: _onPlayingChanged,
        onPositionChanged: _onPositionChanged,
        onEnded: () {
          _playing = false;
          _sendHeartbeat(force: true);
        },
      );
    }

    return SecureWebPlayer(
      // Rebuild from scratch when a signed URL is re-minted.
      key: ValueKey(embed.playbackUrl),
      embed: embed,
      watermark: watermark,
      screenGuard: guard,
      startAtSeconds: resumeFrom,
      onPlayingChanged: _onPlayingChanged,
      onPositionChanged: _onPositionChanged,
      onEnded: () {
        _playing = false;
        _sendHeartbeat(force: true);
      },
      // A Bunny embed is signed and expires; re-fetch rather than let the
      // iframe start refusing mid-lesson.
      onExpired: () => ref.invalidate(contentEmbedProvider(widget.contentId)),
    );
  }

  Widget _stage({
    required ContentEmbed embed,
    required String watermark,
    required int resumeFrom,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleChrome,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The player, chosen by provider.
          //
          // Drive now streams through our own origin, so it plays natively —
          // no WebView, and therefore no Google chrome to lock down. Bunny and
          // Cloudflare are still iframes and get the full navigation
          // allowlist, injected hardening and control-strip overlay.
          _buildPlayer(
              embed: embed, watermark: watermark, resumeFrom: resumeFrom),

          // Persistent close/back button (never auto-hides) so the user can
          // always exit the player even when the chrome has faded out.
          Positioned(
            top: 12,
            left: 12,
            child: SafeArea(
              child: _RoundIcon(
                icon: _fullscreen
                    ? Icons.close_rounded
                    : Icons.arrow_back_ios_new_rounded,
                onTap: () async {
                  if (_fullscreen) {
                    await _exitFullscreen();
                  } else {
                    await _sendHeartbeat(force: true);
                    if (mounted) {
                      Navigator.of(context).maybePop();
                    }
                  }
                },
              ),
            ),
          ),

          // Top + bottom chrome (auto-hides).
          AnimatedOpacity(
            opacity: _chromeVisible ? 1 : 0,
            duration: const Duration(milliseconds: 220),
            child: IgnorePointer(
              ignoring: !_chromeVisible,
              child: Stack(
                children: [
                  // Top bar
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                      child: Row(
                        children: [
                          // Spacer matching the persistent close button so the
                          // title doesn't collide with it.
                          const SizedBox(width: 44),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.title ?? 'Lesson',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (_positionSeconds > 0) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _durationSeconds > 0
                                    ? '${_fmt(_positionSeconds)} / ${_fmt(_durationSeconds)}'
                                    : _fmt(_positionSeconds),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          _RoundIcon(
                            icon: Icons.refresh_rounded,
                            onTap: _reload,
                          ),
                          const SizedBox(width: 6),
                          _RoundIcon(
                            icon: _fullscreen
                                ? Icons.fullscreen_exit_rounded
                                : Icons.fullscreen_rounded,
                            onTap: _fullscreen
                                ? _exitFullscreen
                                : _enterFullscreen,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 38,
            height: 38,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2.4,
            ),
          ),
          SizedBox(height: 14),
          Text(
            'Loading video…',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.videocam_off_rounded,
            color: Colors.white54,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

/// Subtle, repeating user watermark. Helps trace shared screenshots/recordings.

/// Shown instead of the player when this device may not play video.
///
/// Deliberately explains the reason and what still works, rather than showing
/// a generic error — a student on a rooted phone is not doing anything wrong
/// and should not be left guessing why one screen is broken.
class _BlockedView extends StatelessWidget {
  const _BlockedView({required this.permission});

  final PlaybackPermission permission;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.gpp_maybe_outlined,
                color: Colors.white70,
                size: 44,
              ),
              const SizedBox(height: 16),
              Text(
                permission.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                permission.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 22),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
