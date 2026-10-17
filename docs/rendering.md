# Native Mobile rendering

T-033 keeps Mobile/Metal and Mik's existing fisheye implementation. Neither `ui/fisheye.gd`, `ui/fisheye.gdshader`, nor the player-camera FOV mapping was modified.

The baseline used 75% 3D resolution, no configured MSAA, and nearest-mipmap vegetation textures. The rendering pass uses native 3D resolution, 4× MSAA, FXAA, 8× anisotropic filtering, linear anisotropic mip filtering for village surfaces/trees, and alpha-to-coverage on cutout foliage. This targets edge aliasing and texture shimmer, not camera control behavior. These settings have a GPU cost that still needs measurement on both target Macs.

The terrain shader also filters its fine procedural variation by pixel footprint and removes the previous screen-space color-derivative normal approximation. A color gradient across pixels is not a stable material normal map.

Godot's [3D antialiasing documentation](https://docs.godotengine.org/en/stable/tutorials/3d/3d_antialiasing.html) distinguishes MSAA edge coverage from temporal methods. This project retains the requested Mobile renderer; Forward+-only temporal features are not claimed or enabled.

## Verify in motion

```sh
"$GODOT" --path . --resolution 1600x1000 --fixed-fps 60 --write-movie /absolute/output/village-motion.avi --script scripts/capture_village.gd -- --host --port=7793 --capture-motion --capture-dir=/absolute/output
```

The script loads the real world and HUD, checks floor/ramp/landing ray collisions, drops the actual player onto four ground locations and requires `is_on_floor()`, saves screenshots, then renders a four-second dolly. `VILLAGE_MOTION_OK` logs the actual viewport's scale and AA enum values. Movie-writer fixed-FPS output verifies rendered motion; it is not proof of live frame pacing, trackpad feel or WAN behavior.

The first capture produced a 1152 × 720 movie with 796 frames at 60 FPS including setup/drop tests and the dolly; the viewport reported native scale 1.0, MSAA enum 2 (4×), and screen AA enum 1 (FXAA). The source AVI is preserved alongside an MP4 preview outside the repository. Human motion review, further art refinement and two-Mac performance measurements remain outstanding.
