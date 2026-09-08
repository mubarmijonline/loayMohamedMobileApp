import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loay_mohamed_elearning/core/design/app_colors.dart';
import 'package:loay_mohamed_elearning/core/design/app_palette.dart';

/// The safety property behind the dark-mode refactor.
///
/// Converting a widget from `AppColors.surface` to `context.palette.surface`
/// is only safe to do in bulk if the light palette is byte-identical to the
/// constants it replaces. If that ever stops being true, every converted
/// screen silently shifts colour in light mode — which is exactly the failure
/// that damaged the app once already.
void main() {
  group('light mode is unchanged by the palette', () {
    test('every light token still equals the constant it replaces', () {
      const p = AppPalette.light;
      expect(p.background, AppColors.background);
      expect(p.surface, AppColors.surface);
      expect(p.surfaceAlt, AppColors.surface);
      expect(p.surfaceTinted, AppColors.primarySurface);
      expect(p.divider, AppColors.divider);
      expect(p.shadow, AppColors.shadow);
      expect(p.textPrimary, AppColors.textPrimary);
      expect(p.textSecondary, AppColors.textSecondary);
      expect(p.textHint, AppColors.textHint);
      expect(p.onBrand, AppColors.textOnPrimary);
      expect(p.successBg, AppColors.successLight);
      expect(p.warningBg, AppColors.warningLight);
      expect(p.dangerBg, AppColors.dangerLight);
      expect(p.infoBg, AppColors.infoLight);
      expect(p.isDark, isFalse);
    });
  });

  group('dark mode is actually dark', () {
    test('surfaces step upward from the background', () {
      const p = AppPalette.dark;
      double lum(Color c) => c.computeLuminance();
      expect(lum(p.background), lessThan(lum(p.surface)),
          reason: 'a card must read above the scaffold without a border');
      expect(lum(p.surface), lessThan(lum(p.surfaceAlt)));
      expect(lum(p.surfaceAlt), lessThan(lum(p.surfaceTinted)));
      expect(lum(p.background), lessThan(0.05));
    });

    test('text carries enough contrast against its surface', () {
      const p = AppPalette.dark;
      // WCAG AA for body text is 4.5:1; large/secondary text 3:1.
      double ratio(Color fg, Color bg) {
        final a = fg.computeLuminance();
        final b = bg.computeLuminance();
        final hi = a > b ? a : b;
        final lo = a > b ? b : a;
        return (hi + 0.05) / (lo + 0.05);
      }

      expect(ratio(p.textPrimary, p.surface), greaterThan(4.5));
      expect(ratio(p.textPrimary, p.background), greaterThan(4.5));
      expect(ratio(p.textSecondary, p.surface), greaterThan(3.0));
      expect(ratio(p.textPrimary, p.surfaceAlt), greaterThan(4.5));
    });

    test('text is never the pure white that haloes on OLED', () {
      expect(AppPalette.dark.textPrimary, isNot(const Color(0xFFFFFFFF)));
    });

    test('semantic fills are washes, not the near-white light pastels', () {
      const p = AppPalette.dark;
      for (final c in [p.successBg, p.warningBg, p.dangerBg, p.infoBg]) {
        expect(c.a, lessThan(0.5),
            reason: 'an opaque pastel would blaze on a dark card');
      }
    });
  });

  group('resolution follows the theme, not the platform', () {
    testWidgets('of() picks dark under a dark theme', (tester) async {
      late AppPalette seen;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Builder(
            builder: (c) {
              seen = c.palette;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen.isDark, isTrue);
      expect(seen.surface, AppPalette.dark.surface);
    });

    testWidgets('of() picks light under a light theme', (tester) async {
      late AppPalette seen;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.light),
          home: Builder(
            builder: (c) {
              seen = c.palette;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen.isDark, isFalse);
      expect(seen.surface, AppColors.surface);
    });

    testWidgets(
        'a locally overridden light theme wins, as the auth screens '
        'rely on', (tester) async {
      // Login/register/OTP pin themselves to light with a nested Theme. That
      // must keep working — they are a branded surface, not a themed one.
      late AppPalette seen;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Theme(
            data: ThemeData(brightness: Brightness.light),
            child: Builder(
              builder: (c) {
                seen = c.palette;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(seen.isDark, isFalse);
    });
  });
}
