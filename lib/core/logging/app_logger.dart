import 'package:logger/logger.dart';

import '../env/app_env.dart';

class AppLogger {
  AppLogger._();
  static final Logger I = Logger(
    level: AppEnv.I.enableLogging ? Level.debug : Level.warning,
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 6,
      colors: true,
      printEmojis: false,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );
}
