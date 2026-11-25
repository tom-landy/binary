"""Generate the Binary app icons as SVG.

The mark is one bold orbit with a moon in its gap and a planet off-centre. It descends from the
original Binary artwork (mark-source.png) and is drawn in the same style as the other Warhound
app icons: heavy round-capped strokes, one gradient per shape, a dark background with a soft
glow of the accent colour.

    python3 Design/icon/generate.py /tmp/icons      # writes SVGs
    node Design/icon/render.js /tmp/icons           # renders each SVG to a 1024px PNG

Copy the PNGs into the asset catalogs as listed in README.md.
"""
import math
import os
import sys

S = 1024

# Geometry in design units; everything is scaled to FILL afterwards.
ORBIT = dict(rx=330, ry=265, tilt=-40, gap=(328, 32), stroke=96)   # gap centred on the upper-right end
MOON = dict(t=0, r=58)                    # sits in the gap, on the orbit path
PLANET = dict(t=180, inset=0.42, r=82)    # inside the orbit, toward the lower-left end

FILL = 0.74          # share of the canvas width or height the mark spans
WATCH_MARGIN = 0.43  # Watch icons are cropped to a circle; keep the mark within this radius (share of S)

EDGE = '#14151B'
MID = '#1C1C26'
VIOLET = dict(light='#FF9BC8', deep='#7448EE', glow='#3A2A66')   # the chosen palette

ACCENTS = {'Orange': 0xFA7A2E, 'Ember': 0xEB4742, 'Gold': 0xF5BD38, 'Lime': 0x8FD93D, 'Mint': 0x3DD69E,
           'Teal': 0x2EB8D1, 'Blue': 0x3D85FA, 'Pink': 0xF25794, 'Silver': 0xC7CCD6}


def _rgb(value):
    return ((value >> 16) & 255, (value >> 8) & 255, value & 255)


def _hex(rgb):
    return '#%02X%02X%02X' % tuple(max(0, min(255, round(c))) for c in rgb)


def _mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def accent_palette(value):
    """Same recipe as violet: a warm, lighter top fading to a deeper accent, and a glow of the accent."""
    base = _rgb(value)
    light = _mix(_mix(base, _rgb(0xFF9BC8), 0.3), (255, 255, 255), 0.25)
    deep = _mix(base, (0, 0, 0), 0.12)
    glow = _mix(_rgb(0x1C1C26), base, 0.22)
    return dict(light=_hex(light), deep=_hex(deep), glow=_hex(glow))


def _point(rx, ry, tilt, t):
    th, t = math.radians(tilt), math.radians(t)
    x, y = rx * math.cos(t), ry * math.sin(t)
    return x * math.cos(th) - y * math.sin(th), x * math.sin(th) + y * math.cos(th)


def shapes():
    """Orbit arc, moon and planet in design units, centred on their bounding box."""
    rx, ry, tilt = ORBIT['rx'], ORBIT['ry'], ORBIT['tilt']
    start, end = ORBIT['gap'][1], ORBIT['gap'][0]
    if end < start:
        end += 360
    arc = [_point(rx, ry, tilt, start + (end - start) * k / 240) for k in range(241)]
    moon = _point(rx, ry, tilt, MOON['t'])
    planet = _point(rx * PLANET['inset'], ry * PLANET['inset'], tilt, PLANET['t'])
    items = [('arc', arc, ORBIT['stroke']), ('dot', moon, MOON['r']), ('dot', planet, PLANET['r'])]
    xs, ys = [], []
    for kind, geo, size in items:
        if kind == 'arc':
            for x, y in geo:
                xs += [x - size / 2, x + size / 2]; ys += [y - size / 2, y + size / 2]
        else:
            xs += [geo[0] - size, geo[0] + size]; ys += [geo[1] - size, geo[1] + size]
    cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    span = max(max(xs) - min(xs), max(ys) - min(ys))
    centred = []
    for kind, geo, size in items:
        if kind == 'arc':
            centred.append((kind, [(x - cx, y - cy) for x, y in geo], size))
        else:
            centred.append((kind, (geo[0] - cx, geo[1] - cy), size))
    return centred, span


def _reach(items):
    """Furthest distance of any painted pixel from the centre, in design units."""
    far = 0
    for kind, geo, size in items:
        if kind == 'arc':
            far = max(far, max(math.hypot(x, y) for x, y in geo) + size / 2)
        else:
            far = max(far, math.hypot(*geo) + size)
    return far


def scale_for(fill=None, circle=None):
    items, span = shapes()
    if circle is not None:
        return items, circle * S / _reach(items)
    return items, fill * S / span


def svg(palette, background=True, tinted=False, fill=FILL, circle=None):
    items, k = scale_for(fill, circle)
    light, deep = palette['light'], palette['deep']
    if tinted:  # iOS tints greyscale artwork
        light, deep = '#FFFFFF', '#B8B8B8'
    body = []
    for kind, geo, size in items:
        if kind == 'arc':
            d = 'M' + ' L'.join(f'{x * k + S / 2:.1f},{y * k + S / 2:.1f}' for x, y in geo)
            body.append(f'<path d="{d}" fill="none" stroke="url(#mark)" stroke-width="{size * k:.1f}" '
                        f'stroke-linecap="round" stroke-linejoin="round"/>')
        else:
            body.append(f'<circle cx="{geo[0] * k + S / 2:.1f}" cy="{geo[1] * k + S / 2:.1f}" '
                        f'r="{size * k:.1f}" fill="url(#mark)"/>')
    # One vertical gradient per shape, light at the top, as in the family's icons.
    defs = (f'<linearGradient id="mark" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{light}"/><stop offset="1" stop-color="{deep}"/></linearGradient>')
    back = ''
    if background:
        defs += (f'<radialGradient id="bg" cx="50%" cy="48%" r="70%"><stop offset="0" stop-color="{palette["glow"]}"/>'
                 f'<stop offset=".55" stop-color="{MID}"/><stop offset="1" stop-color="{EDGE}"/></radialGradient>')
        back = f'<rect width="{S}" height="{S}" fill="url(#bg)"/>'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {S} {S}" width="{S}" height="{S}">'
            f'<defs>{defs}</defs>{back}{"".join(body)}</svg>')


def main(out):
    os.makedirs(out, exist_ok=True)
    files = {
        'binary-default.svg': svg(VIOLET),
        'binary-dark.svg': svg(VIOLET, background=False),
        'binary-tinted.svg': svg(VIOLET, background=False, tinted=True),
        'watch.svg': svg(VIOLET, circle=WATCH_MARGIN),
    }
    for name, value in ACCENTS.items():
        files[f'alt-{name}.svg'] = svg(accent_palette(value))
    for name, text in files.items():
        with open(os.path.join(out, name), 'w') as f:
            f.write(text)
    items, span = shapes()
    print(f'wrote {len(files)} SVGs to {out}')
    print(f'phone: mark spans {FILL:.0%} of the canvas, stroke {ORBIT["stroke"] * FILL / span:.1%}')
    watch_k = WATCH_MARGIN * S / _reach(items)
    print(f'watch: mark spans {span * watch_k / S:.0%}, furthest point {WATCH_MARGIN:.0%} of S from centre')


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'icons')
