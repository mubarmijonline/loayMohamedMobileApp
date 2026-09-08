import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../logging/app_logger.dart';
import 'capture_event.dart';

/// Local, durable queue of capture events.
///
/// There is **no capture-report endpoint** in the verified API contract
/// (`docs/mobile/API_BRIEF.md`). Screenshot and recording events on iOS are
/// detections rather than preventions, so they have to go somewhere: dropping
/// them silently would make the whole detection layer pointless, and inventing
/// an endpoint would 404 and hide the gap.
///
/// So they land here. When the backend adds a route, [drain] gives you the
/// pending batch and [clear] confirms the handoff — that is the only change
/// needed on this side.
///
/// Deliberately stored in `SharedPreferences`, not secure storage: these are
/// telemetry breadcrumbs, not secrets, and they must survive a cold start.
class CaptureEventQueue {
  CaptureEventQueue(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'security.capture_events';

  /// Beyond this the oldest events are dropped. A device stuck in a recording
  /// loop must not grow this file without bound.
  static const maxEvents = 200;

  List<CaptureEvent> read() {
    final raw = _prefs.getStringList(_key) ?? const <String>[];
    final out = <CaptureEvent>[];
    for (final s in raw) {
      try {
        out.add(CaptureEvent.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {
        // A malformed row must not poison the queue.
      }
    }
    return out;
  }

  Future<void> add(CaptureEvent e) async {
    final raw = List<String>.from(_prefs.getStringList(_key) ?? const []);
    raw.add(jsonEncode(e.toJson()));
    // Keep the newest window.
    if (raw.length > maxEvents) {
      raw.removeRange(0, raw.length - maxEvents);
    }
    await _prefs.setStringList(_key, raw);
    AppLogger.I.w(
      'Capture event queued: ${e.type.name}'
      '${e.contentId == null ? '' : ' (content ${e.contentId})'}'
      ' — ${raw.length} pending, no endpoint to send to yet',
    );
  }

  /// How many times this device has been caught capturing, ever.
  ///
  /// Used to escalate: warn on the first offence, harden on repeats.
  int countOf(CaptureEventType type) =>
      read().where((e) => e.type == type).length;

  /// Everything pending, oldest first. Does not clear — call [clear] only
  /// after the backend has acknowledged the batch.
  List<CaptureEvent> drain() => read();

  Future<void> clear() => _prefs.remove(_key);
}
