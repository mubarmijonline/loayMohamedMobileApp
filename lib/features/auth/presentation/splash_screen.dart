import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Full-bleed brand splash. Uses the Arabic primary_dark lockup on the
/// brand navy (#0F1B3D) so the logo fills the entire viewport.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  static const Color _brandNavy = Color(0xFF0F1B3D);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _brandNavy,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Show the brand image at its natural aspect ratio (matches the
          // native iOS launch screen) so the transition is seamless and the
          // logo isn't zoomed/cropped on the second frame.
          Center(
            child: Image.asset(
              'assets/images/splash.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ).animate().fadeIn(duration: 250.ms),
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
