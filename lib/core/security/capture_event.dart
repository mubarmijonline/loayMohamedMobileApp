import 'package:equatable/equatable.dart';

/// What the platform told us about a capture attempt.
///
/// On Android these are mostly informational — `FLAG_SECURE` already refused
/// the capture. On iOS they are the *only* signal available, because the OS
/// cannot be told to refuse.
enum CaptureEventType {
  /// A screenshot was taken. iOS only, and always after the fact — the image
  /// exists and cannot be recalled. Android blocks the capture outright and
  /// (below API 34) reports nothing.
  screenshot,

  /// Screen recording or AirPlay mirroring started (`UIScreen.isCaptured`).
  recordingStarted,

  /// Recording/mirroring stopped.
  recordingStopped,

  /// A second display appeared — HDMI dongle, AirPlay, scrcpy.
  externalDisplayConnected,

  /// Back down to a single display.
  externalDisplayDisconnected,

  /// The platform reported that protection could not be applied. The player
  /// must refuse to render.
  protectionUnavailable,

  /// An event name we do not recognise. Kept rather than dropped so a native
  /// change shows up in the queue instead of vanishing.
  unknown;

  static CaptureEventType parse(String? raw) => switch (raw) {
        'screenshot' || 'screenshot_attempt' => CaptureEventType.screenshot,
        'recording_detected' ||
        'recording_started' =>
          CaptureEventType.recordingStarted,
        'capture_ended' ||
        'recording_stopped' =>
          CaptureEventType.recordingStopped,
        'external_display_detected' =>
          CaptureEventType.externalDisplayConnected,
        'external_display_disconnected' =>
          CaptureEventType.externalDisplayDisconnected,
        'protection_unavailable' => CaptureEventType.protectionUnavailable,
        _ => CaptureEventType.unknown,
      };

  /// Events that must blank the player and stop playback while they hold.
  bool get blocksPlayback =>
      this == CaptureEventType.recordingStarted ||
      this == CaptureEventType.externalDisplayConnected ||
      this == CaptureEventType.protectionUnavailable;

  /// Events that clear a previous block.
  bool get clearsBlock =>
      this == CaptureEventType.recordingStopped ||
      this == CaptureEventType.externalDisplayDisconnected;
}

/// A capture signal from the platform, stamped for later reporting.
class CaptureEvent extends Equatable {
  const CaptureEvent({
    required this.type,
    required this.at,
    this.contentId,
    this.raw,
    this.meta = const {},
  });

  final CaptureEventType type;
  final DateTime at;

  /// Which video was on screen. Set by [ScreenGuard.bindContent] so the queued
  /// event is attributable to a lesson, not just a timestamp.
  final String? contentId;

  /// The platform's original event name, kept for unknown types.
  final String? raw;

  final Map<String, dynamic> meta;

  CaptureEvent withContent(String? id) => CaptureEvent(
        type: type,
        at: at,
        contentId: id ?? contentId,
        raw: raw,
        meta: meta,
      );

  factory CaptureEvent.fromPlatform(Map<String, dynamic> m) {
    final name = (m['event'] ?? m['type'])?.toString();
    return CaptureEvent(
      type: CaptureEventType.parse(name),
      at: DateTime.now(),
      raw: name,
      meta: {
        for (final e in m.entries)
          if (e.key != 'event' && e.key != 'type') e.key: e.value,
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'event': raw ?? type.name,
        'type': type.name,
        'at': at.toUtc().toIso8601String(),
        if (contentId != null) 'content_id': contentId,
        if (meta.isNotEmpty) 'meta': meta,
      };

  static CaptureEvent fromJson(Map<String, dynamic> j) => CaptureEvent(
        type: CaptureEventType.values.firstWhere(
          (t) => t.name == j['type'],
          orElse: () => CaptureEventType.unknown,
        ),
        at: DateTime.tryParse(j['at']?.toString() ?? '') ?? DateTime.now(),
        contentId: j['content_id']?.toString(),
        raw: j['event']?.toString(),
        meta: j['meta'] is Map
            ? Map<String, dynamic>.from(j['meta'] as Map)
            : const {},
      );

  @override
  List<Object?> get props => [type, at, contentId, raw];
}
