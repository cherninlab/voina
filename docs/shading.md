# Shading themes

`ui/shading.gd` adds one full-screen pass, `ui/shading.gdshader`, over the 3D frame. It is canvas layer 1: above the fisheye (layer 0), whose output it reads through a `BackBufferCopy`, and below the HUD (layer 2), which stays untouched. It is local presentation only and nothing is networked.

- **T** next theme, **Shift+T** previous. A short "Shading: name" label confirms the switch. T is ignored while it is bound to a game action in Controls.
- **Shading tweaks** (bottom right, shown with the pause menu like the sword and MPEG tweaks): theme picker and sliders for the current theme. Each theme keeps its own tuning in `user://shading_tweaks.cfg`. **Theme defaults** clears it, and **Print values** logs a line that pastes into `THEMES`.
- `--shading=Concrete` (a name or an index) on the command line starts with that theme.

## The pass

Pixelate → flatten → grade → posterize → palette → blood → ink, then mix with the untouched frame by **Strength**.

| Slider | Effect |
| --- | --- |
| Pixel size | block size; every later step works on the block grid |
| Flat shading | Kuwahara radius: of four quadrants around the pixel, the one with the least colour variance wins, so gradients turn into flat patches and edges stay sharp. Cost grows with (r+1)² × 4 taps |
| Exposure, Contrast, Saturation | grading before quantising; saturation 0 is greyscale |
| Posterize levels | steps per channel (below 2 is off) |
| Palette mix | themes with a palette map to it, either as a dark-to-light ramp or to the nearest colour |
| Dither | 4×4 ordered Bayer offset before posterize and palette |
| Ink outlines, Ink threshold | Sobel edges on the block grid's luminance, painted in the theme's ink colour |
| Blood override, Blood redness, Blood hue, Blood shading | see below |

## Blood

The pass finds blood in the source frame by colour. On screen the raider blood (`hit_effects.gd`, albedo 0.3, 0.012, 0.01) is a dark crimson, about (53, 23, 29) in sRGB on the village ground. Lit skin is just as red by a red/max(green, blue) ratio, but it leans orange: its green is at or above its blue. So a pixel counts as blood when red / blue ≥ **Blood redness** (1.5) and blue / green ≥ **Blood hue** (1.12). On a test frame, that mask covered the spray and the puddles but not skin. It caught only the rims of the red shorts and of the pink name labels.

Blood pixels are repainted with the theme's blood colour. **Blood shading** 0 paints it flat; 1 keeps the source's light and dark. Blood is painted after posterize and palette, so it stays vivid red in the grey, green and four-colour themes.

## Themes

| Theme | Look |
| --- | --- |
| Natural | off |
| Red Only | greyscale, high contrast, shaded red blood |
| Brutalist Web | black, white, #0000ff, #ffff00, silver and magenta by nearest colour; 2 px blocks, dither, flat shading, black ink |
| Concrete | six-grey ramp, flat shading, heavy ink, flat #ff0a0a blood |
| Acid Poster | saturation 2.2, 3 levels per channel, dither, purple ink |
| Terminal | green phosphor ramp, 3 px blocks, heavy dither, red blood |
| Risograph | paper, fluorescent pink, blue, yellow and black by nearest colour; dither |
| Bleach Bypass | saturation 0.3, 6 levels, darker shaded blood |
| Hyper Flat | full colour, 5 levels, flat shading, black ink, flat red blood |

## Verify

```sh
"$GODOT" --path . --resolution 1152x720 --script scripts/capture_shading.gd -- --host --pve --port=7796 --capture-dir=/absolute/output
```

It cuts a raider in half in front of a fixed camera and saves one frame per theme. It then checks that Natural leaves the frame untouched, that every other theme changes it, that Concrete shows thousands of vivid red pixels where the plain frame has none, and that a T key event advances the theme. The script prints `SHADING_OK`. The 1152 × 720 run on an M2 passed. Frame cost on the target Macs and how the themes look in motion are not measured.
