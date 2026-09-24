import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTypography {
  AppTypography._();

  /// Body copy — `--mj-font`. Installed as the theme's default `fontFamily`
  /// so even inline `TextStyle(...)` calls inherit it.
  static String get fontFamily => GoogleFonts.dmSans().fontFamily!;

  /// Headings, buttons, chips, stat numerals, card names — `--mj-font-display`.
  static String get displayFamily =>
      GoogleFonts.bricolageGrotesque().fontFamily!;

  /// Kickers, eyebrows and spec labels — `--mj-font-mono`.
  static String get monoFamily => GoogleFonts.jetBrainsMono().fontFamily!;

  /// Arabic / RTL — `--mj-font-ar`.
  ///
  /// Wired as a *fallback* rather than a separate theme: neither Bricolage
  /// Grotesque nor DM Sans ships Arabic glyphs, so without this an Arabic
  /// string renders as tofu boxes. As a fallback it kicks in per-glyph, which
  /// also handles a mixed Arabic/Latin line correctly.
  static String get arabicFamily => GoogleFonts.notoKufiArabic().fontFamily!;

  /// Arabic first, then the platform emoji fonts, so an emoji a teacher types
  /// into an announcement has somewhere to come from. Flag emoji are beyond
  /// rescue on iOS 26 — the country picker spells the country out instead.
  static List<String> get fallbacks =>
      [arabicFamily, 'Apple Color Emoji', 'Noto Color Emoji'];

  /// A monospaced label style for kickers and eyebrows.
  static TextStyle kicker({Color? color}) => GoogleFonts.jetBrainsMono(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.8,
        height: 1.4,
        color: color,
      );

  static TextTheme build(Brightness brightness) {
    final base = brightness == Brightness.dark
        ? Typography.whiteMountainView
        : Typography.blackMountainView;

    // Two typefaces with distinct jobs: Bricolage Grotesque carries the
    // display/title/label roles (headings, buttons, chips, stat numerals),
    // DM Sans carries body copy. Both fall back to Noto Kufi Arabic so Arabic
    // text renders instead of tofu.
    final body =
        GoogleFonts.dmSansTextTheme(base).apply(fontFamilyFallback: fallbacks);
    final heading = GoogleFonts.bricolageGrotesqueTextTheme(base)
        .apply(fontFamilyFallback: fallbacks);

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
          // Kickers, eyebrows and spec labels — the mono role. Slightly wider
          // tracking because JetBrains Mono is already monospaced and reads
          // tight at this size.
          labelSmall: GoogleFonts.jetBrainsMono(
            textStyle: heading.labelSmall,
            fontWeight: FontWeight.w500,
            fontSize: 11,
            height: 1.35,
            letterSpacing: 0.5,
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
