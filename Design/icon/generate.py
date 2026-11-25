"""Rebuild the Binary icon set from the original mark: larger, no glow, one clean gradient per theme."""
import sys, colorsys
import numpy as np
from PIL import Image, ImageFilter

S = 1024
SRC = 'Design/icon/mark-source.png'  # original mark on a transparent background

def mark_mask():
    """Binary stroke shape from the original, re-anti-aliased so no glow or halo survives."""
    im = np.asarray(Image.open(SRC).convert('RGBA')).astype(float) / 255
    rgb, a = im[..., :3], im[..., 3]
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    # Coverage weighted by saturation: strokes are saturated aqua, the glow is grey.
    cover = a * np.clip((sat - 0.25) / 0.25, 0, 1)
    big = 4
    up = Image.fromarray((cover * 255).astype(np.uint8)).resize((S * big, S * big), Image.BICUBIC)
    up = up.filter(ImageFilter.GaussianBlur(big * 0.6))
    hard = (np.asarray(up) > 127).astype(np.uint8) * 255
    down = Image.fromarray(hard).resize((S, S), Image.LANCZOS)
    return np.asarray(down).astype(float) / 255

def scaled(mask, scale, out=S):
    """Scale the mask about its bounding-box centre and recentre it on the canvas."""
    ys, xs = np.where(mask > 0.5)
    cx, cy = (xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2
    big = 4  # supersample for clean edges
    m = Image.fromarray((mask * 255).astype(np.uint8)).resize((S * big, S * big), Image.LANCZOS)
    size = int(S * big * scale)
    m = m.resize((size, size), Image.LANCZOS)
    canvas = Image.new('L', (S * big, S * big), 0)
    ox = int(S * big / 2 - cx * big * scale)
    oy = int(S * big / 2 - cy * big * scale)
    canvas.paste(m, (ox, oy))
    return np.asarray(canvas.resize((out, out), Image.LANCZOS)).astype(float) / 255

def hexrgb(h): return np.array([(h >> 16) & 255, (h >> 8) & 255, h & 255], float) / 255

def gradient(base):
    """Light at top-right, deeper at bottom-left, as in the original artwork."""
    b = hexrgb(base)
    light = b + (1 - b) * 0.24
    deep = b * 0.80
    y, x = np.mgrid[0:S, 0:S] / (S - 1)
    t = np.clip(((1 - x) + y) / 2, 0, 1)[..., None]   # 0 at top-right, 1 at bottom-left
    return light * (1 - t) + deep * t

def background():
    y, x = np.mgrid[0:S, 0:S]
    d = np.sqrt((x - S * 0.5) ** 2 + (y - S * 0.42) ** 2) / (S * 0.75)
    c0, c1 = hexrgb(0x272040), hexrgb(0x100D19)
    t = np.clip(d, 0, 1)[..., None] ** 1.2
    return c0 * (1 - t) + c1 * t

def compose(mask, base, bg=True):
    col = gradient(base)
    if bg:
        out = background() * (1 - mask[..., None]) + col * mask[..., None]
        return Image.fromarray((out * 255).round().astype(np.uint8), 'RGB')
    rgba = np.dstack([col, mask])
    return Image.fromarray((rgba * 255).round().astype(np.uint8), 'RGBA')

def tinted(mask):
    white = np.ones((S, S, 3))
    return Image.fromarray((np.dstack([white, mask]) * 255).round().astype(np.uint8), 'RGBA')

THEMES = {'Violet': 0x9E6BFA, 'Orange': 0xFA7A2E, 'Ember': 0xEB4742, 'Gold': 0xF5BD38, 'Lime': 0x8FD93D,
          'Mint': 0x3DD69E, 'Teal': 0x2EB8D1, 'Blue': 0x3D85FA, 'Pink': 0xF25794, 'Silver': 0xC7CCD6}

if __name__ == '__main__':
    out = sys.argv[1]
    base = mark_mask()
    phone = scaled(base, 1.28)
    watch = scaled(base, 1.12)
    import os
    os.makedirs(out, exist_ok=True)
    compose(phone, THEMES['Violet']).save(f'{out}/binary-default.png')
    compose(phone, THEMES['Violet'], bg=False).save(f'{out}/binary-dark.png')
    tinted(phone).save(f'{out}/binary-tinted.png')
    for name, rgb in THEMES.items():
        if name != 'Violet':
            compose(phone, rgb).save(f'{out}/alt-{name}.png')
    compose(watch, THEMES['Violet']).save(f'{out}/watch.png')
    for name, m in (('phone', phone), ('watch', watch)):
        ys, xs = np.where(m > 0.5)
        print(name, 'bbox w', xs.max() - xs.min(), 'h', ys.max() - ys.min(),
              f'= {(xs.max()-xs.min())/S:.0%} of canvas')
