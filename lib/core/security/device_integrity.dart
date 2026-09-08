import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart';

import '../logging/app_logger.dart';

/// Root / jailbreak detection.
///
/// On a compromised device every client-side protection in this directory is
/// defeatable — `FLAG_SECURE` can be patched out, the secure canvas can be
/// hooked, and the WebView can be instrumented. So on such a device we refuse
/// **video playback** specifically. Everything else in the app keeps working:
/// a student on a rooted phone can still read announcements, submit homework
/// and check their marks.
///
/// Implemented over the existing `app/playback_security` channel rather than
/// adding `freerasp` / `flutter_jailbreak_detection`. Those are good packages,
/// but their APIs move between majors and a wrong call compiles cleanly and
/// silently reports "clean" forever — the exact failure mode that matters most
/// here. Owning the check means it cannot drift silently.
///
/// This is a heuristic, and a determined attacker with a hooking framework
/// will pass it. It raises the cost; it does not make the device trustworthy.
class DeviceIntegrity {
  DeviceIntegrity({MethodChannel? method})
      : _method = method ?? const MethodChannel('app/playback_security');

  final MethodChannel _method;

  bool? _cached;

  /// Whether the device looks rooted / jailbroken.
  ///
  /// Cached for the process lifetime: the answer cannot change without a
  /// reboot, and re-running the filesystem probes on every player open is
  /// wasted I/O.
  ///
  /// **Fails open on error.** A detection bug must not lock every student out
  /// of their lessons; the watermark still makes any leak attributable.
  Future<bool> isCompromised() async {
    final cached = _cached;
    if (cached != null) return cached;

    // A debug build runs on emulators and dev devices that trip every root
    // heuristic there is. Gating playback there would make the app
    // undevelopable, and a debug build is not what ships.
    if (kDebugMode) {
      _cached = false;
      return false;
    }

    try {
      final v = await _method.invokeMethod<bool>('isDeviceCompromised');
      _cached = v == true;
      if (_cached!) {
        AppLogger.I.e('DeviceIntegrity: compromised device — playback refused');
      }
      return _cached!;
    } on MissingPluginException {
      _cached = false;
      return false;
    } on PlatformException catch (e) {
      AppLogger.I.w('DeviceIntegrity: check failed (${e.code}) — failing open');
      _cached = false;
      return false;
    }
  }

  /// Test seam.
  void debugOverride(bool? value) => _cached = value;
}
