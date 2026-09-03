import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loay_mohamed_elearning/core/design/app_theme.dart';
import 'package:loay_mohamed_elearning/features/auth/presentation/login_screen.dart';
import 'package:loay_mohamed_elearning/features/auth/presentation/auth_controller.dart';
import 'package:loay_mohamed_elearning/core/providers.dart';
import 'package:loay_mohamed_elearning/core/storage/kv_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Login form shows validation errors when submitted empty',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const LoginScreen(),
        ),
      ),
    );
    // Let initial animations settle.
    await tester.pump(const Duration(seconds: 1));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(LoginScreen)),
    );
    expect(container.read(authControllerProvider).status, AuthStatus.unknown);
    expect(container.read(kvCacheProvider), isA<KvCache>());

    // Tap Sign In with empty fields.
    await tester.tap(find.text('Sign In'));
    await tester.pump();

    expect(find.text('Email or mobile is required'), findsOneWidget);
    expect(find.text('Password must be at least 6 characters'), findsOneWidget);

    // Drain pending animation timers before tear-down.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
