"""Generate the Binary app icons as SVG.

The mark is a vector rebuild of the original orbit artwork (mark-source.png): two open
orbits, a planet and a moon. The geometry below was fitted to that artwork, then made
rounder (ROUNDNESS) with a lighter outer orbit and a larger planet.

    python3 Design/icon/generate.py /tmp/icons      # writes SVGs
    node Design/icon/render.js /tmp/icons           # renders each SVG to a 1024px PNG

Copy the PNGs into the asset catalogs as listed in README.md.
"""
import math
import os
import sys

# Fitted to mark-source.png on a 1024 canvas. Angles in degrees.
OUTER = dict(ra=339.94, ratio=0.5766, arc=(213.94, 145.97 + 360), stroke=54.92)
INNER = dict(ra=149.91, ratio=0.5871, arc=(58.14, 301.87), stroke=48.37)
# Dot radii; positions come from _dot_positions().
MOON = dict(r=39.94)
PLANET = dict(r=62.10)

ROUNDNESS = 0.74        # short/long axis of the outer orbit (original 0.58)
TILT = -40              # degrees
OUTER_WEIGHT = 0.7      # outer orbit stroke relative to the original
PLANET_SCALE = 1.3
FILL = 0.79             # share of the canvas the mark spans (Apple's grid allows about 80%)
WATCH_FILL = 0.69       # Watch icons are cropped to a circle

BACKGROUND = ('#272040', '#100D19')
PLANET_COLOR = '#F3F0F7'
VIOLET = dict(light='#FF8FC0', deep='#7E54F0', moon='#FFC2DD')   # the chosen palette

ACCENTS = {'Orange': 0xFA7A2E, 'Ember': 0xEB4742, 'Gold': 0xF5BD38, 'Lime': 0x8FD93D, 'Mint': 0x3DD69E,
           'Teal': 0x2EB8D1, 'Blue': 0x3D85FA, 'Pink': 0xF25794, 'Silver': 0xC7CCD6}


def _dot_positions():
    """Each dot's centre in the original artwork, expressed in the outer orbit's normalised frame
    (u along the long axis, v along the short one), so dots follow the orbit when it is made rounder."""
    th = math.radians(139.997)
    out = {}
    for name, (px, py) in (('moon', (771.995, 292.987)), ('planet', (396.613, 607.860))):
        dx, dy = px - 511.5, py - 511.5
        x = dx * math.cos(-th) - dy * math.sin(-th)
        y = dx * math.sin(-th) + dy * math.cos(-th)
        out[name] = (x / 339.94, y / 196.01)
    return out


DOTS = _dot_positions()


def _hex(rgb):
    return '#%02X%02X%02X' % tuple(max(0, min(255, round(c))) for c in rgb)


def _rgb(value):
    return ((value >> 16) & 255, (value >> 8) & 255, value & 255)


def _mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def accent_palette(value):
    """Same recipe as violet: deep accent at the bottom left fading to a warm pink-tinted light."""
    base = _rgb(value)
    deep = _mix(base, (0, 0, 0), 0.12)
    light = _mix(base, _rgb(0xFF8FC0), 0.3)
    light = _mix(light, (255, 255, 255), 0.25)
    moon = _mix(light, (255, 255, 255), 0.45)
    return dict(light=_hex(light), deep=_hex(deep), moon=_hex(moon))


def shapes(fill, size=1024):
    th = math.radians(180 + TILT)

    def point(ra, rb, t):
        t = math.radians(t)
        x, y = ra * math.cos(t), rb * math.sin(t)
        return x * math.cos(th) - y * math.sin(th), x * math.sin(th) + y * math.cos(th)

    items = []
    for orbit, weight in ((OUTER, OUTER_WEIGHT), (INNER, 1.0)):
        ra = orbit['ra']
        rb = ra * ROUNDNESS * orbit['ratio'] / OUTER['ratio']
        a0, a1 = orbit['arc']
        pts = [point(ra, rb, a0 + (a1 - a0) * k / 240) for k in range(241)]
        items.append(['arc', pts, orbit['stroke'] * weight])
    for name, scale, radius in (('moon', 1.0, MOON['r']), ('planet', PLANET_SCALE, PLANET['r'])):
        u, v = DOTS[name]
        items.append(['dot', point(OUTER['ra'] * u, OUTER['ra'] * ROUNDNESS * v, 0), radius * scale, name])

    def bounds(items):
        xs, ys = [], []
        for item in items:
            if item[0] == 'arc':
                w = item[2] / 2
                for x, y in item[1]:
                    xs += [x - w, x + w]; ys += [y - w, y + w]
            else:
                (x, y), r = item[1], item[2]
                xs += [x - r, x + r]; ys += [y - r, y + r]
        return min(xs), max(xs), min(ys), max(ys)

    x0, x1, y0, y1 = bounds(items)
    k = fill * size / max(x1 - x0, y1 - y0)
    ox, oy = size / 2 - (x0 + x1) / 2 * k, size / 2 - (y0 + y1) / 2 * k
    for item in items:
        if item[0] == 'arc':
            item[1] = [(x * k + ox, y * k + oy) for x, y in item[1]]
        else:
            item[1] = (item[1][0] * k + ox, item[1][1] * k + oy)
        item[2] *= k
    return items


def svg(palette, background=True, fill=FILL, tinted=False, size=1024):
    orbit_paint = 'url(#orbit)'
    planet, moon = PLANET_COLOR, palette['moon']
    if tinted:  # iOS tints greyscale artwork; keep the planet brightest
        orbit_paint, planet, moon = '#BDBDBD', '#FFFFFF', '#E6E6E6'
    body = []
    for item in shapes(fill, size):
        if item[0] == 'arc':
            d = 'M' + ' L'.join(f'{x:.1f},{y:.1f}' for x, y in item[1])
            body.append(f'<path d="{d}" fill="none" stroke="{orbit_paint}" stroke-width="{item[2]:.1f}" '
                        f'stroke-linecap="round" stroke-linejoin="round"/>')
        else:
            (x, y), r = item[1], item[2]
            colour = planet if item[3] == 'planet' else moon
            body.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r:.1f}" fill="{colour}"/>')
    defs = (f'<linearGradient id="orbit" gradientUnits="userSpaceOnUse" x1="{size}" y1="0" x2="0" y2="{size}">'
            f'<stop offset="0" stop-color="{palette["light"]}"/><stop offset="1" stop-color="{palette["deep"]}"/>'
            f'</linearGradient>')
    back = ''
    if background:
        defs += (f'<radialGradient id="bg" cx="50%" cy="42%" r="75%"><stop offset="0" stop-color="{BACKGROUND[0]}"/>'
                 f'<stop offset="1" stop-color="{BACKGROUND[1]}"/></radialGradient>')
        back = f'<rect width="{size}" height="{size}" fill="url(#bg)"/>'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" width="{size}" height="{size}">'
            f'<defs>{defs}</defs>{back}{"".join(body)}</svg>')


def main(out):
    os.makedirs(out, exist_ok=True)
    files = {
        'binary-default.svg': svg(VIOLET),
        'binary-dark.svg': svg(VIOLET, background=False),
        'binary-tinted.svg': svg(VIOLET, background=False, tinted=True),
        'watch.svg': svg(VIOLET, fill=WATCH_FILL),
    }
    for name, value in ACCENTS.items():
        files[f'alt-{name}.svg'] = svg(accent_palette(value))
    for name, text in files.items():
        with open(os.path.join(out, name), 'w') as f:
            f.write(text)
    print(f'wrote {len(files)} SVGs to {out}')


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'icons')
