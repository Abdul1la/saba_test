"""The demo's product photos: one folder in, small square files out.

Put photos in saba_test/demo-photos/, named after their category:

    phones.jpg  laptops.png  headphones.jpg  smartwatches.jpg
    cameras.jpg  home-appliances.jpg  accessories.webp

and more of a category as phones-2.jpg, phones-3.jpg, ... Any size or shape.
Then, from mobile/:

    python tool/demo_photos.py        (needs Pillow: pip install pillow)

Each photo is cropped square from its centre, shrunk to 800x800 and
compressed into assets/images/products/<category>-<n>.jpg, and
lib/core/mock/demo_photos.dart is rewritten with how many each category
has. The products of a category take its photos in turn; the first is the
category's own picture. A category with no photo in the folder keeps the
files it already has.
"""
import re
import sys
from pathlib import Path

from PIL import Image, ImageOps

MOBILE = Path(__file__).resolve().parents[1]
SOURCE = MOBILE.parent / 'demo-photos'
OUT = MOBILE / 'assets' / 'images' / 'products'
COUNTS = MOBILE / 'lib' / 'core' / 'mock' / 'demo_photos.dart'

GROUPS = ('phones', 'laptops', 'headphones', 'smartwatches', 'cameras',
          'home-appliances', 'accessories')
SIZE = 800
MAX_BYTES = 150 * 1024
NAME = re.compile(r'^(%s)(?:-(\d+))?$' % '|'.join(map(re.escape, GROUPS)))
KINDS = {'.jpg', '.jpeg', '.png', '.webp'}


def square(path):
    image = ImageOps.exif_transpose(Image.open(path))
    if image.mode != 'RGB':
        # A transparent PNG goes on white, as a shop photographs on white.
        flat = Image.new('RGB', image.size, 'white')
        rgba = image.convert('RGBA')
        flat.paste(rgba, mask=rgba.split()[3])
        image = flat
    return ImageOps.fit(image, (SIZE, SIZE), Image.LANCZOS)


def save_small(image, target):
    for quality in (82, 78, 74, 70):
        image.save(target, 'JPEG', quality=quality, optimize=True,
                   progressive=True)
        if target.stat().st_size <= MAX_BYTES:
            return


def main():
    found = {group: [] for group in GROUPS}
    for path in sorted(SOURCE.glob('*')) if SOURCE.is_dir() else []:
        match = NAME.match(path.stem.lower())
        if path.suffix.lower() not in KINDS or not match:
            print('skipped (name it after a category):', path.name)
            continue
        found[match.group(1)].append((int(match.group(2) or 1), path))

    OUT.mkdir(parents=True, exist_ok=True)
    for group, photos in found.items():
        if not photos:
            continue
        for old in OUT.glob(group + '-*.jpg'):
            old.unlink()
        for number, (_, path) in enumerate(sorted(photos), start=1):
            target = OUT / ('%s-%d.jpg' % (group, number))
            save_small(square(path), target)
            print('%s <- %s (%d KB)' % (target.name, path.name,
                                         target.stat().st_size // 1024))

    counts = {group: len(list(OUT.glob(group + '-*.jpg'))) for group in GROUPS}
    lines = ''.join("  '%s': %d,\n" % item for item in counts.items())
    COUNTS.write_text(
        '// Written by tool/demo_photos.py. Add a photo to saba_test/demo-photos/\n'
        '// and run it again rather than editing this.\n'
        '\n'
        '/// How many photos each demo category has in assets/images/products/.\n'
        'const Map<String, int> demoPhotoCounts = <String, int>{\n'
        + lines + '};\n',
        encoding='utf-8', newline='\n')
    print('counts:', counts)
    missing = [group for group, count in counts.items() if count == 0]
    if missing:
        print('no photo yet for:', ', '.join(missing))
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
