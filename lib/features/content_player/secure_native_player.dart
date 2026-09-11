import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/design/app_colors.dart';
import '../../core/logging/app_logger.dart';
import '../../core/security/capture_event.dart';
import '../../core/security/screen_guard.dart';
import '../_shared/models.dart';
import 'player_seek.dart';
import 'watermark_layer.dart';

/// Native player for Drive content.
///
/// The backend now proxies Drive bytes through
/// `/api/v1/student/content/<id>/drive-stream` on our own origin, serving raw
/// `video/mp4` with `Accept-Ranges: bytes` and forwarding the client's `Range`
/// header (API_BRIEF §6). That changes the security story completely:
///
///   * There is no Google player, so there is no share button, no pop-out and
///     no download item — nothing to hide, rather than something hidden.
///   * The Drive file id never reaches the device.
///   * The URL is useless without an `Authorization` header, unlike the old
///     unsigned `/preview` link which anyone could open in a browser.
///   * Seeking works, because Range is forwarded end to end.
///
/// So this widget deliberately does NOT use a WebView. Everything in
/// `SecureWebPlayer` about navigation lockdown and hiding Drive's chrome
/// exists only for the two remaining iframe providers.
///
/// SECURITY: the stream URL is session-scoped but still a video. It must never
/// be logged, copied, or handed to anything outside this widget.
class SecureNativePlayer extends StatefulWidget {
  const SecureNativePlayer({
    super.key,
    required this.embed,
    required this.watermark,
    required this.authHeader,
    required this.screenGuard,
    this.startAtSeconds = 0,
    this.title,
    this.poster,
    this.onRetry,
    this.onPositionChanged,
    this.onPlayingChanged,
    this.onEnded,
    this.onError,
  });

  final ContentEmbed embed;
  final String watermark;

  /// `Bearer <access_token>`. The proxy rejects the request without it.
  final String? authHeader;

  final ScreenGuard screenGuard;
  final int startAtSeconds;

  final void Function(int position, int? duration)? onPositionChanged;
  final void Function(bool playing)? onPlayingChanged;
  final VoidCallback? onEnded;
  final VoidCallback? onError;

  /// Shown in the control layer's top bar.
  final String? title;

  /// The lesson's thumbnail, shown until the first frame so the wait reads as
  /// the video arriving rather than a black screen.
  final ImageProvider? poster;

  /// "Try again" on the failure view.
  final VoidCallback? onRetry;

  @override
  State<SecureNativePlayer> createState() => _SecureNativePlayerState();
}

class _SecureNativePlayerState extends State<SecureNativePlayer>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  StreamSubscription<CaptureEvent>? _guardSub;
  Timer? _watermarkTimer;

  bool _loading = true;
  bool _failed = false;
  bool _seeded = false;
  CaptureEventType? _blockedBy;

  Alignment _wmPrimary = Alignment.topLeft;
  Alignment _wmSecondary = Alignment.bottomRight;
  final _rng = math.Random();

  /// Measures start-up, for the diagnostics in [_open] and [_onTick].
  final _clock = Stopwatch();
  bool _loggedFirstFrame = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenToGuard();
    _startWatermarkDrift();
    _open();
  }

  Future<void> _open() async {
    final url = Uri.tryParse(widget.embed.playbackUrl);
    // `Uri.tryParse` accepts a bare path and returns a valid *relative* Uri,
    // so a null check alone let `/api/v1/...` through to AVPlayer/ExoPlayer,
    // which cannot open it and reports nothing useful. Require a real origin.
    if (url == null || !url.hasScheme || !url.hasAuthority) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    final c = VideoPlayerController.networkUrl(
      url,
      httpHeaders: {
        if (widget.authHeader != null) 'Authorization': widget.authHeader!,
      },
    );
    _controller = c;
    c.addListener(_onTick);
    _clock.start();
    try {
      await c.initialize();
      if (!mounted) return;
      // Diagnostics, without the URL: how long the proxy takes to give the
      // player enough of the file to start. The server half of this is
      // docs/mobile/BACKEND_VIDEO_STREAMING.md.
      AppLogger.I.i('Video: ready after ${_clock.elapsedMilliseconds} ms');
      if (widget.startAtSeconds > 3) {
        await c.seekTo(Duration(seconds: widget.startAtSeconds));
      }
      await c.play();
      setState(() => _loading = false);
    } on Object catch (e) {
      // Never surface the URL in an error — it is a video credential. The
      // exception type and message are safe and are what identify a 401, a
      // 404 or an undecodable response.
      AppLogger.I.e('Native player failed to initialise: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
      widget.onError?.call();
    }
  }

  void _onTick() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;

    if (c.value.hasError && !_failed) {
      setState(() => _failed = true);
      widget.onError?.call();
      return;
    }

    if (!_loggedFirstFrame &&
        c.value.isPlaying &&
        !c.value.isBuffering &&
        c.value.position > Duration.zero) {
      _loggedFirstFrame = true;
      AppLogger.I
          .i('Video: first frame after ${_clock.elapsedMilliseconds} ms');
    }

    final playing = c.value.isPlaying;
    if (playing != _seeded) {
      _seeded = playing;
      widget.onPlayingChanged?.call(playing);
    }
    widget.onPositionChanged?.call(
      c.value.position.inSeconds,
      c.value.duration.inSeconds,
    );
    if (c.value.position >= c.value.duration &&
        c.value.duration > Duration.zero) {
      widget.onEnded?.call();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _controller?.pause();
  }

  void _listenToGuard() {
    _guardSub = widget.screenGuard.events.listen((e) {
      if (!mounted) return;
      if (e.type.blocksPlayback) {
        _controller?.pause();
        setState(() => _blockedBy = e.type);
      } else if (e.type.clearsBlock) {
        setState(() => _blockedBy = null);
      }
    });
  }

  void _startWatermarkDrift() {
    void schedule() {
      _watermarkTimer = Timer(Duration(seconds: 20 + _rng.nextInt(11)), () {
        if (!mounted) return;
        setState(() {
          _wmPrimary = _randomAlignment(top: true);
          _wmSecondary = _randomAlignment(top: false);
        });
        schedule();
      });
    }

    schedule();
  }

  Alignment _randomAlignment({required bool top}) {
    final x = -0.75 + _rng.nextDouble() * 1.5;
    final y =
        top ? -0.85 + _rng.nextDouble() * 0.35 : 0.5 + _rng.nextDouble() * 0.35;
    return Alignment(x, y);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watermarkTimer?.cancel();
    _guardSub?.cancel();
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized && !_failed;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (ready)
            Center(
              child: AspectRatio(
                aspectRatio: c!.value.aspectRatio,
                child: VideoPlayer(c),
              ),
            ),

          // Until the first frame: the lesson's poster, so the wait looks like
          // the video arriving rather than a black screen.
          if (_loading && widget.poster != null)
            Image(
              image: widget.poster!,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),

          if (ready && _blockedBy == null)
            _Controls(controller: c!, title: widget.title),

          // Above the video, below nothing. Present in fullscreen because this
          // widget IS the fullscreen surface.
          IgnorePointer(
            child: WatermarkLayer(
              text: widget.watermark,
              primary: _wmPrimary,
              secondary: _wmSecondary,
            ),
          ),

          if (_loading) const _LoadingIndicator(),

          if (_failed) _NativePlayerError(onRetry: widget.onRetry),

          if (_blockedBy != null) CaptureBlockPanel(type: _blockedBy!),
        ],
      ),
    );
  }
}

/// Transport controls for the native player.
///
/// Hand-rolled rather than `chewie`, which ships a share/options affordance in
/// some configurations — and nothing in or around this player may offer to
/// share.
///
/// Shaped by three things students hit in the previous version:
///
/// * **The seek bar was a 4-pixel strip**, grabbable only exactly on the line
///   and 8 px from the bottom of the screen. In fullscreen that is inside the
///   iPhone's home-indicator zone, where a sideways swipe switches apps, so
///   trying to scrub sent the student out of the app. The bar is now a 44 pt
///   target, and the whole layer sits inside a [SafeArea], clear of the notch
///   and the home indicator in either orientation.
/// * **No way to skip.** ±10 s buttons either side of play; a double tap on the
///   left or right of the video does the same.
/// * **No sign of buffering** once playing. A stall now shows a spinner rather
///   than looking frozen.
class _Controls extends StatefulWidget {
  const _Controls({required this.controller, this.title});

  final VideoPlayerController controller;
  final String? title;

  @override
  State<_Controls> createState() => _ControlsState();
}

class _ControlsState extends State<_Controls> {
  bool _visible = true;
  bool _wasPlaying = false;
  Timer? _hide;

  /// Seek-bar position (0 to 1) while the student is dragging; null otherwise.
  double? _scrub;

  /// Which "10 s" badge a double tap is showing: -1 back, 1 forward, 0 none.
  int _skipBadge = 0;
  Timer? _skipBadgeTimer;

  VideoPlayerController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _wasPlaying = _c.value.isPlaying;
    _c.addListener(_onValue);
    _scheduleHide();
  }

  @override
  void didUpdateWidget(covariant _Controls old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onValue);
      widget.controller.addListener(_onValue);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onValue);
    _hide?.cancel();
    _skipBadgeTimer?.cancel();
    super.dispose();
  }

  /// The clock, seek bar and buffering state need every position tick, and
  /// the controls should come back the moment playback pauses.
  void _onValue() {
    if (!mounted) return;
    final playing = _c.value.isPlaying;
    if (playing != _wasPlaying) {
      _wasPlaying = playing;
      if (playing) {
        _scheduleHide();
      } else {
        _hide?.cancel();
        _visible = true;
      }
    }
    setState(() {});
  }

  /// Hide after 4 s of playback — never while paused or mid-drag, when the
  /// student is plainly looking at the controls.
  void _scheduleHide() {
    _hide?.cancel();
    if (!_c.value.isPlaying || _scrub != null) return;
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted && _c.value.isPlaying && _scrub == null) {
        setState(() => _visible = false);
      }
    });
  }

  void _poke() {
    if (!_visible) setState(() => _visible = true);
    _scheduleHide();
  }

  void _toggle() {
    setState(() => _visible = !_visible);
    if (_visible) _scheduleHide();
  }

  Future<void> _playPause() async {
    if (_c.value.isPlaying) {
      await _c.pause();
    } else {
      // At the end, play means "watch it again".
      final v = _c.value;
      if (v.duration > Duration.zero && v.position >= v.duration) {
        await _c.seekTo(Duration.zero);
      }
      await _c.play();
    }
    _poke();
  }

  Future<void> _skip(int direction) async {
    final v = _c.value;
    await _c.seekTo(
      PlayerSeek.by(v.position, PlayerSeek.skip * direction, v.duration),
    );
    _poke();
  }

  void _doubleTapSkip(int direction) {
    _skip(direction);
    _skipBadgeTimer?.cancel();
    setState(() => _skipBadge = direction);
    _skipBadgeTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _skipBadge = 0);
    });
  }

  // The seek happens once, on release, not on every drag update. Each seek is
  // a new Range request through the Drive proxy; seeking continuously while
  // the finger moves would queue dozens of them and make the video slower to
  // resume, which is the opposite of the point.
  void _scrubStart(double f) {
    _hide?.cancel();
    setState(() {
      _scrub = f;
      _visible = true;
    });
  }

  void _scrubUpdate(double f) => setState(() => _scrub = f);

  Future<void> _scrubEnd() async {
    final f = _scrub;
    setState(() => _scrub = null);
    if (f != null) await _c.seekTo(PlayerSeek.at(f, _c.value.duration));
    _scheduleHide();
  }

  void _scrubCancel() {
    setState(() => _scrub = null);
    _scheduleHide();
  }

  Future<void> _tapSeek(double f) async {
    await _c.seekTo(PlayerSeek.at(f, _c.value.duration));
    _poke();
  }

  static String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final v = _c.value;
    final duration = v.duration;
    final ms = duration.inMilliseconds;
    final scrub = _scrub;
    final played = scrub ?? (ms > 0 ? v.position.inMilliseconds / ms : 0.0);
    var bufferedMs = 0;
    for (final r in v.buffered) {
      if (r.end.inMilliseconds > bufferedMs) bufferedMs = r.end.inMilliseconds;
    }
    final buffered = ms > 0 ? bufferedMs / ms : 0.0;
    final shown = scrub == null ? v.position : PlayerSeek.at(scrub, duration);
    final buffering = v.isBuffering && scrub == null;

    return Stack(
      fit: StackFit.expand,
      children: [
        // The tap surface: a single tap shows or hides the controls, a double
        // tap on either side skips 10 s. It is deliberately a sibling of the
        // buttons, not their parent — a double-tap detector wrapping them
        // would hold every button press back by the double-tap timeout.
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 2,
              child: _TapZone(
                onTap: _toggle,
                onDoubleTap: () => _doubleTapSkip(-1),
              ),
            ),
            Expanded(child: _TapZone(onTap: _toggle)),
            Expanded(
              flex: 2,
              child: _TapZone(
                onTap: _toggle,
                onDoubleTap: () => _doubleTapSkip(1),
              ),
            ),
          ],
        ),

        if (_skipBadge != 0)
          IgnorePointer(
            child: Align(
              alignment: Alignment(_skipBadge * 0.6, 0),
              child: _SkipBadge(forward: _skipBadge > 0),
            ),
          ),

        // A stall with the controls hidden still has to say so.
        if (buffering && !_visible) const IgnorePointer(child: _Spinner()),

        IgnorePointer(
          ignoring: !_visible,
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Legibility scrim. Visual only: a DecoratedBox claims every
                // tap inside it, which would starve the tap surface below.
                const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x99000000),
                          Color(0x00000000),
                          Color(0x00000000),
                          Color(0xB3000000),
                        ],
                        stops: [0, 0.28, 0.62, 1],
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  minimum: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Stack(
                    children: [
                      if (widget.title != null)
                        Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            // Clears the screen's own back and fullscreen
                            // buttons in the top corners.
                            padding: const EdgeInsets.fromLTRB(52, 8, 52, 0),
                            child: Text(
                              widget.title!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      Center(
                        child: scrub != null
                            // While dragging, the target time is what matters.
                            ? Text(
                                '${_fmt(shown)} / ${_fmt(duration)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _RoundButton(
                                    icon: Icons.replay_10_rounded,
                                    diameter: 52,
                                    label: 'Back 10 seconds',
                                    onTap: () => _skip(-1),
                                  ),
                                  const SizedBox(width: 28),
                                  if (buffering)
                                    const SizedBox(
                                      width: 72,
                                      height: 72,
                                      child: _Spinner(),
                                    )
                                  else
                                    _RoundButton(
                                      icon: v.isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      diameter: 72,
                                      label: v.isPlaying ? 'Pause' : 'Play',
                                      onTap: _playPause,
                                    ),
                                  const SizedBox(width: 28),
                                  _RoundButton(
                                    icon: Icons.forward_10_rounded,
                                    diameter: 52,
                                    label: 'Forward 10 seconds',
                                    onTap: () => _skip(1),
                                  ),
                                ],
                              ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Row(
                          children: [
                            _Clock(_fmt(shown), emphasised: scrub != null),
                            Expanded(
                              child: _SeekBar(
                                played: played.clamp(0.0, 1.0).toDouble(),
                                buffered: buffered.clamp(0.0, 1.0).toDouble(),
                                active: scrub != null,
                                onStart: _scrubStart,
                                onUpdate: _scrubUpdate,
                                onEnd: _scrubEnd,
                                onCancel: _scrubCancel,
                                onTap: _tapSeek,
                              ),
                            ),
                            _Clock(_fmt(duration)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TapZone extends StatelessWidget {
  const _TapZone({required this.onTap, this.onDoubleTap});

  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: const SizedBox.expand(),
      );
}

/// A seek bar you can actually hit: a 44 pt tall target around a 4 pt track.
class _SeekBar extends StatelessWidget {
  const _SeekBar({
    required this.played,
    required this.buffered,
    required this.active,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
    required this.onTap,
  });

  final double played;
  final double buffered;
  final bool active;
  final ValueChanged<double> onStart;
  final ValueChanged<double> onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;
  final ValueChanged<double> onTap;

  /// Room at each end for the thumb, so it is never clipped at 0 or 100%.
  static const _inset = 12.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final track = (box.maxWidth - 2 * _inset).clamp(1.0, 1e9).toDouble();
        double at(double dx) => ((dx - _inset) / track).clamp(0.0, 1.0);
        return Semantics(
          slider: true,
          value: '${(played * 100).round()}%',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (d) => onStart(at(d.localPosition.dx)),
            onHorizontalDragUpdate: (d) => onUpdate(at(d.localPosition.dx)),
            onHorizontalDragEnd: (_) => onEnd(),
            onHorizontalDragCancel: onCancel,
            onTapUp: (d) => onTap(at(d.localPosition.dx)),
            child: SizedBox(
              height: 44,
              child: CustomPaint(
                size: Size.infinite,
                painter: _SeekPainter(
                  played: played,
                  buffered: buffered,
                  active: active,
                  inset: _inset,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SeekPainter extends CustomPainter {
  _SeekPainter({
    required this.played,
    required this.buffered,
    required this.active,
    required this.inset,
  });

  final double played;
  final double buffered;
  final bool active;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final h = active ? 6.0 : 4.0;
    final y = size.height / 2;
    final w = size.width - 2 * inset;
    RRect bar(double f) => RRect.fromLTRBR(
          inset,
          y - h / 2,
          inset + w * f,
          y + h / 2,
          Radius.circular(h / 2),
        );
    canvas.drawRRect(bar(1), Paint()..color = const Color(0x40FFFFFF));
    canvas.drawRRect(bar(buffered), Paint()..color = const Color(0x80FFFFFF));
    canvas.drawRRect(bar(played), Paint()..color = AppColors.accent);
    canvas.drawCircle(
      Offset(inset + w * played, y),
      active ? 10 : 7,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_SeekPainter old) =>
      old.played != played || old.buffered != buffered || old.active != active;
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.diameter,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final double diameter;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: Material(
          color: Colors.black.withValues(alpha: 0.35),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: diameter,
              height: diameter,
              child: Icon(icon, color: Colors.white, size: diameter * 0.55),
            ),
          ),
        ),
      );
}

class _SkipBadge extends StatelessWidget {
  const _SkipBadge({required this.forward});

  final bool forward;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              forward ? Icons.forward_10_rounded : Icons.replay_10_rounded,
              color: Colors.white,
              size: 22,
            ),
            const SizedBox(width: 6),
            Text(
              forward ? '+10 s' : '−10 s',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

class _Clock extends StatelessWidget {
  const _Clock(this.text, {this.emphasised = false});

  final String text;
  final bool emphasised;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          color: emphasised ? AppColors.accent : Colors.white,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const Center(
        child: SizedBox(
          width: 44,
          height: 44,
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
        ),
      );
}

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: Color(0x66000000),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 38,
                height: 38,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.6,
                ),
              ),
              SizedBox(height: 14),
              Text(
                'Loading video…',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      );
}

class _NativePlayerError extends StatelessWidget {
  const _NativePlayerError({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Colors.white70,
                  size: 36,
                ),
                const SizedBox(height: 12),
                const Text(
                  'This video could not be played.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 15),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Check your connection and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Try again'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}
