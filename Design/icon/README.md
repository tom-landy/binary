# App icon

The Binary mark is one bold orbit with a moon in its gap and a planet off-centre, in a
pink-to-violet gradient. It descends from the original artwork (`mark-source.png`, kept for
reference) and follows the house style of the other Warhound icons: heavy round-capped strokes,
one gradient per shape, and a dark background with a soft glow of the accent colour.

`generate.py` holds the geometry and colours as settings at the top. `FILL` sets how much of the
icon the mark spans (currently 74%); the Watch icon is sized separately so its circular crop
never clips the mark.

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
