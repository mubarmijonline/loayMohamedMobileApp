import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Surface and text colours that resolve against the active brightness.
///
/// [AppColors] is a set of `static const` light-mode values, so a widget that
/// paints `AppColors.surface` renders white whatever the theme says. That is
/// why dark mode was broken across most of the app rather than on a few
/// screens: Material's own widgets flipped, ~370 hardcoded colours did not,
/// and the mismatch showed up as light cards stranded on a dark scaffold and,
/// where a painted surface met themed text, white on white.
///
/// The light palette below is defined **by reference to the existing
/// constants**, not by copying their hex values. Swapping a widget from
/// `AppColors.surface` to `context.palette.surface` therefore cannot change
/// anything in light mode — that is enforced by a test, and it is the property
/// that makes this refactor safe to do screen by screen.
@immutable
class AppPalette {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceTinted,
    required this.divider,
    required this.shadow,
    required this.textPrimary,
    required this.textSecondary,
    required this.textHint,
    required this.onBrand,
    required this.successBg,
    required this.warningBg,
    required this.dangerBg,
    required this.infoBg,
    required this.isDark,
  });

  /// Scaffold / page background.
  final Color background;

  /// Cards, sheets, list rows — anything that sits above [background].
  final Color surface;

  /// A surface that must read as raised *above* [surface] (nested cards,
  /// menus). In light mode this is white-on-grey; in dark, lighter navy.
  final Color surfaceAlt;

  /// Tinted fill for chips, icon tiles and inactive segments.
  final Color surfaceTinted;

  final Color divider;
  final Color shadow;

  final Color textPrimary;
  final Color textSecondary;
  final Color textHint;

  /// Text/icon colour on a brand-navy field. Constant across both modes —
  /// the navy header is navy in either theme.
  final Color onBrand;

  /// Soft semantic fills behind status badges. The foreground stays
  /// [AppColors.success] etc., which carries enough contrast on both.
  final Color successBg;
  final Color warningBg;
  final Color dangerBg;
  final Color infoBg;

  final bool isDark;

  /// Exactly today's light values, by reference. Do not inline the hex.
  static const light = AppPalette(
    background: AppColors.background,
    surface: AppColors.surface,
    surfaceAlt: AppColors.surface,
    surfaceTinted: AppColors.primarySurface,
    divider: AppColors.divider,
    shadow: AppColors.shadow,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textHint: AppColors.textHint,
    onBrand: AppColors.textOnPrimary,
    successBg: AppColors.successLight,
    warningBg: AppColors.warningLight,
    dangerBg: AppColors.dangerLight,
    infoBg: AppColors.infoLight,
    isDark: false,
  );

  /// Navy-tinted rather than neutral grey, so the dark theme still reads as
  /// this brand and not as a generic Material dark. The steps are deliberate:
  /// background is the darkest, surface sits one step above it so a card has
  /// an edge without needing a border, and surfaceAlt one above that.
  static const dark = AppPalette(
    background: Color(0xFF0A1120),
    surface: Color(0xFF141F35),
    surfaceAlt: Color(0xFF1B2A44),
    surfaceTinted: Color(0xFF22334F),
    divider: Color(0xFF2A3A57),
    shadow: Color(0x66000000),
    // Not pure white. #FFFFFF on a dark field haloes badly on OLED and is the
    // usual reason dark text looks "buzzy"; a hair off reads cleaner.
    textPrimary: Color(0xFFEDF1F7),
    textSecondary: Color(0xFFA3AEC2),
    textHint: Color(0xFF6E7A90),
    onBrand: AppColors.textOnPrimary,
    // The light-mode pastels (#E6F6F0 etc.) are near-white and would blaze on
    // a dark card, so dark uses a low-alpha wash of the same semantic hue.
    successBg: Color(0x2610B981),
    warningBg: Color(0x26D9930B),
    dangerBg: Color(0x26E05252),
    infoBg: Color(0x261E88E5),
    isDark: true,
  );

  static AppPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

extension AppPaletteX on BuildContext {
  /// `context.palette.surface` — the adaptive replacement for
  /// `AppColors.surface` and friends.
  AppPalette get palette => AppPalette.of(this);
}
