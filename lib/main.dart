import 'bootstrap.dart';
import 'core/env/app_env.dart';

/// Default entry. Use `flutter run -t lib/main_dev.dart` for explicit flavors.
Future<void> main() => bootstrap(Flavor.dev);
