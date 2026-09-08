import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/assets.dart';
import '../../../core/design/app_colors.dart';

/// Brand splash, shown while the session is resolved.
///
/// Carries the same portrait and logo as `loaymotawie.com` and the login
/// screen, so the app is recognisably the same product from the first frame.
/// Both assets are bundled, so nothing here waits on the network.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      // Matches the native launch screen so the handover is seamless.
      backgroundColor: AppColors.primary,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The portrait, bled off the bottom so it reads as a full-height
          // figure rather than a floating cut-out.
          Align(
            alignment: Alignment.bottomCenter,
            child: Image.asset(
              AppAssets.heroFor(size.width),
              height: size.height * 0.62,
              fit: BoxFit.contain,
              alignment: Alignment.bottomCenter,
              filterQuality: FilterQuality.high,
              // A missing asset must never be a blank launch screen.
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ).animate().fadeIn(duration: 400.ms).slideY(
                begin: 0.04,
                end: 0,
                duration: 500.ms,
                curve: Curves.easeOut,
              ),

          // Scrim so the logo and spinner stay legible over the photograph.
          // JUSTIFIED GRADIENT: a readability scrim over a photo, not brand
          // styling — see docs/mobile/THEME_SPEC.md on the portal being flat.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary.withValues(alpha: 0.80),
                  AppColors.primary.withValues(alpha: 0.20),
                  AppColors.primary.withValues(alpha: 0.80),
                ],
              ),
            ),
          ),

          Align(
            alignment: const Alignment(0, -0.45),
            child: Image.asset(
              AppAssets.logo,
              width: 116,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.school_rounded,
                size: 72,
                color: Colors.white,
              ),
            ),
          ).animate().fadeIn(duration: 350.ms),

          const Positioned(
            left: 0,
            right: 0,
            bottom: 56,
            child: Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
