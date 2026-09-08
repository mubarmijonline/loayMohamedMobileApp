import 'package:flutter/material.dart';

/// Brand color tokens — Loay Mohamed E-Learning (student app).
/// Identity per design brief: deep **navy** with **gold** accents.
class AppColors {
  AppColors._();

  // Brand — navy from the Loay Mohamed logo background.
  static const Color primary = Color(0xFF1B2A44);
  static const Color primaryLight = Color(0xFF2C436B);
  static const Color primaryDark = Color(0xFF0B1426);
  static const Color primarySurface =
      Color(0xFFE8ECF3); // tinted bg behind primary

  // Accent — bright cyan from the logo "eye" detail.
  static const Color accent = Color(0xFF1FC8E8);
  static const Color accentLight = Color(0xFF7FE0F2);
  static const Color accentDark = Color(0xFF0F8FAB);

  // Compatibility alias (legacy code referenced AppColors.secondary).
  static const Color secondary = accent;

  // Neutrals
  static const Color surface = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF4F4F7);
  static const Color divider = Color(0xFFEDEDF2);
  static const Color shadow = Color(0x14000000);

  static const Color textPrimary = Color(0xFF0E1116);
  static const Color textSecondary = Color(0xFF8A8E99);
  static const Color textHint = Color(0xFFB6BAC2);
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color textOnAccent = Color(0xFFFFFFFF);

  // Semantic
  // Emerald rather than the old forest green. #2E7D32 next to a bright
  // amber read as a traffic light; this sits with the brand cyan.
  static const Color success = Color(0xFF0E9F6E);
  static const Color successLight = Color(0xFFE6F6F0);
  // Muted amber. The old #F57F17 was the loudest colour on every screen
  // and pulled attention away from the content.
  static const Color warning = Color(0xFFC2760B);
  static const Color warningLight = Color(0xFFFDF3E2);
  static const Color danger = Color(0xFFD64545);
  static const Color dangerLight = Color(0xFFFFF0F0);
  static const Color info = Color(0xFF1565C0);
  static const Color infoLight = Color(0xFFE3F2FD);

  // Status pairs (background, text) used by StatusBadge
  static const Color pendingBg = Color(0xFFFFF3E0);
  static const Color pendingText = Color(0xFFE65100);
  static const Color approvedBg = Color(0xFFE8F5E9);
  static const Color approvedText = Color(0xFF2E7D32);
  static const Color cancelledBg = Color(0xFFF3E5F5);
  static const Color cancelledText = Color(0xFF7B1FA2);
  static const Color rejectedBg = Color(0xFFFFEBEE);
  static const Color rejectedText = Color(0xFFC62828);

  // Legacy ink* aliases kept so older screens keep compiling.
  static const Color ink900 = textPrimary;
  static const Color ink800 = Color(0xFF1A1D24);
  static const Color ink700 = Color(0xFF3A3F4A);
  static const Color ink500 = textSecondary;
  static const Color ink400 = textHint;
  static const Color ink300 = Color(0xFFD7D9E0);
  static const Color ink200 = divider;
  static const Color ink100 = Color(0xFFF7F7FA);
  static const Color primarySoft = primarySurface;

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1B2A44), Color(0xFF152238), Color(0xFF0B1426)],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accentLight],
  );

  static const LinearGradient splashGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF2C436B), Color(0xFF1B2A44), Color(0xFF0B1426)],
  );

  /// Soft tinted gradient used for course thumbnails and "resume" cards.
  static const LinearGradient lavenderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE8ECF3), Color(0xFFCFD7E5)],
  );

  // Compat aliases used elsewhere.
  static const LinearGradient brandGradient = primaryGradient;
  static const LinearGradient blueGradient = primaryGradient;
  static const LinearGradient cyanGradient = primaryGradient;

  /// Dark navy used in the brand logo. Used as the auth screens background.
  static const Color brandNavy = Color(0xFF152238);
  static const Color brandNavyDark = Color(0xFF0B1426);
  static const LinearGradient authBackgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1B2A44), brandNavy, brandNavyDark],
  );
}
