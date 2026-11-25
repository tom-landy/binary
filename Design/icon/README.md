# App icon

`generate.py` rebuilds every app icon from `mark-source.png`, the original mark on a transparent background.
It outputs the primary icon (default, dark and tinted), the nine accent alternates and the Watch icon.
The mark is scaled to about 79% of the canvas (69% on Watch, which is cropped to a circle),
the glow is dropped, and each accent gets one gradient.

Run from the repository root (needs Pillow and NumPy):

```bash
python3 Design/icon/generate.py /tmp/icons
```

Then copy the output into `App/Assets.xcassets` and `Watch/Assets.xcassets`.
