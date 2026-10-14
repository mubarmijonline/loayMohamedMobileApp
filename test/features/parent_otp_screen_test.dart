import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loay_mohamed_elearning/core/providers.dart';
import 'package:loay_mohamed_elearning/features/auth/presentation/parent_otp_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Verify with no code says what is missing instead of nothing',
      (tester) async {
    tester.view.physicalSize = const Size(820, 1180); // iPad Air 11-inch
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(
          home: ParentOtpScreen(
            phone: '+12025550124',
            expiresIn: 300,
            resendAfter: 60,
          ),
        ),
      ),
    );
    await tester.pump();

    // App Review, 3 October 2026: six placeholder dots read as a code already
    // filled in, and tapping Verify on the empty box did nothing at all.
    expect(find.text('••••••'), findsNothing);
    expect(find.text('6-digit code'), findsOneWidget);

    await tester.tap(find.text('Verify & Continue'));
    await tester.pump();
    expect(find.text('Enter the 6-digit code.'), findsOneWidget);

    // Typing clears the hint again.
    await tester.enterText(find.byType(TextField), '12');
    await tester.pump();
    expect(find.text('Enter the 6-digit code.'), findsNothing);

    // Dispose, which also cancels the one-second countdown timer.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
