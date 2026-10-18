# Camera sampling investigation

The current game uses Mobile/Metal, 4x MSAA, FXAA, native 3D resolution and trilinear anisotropic texture sampling. Mik's `ui/fisheye.gd` and `ui/fisheye.gdshader` remain unchanged. No production rendering setting changed in this investigation.

Run the actual-renderer probe with a host and an external output directory:

```sh
"$GODOT" --path . --script scripts/camera_sampling_probe.gd -- --host --port=7797 --capture-dir=/absolute/output/path
```

It renders the same fixed-orientation 16-step, 0.004m-per-step lateral camera movement at 1600x1000 and the owner's 108-degree source FOV. Each trial warms up, collects 60 viewport render-time samples without image readback, then saves 16 frames. Variants are 4x/8x MSAA at native/1.25x 3D scale. FXAA and the lens stay constant.

## Observations on 2026-10-18

Device: Apple M5 Max, 40 GPU cores. This is not M2 performance evidence. GPU timestamp values returned zero for every trial; treat them as unavailable, not zero rendering cost. CPU setup averages ranged 0.94-1.16ms and do not measure GPU cost or total frame time.

Frames are saved outside Git under the current task visualization directory, `camera-sampling-timed/`. The following mean absolute consecutive-frame RGB differences use 0-255 channel values:

| Sampling | Ground | Left foliage | Right foliage | Periphery |
|---|---:|---:|---:|---:|
| 4x native | 3.5620 | 0.7205 | 0.8867 | 1.3586 |
| 8x native | 3.3748 | 0.6803 | 0.7904 | 1.3101 |
| 4x at 1.25 | 3.2067 | 0.6370 | 0.7591 | 1.2654 |
| 8x at 1.25 | 3.0963 | 0.6020 | 0.6727 | 1.2386 |

Regions `(left, top, right, bottom)` are ground `(500,700,1100,930)`, left foliage `(190,335,420,470)`, right foliage `(1100,410,1450,580)`, periphery `(0,150,180,900)`. Compute each pair's absolute RGB difference, average over pixels/channels, then average over all 15 pairs. Both native and supersampled trials completed twice; the saved-frame metric matched across runs.

This metric includes legitimate scene motion and smoothing, and is not an isolated flicker measurement or human camera acceptance. Higher sampling lowered differences in this small test, but does not prove sufficient visual improvement at an acceptable M2 cost. Therefore the default remains unchanged.

## Structural lens limit

The preserved shader clamps the radial source angle at `source_half_fov - 0.01`. At the default 108-degree source FOV and 0.82 angle factor, this begins near radial distance 1.207 in its aspect-scaled plane. A 1600x1000 view reaches radius 1.6 at the horizontal edge even at mid-height, so some peripheral samples are in the clamped region. This explains a geometric stretching mechanism visible in the captures. More MSAA or source pixels cannot recreate angular information removed by that clamp; it is separate from texture shimmer. No lens edit or bypass was made.

Next acceptance still needs native-speed human review and real M2 GPU/frame-time evidence before selecting a more expensive default. The wider visual goal remains open.
