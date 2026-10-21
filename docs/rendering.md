# Native Mobile rendering

T-033 keeps Mobile/Metal and Mik's existing fisheye implementation. Neither `ui/fisheye.gd`, `ui/fisheye.gdshader`, nor the player-camera FOV mapping was modified. T-057 later changed only the fisheye falloff (see below).

The baseline used 75% 3D resolution, no configured MSAA, and nearest-mipmap vegetation textures. The rendering pass uses native 3D resolution, 4× MSAA, FXAA, 8× anisotropic filtering, linear anisotropic mip filtering for village surfaces/trees, and alpha-to-coverage on cutout foliage. This targets edge aliasing and texture shimmer, not camera control behavior. These settings have a GPU cost that still needs measurement on both target Macs.

The terrain shader also filters its fine procedural variation by pixel footprint and removes the previous screen-space color-derivative normal approximation. A color gradient across pixels is not a stable material normal map.

Godot's [3D antialiasing documentation](https://docs.godotengine.org/en/stable/tutorials/3d/3d_antialiasing.html) distinguishes MSAA edge coverage from temporal methods. This project retains the requested Mobile renderer; Forward+-only temporal features are not claimed or enabled.

## Verify in motion

```sh
"$GODOT" --path . --resolution 1600x1000 --fixed-fps 60 --write-movie /absolute/output/village-motion.avi --script scripts/capture_village.gd -- --host --port=7793 --capture-motion --capture-dir=/absolute/output
```

The script loads the real world and HUD, checks floor/ramp/landing ray collisions, drops the actual player onto four ground locations and requires `is_on_floor()`, saves screenshots, then renders a four-second dolly. `VILLAGE_MOTION_OK` logs the actual viewport's scale and AA enum values. Movie-writer fixed-FPS output verifies rendered motion; it is not proof of live frame pacing, trackpad feel or WAN behavior.

The first capture produced a 1152 × 720 movie with 796 frames at 60 FPS including setup/drop tests and the dolly; the viewport reported native scale 1.0, MSAA enum 2 (4×), and screen AA enum 1 (FXAA). The source AVI is preserved alongside an MP4 preview outside the repository. Human motion review, further art refinement and two-Mac performance measurements remain outstanding.

## Fisheye falloff

The Controls **Fisheye** slider widens the local camera from 75° up to 142° (`ui/fisheye.gd`), and `ui/fisheye.gdshader` resamples that wide rectilinear frame. Until T-057 the camera went to 130° and the shader clamped the source angle just inside the camera's half field of view, so everything outside a fixed circle (about 1.2 half-heights from the centre) collapsed onto a near-flat ring: a visible kink in straight lines and radial smearing towards the frame edges.

The remap is now one smooth radial cubic over the whole frame. With `rho` the distance from the centre normalised so the frame corners are 1, a pixel samples the source at `plane * (1 - b + b * rho^2)`. Radial scale `1 - b + 3b * rho^2` grows continuously from the centre to the corners. There is no clamp radius, every pixel stays inside the rendered frame (no black borders), and the corners sample the source corners.

`b = 1 - tan(centre_half_fov) / tan(source_half_fov)`: the frame centre shows the view of a plain camera whose vertical FOV goes from 75° to `CENTRE_FOV` (100°), and the remaining width of the 142° render is squeezed toward the edges. At the default 0.6 the centre matches the old look (about 90°) and `b` is about 0.36. Raising `WIDE_FOV` strengthens only the edges; each step also upsamples the centre more (1/(1 - b), about 1.6× at 0.6), so the centre softens. `scripts/capture_village.gd` still reads `source_half_fov`.

## Graphics settings

T-126. Settings (title and pause menus) shows a Graphics panel beside the controls (`ui/graphics_panel.gd`). `core/graphics_settings.gd` (autoload `GraphicsSettings`) applies it and saves it in `user://graphics.cfg`.

| Option | Choices | What it changes |
|---|---|---|
| Preset | Low, Medium (default), High | the four options below; editing one afterwards reads as Custom |
| Render scale | 50–100 % in 5 % steps | `Viewport.scaling_3d_scale`, upscaled with MetalFX spatial below 100 % (FSR 1 is Forward+ only); the HUD stays native |
| Anti-aliasing | Off, FXAA, MSAA 2× + FXAA, MSAA 4× + FXAA | `msaa_3d`, `screen_space_aa` |
| Shadows | Off, Low, High | sun shadows; Low is 2 cascades to 50 m with no ground cover shadows; High is the sun as built (4 cascades, 100 m) |
| Grass distance | Near 30 m, Medium 45 m, Far (unlimited) | visibility range of the ground cover cells |
| Frame cap | 30, 60, 120, unlimited | `Engine.max_fps`; headless always 60 |
| Fullscreen | on/off | window mode, restored at start |

Presets: Low is 50 %, FXAA, Low shadows, Near grass. Medium is 70 %, MSAA 2× + FXAA, Low shadows, Medium grass. High is 100 %, MSAA 2× + FXAA, High shadows, Far grass: the look before T-126. Frame cap and fullscreen stay out of the presets.

Ground cover (multimeshes of at least 50 instances with meshes under 0.7 m: trail grass, ferns, stones, clover, dead grass) spans the whole village in a few multimeshes, so neither frustum culling nor a visibility range could skip any of it. Once the match world's builders are done (`match_world.gd` calls `register_world`; it waits 30 frames for the church clearing and forest grade, which edit those multimeshes), each one is split into 16 m cells and hidden; the cells carry the visibility range and, under Low shadows, no shadow casting. Collapsed instances (church yard, bog pools) are dropped. Headless runs skip the split: the dummy renderer keeps no multimesh buffers.

### Why these options: M2 Air benchmark, 2026-10-21

MacBook Air M2 (15"), playtest build c09259e, Folk Ink, fisheye 1.0. Fullscreen renders 3420×2146 (7.3 Mpx), more than the 2880×1864 panel, because macOS display scaling is set above default. Forced draws without presenting (as `grim_render_check.gd`; the configs asking for FSR fell back to bilinear, since FSR 1 is Forward+ only), median of 30 per view over three views (square, village diagonal, north trail). Each config is paired with baseline runs measured right before and after it, because the fanless Air throttled: baseline frame time went from 44 to 57 ms after about 2 minutes and to 69–81 ms after about 4.5 minutes. The sun's shadow pass drew 12–16M triangles against 4–5M in the visible pass.

| Change from the old defaults | Speedup |
|---|---|
| Render scale 50 % | +50 % |
| Render scale 67 % / 75 % | +32 % / +22 % |
| MSAA off (and FXAA off) | +22 % (+25 %) |
| Sun shadows off | +47 % |
| 2 shadow cascades | +14 % |
| Ground cover casts no shadows | +15 % |
| Ground cover in 16 m cells / plus 35 m range | +7 % / +17 % |
| Shadow distance 50 m, shadow atlas 2048 | +2 %, +1 % (noise) |
| Shading pass off, fisheye pass off, both | +1 %, +1 %, +7 % |
| Natural theme, fisheye 0 or 0.6 | none |
| Cheap shadows + ground cells + 35 m + no shading pass | +51 % |
| that + 67 % / + 50 % | 2.3× / 3.1× |

In the presented game loop, the same machine went from about 20 fps to about 32 fps (67 %) and 40 fps (50 %). The forced-draw numbers leave out presenting and the game's scripts. Post passes, fisheye and theme are not options because they cost almost nothing.

After T-126, same machine and method, a screen-sized window (3420×2082) and paired with High each time: Medium 24 ms against 36 ms (1.5×), Low 16.5 ms (2.2×). MetalFX spatial costs about 1 ms over bilinear at those scales and is visibly sharper, close to native.
