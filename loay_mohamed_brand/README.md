# Loay Mohamed — Brand Identity v1

Personal brand identity for Loay Mohamed (Teacher), built as a unified evolution of the LOAY brand persona — keeping the friendly smile, the plus-sign accents, and the navy palette, adapted for a personal teacher brand in both English and Arabic.

---

## Package contents

```
loay_mohamed_brand/
├── README.md                       (this file)
├── palette.json                    (color + type tokens for design tools)
├── brand_sheet_english.png         (poster — full English brand sheet)
├── brand_sheet_english.svg
├── brand_sheet_arabic.png          (poster — full Arabic brand sheet)
├── brand_sheet_arabic.svg
│
├── english/
│   ├── logo/
│   │   ├── primary_dark.{svg,png}      Wordmark on navy — primary use
│   │   ├── primary_light.{svg,png}     Wordmark on white — light backgrounds
│   │   ├── stacked_dark.{svg,png}      Two-line wordmark — narrow contexts
│   │   └── monogram.{svg,png}          LM monogram — favicons, watermarks
│   └── app_icons/
│       ├── icon_master.svg             Master app icon source
│       ├── icon_monogram_master.svg    Alternative LM-on-white app icon
│       ├── icon_1024.png               App Store
│       ├── icon_512.png                Play Store
│       ├── icon_180.png                iPhone @3x
│       ├── icon_167.png                iPad Pro
│       ├── icon_152.png                iPad
│       ├── icon_120.png                iPhone @2x / Settings @3x
│       ├── icon_87.png                 Settings @3x
│       ├── icon_80.png                 Spotlight @2x
│       ├── icon_76.png                 iPad legacy
│       ├── icon_60.png                 Spotlight / Settings
│       ├── icon_58.png                 Settings @2x
│       ├── icon_40.png                 Spotlight
│       ├── icon_29.png                 Settings
│       ├── icon_20.png                 Notification
│       ├── icon_monogram_1024.png      LM-on-white variant
│       └── icon_monogram_512.png
│
└── arabic/
    ├── logo/
    │   ├── primary_dark.{svg,png}      لؤي wordmark on navy + محمد subtitle
    │   ├── primary_light.{svg,png}     Light variant
    │   ├── stacked_dark.{svg,png}      لؤي / محمد stacked
    │   └── monogram.{svg,png}          ل (lam) monogram
    └── app_icons/
        ├── icon_master.svg             لم (lam-meem) icon — primary
        ├── icon_alt_master.svg         Single ل (lam) — alternative
        ├── icon_monogram_master.svg    لم on white
        ├── icon_1024.png ... icon_20.png   (full size set, لم primary)
        ├── icon_alt_1024.png, icon_alt_512.png   (single ل variant)
        ├── icon_monogram_1024.png, _512.png      (لم on white)
```

---

## Color palette

| Role | Hex | Notes |
|---|---|---|
| Navy (primary) | `#0F1B3D` | Backgrounds, primary brand color |
| Teal (accent 1) | `#2DD4BF` | Primary accent on dark; hand-paired with navy |
| Sky (accent 2) | `#60A5FA` | Secondary accent (the smaller plus) |
| Cyan (light variant accent) | `#06B6D4` | Use on light backgrounds where teal feels too soft |
| Pure white | `#FFFFFF` | Wordmark on dark, secondary background |
| Light bg | `#F8FAFC` | Soft surface, off-white |
| Border | `#E2E8F0` | Subtle dividers |
| Muted text | `#94A3B8` | Subtitles on dark |
| Body muted | `#64748B` / `#475569` | Subtitles on light |

Machine-readable tokens in `palette.json`.

---

## Typography

**Latin: Plus Jakarta Sans** — modern geometric sans, clean and friendly.
- Weights used: 400 (Regular), 500 (Medium), 700 (Bold), 800 (ExtraBold)
- Available free on Google Fonts: https://fonts.google.com/specimen/Plus+Jakarta+Sans

**Arabic: Noto Kufi Arabic** — geometric Kufi-style, pairs well with Plus Jakarta Sans.
- Weights used: 400 (Regular), 500 (Medium), 700 (Bold), 800 (ExtraBold)
- Available free on Google Fonts: https://fonts.google.com/specimen/Noto+Kufi+Arabic

---

## Usage guidelines

**Primary logo** — use on pitch decks, website hero, business cards, headed paper. Maintain at least 32px clearspace on all sides (equal to the height of the lowercase "o" in Loay).

**Stacked variant** — use in narrow vertical contexts (sidebar, mobile splash screen, video frames where horizontal space is limited).

**Monogram (LM / لم)** — use only when the wordmark is too small to be legible (≤24px height). Best for favicons, social avatars, watermarks.

**App icon** — the primary `icon_*.png` files are ready to drop straight into Xcode asset catalogs and Android `mipmap-*` folders. The monogram-on-white variant is provided as an alternative for products that need a white icon for contrast against system backgrounds.

**Arabic vs English** — the brand is symmetrical: same color palette, same smile motif, same plus accents. The plus accents are positioned upper-LEFT in English (leading into the LTR text) and upper-RIGHT in Arabic (leading into the RTL text). Use the language version that matches the audience.

**Don't:**
- Recolor the navy or change the smile shape
- Use heavy drop shadows, glows, or 3D effects on the wordmark
- Place the wordmark on busy photographic backgrounds without a flat overlay
- Stretch or distort the proportions
- Use a different font for "Loay" (the Plus Jakarta Sans 800 weight + tight letter-spacing is the brand)

---

## Production export notes

**iOS** — all sizes you need are provided. Drag the icon files into Xcode → Assets.xcassets → AppIcon set, matching by size. The 1024 goes in App Store Connect.

**Android** — use `icon_512.png` for Play Store. For adaptive icons, use Android Studio's Image Asset Studio:
- Foreground layer: extract the L (or لم) + smile + plus accents from `icon_master.svg` (delete the navy background rect)
- Background layer: solid `#0F1B3D` color

**Web** — use `icon_180.png` for `apple-touch-icon`, `icon_60.png` and `icon_40.png` for various favicon sizes. SVG monogram is good for theme-color favicons in modern browsers.

**Print** — use the SVG files. They scale to any size without quality loss. Convert to outlines/paths in your design tool before sending to print so the printer doesn't need the fonts installed.

---

## Tweak it yourself

The SVG files are the master source. Open any `.svg` in:
- **Figma** — paste-import via copy/paste of SVG markup, or File → Import
- **Inkscape** (free) — File → Open
- **Adobe Illustrator** — File → Open

All text remains editable (fonts must be installed). To "lock" the design, convert text to outlines.

---

Generated with care. Brand identity v1.
