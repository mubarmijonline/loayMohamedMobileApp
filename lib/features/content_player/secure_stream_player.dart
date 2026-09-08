import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_application/secure_application.dart';
import 'package:video_player/video_player.dart';

import '../../core/error/failures.dart';
import '../../core/security/playback_security.dart';
import '../_shared/models.dart';
import '../auth/presentation/auth_controller.dart';
import '../providers.dart';
import '../student_repository.dart';

/// Full-screen player for Cloudflare Stream videos. This widget is the **only**
/// allowed entry point for lesson video playback — it enforces every
/// protection required by the security spec:
///
///   * Mints a fresh signed playback ticket per session and re-mints after
///     background > 5 min (token expiry) or whenever the cached ticket has
///     expired.
///   * Refuses to play when the per-platform DRM flag is false.
///   * Toggles platform capture protection (FLAG_SECURE on Android, screen
///     capture / screenshot / external-display observers on iOS) via
///     [PlaybackSecurity].
///   * Disables AirPlay / external playback on iOS (AVPlayer level).
///   * Renders a per-user drifting watermark over the video.
///   * Reports security telemetry (`screenshot_attempt`,
///     `recording_detected`, `external_display_detected`, …) and playback
///     progress (`tick` / `completed` / `pause`) to the backend.
///   * Locks orientation to landscape on phones, restores on dispose.
///   * Plays through an "Up Next" queue and surfaces a "Part N of M" badge.
class SecureStreamPlayer extends ConsumerStatefulWidget {
  const SecureStreamPlayer({
    super.key,
    required this.video,
    this.groupTitle,
    this.upNext = const <VideoItem>[],
    this.autoPlay = true,
  });

  /// The video to play first.
  final VideoItem video;

  /// Lesson group title — shown in the overlay (e.g. "Lesson 3 — Quadratic…").
  final String? groupTitle;

  /// Remaining videos in the same lesson group, in order. The player auto-
  /// advances through them when each clip completes and shows an Up-Next
  /// strip in the overlay.
  final List<VideoItem> upNext;

  final bool autoPlay;

  @override
  ConsumerState<SecureStreamPlayer> createState() => _SecureStreamPlayerState();
}

class _SecureStreamPlayerState extends ConsumerState<SecureStreamPlayer>
    with WidgetsBindingObserver {
  // Queue: [current, ...upNext]
  late List<VideoItem> _queue;
  int _index = 0;
  VideoItem get _current => _queue[_index];

  VideoPlayerController? _video;
  ChewieController? _chewie;
  PlaybackTicket? _ticket;

  bool _loading = true;
  String? _error;

  // ── Capture protection state ─────────────────────────────────────────────
  StreamSubscription<Map<String, dynamic>>? _securitySub;
  bool _captureBlocked = false; // hides video layer while recording detected
  String _captureReason = '';
  Timer? _screenshotFlashTimer;
  bool _screenshotFlash = false;

  // ── Lifecycle / token refresh ────────────────────────────────────────────
  DateTime? _backgroundedAt;
  bool _completedReported = false;

  // ── Heartbeats ───────────────────────────────────────────────────────────
  Timer? _tickTimer;
  int _lastReportedPosition = 0;

  // Cached repository so dispose-time flushes don't touch `ref` after the
  // widget has been unmounted (Riverpod throws if you do).
  StudentRepository? _repo;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(studentRepositoryProvider);
    _queue = [widget.video, ...widget.upNext];
    WidgetsBinding.instance.addObserver(this);
    _lockLandscape();
    _enableProtection();
    _subscribeSecurityEvents();
    _loadCurrent();
  }

  @override
  void dispose() {
    _flushProgress(event: 'pause');
    _tickTimer?.cancel();
    _screenshotFlashTimer?.cancel();
    _securitySub?.cancel();
    _chewie?.dispose();
    _video?.dispose();
    PlaybackSecurity.I.disable();
    final ctl = SecureApplicationProvider.of(context, listen: false);
    // Keep the app-wide secure mode on (it was on before we entered).
    ctl?.secure();
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ───────────────────────── Orientation / chrome ─────────────────────────

  Future<void> _lockLandscape() async {
    // Force landscape on phones; tablets allow both.
    final shortest = WidgetsBinding
            .instance.platformDispatcher.views.first.physicalSize.shortestSide /
        WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    final isTablet = shortest >= 600;
    if (isTablet) {
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    } else {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  // ───────────────────────── Protection wiring ─────────────────────────

  void _enableProtection() {
    // App-wide FLAG_SECURE / iOS background blur (covers app switcher).
    final ctl = SecureApplicationProvider.of(context, listen: false);
    ctl?.secure();
    // Native player-time protection (iOS observers / Android external-display
    // listener). FLAG_SECURE is already on via secure_application.
    PlaybackSecurity.I.enable();
  }

  void _subscribeSecurityEvents() {
    _securitySub = PlaybackSecurity.I.events.listen((evt) {
      final name = evt['event']?.toString() ?? '';
      switch (name) {
        case 'screenshot_attempt':
          _onScreenshotAttempt();
          break;
        case 'recording_detected':
          _blockCapture('Recording detected — playback paused');
          _reportSecurity('recording_detected');
          break;
        case 'capture_ended':
          _unblockCapture();
          break;
        case 'external_display_detected':
          _blockCapture('External display detected — playback paused');
          _reportSecurity('external_display_detected');
          break;
        case 'external_display_disconnected':
          _unblockCapture();
          break;
      }
    });
  }

  void _onScreenshotAttempt() {
    _reportSecurity('screenshot_attempt');
    // iOS cannot block the capture itself; flash the video layer black so
    // the captured frame contains only the watermark + black box.
    if (!mounted) return;
    setState(() => _screenshotFlash = true);
    _screenshotFlashTimer?.cancel();
    _screenshotFlashTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _screenshotFlash = false);
    });
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('Screenshots are disabled.'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _blockCapture(String reason) {
    if (!mounted) return;
    _video?.pause();
    setState(() {
      _captureBlocked = true;
      _captureReason = reason;
    });
  }

  void _unblockCapture() {
    if (!mounted) return;
    setState(() {
      _captureBlocked = false;
      _captureReason = '';
    });
  }

  void _reportSecurity(String event) {
    // Fire-and-forget telemetry. Use the cached repo so this still works if
    // the widget is being torn down.
    final repo = _repo;
    if (repo == null) return;
    repo.postSecurityEvent(
      event: event,
      videoId: _current.id,
      deviceInfo: {
        'platform': Platform.isIOS ? 'ios' : 'android',
      },
    );
  }

  // ───────────────────────── Token / player setup ─────────────────────────

  Future<void> _loadCurrent({int? startAt}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // Tear down any prior controllers before mounting a new one.
    await _chewie?.videoPlayerController.pause();
    _chewie?.dispose();
    await _video?.dispose();
    _chewie = null;
    _video = null;

    try {
      final StudentRepository repo =
          _repo ?? ref.read(studentRepositoryProvider);
      _repo = repo;
      final ticket = await repo.videoPlayback(_current.id);
      // DRM gate — spec section 3.1: refuse if the per-platform flag is false.
      final drmOk = Platform.isIOS ? ticket.fairplay : ticket.widevine;
      if (!drmOk) {
        _reportSecurity(
            Platform.isIOS ? 'fairplay_unavailable' : 'l1_unavailable');
        setState(() {
          _loading = false;
          _error = 'Playback unavailable on this device.';
        });
        return;
      }
      _ticket = ticket;

      // HLS for iOS (native AVPlayer support) and Android (ExoPlayer).
      final vc = VideoPlayerController.networkUrl(
        Uri.parse(ticket.hlsUrl),
        formatHint: VideoFormat.hls,
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      );
      await vc.initialize();
      // Disable AirPlay / external playback on iOS at the AVPlayer level.
      // (video_player exposes no API for this; the native side disables it
      // via the same MethodChannel in PlaybackSecurity.enable().)
      final resumeFrom = startAt ?? _current.watchedSeconds;
      if (resumeFrom > 3 && resumeFrom < (_current.durationSeconds - 5)) {
        await vc.seekTo(Duration(seconds: resumeFrom));
      }
      _video = vc;
      _chewie = ChewieController(
        videoPlayerController: vc,
        autoPlay: widget.autoPlay,
        looping: false,
        allowFullScreen: false, // we ARE the full-screen surface
        allowMuting: true,
        allowPlaybackSpeedChanging: true,
        showControlsOnInitialize: true,
        showOptions: false, // disables built-in "share / open in browser" menu
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.white,
          handleColor: Colors.white,
          backgroundColor: Colors.white24,
          bufferedColor: Colors.white38,
        ),
        cupertinoProgressColors: ChewieProgressColors(
          playedColor: Colors.white,
          handleColor: Colors.white,
          backgroundColor: Colors.white24,
          bufferedColor: Colors.white38,
        ),
        placeholder: ColoredBox(
          color: Colors.black,
          child: ticket.posterUrl != null && ticket.posterUrl!.isNotEmpty
              ? Image.network(ticket.posterUrl!, fit: BoxFit.contain)
              : const SizedBox.expand(),
        ),
      );
      vc.addListener(_onVideoTick);
      _scheduleHeartbeats();
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e is AppFailure ? e.message : 'Could not load video.';
      });
    }
  }

  void _scheduleHeartbeats() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _flushProgress(event: 'tick');
    });
  }

  void _onVideoTick() {
    final vc = _video;
    if (vc == null || !vc.value.isInitialized) return;
    // Auto-advance / completion detection.
    final pos = vc.value.position.inSeconds;
    final dur = vc.value.duration.inSeconds;
    if (!_completedReported && dur > 0 && pos / dur >= 0.9) {
      _completedReported = true;
      _flushProgress(event: 'completed');
    }
    if (vc.value.position >= vc.value.duration &&
        vc.value.duration > Duration.zero &&
        !vc.value.isPlaying) {
      _advanceQueue();
    }
  }

  void _advanceQueue() {
    if (_index + 1 >= _queue.length) return;
    setState(() {
      _index++;
      _completedReported = false;
      _lastReportedPosition = 0;
    });
    _loadCurrent();
  }

  Future<void> _flushProgress({required String event}) async {
    final vc = _video;
    if (vc == null || !vc.value.isInitialized) return;
    final pos = vc.value.position.inSeconds;
    final dur = vc.value.duration.inSeconds;
    final delta = pos - _lastReportedPosition;
    if (pos <= 0) return;
    if (event == 'tick' && delta < 60) return;
    _lastReportedPosition = pos;
    final repo = _repo;
    if (repo == null) return;
    await repo.videoProgress(
      videoId: _current.id,
      positionSeconds: pos,
      durationSeconds: dur,
      event: event,
    );
  }

  // ───────────────────────── Lifecycle / token refresh ─────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _backgroundedAt = DateTime.now();
        _video?.pause();
        _flushProgress(event: 'pause');
        break;
      case AppLifecycleState.resumed:
        _onResume();
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _onResume() async {
    final bgAt = _backgroundedAt;
    _backgroundedAt = null;
    final stale = _ticket == null || !(_ticket!.isFresh());
    final longBackground = bgAt != null &&
        DateTime.now().difference(bgAt) > const Duration(minutes: 5);
    if (stale || longBackground) {
      // Re-mint and re-mount the player from the current position.
      final startAt =
          _video?.value.position.inSeconds ?? _current.watchedSeconds;
      await _loadCurrent(startAt: startAt);
    }
  }

  // ───────────────────────── Build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final identity = user?.email ?? user?.phone ?? user?.name ?? '';
    final wm = identity.isEmpty ? 'Loay Mohamed' : 'Loay Mohamed · $identity';

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _flushProgress(event: 'pause');
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          top: false,
          bottom: false,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Video / placeholders ───────────────────────────────────
              if (_loading)
                const _Loading()
              else if (_error != null)
                _ErrorView(
                  message: _error!,
                  onRetry: _loadCurrent,
                )
              else if (_chewie != null)
                // Hide the video frame while a recording / mirror is detected
                // OR during the post-screenshot flash, so captured frames are
                // empty (covered by the black box + watermark).
                Opacity(
                  opacity: (_captureBlocked || _screenshotFlash) ? 0.0 : 1.0,
                  child: Chewie(controller: _chewie!),
                ),

              // ── Recording / mirroring overlay ─────────────────────────
              if (_captureBlocked)
                _CaptureBlockedOverlay(reason: _captureReason),

              // ── Per-user watermark (drifts slowly) ────────────────────
              IgnorePointer(child: _Watermark(label: wm)),

              // ── Top bar: back + group title + part counter ────────────
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: SafeArea(
                  child: Row(
                    children: [
                      _RoundIcon(
                        icon: Icons.close_rounded,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.groupTitle != null)
                              Text(
                                widget.groupTitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            Text(
                              _queue.length > 1
                                  ? 'Part ${_index + 1} of ${_queue.length}'
                                  : _current.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Up Next strip (bottom-right) ──────────────────────────
              if (_index + 1 < _queue.length && !_captureBlocked)
                Positioned(
                  right: 12,
                  bottom: 80,
                  child: _UpNextStrip(
                    next: _queue[_index + 1],
                    onTap: _advanceQueue,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Sub-widgets ─────────────────────────

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => Container(
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
          const Icon(Icons.videocam_off_rounded,
              color: Colors.white54, size: 48),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => onRetry!(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }
}

class _CaptureBlockedOverlay extends StatelessWidget {
  const _CaptureBlockedOverlay({required this.reason});
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.shield_outlined, color: Colors.white70, size: 56),
          const SizedBox(height: 14),
          Text(
            reason,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Disconnect mirroring or stop recording to resume.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
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

class _UpNextStrip extends StatelessWidget {
  const _UpNextStrip({required this.next, required this.onTap});
  final VideoItem next;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (next.thumbnailUrl != null && next.thumbnailUrl!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.network(
                    next.thumbnailUrl!,
                    width: 48,
                    height: 28,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const SizedBox(width: 48, height: 28),
                  ),
                ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'UP NEXT',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(
                      next.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              const Icon(Icons.play_arrow_rounded,
                  color: Colors.white, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// Repeating per-user watermark. Faint, rotated, slowly drifting; designed
/// to make captured frames traceable even if the screenshot bypasses the
/// platform protections.
class _Watermark extends StatefulWidget {
  const _Watermark({required this.label});
  final String label;

  @override
  State<_Watermark> createState() => _WatermarkState();
}

class _WatermarkState extends State<_Watermark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift;

  @override
  void initState() {
    super.initState();
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.label.isEmpty) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _drift,
      builder: (_, __) {
        final t = _drift.value * 2 * math.pi;
        final dx = math.sin(t) * 24;
        final dy = math.cos(t) * 18;
        return LayoutBuilder(
          builder: (_, c) {
            const tileW = 220.0;
            const tileH = 140.0;
            final cols = (c.maxWidth / tileW).ceil() + 2;
            final rows = (c.maxHeight / tileH).ceil() + 2;
            return SizedBox.expand(
              child: Stack(
                children: [
                  for (var r = 0; r < rows; r++)
                    for (var col = 0; col < cols; col++)
                      Positioned(
                        left: col * tileW - (r.isOdd ? tileW / 2 : 0) + dx,
                        top: r * tileH + dy,
                        child: Transform.rotate(
                          angle: -math.pi / 9,
                          child: Opacity(
                            opacity: 0.10,
                            child: Text(
                              widget.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
