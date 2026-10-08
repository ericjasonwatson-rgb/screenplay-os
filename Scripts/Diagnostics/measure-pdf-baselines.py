"""Read-only PDF baseline inspection. Requires pypdf; page numbers are one-based.

Measures horizontal text in PDF user space, not font metadata or screenshot pixels.
Headers and paragraph gaps remain in the histogram; do not call every gap line pitch.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
from pypdf import PdfReader

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('pdf', type=Path)
parser.add_argument('--page', type=int, default=1)
args = parser.parse_args()
reader = PdfReader(args.pdf)
if not 1 <= args.page <= len(reader.pages):
    parser.error('page is outside the PDF')
ys = set()
def visit(text, cm, tm, font, size):
    if text.strip():
        # Compose text origin with current transform (handles Final Draft's flipped page).
        ys.add(round(tm[4] * cm[1] + tm[5] * cm[3] + cm[5], 3))
reader.pages[args.page - 1].extract_text(visitor_text=visit)
ordered = sorted(ys)
print(json.dumps({
    'file': args.pdf.name,
    'sha256': hashlib.sha256(args.pdf.read_bytes()).hexdigest(),
    'page_count': len(reader.pages), 'measured_page': args.page,
    'baseline_y_coordinates': ordered,
    'adjacent_baseline_deltas': dict(Counter(round(b-a, 3) for a,b in zip(ordered, ordered[1:]))),
}, indent=2))
