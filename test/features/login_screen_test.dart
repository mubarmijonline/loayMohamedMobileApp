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
    // A phone-sized but tall viewport, so the entire login form is built and
    // the submit button is reachable without scroll gymnastics.
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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

    // Tap submit with empty fields. The button sits below the fold on the
    // default 800px test surface, hence the taller viewport set up above.
    final submit = find.text('Sign in');
    expect(submit, findsOneWidget);
    await tester.tap(submit);
    await tester.pump();

    // Both fields fail validation, so the form never submits and the
    // controller stays unauthenticated.
    expect(find.text('Mobile is required'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    expect(container.read(authControllerProvider).status, AuthStatus.unknown);
    expect(container.read(authControllerProvider).loading, isFalse);

    // Drain pending animation timers before tear-down.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
