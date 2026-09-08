# Mobile Theme Spec — match the student portal

Every value here was read from
`frontend/student-portal/src/design-system/theme.ts`. That file is the
portal's whole theme; there is no second stylesheet layered on top of it.

## 0. There are two design systems in this repo. Use the right one.

| | Public marketing site | Student portal |
|---|---|---|
| File | `backend/static/css/loay-site.css` | `frontend/student-portal/src/design-system/theme.ts` |
| Primary | navy `#14304F`, blue `#1F7AE0` | blue `#1a73e8` |
| Accents | cyan `#7FE9F2`, amber `#F5A524` | Google green/yellow/red |
| Radius | 24px / 32px | 8px / 12px |
| Shadows | deep, long, `0 40px 80px -50px` | flat, `0 1px 2px` |
| Feel | marketing, editorial | Material, dense, utilitarian |

**The app is the portal, not the site.** Use the portal tokens for every
screen, login included. The one thing you take from the marketing site is the
hero photograph in §6 — put it on the login screen, but style the fields and
buttons around it with portal tokens. Mixing the two palettes in one screen
looks like two apps stitched together.

## 1. Palette

Light on the left, dark on the right.

| Role | Light | Dark |
|---|---|---|
| primary | `#1a73e8` | `#8ab4f8` |
| primary dark | `#1557b0` | `#669df6` |
| primary light | `#4285f4` | `#aecbfa` |
| on primary | `#ffffff` | `#202124` |
| secondary | `#5f6368` | `#c3cede` |
| secondary light / dark | `#80868b` / `#3c4043` | same |
| success | `#34a853` (light `#81c995`, dark `#0d652d`) | same |
| warning | `#fbbc04` (light `#fde293`, dark `#b06000`) | same |
| error | `#ea4335` (light `#f28b82`, dark `#a50e0e`) | same |
| **background** (scaffold) | `#f8f9fa` | `#111827` |
| **surface** (cards, bars, sheets) | `#ffffff` | `#182233` |
| text primary | `#202124` | `#f8fbff` |
| text secondary | `#5f6368` | `#c3cede` |
| text disabled | `#9aa0a6` | `#8793a6` |
| divider / border | `#dadce0` | `#304158` |
| hover | `#f1f3f4` | `#223149` |
| selected | `#e8f0fe` | `#1f3b68` |
| selected text | `#1967d2` | `#d7e6ff` |
| selected hover | `#d2e3fc` | `#284a7d` |

On success, warning and error, `contrastText` is white except **warning**,
which is `#202124`. Yellow with white text is unreadable, and the portal gets
this right.

Background and surface are different colours. A card that uses the scaffold
colour disappears; one that uses surface reads as raised without a shadow. Do
not collapse them into one.

### Status colours

From the portal's CSS baseline. Gradients, not flat fills.

| State | Value |
|---|---|
| available | `linear-gradient(180deg, #34c2b1, #2aa597)` |
| booked | `linear-gradient(180deg, #c9434b, #b1333b)` |
| live / selected | primary, flat |
| finished | `linear-gradient(180deg, #f59e0b, #b45309)` |
| blocked | text primary, flat |

## 2. Shadows

The portal uses exactly two elevations. Do not invent more.

- **shadow1** (cards, `elevation1`)
  light `0 1px 2px 0 rgba(60,64,67,0.10)`
  dark `0 1px 2px rgba(0,0,0,0.45)`
- **shadow2** (menus, dialogs, hovered buttons, `elevation2` and `3`)
  light `0 1px 3px 0 rgba(60,64,67,0.302), 0 4px 8px 3px rgba(60,64,67,0.149)`
  dark `0 4px 12px rgba(0,0,0,0.5)`

Cards carry shadow1 **and** a 1px border in the divider colour. Both, not
either.

## 3. Shape and metrics

| Token | Value |
|---|---|
| radius (default) | 8 |
| radius large (cards, dialogs) | 12 |
| top bar height | 56 |
| bottom nav height | 60 |
| button min height | 36 (small 32) |
| button padding | 8 / 24 (small 4 / 10) |
| icon button | 40 x 40 (small 32 x 32) |
| list item min height | 40, margin 2 / 8 |
| menu item min height | 40 |
| chip radius | 8, small height 24 |
| tab min height | 44, padding 8 / 14 |

## 4. Typography

Every style has `letterSpacing: 0`. Buttons are **not** uppercased.

| Style | Size | Weight | Line height |
|---|---|---|---|
| h1 | 36 | 500 | — |
| h2 | 28 | 500 | — |
| h3 | 24 | 500 | — |
| h4 | 20 | 500 | — |
| h5 | 18 | 500 | — |
| h6 | 16 | 500 | — |
| body1 | 15 | 400 | 1.5 |
| body2 | 14 | 400 | 1.5 |
| caption | 12 | 400 | 1.35 |
| button | — | 500 | — |
| table head | 12 | 700 | uppercase, letterSpacing 0.08em, secondary colour |

Headings are weight **500**, not 700. This is what makes the portal read as
Material rather than as a marketing page.

### Fonts, and one problem

The portal stack is `"Google Sans", "Inter", "Roboto", "Cairo"`.

**Google Sans is not publicly licensed.** It resolves on Google's own
properties and silently falls back to Inter everywhere else, which is what
your browser is already doing. Do not try to bundle it into the app.

For Flutter: **Inter** for Latin, **Cairo** for Arabic. Both are OFL and both
are on Google Fonts. Bundle them as assets rather than using the `google_fonts`
package's network fetch, so the first frame is not unstyled and the app works
offline. Cairo matters here, since Arabic is the default locale.

## 5. Flutter ThemeData

One function, both modes, mirroring `createAppTheme(mode)`.

```dart
import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();
  // Light
  static const primaryL = Color(0xFF1A73E8);
  static const primaryDarkL = Color(0xFF1557B0);
  static const primaryLightL = Color(0xFF4285F4);
  static const bgL = Color(0xFFF8F9FA);
  static const surfaceL = Color(0xFFFFFFFF);
  static const textL = Color(0xFF202124);
  static const textSecondaryL = Color(0xFF5F6368);
  static const textDisabledL = Color(0xFF9AA0A6);
  static const borderL = Color(0xFFDADCE0);
  static const hoverL = Color(0xFFF1F3F4);
  static const selectedL = Color(0xFFE8F0FE);
  static const selectedTextL = Color(0xFF1967D2);
  static const selectedHoverL = Color(0xFFD2E3FC);
  // Dark
  static const primaryD = Color(0xFF8AB4F8);
  static const primaryDarkD = Color(0xFF669DF6);
  static const primaryLightD = Color(0xFFAECBFA);
  static const bgD = Color(0xFF111827);
  static const surfaceD = Color(0xFF182233);
  static const textD = Color(0xFFF8FBFF);
  static const textSecondaryD = Color(0xFFC3CEDE);
  static const textDisabledD = Color(0xFF8793A6);
  static const borderD = Color(0xFF304158);
  static const hoverD = Color(0xFF223149);
  static const selectedD = Color(0xFF1F3B68);
  static const selectedTextD = Color(0xFFD7E6FF);
  static const selectedHoverD = Color(0xFF284A7D);
  // Shared
  static const success = Color(0xFF34A853);
  static const warning = Color(0xFFFBBC04);
  static const error = Color(0xFFEA4335);
}

ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;

  final primary = dark ? AppColors.primaryD : AppColors.primaryL;
  final onPrimary = dark ? AppColors.textL : Colors.white;
  final bg = dark ? AppColors.bgD : AppColors.bgL;
  final surface = dark ? AppColors.surfaceD : AppColors.surfaceL;
  final text = dark ? AppColors.textD : AppColors.textL;
  final textSecondary = dark ? AppColors.textSecondaryD : AppColors.textSecondaryL;
  final border = dark ? AppColors.borderD : AppColors.borderL;
  final selected = dark ? AppColors.selectedD : AppColors.selectedL;
  final selectedText = dark ? AppColors.selectedTextD : AppColors.selectedTextL;

  // Two elevations, the portal's shadow1 and shadow2.
  final shadow1 = <BoxShadow>[
    BoxShadow(
      color: dark ? Colors.black.withValues(alpha: 0.45) : const Color(0xFF3C4043).withValues(alpha: 0.10),
      offset: const Offset(0, 1),
      blurRadius: 2,
    ),
  ];

  const fontFamily = 'Inter';
  // Arabic falls through to Cairo. Register both in pubspec.yaml.
  const fallback = ['Cairo'];

  TextStyle heading(double size) => const TextStyle(
        fontFamily: fontFamily,
        fontFamilyFallback: fallback,
      ).copyWith(fontSize: size, fontWeight: FontWeight.w500, letterSpacing: 0, color: text);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: primary,
    onPrimary: onPrimary,
    secondary: textSecondary,
    onSecondary: Colors.white,
    error: AppColors.error,
    onError: Colors.white,
    surface: surface,
    onSurface: text,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    dividerColor: border,
    fontFamily: fontFamily,
    fontFamilyFallback: fallback,
    textTheme: TextTheme(
      displayLarge: heading(36),
      displayMedium: heading(28),
      displaySmall: heading(24),
      headlineMedium: heading(20),
      headlineSmall: heading(18),
      titleLarge: heading(16),
      bodyLarge: TextStyle(fontSize: 15, height: 1.5, letterSpacing: 0, color: text),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5, letterSpacing: 0, color: text),
      bodySmall: TextStyle(fontSize: 12, height: 1.35, letterSpacing: 0, color: textSecondary),
      labelLarge: const TextStyle(fontWeight: FontWeight.w500, letterSpacing: 0),
    ),
    appBarTheme: AppBarTheme(
      toolbarHeight: 56,
      backgroundColor: surface,
      foregroundColor: text,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: border)),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0, // the border plus shadow1 does the work
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 0,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w500, letterSpacing: 0),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: primary, width: 2),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      backgroundColor: dark ? AppColors.hoverD : AppColors.hoverL,
      side: BorderSide(color: border),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      selectedColor: selectedText,
      selectedTileColor: selected,
      minVerticalPadding: 8,
      iconColor: textSecondary,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 60,
      backgroundColor: surface,
      indicatorColor: selected,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: states.contains(WidgetState.selected) ? primary : textSecondary,
        ),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: primary,
      unselectedLabelColor: textSecondary,
      indicatorColor: primary,
      labelStyle: const TextStyle(fontWeight: FontWeight.w500, letterSpacing: 0),
    ),
  );
}
```

Two notes on that code: `CardThemeData` / `DialogThemeData` / `TabBarThemeData`
are the current names (the un-suffixed ones were deprecated), and
`withValues(alpha:)` replaced `withOpacity`. Both changed recently enough that
you should check them against the Flutter version in your `pubspec.lock`
rather than trusting the snippet.

## 6. Dark mode

The portal stores the choice under `localStorage['loay-student-color-mode']`,
values `light` or `dark`, and falls back to the OS preference when nothing is
stored.

Mirror it: `ThemeMode.system` by default, persisted override in
`SharedPreferences` under the same key name. Reading the same key name costs
nothing and means a support person can reason about both clients at once.

Offer the toggle in the app bar, as the portal does.

## 7. Login screen assets

### Yes, you can use the hero image. It is yours.

`backend/static/images/loay-instructor*` is a photograph of Loay Motawie on
his own platform, committed to this repo and already served publicly as the
hero of `loaymotawie.com`. There is no third-party licence in play. The only
thing to confirm is the obvious one: he is a real person, so his agreement to
appear in an App Store listing should be on the record. It is his platform, so
this is a formality, not an obstacle.

### The files

**Download them directly** — all public, no auth, `curl` or a browser:

| Asset | Link | Size |
|---|---|---|
| Hero, 733w | https://loaymotawie.com/static/images/loay-instructor-733.webp | 733x1193, 63 KB |
| Hero, 400w | https://loaymotawie.com/static/images/loay-instructor-400.webp | 400x651, 28 KB |
| Logo, 256 | https://loaymotawie.com/static/images/loay-logo-256.webp | 256x256, 12 KB |
| Logo, 128 | https://loaymotawie.com/static/images/loay-logo-128.webp | 128x128, 3 KB |
| Hero PNG fallback | https://loaymotawie.com/static/images/loay-instructor-fallback.png | 400x651, 250 KB |
| Logo PNG | https://loaymotawie.com/static/images/loay-logo.png | 500x500, 117 KB |

One command puts the whole set in place:

```bash
mkdir -p assets/images && cd assets/images && \
for f in loay-instructor-733.webp loay-instructor-400.webp \
         loay-logo-256.webp loay-logo-128.webp; do
  curl -fsSLO "https://loaymotawie.com/static/images/$f"
done
```

Then:

```yaml
flutter:
  assets:
    - assets/images/loay-instructor-733.webp
    - assets/images/loay-instructor-400.webp
    - assets/images/loay-logo-256.webp
    - assets/images/loay-logo-128.webp
```

List the four files rather than the `assets/images/` directory. A directory
entry silently ships whatever else lands in that folder later, and a typo'd
filename then fails at runtime instead of at build.

### Reference them through one constants class

`lib/core/assets.dart`:

```dart
class AppAssets {
  const AppAssets._();

  /// Login hero. 733x1193. Same crop as the website hero.
  static const heroPortrait = 'assets/images/loay-instructor-733.webp';

  /// Narrower hero for small screens. 400x651.
  static const heroPortraitSmall = 'assets/images/loay-instructor-400.webp';

  /// Logo for the login screen and app bar. 256x256.
  static const logo = 'assets/images/loay-logo-256.webp';

  /// Logo for tight slots. 128x128.
  static const logoSmall = 'assets/images/loay-logo-128.webp';
}
```

Used as:

```dart
Image.asset(AppAssets.heroPortrait, fit: BoxFit.contain)
```

No bare asset-path string appears anywhere else in the app. A path typed
inline is a runtime failure on one screen that nothing catches until someone
opens it.

Ship the WebP files and skip the PNGs. Android and iOS both decode WebP
natively, and the PNG fallback is four times the size for no benefit.

### Take them from the live site, not from this repo

The deployed images and the copies in `backend/static/images/` have drifted:

| File | Live | In repo |
|---|---|---|
| `loay-instructor-733.webp` | 733 x 1193, 63 KB | 733 x 1456, 72 KB |
| `loay-instructor-fallback.png` | 400 x 651, 250 KB | 400 x 795, 358 KB |
| `loay-logo-256.webp` | identical | identical |

It is not recompression, it is a different crop — the deployed hero is
shorter. **Use the live files**, so the app's login screen shows the same
portrait as the website.

The repo copies being stale is a separate problem worth a ticket: whatever
re-cropped those two images updated the server without committing the result,
so the next deploy from a clean checkout would silently revert the hero.

### Composing the login screen

The marketing site frames the portrait with two concentric rings and a tinted
disc behind it:

- disc: 430px, fill `#DCE8F8`
- ring: 500px, 1px solid `rgba(31,122,224,0.28)`
- outer ring: 570px, 1px **dashed** `rgba(31,122,224,0.18)`

Those are marketing-site tokens. If you want the login screen to echo the
site, reproduce the disc and rings behind the portrait and leave everything
else on portal tokens. If you would rather it read as the app, drop the rings
and put the portrait on the plain `#f8f9fa` background. Either is coherent;
what is not coherent is the site's 24px radii and deep shadows on the login
form fields while every other screen uses 8px and flat.

Do not carry over the site's `#14304F` navy or `#F5A524` amber. They appear
nowhere in the portal, and a login screen in a palette the rest of the app
never uses is the most common way an app ends up looking unfinished.

## 8. What I could not confirm

The faint blue grid at the edges of your screenshot is not in the portal
source. `loay-site.css`, the portal theme, `AppShell.tsx` and the SPA
`index.html` contain no grid or graph-paper background. It is either from a
newer build than this worktree has, or it is not part of the page at all.
Check a built `static/student_spa/assets/*.css` before trying to reproduce it.
