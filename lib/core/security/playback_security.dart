import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Native bridge for playback-time protection events.
///
/// Method channel:    `app/playback_security`  (Dart → native)
/// Event channel:     `app/playback_security/events`  (native → Dart)
///
/// Events emitted (map with `event` and optional `meta`):
///   * `screenshot_attempt`              — user took a screenshot (iOS only,
///                                          Android blocks at OS level via
///                                          FLAG_SECURE).
///   * `recording_detected`              — UIScreen.isCaptured became true.
///   * `external_display_detected`       — secondary display connected /
///                                          AirPlay mirroring started.
///   * `external_display_disconnected`   — display disconnected.
///
/// All methods are no-ops if the native side is not wired (e.g. unit tests).
class PlaybackSecurity {
  PlaybackSecurity._();
  static final PlaybackSecurity I = PlaybackSecurity._();

  static const _method = MethodChannel('app/playback_security');
  static const _events = EventChannel('app/playback_security/events');

  Stream<Map<String, dynamic>>? _eventStream;

  /// Broadcast stream of native security events. Safe to listen multiple
  /// times — Dart-side broadcasts to all listeners.
  Stream<Map<String, dynamic>> get events {
    _eventStream ??= _events
        .receiveBroadcastStream()
        .map((raw) {
          if (raw is Map) {
            return raw.map((k, v) => MapEntry(k.toString(), v));
          }
          if (raw is String) return <String, dynamic>{'event': raw};
          return <String, dynamic>{};
        })
        .where((m) => (m['event']?.toString().isNotEmpty ?? false))
        .asBroadcastStream();
    return _eventStream!;
  }

  /// Enables platform-level capture protection while the player is mounted.
  /// On Android: FLAG_SECURE on the host Activity window. On iOS: starts the
  /// capture/screenshot/external-display observers and arms the
  /// app-switcher snapshot blur.
  Future<void> enable() async {
    try {
      await _method.invokeMethod<void>('enable');
    } on PlatformException {
      // Native side not registered (e.g. tests) — fail open silently.
    } on MissingPluginException {
      // Same.
    }
  }

  /// Tears down all protections. Always called from the player's dispose().
  Future<void> disable() async {
    try {
      await _method.invokeMethod<void>('disable');
    } on PlatformException {
      // Ignore.
    } on MissingPluginException {
      // Ignore.
    }
  }

  /// Returns true when iOS reports `UIScreen.main.isCaptured == true` (screen
  /// recording or AirPlay mirroring). Always false on Android — capture is
  /// blocked at the OS layer by FLAG_SECURE so there is nothing to detect.
  Future<bool> isCaptured() async {
    if (!Platform.isIOS) return false;
    try {
      final v = await _method.invokeMethod<bool>('isCaptured');
      return v == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// True when more than one display is currently attached (HDMI dongle,
  /// scrcpy, AirPlay mirror, etc.).
  Future<bool> hasExternalDisplay() async {
    try {
      final v = await _method.invokeMethod<bool>('hasExternalDisplay');
      return v == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
