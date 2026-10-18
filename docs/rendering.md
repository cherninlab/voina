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
