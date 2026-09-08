import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../logging/app_logger.dart';
import 'capture_event.dart';
import 'capture_event_queue.dart';

/// The single surface for screen-capture protection.
///
/// **Nothing else in the app talks to the platform channel.** Features depend
/// on this class; if you are importing a channel from a feature, that is the
/// bug. See `lib/core/security/README.md` for what this can and cannot do —
/// the short version:
///
///   * Android genuinely blocks screenshots and recording (`FLAG_SECURE`,
///     applied natively in `MainActivity.onCreate`, before the first frame).
///   * **iOS cannot block screenshots.** No such API exists. What we get is
///     blank captured frames, plus detection after the fact.
///   * Nothing stops a second phone pointed at the screen. The watermark is
///     what makes a leak attributable.
///
/// The important guarantee here is [isProtected]: if the platform cannot
/// confirm protection is live, the player refuses to render rather than
/// showing video under a protection that silently failed. An app that believes
/// it is protected and is not is worse than one that never tried.
class ScreenGuard {
  ScreenGuard({
    CaptureEventQueue? queue,
    MethodChannel? method,
    EventChannel? events,
  })  : _queue = queue,
        _method = method ?? const MethodChannel(_methodChannelName),
        _events = events ?? const EventChannel(_eventChannelName);

  static const _methodChannelName = 'app/playback_security';
  static const _eventChannelName = 'app/playback_security/events';

  final CaptureEventQueue? _queue;
  final MethodChannel _method;
  final EventChannel _events;

  final _controller = StreamController<CaptureEvent>.broadcast();
  StreamSubscription<dynamic>? _nativeSub;

  bool _enabled = false;
  String? _contentId;

  /// Cached answer from the last [refreshProtectionState]. Null = never asked.
  bool? _protected;

  /// Capture events, newest first as they arrive.
  ///
  /// Every event is also persisted to [CaptureEventQueue], because there is no
  /// endpoint to report them to yet and they must not be lost.
  Stream<CaptureEvent> get events => _controller.stream;

  /// Whether platform protection is currently confirmed active.
  ///
  /// `false` means the player must not render. `null` means we have not asked
  /// yet — treat that as unprotected for gating purposes.
  bool? get protectionState => _protected;

  bool get isProtected => _protected == true;

  /// Tags subsequent events with the content being watched, so a queued
  /// screenshot is attributable to a lesson rather than just a timestamp.
  void bindContent(String? contentId) => _contentId = contentId;

  /// Turns on platform protection and starts listening for capture events.
  ///
  /// Safe to call repeatedly. Returns whether protection is confirmed active —
  /// callers that render video **must** check this.
  Future<bool> enable() async {
    if (!_enabled) {
      _enabled = true;
      try {
        await _method.invokeMethod<void>('enable');
      } on MissingPluginException {
        // No native side (unit tests, desktop). Not an error, but definitely
        // not protected.
        _enabled = false;
        return _record(false, 'no native implementation registered');
      } on PlatformException catch (e) {
        _enabled = false;
        return _record(false, 'native enable failed: ${e.code} ${e.message}');
      }
      _listen();
    }
    return refreshProtectionState();
  }

  /// Tears protection down. Always call from the player's `dispose()`.
  ///
  /// NOTE: this does *not* clear Android's `FLAG_SECURE`. That flag is set
  /// app-wide at activity creation and stays set for the process lifetime —
  /// toggling it per screen leaves a window where it is off, and that window
  /// is exactly when someone screenshots. This only stops the observers.
  Future<void> disable() async {
    if (!_enabled) return;
    _enabled = false;
    _contentId = null;
    await _nativeSub?.cancel();
    _nativeSub = null;
    try {
      await _method.invokeMethod<void>('disable');
    } on MissingPluginException {
      // Nothing to tear down.
    } on PlatformException {
      // Nothing useful to do — protection state is re-queried on next enable.
    }
  }

  /// Asks the platform whether protection is actually in force right now.
  ///
  /// This is the runtime integrity check: a silent failure here is the whole
  /// risk, so we ask the platform rather than assuming `enable()` worked.
  Future<bool> refreshProtectionState() async {
    try {
      final v = await _method.invokeMethod<bool>('isProtected');
      if (v == null) {
        return _record(false, 'platform returned no protection state');
      }
      return _record(v, v ? null : 'platform reports protection is NOT active');
    } on MissingPluginException {
      return _record(false, 'no native implementation registered');
    } on PlatformException catch (e) {
      return _record(false, 'isProtected failed: ${e.code} ${e.message}');
    }
  }

  bool _record(bool value, [String? why]) {
    _protected = value;
    if (!value) {
      AppLogger.I.e('ScreenGuard: NOT PROTECTED — ${why ?? 'unknown reason'}');
      _emit(
        CaptureEvent(
          type: CaptureEventType.protectionUnavailable,
          at: DateTime.now(),
          raw: 'protection_unavailable',
          meta: {if (why != null) 'reason': why},
        ),
      );
    }
    return value;
  }

  /// True when a screen recording or mirror is active *right now*.
  ///
  /// Always false on Android: capture is refused at the OS layer, so there is
  /// nothing to detect.
  Future<bool> isCapturing() async {
    if (!Platform.isIOS) return false;
    try {
      return await _method.invokeMethod<bool>('isCaptured') == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> hasExternalDisplay() async {
    try {
      return await _method.invokeMethod<bool>('hasExternalDisplay') == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// How many screenshots this device has been caught taking, ever. Used to
  /// escalate from a warning to something firmer on repeat offences.
  int get screenshotCount => _queue?.countOf(CaptureEventType.screenshot) ?? 0;

  void _listen() {
    _nativeSub ??= _events.receiveBroadcastStream().listen(
      (raw) {
        final map = switch (raw) {
          final Map m => m.map((k, v) => MapEntry(k.toString(), v)),
          final String s => <String, dynamic>{'event': s},
          _ => <String, dynamic>{},
        };
        if (map.isEmpty) return;
        _emit(CaptureEvent.fromPlatform(map).withContent(_contentId));
      },
      onError: (Object e) {
        AppLogger.I.w('ScreenGuard: event channel error: $e');
      },
    );
  }

  void _emit(CaptureEvent e) {
    final stamped = e.withContent(_contentId);
    // Persist first: the queue is the durable record, the stream is just the
    // live notification and may have no listeners.
    unawaited(_queue?.add(stamped) ?? Future<void>.value());
    if (!_controller.isClosed) _controller.add(stamped);
  }

  Future<void> dispose() async {
    await disable();
    await _controller.close();
  }
}
