import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/env/app_env.dart';
import 'core/logging/app_logger.dart';
import 'core/providers.dart';

Future<void> bootstrap(Flavor flavor) async {
  WidgetsFlutterBinding.ensureInitialized();
  final env = await AppEnv.load(flavor);
  // Dev/staging only: install a permissive HttpOverrides so `Image.network`
  // (and any other consumer of the global HttpClient) can load avatars and
  // other media served from the self-signed API host. Production keeps the
  // platform's strict TLS validation.
  if (env.allowInsecureTls && !kReleaseMode) {
    HttpOverrides.global = _DevHttpOverrides();
  }
  final prefs = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );

  // Arm capture protection.
  //
  // Deliberately NOT awaited. Android's FLAG_SECURE is already set natively in
  // MainActivity.onCreate, before any Dart runs, so nothing here is racing the
  // first frame. Blocking runApp on a platform-channel round trip only buys a
  // white screen if the channel is slow or the native side is missing.
  //
  // The authoritative check happens later, per player, in
  // playbackPermissionProvider — which asks the platform again rather than
  // trusting this call.
  unawaited(
    container.read(screenGuardProvider).enable().then((protected) {
      if (!protected) {
        AppLogger.I.e(
          'Screen protection is NOT active. Video playback will be refused. '
          'See lib/core/security/README.md.',
        );
      }
    }),
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const LoayMohamedApp(),
    ),
  );
}

class _DevHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}
