import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/logging/app_logger.dart';
import '../../core/security/capture_event.dart';
import '../../core/security/screen_guard.dart';
import '../_shared/models.dart';
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
    try {
      await c.initialize();
      if (!mounted) return;
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
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (c != null && c.value.isInitialized && !_failed)
            Center(
              child: AspectRatio(
                aspectRatio: c.value.aspectRatio,
                child: VideoPlayer(c),
              ),
            ),

          if (c != null &&
              c.value.isInitialized &&
              !_failed &&
              _blockedBy == null)
            _Controls(controller: c),

          // Above the video, below nothing. Present in fullscreen because this
          // widget IS the fullscreen surface.
          IgnorePointer(
            child: WatermarkLayer(
              text: widget.watermark,
              primary: _wmPrimary,
              secondary: _wmSecondary,
            ),
          ),

          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: Colors.white70),
            ),

          if (_failed) const _NativePlayerError(),

          if (_blockedBy != null) CaptureBlockPanel(type: _blockedBy!),
        ],
      ),
    );
  }
}

/// Minimal transport controls.
///
/// Deliberately hand-rolled rather than `chewie`: chewie ships a share/other
/// options affordance in some configurations, and hard requirement 2 says
/// there is no share button anywhere in or around the player.
class _Controls extends StatefulWidget {
  const _Controls({required this.controller});

  final VideoPlayerController controller;

  @override
  State<_Controls> createState() => _ControlsState();
}

class _ControlsState extends State<_Controls> {
  bool _visible = true;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _visible = !_visible);
        if (_visible) _scheduleHide();
      },
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          color: Colors.black26,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Center(
                child: IconButton(
                  iconSize: 56,
                  color: Colors.white,
                  icon: Icon(
                    c.value.isPlaying
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                  ),
                  onPressed: () {
                    c.value.isPlaying ? c.pause() : c.play();
                    _scheduleHide();
                  },
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
                  children: [
                    Text(
                      _fmt(c.value.position),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    Expanded(
                      child: VideoProgressIndicator(
                        c,
                        allowScrubbing: true,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        colors: const VideoProgressColors(
                          playedColor: Colors.white,
                          bufferedColor: Colors.white30,
                          backgroundColor: Colors.white12,
                        ),
                      ),
                    ),
                    Text(
                      _fmt(c.value.duration),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NativePlayerError extends StatelessWidget {
  const _NativePlayerError();

  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded,
                    color: Colors.white70, size: 36),
                SizedBox(height: 12),
                Text(
                  'This video could not be played.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 15),
                ),
                SizedBox(height: 4),
                Text(
                  'Check your connection and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      );
}
