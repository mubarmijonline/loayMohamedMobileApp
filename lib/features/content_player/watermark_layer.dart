import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/security/capture_event.dart';

/// The identity overlay, drawn twice, with a live clock.
///
/// The timestamp is not decoration. Identity alone tells you *who* leaked a
/// recording; identity plus a ticking clock tells you *which session*, which
/// is what distinguishes a student who recorded a lesson from one whose
/// account was shared. The web portal carries one for the same reason; the
/// mobile watermark did not until now.
///
/// The portal refreshes its text every 5s and repositions every 8s. This
/// refreshes every 5s and repositions every 20-30s, per the app's own spec —
/// tighten [_tick] and the drift timer if you want exact parity.
class WatermarkLayer extends StatefulWidget {
  const WatermarkLayer({
    required this.text,
    required this.primary,
    required this.secondary,
  });

  final String text;
  final Alignment primary;
  final Alignment secondary;

  @override
  State<WatermarkLayer> createState() => WatermarkLayerState();
}

class WatermarkLayerState extends State<WatermarkLayer> {
  static const _tick = Duration(seconds: 5);

  late Timer _timer;
  late String _stamp;

  @override
  void initState() {
    super.initState();
    _stamp = _now();
    _timer = Timer.periodic(_tick, (_) {
      if (mounted) setState(() => _stamp = _now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  /// UTC, so a recording made abroad still lines up with server logs.
  static String _now() {
    final t = DateTime.now().toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}Z';
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final primary = widget.primary;
    final secondary = widget.secondary;
    if (text.isEmpty) return const SizedBox.shrink();
    Widget mark(Alignment a) => AnimatedAlign(
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeInOut,
          alignment: a,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              '$text\n$_stamp',
              textAlign: TextAlign.center,
              style: TextStyle(
                // Legible enough to read off a recording, faint enough not to
                // fight the lesson.
                color: Colors.white.withValues(alpha: 0.22),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                shadows: const [
                  Shadow(color: Colors.black38, blurRadius: 2),
                ],
              ),
            ),
          ),
        );

    return Stack(children: [mark(primary), mark(secondary)]);
  }
}

/// Opaque panel shown while a recording, mirror or external display is live.
class CaptureBlockPanel extends StatelessWidget {
  const CaptureBlockPanel({required this.type});

  final CaptureEventType type;

  @override
  Widget build(BuildContext context) {
    final (icon, title, body) = switch (type) {
      CaptureEventType.recordingStarted => (
          Icons.videocam_off_rounded,
          'Screen recording is not allowed',
          'Stop the recording to continue watching.',
        ),
      CaptureEventType.externalDisplayConnected => (
          Icons.cast_connected_rounded,
          'Screen mirroring is not allowed',
          'Disconnect the external display or AirPlay to continue.',
        ),
      _ => (
          Icons.shield_outlined,
          'Playback is unavailable',
          'Screen protection could not be enabled on this device.',
        ),
    };

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white70, size: 40),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
