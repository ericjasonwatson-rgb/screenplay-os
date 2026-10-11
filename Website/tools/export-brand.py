#!/usr/bin/env python3
"""Regenerate public brand sizes from the approved transparent source image.

Run `python3 Website/tools/export-brand.py --source path/to/new-mark.svg` to
replace the mark later; HTML and build paths do not change. PNG needs Pillow;
SVG input also needs CairoSVG for this one-time asset export.
"""
import argparse
import io
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=ROOT/'assets'/'ScreenplayOSLogoTransparent.png')
args = parser.parse_args()
source = args.source.resolve()
if source.suffix.lower() == '.svg':
    import cairosvg
    logo = Image.open(io.BytesIO(cairosvg.svg2png(url=str(source), output_width=360, output_height=360)))
else:
    logo = Image.open(source)
logo = logo.convert('RGBA')
out = ROOT/'assets'/'brand'
out.mkdir(exist_ok=True)
for name, size in [('favicon-32.png', 32), ('apple-touch-icon.png', 180), ('header-88.png', 88), ('hero-logo.webp', 640)]:
    image = logo.resize((size, size), Image.Resampling.LANCZOS)
    if size == 180:
        image = image.quantize(colors=96, method=Image.Quantize.FASTOCTREE)
    if name.endswith('.webp'):
        image.save(out/name, 'WEBP', quality=84, method=6)
    else:
        image.save(out/name, optimize=True)
        assert (out/name).stat().st_size < 30_000, name
    print(name, (out/name).stat().st_size, 'bytes')
