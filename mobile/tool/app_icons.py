"""Draws every app icon from the mark's own paths.

The mark lives in lib/core/widgets/saba_logo.dart as SVG paths; this reads
them from there, so the phone's icon and the one inside the app cannot drift
apart. Run from mobile/ after changing the paths:

    python tool/app_icons.py

Writes the Android launcher icons (adaptive vector, and PNGs for phones older
than Android 8), the Android 12 launch mark, the iOS icon set and launch
image, and the web favicon and install icons. Needs Pillow.
"""
import math
import os
import re

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DART = os.path.join(HERE, 'lib', 'core', 'widgets', 'saba_logo.dart')

PURPLE = (0x6B, 0x3F, 0xA0)  # AppPalette.brand
WHITE = (0xFF, 0xFF, 0xFF)
AMBER = (0xF0, 0xA2, 0x2E)  # AppPalette.heat
CORNER = 18  # SabaMark.cornerRadius, in the 100 box


def dart_path(name):
    source = open(DART, encoding='utf-8').read()
    body = re.search(r'static const String %s =\s*((?:\'[^\']*\'\s*)+);' % name, source)
    return ''.join(re.findall(r"'([^']*)'", body.group(1))).strip()


BAG = dart_path('bagPath')
DIAMOND = dart_path('diamondPath')


# ------------------------------------------------------------ rasterising --

def _arc(x1, y1, rx, ry, fa, fs, x2, y2, n=64):
    """SVG endpoint arc (no rotation) as points, without the start."""
    x1p, y1p = (x1 - x2) / 2, (y1 - y2) / 2
    scale = x1p ** 2 / rx ** 2 + y1p ** 2 / ry ** 2
    if scale > 1:
        rx, ry = rx * math.sqrt(scale), ry * math.sqrt(scale)
    num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
    den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    k = math.sqrt(max(0.0, num / den)) if den else 0.0
    if fa == fs:
        k = -k
    cxp, cyp = k * rx * y1p / ry, -k * ry * x1p / rx
    cx, cy = cxp + (x1 + x2) / 2, cyp + (y1 + y2) / 2

    def angle(ux, uy, vx, vy):
        return math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)

    ux, uy = (x1p - cxp) / rx, (y1p - cyp) / ry
    start = angle(1, 0, ux, uy)
    sweep = angle(ux, uy, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not fs and sweep > 0:
        sweep -= 2 * math.pi
    if fs and sweep < 0:
        sweep += 2 * math.pi
    return [(cx + rx * math.cos(start + sweep * i / n),
             cy + ry * math.sin(start + sweep * i / n)) for i in range(1, n + 1)]


def polygons(d):
    """The subpaths of an M/L/A/Z path, as point lists."""
    tokens = re.findall(r'[MLAZ]|-?\d+(?:\.\d+)?', d)
    shapes, points, i, cur = [], [], 0, None
    while i < len(tokens):
        c = tokens[i]
        i += 1
        if c == 'M':
            if points:
                shapes.append(points)
            cur = (float(tokens[i]), float(tokens[i + 1]))
            points = [cur]
            i += 2
        elif c == 'L':
            cur = (float(tokens[i]), float(tokens[i + 1]))
            points.append(cur)
            i += 2
        elif c == 'A':
            rx, ry, _, fa, fs, x, y = map(float, tokens[i:i + 7])
            points += _arc(cur[0], cur[1], rx, ry, int(fa), int(fs), x, y)
            cur = (x, y)
            i += 7
    if points:
        shapes.append(points)
    return shapes


def draw(size, square, bag, diamond, *, rounded=True, bag_scale=1.0, ss=8):
    """The mark at [size] px, drawn 8x larger and scaled down for clean edges.

    [square] None leaves the background clear (a foreground layer).
    """
    big = size * ss
    image = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    pen = ImageDraw.Draw(image)
    unit = big / 100
    if square is not None:
        if rounded:
            pen.rounded_rectangle([0, 0, big - 1, big - 1], radius=CORNER * unit,
                                  fill=square)
        else:
            pen.rectangle([0, 0, big, big], fill=square)

    def place(p):
        return ((50 + (p[0] - 50) * bag_scale) * unit,
                (50 + (p[1] - 50) * bag_scale) * unit)

    outline, keyhole = polygons(BAG)
    pen.polygon([place(p) for p in outline], fill=bag)
    # The keyhole is a hole: the square shows through it, or nothing does.
    hole = Image.new('L', (big, big), 0)
    ImageDraw.Draw(hole).polygon([place(p) for p in keyhole], fill=255)
    clear = Image.new('RGBA', (big, big),
                      square + (255,) if square is not None else (0, 0, 0, 0))
    image.paste(clear, (0, 0), hole)
    pen = ImageDraw.Draw(image)
    pen.polygon([place(p) for p in polygons(DIAMOND)[0]], fill=diamond)
    return image.resize((size, size), Image.LANCZOS)


def save(image, *parts, rgb=False):
    path = os.path.join(HERE, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    (image.convert('RGB') if rgb else image).save(path)
    print('  ' + '/'.join(parts))


def hexcolour(rgb):
    return '#%02X%02X%02X' % rgb


# -------------------------------------------------------------- android ----

VECTOR = '''<?xml version="1.0" encoding="utf-8"?>
<!-- {note} Drawn by tool/app_icons.py from SabaMark's paths. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <group
        android:scaleX="{scale}"
        android:scaleY="{scale}"
        android:translateX="{offset}"
        android:translateY="{offset}">
{paths}
    </group>
</vector>
'''

SQUARE_PATH = ('M18,0 L82,0 A18,18 0 0 1 100,18 L100,82 A18,18 0 0 1 82,100 '
               'L18,100 A18,18 0 0 1 0,82 L0,18 A18,18 0 0 1 18,0 Z')


def vector_path(d, colour, even_odd=False):
    rule = '\n            android:fillType="evenOdd"' if even_odd else ''
    return ('        <path\n            android:fillColor="%s"%s\n'
            '            android:pathData="%s" />' % (hexcolour(colour), rule, d))


def write(text, *parts):
    path = os.path.join(HERE, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as handle:
        handle.write(text)
    print('  ' + '/'.join(parts))


def android():
    print('Android')
    res = ('android', 'app', 'src', 'main', 'res')
    # Android 8 and later: the bag over the purple, which the launcher masks
    # to its own shape. The 100 box fills the 72dp the mask shows.
    write(VECTOR.format(
        note='The launcher icon\'s front layer: the bag and its diamond.',
        scale=0.72, offset=18,
        paths='\n'.join([vector_path(BAG, WHITE, even_odd=True),
                         vector_path(DIAMOND, AMBER)])),
        *res, 'drawable', 'ic_launcher_foreground.xml')
    write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
''', *res, 'mipmap-anydpi-v26', 'ic_launcher.xml')
    # Android 12's own launch screen: the mark in white on the purple, inside
    # the circle it shows (72 of 108).
    write(VECTOR.format(
        note='The launch screen\'s mark, white on the purple.',
        scale=0.52, offset=26,
        paths='\n'.join([vector_path(SQUARE_PATH, WHITE),
                         vector_path(BAG, PURPLE, even_odd=True),
                         vector_path(DIAMOND, AMBER)])),
        *res, 'drawable', 'saba_splash_mark.xml')
    # Older phones: the whole icon as a picture.
    for folder, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                         ('xxhdpi', 144), ('xxxhdpi', 192)]:
        save(draw(size, PURPLE, WHITE, AMBER), *res, 'mipmap-' + folder,
             'ic_launcher.png')


# ------------------------------------------------------------------ ios ----

def ios():
    print('iOS')
    icons = os.path.join(HERE, 'ios', 'Runner', 'Assets.xcassets',
                         'AppIcon.appiconset')
    for name in sorted(os.listdir(icons)):
        if not name.endswith('.png'):
            continue
        size = Image.open(os.path.join(icons, name)).size[0]
        # Square and opaque: iOS rounds the corners itself, and the store
        # refuses an icon with an alpha channel.
        save(draw(size, PURPLE, WHITE, AMBER, rounded=False), 'ios', 'Runner',
             'Assets.xcassets', 'AppIcon.appiconset', name, rgb=True)
    for suffix, scale in [('', 1), ('@2x', 2), ('@3x', 3)]:
        save(draw(96 * scale, WHITE, PURPLE, AMBER), 'ios', 'Runner',
             'Assets.xcassets', 'LaunchImage.imageset',
             'LaunchImage%s.png' % suffix)


# ------------------------------------------------------------------ web ----

def web():
    print('Web')
    save(draw(32, PURPLE, WHITE, AMBER), 'web', 'favicon.png')
    for size in (192, 512):
        save(draw(size, PURPLE, WHITE, AMBER), 'web', 'icons',
             'Icon-%d.png' % size)
        # Maskable: full bleed, the bag inside the 80% the platform keeps.
        save(draw(size, PURPLE, WHITE, AMBER, rounded=False, bag_scale=0.8),
             'web', 'icons', 'Icon-maskable-%d.png' % size)


if __name__ == '__main__':
    android()
    ios()
    web()
