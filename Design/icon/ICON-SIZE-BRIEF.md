# Warhound app icon sizing brief

Resize the mark in this app's icon to match the Binary icon. Change only size and line weight.
Shapes, colours, gradient direction, background and glow stay as they are.

## Target, measured on the 1024 × 1024 master

| Property | Target | At 1024 px |
| --- | --- | --- |
| Mark span (widest of width or height, including stroke caps and dots) | 74% of the canvas | 758 px |
| Margin on each side | 13% | 133 px |
| Stroke width of arcs and lines | 10% | 103 px |
| Small dot (moon, knob) diameter | about 12% | about 125 px |
| Large dot (planet, centre dot) diameter | about 17% | about 176 px |
| Mark centre | the canvas centre, within ±1.5% | within 15 px |

## The rule that matters

Do not scale the whole mark uniformly. A uniform scale from today's size to 74% also thickens the
strokes, to about 14% on some icons, which makes the icon far heavier than Binary.

1. Scale the geometry (radii, arc paths, line lengths, dot positions) about the canvas centre until
   the mark spans 74%.
2. Set every stroke to 103 px at 1024 (10%), whatever it became in step 1.
3. Set dots to the sizes above, keeping each one centred where step 1 put it.
4. Keep round caps and the existing gaps between elements. Where a gap closes up because strokes got
   relatively thinner or thicker, restore it to the same visual spacing as before.

## Apply to every variant

- The primary icon: default, dark (transparent background) and tinted (greyscale) versions.
- Every alternate icon.
- The Apple Watch icon, which watchOS crops to a circle. Size it so no part of the mark is more than
  43% of the canvas width from the centre, instead of using the 74% span.

## Check your result

Run the measuring script on each 1024 PNG you produce:

```bash
python3 measure_icon.py path/to/icon-1024.png
```

Every line must read OK. A result like this is correct:

```
mark span   74%   target 74% ±2%   OK
stroke      10.5%  target 10% ±1%  OK
off-centre  x -0.0%, y -0.0%   target within ±1.5%   OK
```

The script needs Python 3 with Pillow and NumPy. It treats bright, saturated pixels as the mark, so it
will not read the tinted greyscale variant correctly. Check that one by eye against the default.

## Per-app notes

**Blue app (open arc with a needle and knob).** The mark currently spans about 51% and the stroke is
already about 10%. Scale the geometry by about 1.45× (arc radius and needle length). Leave the stroke at
103 px. Keep the knob at its current size relative to the stroke rather than scaling it 1.45×.

**Orange app (ring with a moon in the gap and a centre dot).** The mark currently spans about 57% with a
stroke of about 9%. Scale the geometry by about 1.3× and set the stroke to 103 px. This icon has the same
structure as Binary: moon about 125 px across, centre dot about 176 px.
