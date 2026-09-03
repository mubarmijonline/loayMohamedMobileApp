import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTypography {
  AppTypography._();

  /// The single typeface used everywhere in the app. Plus Jakarta Sans is a
  /// modern geometric sans-serif used widely in education / SaaS products in
  /// 2024–2026. Exposed so the theme can install it as the default
  /// `fontFamily`, which makes even inline `TextStyle(...)` calls inherit it.
  static String get fontFamily => GoogleFonts.plusJakartaSans().fontFamily!;

  static TextTheme build(Brightness brightness) {
    final base = brightness == Brightness.dark
        ? Typography.whiteMountainView
        : Typography.blackMountainView;

    // Single typeface across the app for a cleaner, modern look.
    final body = GoogleFonts.plusJakartaSansTextTheme(base);
    final heading = GoogleFonts.plusJakartaSansTextTheme(base);

    return body
        .copyWith(
          // ── Display: huge stat numbers (2.3x, 12, +12%) ─────────────────
          displayLarge: heading.displayLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            height: 1.15,
          ),
          displayMedium: heading.displayMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            height: 1.15,
          ),
          displaySmall: heading.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            height: 1.2,
          ),
          // ── Headline: section headers (Resume Course, Progress Snap) ───
          headlineLarge: heading.headlineLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            height: 1.2,
          ),
          headlineMedium: heading.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            height: 1.2,
          ),
          headlineSmall: heading.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            height: 1.25,
          ),
          // ── Title: card titles, names ──────────────────────────────────
          titleLarge: heading.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            height: 1.3,
            letterSpacing: -0.2,
          ),
          titleMedium: heading.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 17,
            height: 1.3,
          ),
          titleSmall: heading.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            height: 1.35,
          ),
          // ── Body: descriptions, paragraphs ─────────────────────────────
          bodyLarge: body.bodyLarge?.copyWith(
            fontWeight: FontWeight.w400,
            fontSize: 15,
            height: 1.5,
          ),
          bodyMedium: body.bodyMedium?.copyWith(
            fontWeight: FontWeight.w400,
            fontSize: 14,
            height: 1.5,
          ),
          bodySmall: body.bodySmall?.copyWith(
            fontWeight: FontWeight.w400,
            fontSize: 13,
            height: 1.5,
          ),
          // ── Labels: buttons, pills, nav ────────────────────────────────
          labelLarge: heading.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            height: 1.3,
            letterSpacing: 0.1,
          ),
          labelMedium: heading.labelMedium?.copyWith(
            fontWeight: FontWeight.w500,
            fontSize: 13,
            height: 1.35,
          ),
          labelSmall: heading.labelSmall?.copyWith(
            fontWeight: FontWeight.w500,
            fontSize: 11,
            height: 1.35,
            letterSpacing: 0.3,
          ),
        )
        .apply(
          bodyColor: brightness == Brightness.dark
              ? AppColors.surface
              : AppColors.textPrimary,
          displayColor: brightness == Brightness.dark
              ? AppColors.surface
              : AppColors.textPrimary,
        );
  }
}
