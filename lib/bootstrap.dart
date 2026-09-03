import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/env/app_env.dart';
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
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
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
