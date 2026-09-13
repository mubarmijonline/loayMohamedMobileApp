import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MainActivity lives in the Android namespace', () {
    // The manifest declares ".MainActivity", which Android resolves against
    // the Gradle namespace. A class in any other package is never found, and
    // the app crashes on launch — as every Android build did until this test.
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final namespace =
        RegExp(r'namespace\s*=\s*"([^"]+)"').firstMatch(gradle)!.group(1)!;
    final activity = File(
      'android/app/src/main/kotlin/'
      '${namespace.replaceAll('.', '/')}/MainActivity.kt',
    );

    expect(activity.existsSync(), isTrue, reason: 'missing ${activity.path}');
    expect(activity.readAsStringSync(), startsWith('package $namespace\n'));
  });
}
