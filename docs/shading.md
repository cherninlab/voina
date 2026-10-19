# Shading themes

A theme is a whole rendering look: scene lighting plus an image pass. Cycle with **T** (Shift+T back), pick one, then tune it. Everything is local presentation; nothing is networked.

- `ui/shading.gd` holds the theme list and the T key. It owns two parts:
  - `ui/shading_lighting.gd`: the scene's sun, ambient, sky, fog, exposure, glow, a lantern on the camera, and the unshaded render mode.
  - `ui/shading.gdshader`: a full-screen pass on canvas layer 1. It sits above the fisheye (layer 0), whose output it reads through a `BackBufferCopy`, and below the HUD (layer 2).
- **Shading tweaks** (bottom right, shown with the pause menu like the sword and MPEG tweaks): a theme picker and about 30 sliders in four groups, in a scrolling box. Each theme keeps its own tuning in `user://shading_tweaks.cfg`. **Theme defaults** clears it, and **Print values** logs a line that pastes into `THEMES`.
- `--shading=Night` (a name or an index) starts with that theme. `--shading-ephemeral` neither loads nor saves the tweaks file; captures use it so they never touch a player's settings.
- T is ignored while it is bound to a game action in Controls.

## Lighting

The village's bounce light is baked into a `LightmapGI`; only the sun's direct light is realtime (`BAKE_DYNAMIC`). Dimming the sun alone would leave the baked bounce lighting the village, so night would still look like day. A theme with a `"light"` entry, or any Lighting slider moved off its default, therefore detaches the lightmap data and drives the scene directly:

| Slider | Effect |
| --- | --- |
| Sun, Sun height | sun energy (× original) and elevation in degrees; low sun means long shadows |
| Ambient, Sky | ambient light energy and sky brightness (× original) |
| Fog density | absolute; the village default is 0.0015 |
| Scene exposure | tonemap exposure (× original) |
| Glow | environment glow intensity |
| Lantern | energy of the light carried at the camera; 0 is off |
| Lantern spread | 180° shines all around like a carried lantern; narrower is a cone along the view, from a torch up to a wide flash |
| Lantern range, Lantern falloff | how far it reaches and how fast it fades |
| Lantern warmth | 0 is cold flash white, 1 is warm lantern orange |
| Lantern height | metres above the lens; a little height drops crisp shadows below what it hits |
| Lantern shadows | 0 or 1 |

There is one lantern, shaped by its sliders. Night uses it as a warm all-around lantern. Night Flash uses it as a point-and-shoot flash: a wide 150° cold cone, energy 45, 22 cm above the lens, with shadows. Godot needs an omni light for 180° and a spot light for a cone, so both nodes exist and only the active one is lit. They hang on a rig that copies the current camera's transform every frame. They are never children of a camera, because the player and its camera are freed on leave or rejoin. That used to free the lantern with them, and the Night lantern stayed dark afterwards.

Theme colours set the sun, ambient, fog and lantern tints. Natural, or any theme without lighting, puts back the lightmap, sun, environment and render mode exactly as they were. Without the lightmap's bounce light, shadows are only filled by ambient light; themes raise Ambient to compensate. The realtime path's frame cost against the baked one is not measured.

`"render": "unshaded"` (the **Flat** theme) switches the viewport to `DEBUG_DRAW_UNSHADED`. Every surface shows its material colour with no light or shadow at all: true flat shading.

## Image pass

Pixelate → flatten → grade → hue → spectrum → cel bands → tint → posterize → palette → invert → outline paper → blood → ink → vignette → grain, then mix with the untouched frame by **Strength**.

| Slider | Effect |
| --- | --- |
| Exposure, Contrast, Saturation | grading |
| Hue shift, Hue cycling | rotation about the grey axis; cycling animates it (turns per second) |
| Tint | recolours by luminance toward the theme's tint colour (sepia, rose) |
| Invert | negative |
| Vignette, Grain | corner darkening and animated noise |
| Pixel size | block size; every later step works on the block grid |
| Flatten (paint) | Kuwahara radius: of four quadrants around the pixel, the one with the least colour variance wins. Gradients become painted patches and edges stay sharp. Cost grows with (r+1)² × 4 taps |
| Cel bands | luminance steps that keep each pixel's hue (toon shading) |
| Posterize levels | steps per channel |
| Spectrum, Spectrum bands | rainbow indexed by luminance; with Hue cycling it flows |
| Palette mix, Dither | themes with a palette map to it, as a dark-to-light ramp or by nearest colour, with 4×4 Bayer dither |
| Ink outlines, Ink threshold | Sobel edges on the block grid's luminance in the theme's ink colour |
| Outline only | replaces the picture with the theme's paper colour, leaving just the ink |

## Blood

Off by default (**Blood override** 0). Four lo-fi themes use it as a red accent, and Blood Moon uses it partly. The pass finds blood in the source frame by colour. Raider blood is a dark crimson, about (53, 23, 29) in sRGB on the village ground. Lit skin is as red but leans orange (green ≥ blue). A pixel counts as blood when red / blue ≥ **Blood redness** (1.5) and blue / green ≥ **Blood hue** (1.12). It is repainted with the theme's blood colour, flat or keeping its light and dark (**Blood shading**), after posterize and palette.

## Themes

| Group | Themes |
| --- | --- |
| Lighting | Night (moonlight, lantern), Night Flash (the lantern shaped as a polaroid-style flash: blown-out foreground falling off to black, warm print tint), Golden Hour (low warm sun, glow), Fog, Overexposed, Blood Moon, Night Vision (night light amplified into a green ramp, grain), Neon Noir (dim blue light, cyan ink) |
| Shading models | Flat (unshaded), Cel (3 bands, ink), Outline (black on paper), Blueprint (white on blue), Painterly (Kuwahara) |
| Colour | Spectrum, Inverted, Acid Trip (posterized, cycling hue), Thermal, Silent Film (sepia, vignette, grain), Pastel (bright soft light), Bleach Bypass, Vaporwave (pink sun, palette) |
| Lo-fi with a red accent | Red Only, Concrete, Brutalist Web, Risograph, 1-Bit |

## Verify

```sh
"$GODOT" --path . --resolution 1152x720 --script scripts/capture_shading.gd -- --host --pve --port=7796 --shading-ephemeral --capture-dir=/absolute/output
```

It cuts a raider in half in front of a fixed camera and saves one frame per theme. It then checks that:

- Natural leaves the frame untouched and every other theme changes it;
- Night is darker than Natural;
- the lantern still lights and follows a new camera after its camera is freed;
- Concrete shows vivid red where the plain frame has none;
- returning to Natural restores the lightmap, the sun and normal rendering;
- a T key event advances the theme.

It prints `SHADING_OK`. The 1152 × 720 run on an M2 passed. Frame cost on the target Macs and how the themes look in motion are not measured.

## Folk Ink and menu grading

Folk Ink is the default for new settings. Following visual feedback it now uses full-colour cool, subdued lighting with light distance haze, restrained saturation and deeper shadows. It has no palette mapping, posterisation, cel bands, flattening, dithering or added ink outlines; texture detail and smooth gradients are retained. Saved theme choices remain respected. All themes share the same image-grading material with the menu video; changing T/Shift+T updates both. Logo and controls draw after grading for readability. Lighting-only values affect the 3D world, not baked video lighting.
