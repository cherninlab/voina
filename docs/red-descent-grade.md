# Red Descent grade (T-181)

The Red Descent lighting and grade, tuned toward Theo's paintovers in `content/art_direction/theo_paintovers_v1/`. Odd-numbered files are the game frames he painted over, and even-numbered files are his paintovers. They match existing capture views exactly:

| Paintover | Game view | Capture |
|---|---|---|
| 2.webp (over 1) | b4-low-bend | `scripts/capture_bridges.gd` |
| 4.webp (over 3) | b5-low-side | `scripts/capture_bridges.gd` |
| 6.webp (over 5) | b2-high-underside | `scripts/capture_bridges.gd` |
| 8.webp (over 7) | low_span_05_walk_back | `scripts/capture_bridges.gd --tour` |

Target, from his notes: much darker, with warm torch light in pools that fall off fast and corners and vaults nearly black. A cold green-grey fog fills the abyss under the bridges, and red light glows from the shaft depths and through doorways. Stone is desaturated grey-brown and wet. Before this change the frames were evenly lit warm orange and the abyss was a flat red-black.

All settings live in `gameplay/environment/crypt_dungeon.gd`: `atmosphere()`, `torch()`, and the wetness and tint arguments of the `surface()` calls. Review frames are in `content/environments/red_descent/review/grade_v1/`.

## Settings

Godot converts every colour below from sRGB to linear before lighting. A colour that looks pale in the inspector can therefore be a strong tint in the render. The old torch colour `(1, 0.63, 0.3)` is linear `(1, 0.35, 0.07)`, a deep orange, and that is most of why the old frames looked orange.

### Environment (`atmosphere()`)

| Setting | Before | After | Why |
|---|---|---|---|
| ambient colour × energy | (0.36, 0.43, 0.46) × 0.36 | (0.52, 0.53, 0.50) × 0.16 | Neutral, about half the old fill. Unlit stone reads grey, not blue or orange, and vaults fall dark. |
| tonemap | Filmic, exposure 1.15 | Filmic, exposure 1.0 | ACES and AgX were tried. At equal mid-tones both crushed the shaft. A contrast adjustment pivots at 0.5 and clips the darks, so it was rejected. |
| background colour | (0.009, 0.005, 0.005) | haze (0.11, 0.145, 0.13) | Matches the fog wherever the shaft is open. |
| fog colour | (0.075, 0.009, 0.005), energy 0.8 | haze (0.11, 0.145, 0.13), energy 1.0 | Cold green-grey, measured from the abyss in paintovers 2, 4 and 8. |
| fog density | 0.009 | 0.006 | Thin distance fog. At 0.014 to 0.028 the near walls drowned in a flat teal veil. |
| fog height / height density | off | -26 / 0.13 | Exponential height fog below the lowest crossing (y -26 to -28) fills the abyss. At y -36 it is about 70 % fog. Walkable floors (choir at -28) get under 25 %. |
| glow | off | on, intensity 1.0, HDR threshold 0.7, screen blend, Godot's default levels 2–4 (0.8, 0.4, 0.1) plus level 6 at 0.8 | Soft warm halos around flames and flame-lit niches. |
| adjustment saturation | off | 0.92 | A slight overall desaturation. Most of the colour shift comes from light colour and stone tint. |

Volumetric fog does not work on the Mobile renderer. Enabling it prints `Volumetric fog is only available when using the Forward+ renderer` (`environment_storage.cpp`), and the frames are pixel-identical apart from flame flicker. It costs nothing and does nothing. Height fog plus depth fog is the substitute.

### Depth glow (`atmosphere()`)

The four old glow lights hung mid-shaft at y -20 to -43, range 26: three dull red and one green. They tinted the walls along the crossings. They are replaced by:

- four red lights `(0.85, 0.16, 0.06)` at y -38 and -39 around the shaft (energy 8, range 15, attenuation 1.2). They sit inside the height fog, so the lower walls show a dull red glow through 50 to 70 % fog, and the bridge-level walls stay grey;
- one red light in the deep choir at (36, -25, -2) (energy 3, range 16, attenuation 1.5). Red light shows through the choir doorway at the end of the low crossing.

The fog now separates the crossings from the walls, which was the old glow lights' purpose.

### Torches (`torch()`)

| Setting | Before | After | Why |
|---|---|---|---|
| colour | (1, 0.63, 0.30) | (1, 0.62, 0.34) | Still amber: lit stone next to a torch is orange-brown in the paintovers (sRGB about 106, 63, 29). Red minus blue stays above 0.5 so `ui/shading_lighting.gd` still treats torches as fires (Night Flash theme, fire haze). |
| energy / range / attenuation | 3.6 / 10.5 / 1.25 | 8 / 12 / 2.5 | Steeper than inverse-square: bright pools within about 2 m that are nearly gone by 5 m. The antechamber vault drops from sRGB (85, 53, 26) to (40, 29, 16). Lower energy left pools too dim to guide the eye. Attenuation 3 at energy 10 blew flame-lit niches out to cream. |
| specular | 0.5 (default) | 1.0 | Wet patches catch the torch. |
| cup | batched iron box | own `BoxMesh`, no shadow casting, render layer 20; torch light `light_cull_mask` excludes layer 20 | The cup sat 0.5 m under its own light. It printed a black square on the deck where the pool belongs, and with the new falloff its top burned white. |

`gameplay/environment/dungeon_dressing.gd` raises its two nave practicals to energy 5.8 and range 22 after `torch()`. That file is outside T-181. With the new attenuation those two practicals are slightly dimmer than an ordinary torch at 2 to 3 m.

### Materials (`surface()` wetness and tint)

`surface()` gained a `tint` argument; the trim and red-plaster tints moved into it unchanged in purpose. The shader's wet mask is patchy and already scaled by 0.65 above y -24, so `damp` 1.4 makes upper floors fully wet where the mask says. Values far above that extrapolate (darker albedo, roughness below zero), so floors stop at 1.4. Walls and stone, which reach the deep water, stop at 1.0.

| Family | Wetness before → after | Tint before → after |
|---|---|---|
| stone (Bricks089) | 0.22 → 0.8 | 1 → (0.84, 0.9, 1.0) |
| wall (Bricks089) | 0.5 → 1.0 | 1 → (0.84, 0.9, 1.0) |
| plaster (Concrete012) | 0.25 → 0.6 | 1 → (0.86, 0.9, 0.95) |
| red_plaster | 0 → 0.5 | (0.55, 0.055, 0.025), unchanged |
| trim (Bricks083) | 0 → 0.5 | (0.62, 0.57, 0.47) → (0.58, 0.56, 0.52) |
| floor (Rocks025) | 0.4 → 1.4 | 1 → (0.85, 0.9, 0.98) |
| rock and built stone rooms (marble_rock_03) | 0.3 → 1.4 | 1 → (0.78, 0.9, 1.0) |
| wood (procedural timber) | 0.68 → 1.3 | 1 → (0.85, 0.9, 0.95) |

The cool tints pull the yellow-brown scans (Bricks089 averages sRGB 128, 119, 88; marble_rock_03 101, 84, 62) toward grey-brown, so the torch colour is what makes stone warm.

## Measurements

These numbers are from 480 px thumbnails. Each cell gives mean luminance, 5th percentile, 95th percentile, mean HSV saturation and red/blue ratio.

| View | Paintover | Before | After |
|---|---|---|---|
| b4 low bend | 0.137 / 0.03 / 0.29 / 0.33 / 1.44 | 0.104 / 0.02 / 0.19 / 0.53 / 2.31 | 0.095 / 0.03 / 0.16 / 0.39 / 1.51 |
| b5 low side | 0.122 / 0.03 / 0.28 / 0.31 / 1.35 | 0.111 / 0.01 / 0.24 / 0.49 / 2.04 | 0.120 / 0.04 / 0.16 / 0.29 / 1.28 |
| b2 high underside | 0.111 / 0.02 / 0.28 / 0.50 / 1.73 | 0.094 / 0.02 / 0.21 / 0.34 / 1.63 | 0.074 / 0.03 / 0.13 / 0.31 / 1.46 |
| low_span_05 walk back | 0.124 / 0.02 / 0.26 / 0.36 / 1.44 | 0.132 / 0.05 / 0.24 / 0.55 / 2.63 | 0.106 / 0.06 / 0.18 / 0.40 / 1.79 |

Saturation and the red/blue balance now sit at the paintovers' level. The abyss under the low crossing (b5, bottom) was sRGB (16, 12, 9) and is now (32, 41, 36); the paintover has (29, 33, 28). The stone rooms are about 30 % darker: mean 0.214 → 0.151 in the antechamber corner view and 0.235 → 0.166 in the entry.

The highlights still fall short of the paintovers (95th percentile 0.13 to 0.18 against 0.26 to 0.29). Most of that missing brightness is wet glints on the bridge decks; see the follow-ups below.

Frame cost was measured at 1440×900 with 2× MSAA and FXAA on this Mac, with Theo's editor open. Twelve offscreen passes were forced per frame, the same method as `scripts/renderer_benchmark.gd`. The full graded frame took 0.7 to 1.4 ms per pass. Turning glow, adjustments, fog or glow level 6 on and off gave differences below the run-to-run noise of about ±0.2 ms. Unforced frames held the display's 8.33 ms (120 Hz) pacing in every configuration.

## Reproduce

```bash
scripts/godot_bg.sh --path . --script scripts/capture_dungeon.gd -- --dungeon --shading-ephemeral --capture-dir=/abs/views
scripts/godot_bg.sh --path . --script scripts/capture_dungeon.gd -- --dungeon --shading-ephemeral --stone-rooms --capture-dir=/abs/rooms
scripts/godot_bg.sh --path . --script scripts/capture_bridges.gd -- --dungeon --shading-ephemeral --capture-dir=/abs/bridges
scripts/godot_bg.sh --path . --script scripts/capture_bridges.gd -- --dungeon --shading-ephemeral --tour --capture-dir=/abs/tour
```

To tune at runtime, note that `ui/shading_lighting.gd` re-applies the ambient, fog colour and density, exposure and glow it first saw, about once a second. There is no sun in the dungeon, so it keeps refreshing. A script that changes those values live must reset that node's `original_environment` and call `refresh()`, or its changes revert within a second.

## Review frames (`content/environments/red_descent/review/grade_v1/`)

- `01`–`04 *_paintover-before-after.png`: each paintover beside the same game view before and after.
- `05-stone-rooms_before-after.png`: antechamber and entry, stone-built rooms.
- `06-dungeon-views_before-after.png`: the eight default `capture_dungeon.gd` views.
- `07-bridge-tour-readability_after.png`: every walk view of both crossings after the grade. Decks, gaps, rails and route edges stay readable between torch pools.
- `08-proposal-wet-bridge-decks_not-shipped.png`: not shipped. It shows what bridge wetness 1.6 would add (see below).

## Follow-ups outside T-181

- **Wet bridge decks.** The baked bridges use `content/environments/procedural_bridge_v1/bridge_surface.gdshader` through `gameplay/environment/dungeon_structure.gd`. They copy only texture maps from the `wood` material, and their `wetness` stays at the shader default 0.3. The paintovers' strongest feature is torch light glinting on wet planks. Setting `bridge_material` wetness to about 1.6, which the shader's height factor keeps at or below 1 at bridge level, gives those glints (frame 08). That needs an owner for `dungeon_structure.gd`.
- **Entry vault.** `build_landmarks()` keeps a cold entrance light (energy 4, range 16) at y 3 inside the 5 m entry room. It still lights that vault blue-grey: sRGB (50, 41, 33) after, (92, 65, 41) before.
- **Stone surface.** The tiled Bricks089 pattern on the shaft walls and the even albedo read as synthetic next to the paintovers' rough, stained masonry. That belongs to T-177 and T-180.
- **Fog is uniform.** Without volumetric fog on Mobile the haze has one colour and no light shafts. Theo's paintovers have brighter haze high in the shaft and darker depths.
