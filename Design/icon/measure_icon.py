"""Measure an app icon's mark against the Warhound icon spec.

Usage: python3 measure_icon.py icon.png    (a square PNG, ideally the 1024x1024 master)
Needs Pillow and NumPy. Treats saturated, bright pixels as the mark and the dark background as not.
"""
import sys
from collections import Counter

import numpy as np
from PIL import Image

TARGET_SPAN, TARGET_STROKE = 0.74, 0.10


def runs(line):
    out, start = [], None
    for i, on in enumerate(line):
        if on and start is None:
            start = i
        elif not on and start is not None:
            out.append(i - start)
            start = None
    if start is not None:
        out.append(len(line) - start)
    return out


def measure(path):
    img = np.asarray(Image.open(path).convert('RGB')).astype(float) / 255
    size = img.shape[1]
    hi, lo = img.max(-1), img.min(-1)
    sat = (hi - lo) / np.maximum(hi, 1e-6)
    mark = (sat > 0.35) & (hi > 0.35)
    ys, xs = np.where(mark)
    span = max(xs.max() - xs.min(), ys.max() - ys.min()) / size
    centre = ((xs.max() + xs.min()) / 2 / size - 0.5, (ys.max() + ys.min()) / 2 / size - 0.5)
    # Stroke: the most common width of the mark across rows and columns. Arcs dominate, dots are rarer.
    widths = [w for row in mark for w in runs(row)] + [w for col in mark.T for w in runs(col)]
    widths = [w for w in widths if w > size * 0.02]
    stroke = Counter(round(w / (size * 0.005)) for w in widths).most_common(1)[0][0] * 0.005
    return span, stroke, centre


if __name__ == '__main__':
    span, stroke, (cx, cy) = measure(sys.argv[1])
    ok = lambda value, target, tol: 'OK' if abs(value - target) <= tol else 'ADJUST'
    print(f'mark span   {span:.0%}   target {TARGET_SPAN:.0%} ±2%   {ok(span, TARGET_SPAN, 0.02)}')
    print(f'stroke      {stroke:.1%}  target {TARGET_STROKE:.0%} ±1%  {ok(stroke, TARGET_STROKE, 0.01)}')
    print(f'off-centre  x {cx:+.1%}, y {cy:+.1%}   target within ±1.5%   '
          f'{"OK" if max(abs(cx), abs(cy)) <= 0.015 else "ADJUST"}')
