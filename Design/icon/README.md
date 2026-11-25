# App icon

The Binary mark is two open orbits, a planet and a moon. `generate.py` holds it as vector
geometry, fitted to the original artwork (`mark-source.png`, kept for reference) and then
adjusted: rounder orbits, a lighter outer orbit, a larger planet, and a pink-to-violet orbit gradient.
The settings at the top of `generate.py` (roundness, tilt, weights, fill, colours) control the result.

Run from the repository root. `render.js` needs Node with Playwright and Chromium.

```bash
python3 Design/icon/generate.py /tmp/icons
```

```bash
node Design/icon/render.js /tmp/icons
```

Then copy the PNGs:

| File | Destination |
| --- | --- |
| `binary-default.png`, `binary-dark.png`, `binary-tinted.png` | `App/Assets.xcassets/AppIcon.appiconset/` |
| `alt-<Accent>.png` | `App/Assets.xcassets/AppIcon-<Accent>.appiconset/icon.png` |
| `watch.png` | `Watch/Assets.xcassets/AppIcon.appiconset/icon.png` |
