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

### Fog light and flash-photo flames

The Mobile renderer has no volumetric fog: the environment's depth fog only fades things into its colour, and lights never show in it. `ui/flash_fog.gdshader` is a full-screen pass on the light rig that reads the depth buffer and adds the light that lights scatter back to the lens along each view ray, in their own colour, at the environment's live fog density (the haunted forest raises it to about 0.04). With a black fog colour everything else still fades into black.

| Slider | Effect |
| --- | --- |
| Lantern in fog | the lantern's veil: integrated out from 0.6 m in front of the lens (a flash sits above it) to the first surface or the lantern's range, inverse power of its falloff, extinction both ways, brightest along the beam's axis |
| Fires in fog | a haze ball around each of the 16 fire lights nearest the camera (warm omni lights: torches, grave fires, lanterns), the closed-form point-light airlight cut off at the first surface, so a wall in front hides it; it flickers with the light |
| Flash-photo flames | the global shader parameter `flash_grade` (`project.godot`): torch, grave-fire and candle flames turn from deep red into how they come out on a flash photo, a clipped yellow-white core, thin orange edge, smaller yellower halo; fire lights' colour moves toward a less red orange |

Isotropic scattering (1/4π) keeps the haze in the same units as lit surfaces. The pass draws after every other transparent, so it also lies over foliage and flames; it only adds light. None of the three switches the village to realtime light. Night Flash uses 0.12, 1.2 and 1. `scripts/capture_flash_fog.gd` (run through `scripts/godot_bg.sh`, same arguments as the road capture plus `--capture-dir`) saves a torch close-up and the road with them off and on, checks the frame brightens and the flames get less red, and prints `FLASH_FOG_OK`. Its frame cost is not measured.

**Forest fog** and **Forest ambient** (own group) scale the brightness of the haunted forest's blue-grey grade outside the palisade: its fog colour (and light shafts) and its ambient colour. 1 is the grade as tuned for Folk Ink; Night Flash uses 0.08 and 0.2 so the forest stays dark. They do not switch the village to realtime light on their own. See `docs/haunted-forest.md`.

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
| Lighting | Night (moonlight, lantern), Night Flash (the lantern shaped as a polaroid-style flash: blown-out foreground falling off to black, flash- and fire-lit fog, flash-photo flames, warm print tint), Golden Hour (low warm sun, glow), Fog, Overexposed, Blood Moon, Night Vision (night light amplified into a green ramp, grain), Neon Noir (dim blue light, cyan ink) |
| Shading models | Flat (unshaded), Cel (3 bands, ink), Outline (black on paper), Blueprint (white on blue), Painterly (Kuwahara) |
| Colour | Spectrum, Inverted, Acid Trip (posterized, cycling hue), Thermal, Silent Film (sepia, vignette, grain), Pastel (bright soft light), Bleach Bypass, Vaporwave (pink sun, palette) |
| Lo-fi with a red accent | Red Only, Concrete, Brutalist Web, Risograph, 1-Bit |

### Per-map adjustments

A map can show a theme of its own (`GameMaps.SHADING`: the White Room is Overexposed) and can adjust any theme on that map only (`GameMaps.SHADING_ADJUST`, map id → theme name → values). Adjustments sit over the theme's defaults and under the player's own slider overrides, and are never saved. Palette themes map brightness to inks, so a night map can fall entirely onto the darkest ink: Long Grass lifts Risograph's image exposure by 1.4 stops there, while Risograph on every other map and every other theme on Long Grass stay as they were.

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

## Default grim village pass

The existing **Folk Ink** default now uses full-colour cold overcast lighting, distance fog at 0.009 and restrained grading. No palette reduction or painting effect. Saved per-theme slider overrides still take precedence; choose **Theme defaults** to see the new untuned look if you previously adjusted that preset. The menu video retains the shared colour pass; it is prerecorded footage, so scene fog and practical lights apply to the 3D world only.

The village additionally loads `gameplay/environment/grim_village.gd`: a generated storm panorama, matching basecolor/normal/roughness maps on structural wood, rougher/tinted imported materials, quieter mineral earth blending, four market lanterns and collision-ray-positioned house windows/lanterns. Existing materials/maps are reused, not replaced with colour-derived fake normals. `content/environments/grim/README.md` records panorama prompt and provenance. Slow sky drift and restrained red sheet-lightning pulses are local cosmetics. The lightning light is excluded from shading's sun lookup. No lightning damage, thunder, volumetric fog or renderer switch is added.

The mountain haze correction uses a dark blue-grey scattering colour (`303c40`), density 0.006, no sky-derived aerial-colour contribution, and only 0.08 sky fog influence. This avoids pale mountains appearing brighter than the adjacent storm sky while retaining distance extinction. The native title background was recaptured with this correction; the generated polished menu remains a separate visual study.

Deferred village dressing reapplies the selected theme after adding the sky/fixtures, so starting directly in Night no longer resets its fog to the grim default. The panorama uses explicit LOD at its spherical wrap to avoid a bright vertical mip stripe. The audit capture camera matches the player's fisheye source FOV; see `docs/graphics-audit.md` for measured evidence and limitations.
