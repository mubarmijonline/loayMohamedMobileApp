"""Turns raw simulator captures into store-ready images.

    python3 tools/store_screenshots.py

Reads   store_assets/app-store/iphone-6.3/*.png  raw iPhone 16 Pro captures (1206 x 2622)
        store_assets/app-store/ipad-13/*.png     raw iPad Pro 13" captures  (2064 x 2752)
Writes  store_assets/app-store/iphone-6.9/*.png  Apple's required iPhone size (1320 x 2868)
        store_assets/google-play/phone/*.png     Play phone screenshots     (1080 x 1920)
        store_assets/google-play/tablet/*.png    Play tablet screenshots    (2064 x 2664)

The 6.9" set is the 6.3" capture scaled by 9.45%. The two screens have the
same shape to within 0.07%, so nothing is stretched. It exists because the
Mac was too full to install the app on a 6.9" simulator.

Every output is flattened to RGB: Google Play refuses screenshots with an alpha
channel. The iOS status bar and home indicator are cropped off before a capture
goes into a Play image, so no iOS system UI appears on the Android listing.
"""
import glob
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A = lambda *p: os.path.join(ROOT, 'store_assets', *p)

PHONE_RAW = A('app-store', 'iphone-6.3')
PHONE_69 = A('app-store', 'iphone-6.9')
TABLET_RAW = A('app-store', 'ipad-13')

# Brand fonts, as cached by google_fonts inside a simulator on this Mac.
FONT_FILES = glob.glob(os.path.expanduser(
    '~/Library/Developer/CoreSimulator/Devices/*/data/Containers/Data/Application'
    '/*/Library/Application Support/*.ttf'))

CAPTIONS = {
    '01': 'Your classes at a glance',
    '02': 'Every lesson, organised by topic',
    '03': 'Homework and quizzes in one list',
    '04': 'Never miss a new task or grade',
    '05': 'Marked work comes back with feedback',
    '06': 'Easy on the eyes, day or night',
}

NAVY_1, NAVY_2 = (27, 42, 68), (11, 20, 38)
# iPhone at 3x: 54 pt status bar, 34 pt home indicator.
PHONE_CROP_TOP, PHONE_CROP_BOTTOM = 162, 102
# iPad Pro 13" at 2x: 24 pt status bar, 20 pt home indicator.
TABLET_CROP_TOP, TABLET_CROP_BOTTOM = 48, 40


def font(prefix, size):
    for f in FONT_FILES:
        if os.path.basename(f).startswith(prefix):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def gradient(w, h):
    img = Image.new('RGB', (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            t = x / w * 0.35 + y / h * 0.65
            px[x, y] = tuple(int(NAVY_1[i] + (NAVY_2[i] - NAVY_1[i]) * t) for i in range(3))
    return img


def wrap(draw, text, fnt, max_w):
    words, lines, line = text.split(), [], ''
    for w in words:
        trial = (line + ' ' + w).strip()
        if draw.textlength(trial, font=fnt) <= max_w:
            line = trial
        else:
            lines.append(line)
            line = w
    lines.append(line)
    return lines


def rounded(img, radius):
    mask = Image.new('L', img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, img.width - 1, img.height - 1), radius=radius, fill=255)
    out = Image.new('RGBA', img.size)
    out.paste(img, (0, 0), mask)
    return out


def apple_69(raw_path, out_path):
    Image.open(raw_path).convert('RGB').resize((1320, 2868), Image.LANCZOS).save(out_path, optimize=True)


def play_phone(raw_path, caption, out_path):
    W, H = 1080, 1920
    raw = Image.open(raw_path).convert('RGB')
    shot = raw.crop((0, PHONE_CROP_TOP, raw.width, raw.height - PHONE_CROP_BOTTOM))
    sw = 780
    sh = round(shot.height * sw / shot.width)
    shot = rounded(shot.resize((sw, sh), Image.LANCZOS), 44)

    canvas = gradient(W, H).convert('RGBA')
    x, y = (W - sw) // 2, H - sh - 64
    shadow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x, y + 18, x + sw, y + sh + 18), radius=44, fill=(0, 0, 0, 140))
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(28)))
    canvas.alpha_composite(shot, (x, y))

    d = ImageDraw.Draw(canvas)
    f = font('BricolageGrotesque', 60)
    lines = wrap(d, caption, f, W - 140)
    ty = 96 if len(lines) > 1 else 128
    for line in lines:
        d.text(((W - d.textlength(line, font=f)) / 2, ty), line, font=f, fill=(255, 255, 255))
        ty += 74
    canvas.convert('RGB').save(out_path, optimize=True)


def play_tablet(raw_path, out_path):
    raw = Image.open(raw_path).convert('RGB')
    raw.crop((0, TABLET_CROP_TOP, raw.width, raw.height - TABLET_CROP_BOTTOM)).save(out_path, optimize=True)


def flatten_in_place(paths):
    for p in paths:
        im = Image.open(p)
        if im.mode != 'RGB':
            im.convert('RGB').save(p, optimize=True)


def main():
    phones = sorted(glob.glob(os.path.join(PHONE_RAW, '*.png')))
    tablets = sorted(glob.glob(os.path.join(TABLET_RAW, '*.png')))
    flatten_in_place(phones + tablets)
    for d in (PHONE_69, A('google-play', 'phone'), A('google-play', 'tablet')):
        os.makedirs(d, exist_ok=True)
    for p in phones:
        name = os.path.basename(p)
        apple_69(p, os.path.join(PHONE_69, name))
        play_phone(p, CAPTIONS.get(name[:2], ''), A('google-play', 'phone', name))
    for p in tablets:
        play_tablet(p, A('google-play', 'tablet', os.path.basename(p)))
    print(f'{len(phones)} iPhone and {len(tablets)} iPad captures processed')


if __name__ == '__main__':
    main()
