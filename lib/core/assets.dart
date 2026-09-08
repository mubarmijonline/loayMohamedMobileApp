/// Bundled image assets.
///
/// Every asset path in the app goes through this class. A path typed inline is
/// a runtime failure on one screen that nothing catches until someone opens
/// it; a constant here fails at compile time instead.
///
/// The four files are declared **individually** in `pubspec.yaml` rather than
/// as an `assets/images/` directory entry. A directory entry silently ships
/// whatever else lands in that folder later, and hides a typo'd filename until
/// runtime.
///
/// They are taken from the live site rather than the backend repo: the repo
/// copies of the hero have drifted to a taller crop (733x1456 against the
/// live 733x1193), so using them would show a different portrait from the
/// website. See `docs/mobile/THEME_SPEC.md` §7.
class AppAssets {
  const AppAssets._();

  /// Login hero. 733x1193, WebP. Same crop as the website hero.
  static const heroPortrait = 'assets/images/loay-instructor-733.webp';

  /// Narrower hero for small screens. 400x651, WebP.
  static const heroPortraitSmall = 'assets/images/loay-instructor-400.webp';

  /// Logo for the login screen and app bar. 256x256, WebP.
  static const logo = 'assets/images/loay-logo-256.webp';

  /// Logo for tight slots. 128x128, WebP.
  static const logoSmall = 'assets/images/loay-logo-128.webp';

  /// Full-bleed splash artwork. Matches the native launch screen so the
  /// handover between them is seamless.
  static const splash = 'assets/images/splash.png';

  /// Picks the hero variant that suits the viewport.
  ///
  /// The 400w file is a quarter of the bytes to decode; on a small phone the
  /// larger one is scaled down anyway.
  static String heroFor(double width) =>
      width < 420 ? heroPortraitSmall : heroPortrait;
}
