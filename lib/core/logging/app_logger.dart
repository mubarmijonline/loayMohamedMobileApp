import 'package:logger/logger.dart';

import '../env/app_env.dart';

class AppLogger {
  AppLogger._();

  /// The app logger.
  ///
  /// Resolves its level from [AppEnv] when the environment is loaded, and
  /// falls back to warnings-only when it is not.
  ///
  /// The fallback matters: `AppEnv.I` throws until `bootstrap()` has run, and
  /// this getter is reached from the security core, from tests, and from any
  /// failure path that runs *before* or *during* env loading. Letting the
  /// logger throw there turns a log line into a crash, and hides the very
  /// error it was trying to report.
  static final Logger I = Logger(
    level: _resolveLevel(),
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 6,
      colors: true,
      printEmojis: false,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

  static Level _resolveLevel() {
    try {
      return AppEnv.I.enableLogging ? Level.debug : Level.warning;
    } on StateError {
      // Env not loaded yet (early bootstrap, or a unit test). Warnings only —
      // never verbose, since a release build must not log response bodies.
      return Level.warning;
    }
  }
}
