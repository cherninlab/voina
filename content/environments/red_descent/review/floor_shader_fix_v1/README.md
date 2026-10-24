# T-175 flagstone shading investigation

Four approved material defaults improve flagstone readability under the existing dungeon lights:
`tint` (0.88, 0.85, 0.80), `variation` 0.14, `ao_albedo` 0.25, and `grime` 0.15.
Texture/UVs, normals, AO output, wear, roughness, geometry, collision, placement,
clipping, real lights and UI grading stay unchanged.

This is material-response art calibration. A renderer or source-data fault was not proven,
and the change does not remove every dark grain or real fixture shadow. The original
14-control investigation and its unresolved-cause evidence are preserved below.

## Reproduction

Godot 4.7.2, Apple M5 Max, Mobile/Metal. Capture build `71ea44b [785fb8bfd369]`
includes the T-162 rubble/hanging integration. Source hashes are in `source_identity.json`;
`baseline.gdshaderinc.txt` is the unchanged production include. Each mode only replaces
live floor Shader resources and/or changes live diagnostic rendering state.
The chapel, restraint and nave camera positions/FOVs match the integration review.
Frames are 1440 × 900. A missing built scene or flat frame aborts capture.

```sh
GODOT=/Users/theochernin/Library/Caches/voina/engine-4.7.2/Godot.app/Contents/MacOS/Godot \
  scripts/godot_bg.sh --path . --max-fps 30 \
  --script res://content/environments/red_descent/review/floor_shader_fix_v1/capture_shader_controls.gd \
  -- --dungeon --shading-ephemeral \
  --modes=baseline,no-ao,no-noise,flat-texture,no-grade,linear-tonemap,albedo-only,texture-only,no-normal,no-specular,rough-one,no-specular-rough-one,no-shadows,constant-albedo
python3 content/environments/red_descent/review/floor_shader_fix_v1/measure_captures.py
```

## Results

| Control | Observed result |
| --- | --- |
| `baseline` | Per-stone dark rectangles and noisy patches reproduced. |
| `no-ao` | Both ALBEDO AO multiply and AO output removed; patches remain. |
| `no-noise` | Both world-space grime factors removed; patches remain. |
| `no-normal` | NORMAL_MAP and NORMAL_MAP_DEPTH assignments removed entirely; patches remain. |
| `no-specular`, `rough-one`, combined | Full production ALBEDO retained; patches remain. |
| `no-grade` | Canvas grade hidden; chapel pixels identical to baseline. Crypt uses Natural. |
| `linear-tonemap` | Scene tonemapper changed in memory; dark patches remain. |
| `no-shadows` | Dungeon processing frozen FIRST, all 67 Light3D shadows disabled, states asserted after each camera warmup; patches remain. Real fixture shadows disappear. |
| `constant-albedo` | Only ALBEDO becomes vec3(0.3); normal/AO/roughness/specular assignments retained. Floor patches disappear. |
| `flat-texture` | Base texture becomes vec3(0.5); speckle largely disappears, stone tone blocks remain. This also increases reflectance, so it does not prove a corrupt texture. |
| `albedo-only` | Full original ALBEDO rendered unshaded; texture and stone variation look ordinary, without black patches. |
| `texture-only` | Original sampled albedo rendered unshaded; clean cream Concrete012. |

The source texture is visually clean. Coursed-A GLB UVs are bounded around -15.3..15.8;
AO.R is bounded 0.2..1, and normals are nonzero unit vectors. Source GLBs omit tangents,
but imports request tangent generation. Complete normal-map removal still retains the issue.
No corrupted geometry, tangent, baked-AO or texture data was identified, and the lighting
controls do not isolate a fault. The isolated sensitivity is to ALBEDO response. The
subsequent parent-approved art calibration below preserves all source maps and shader
logic; it does not claim to repair a proven renderer or source-data defect.

`display_metrics.json` measures the same chapel floor rectangle in output PNG RGB.
These are display values after scene rendering, **not raw linear HDR or shader ALBEDO**.
The region includes real joints and shadows. The unshaded-vs-lit difference alone is
not proof of a shader or tonemapper defect.

## Verification and limits

- `import.txt`: required headless editor import passed, no errors.
- `smoke.txt`: required two-process ENet smoke passed, including mismatched-build refusal.
- `controls.txt` and `decisive-controls.txt`: valid runtime captures, no script/shader errors.
  Capture teardown retains Godot texture/ObjectDB leak warnings; these are recorded rather
  than reported as a clean runtime shutdown.
- No camera/input/Tailscale/manual multiplayer acceptance was performed.

An intermediate capture attempt raced the arrival of T-162's new global dressing class
before editor import. Its flat frames were detected during log/pixel inspection and overwritten
by the valid post-import captures retained here. All conclusions use the retained real frames.

## Requested material calibration candidate

`material-calibration/` is a runtime-only art-tuning candidate: tint (0.88, 0.85, 0.80),
variation 0.14, ALBEDO AO influence 0.25 and grime 0.15. It preserves all maps/UVs,
normal mapping, AO output, wear, roughness, geometry, real lights and the live torch updater.
`calibration.txt` asserts the updater is running with 5/5/6 active shadow lights.
This is a reflectance calibration, not a proven renderer or source-data bug fix.

Compared with the original baseline, floor-region display luminance below 0.05 changes
from 16.01% to 0.92% in the chapel, 20.56% to 8.82% in the restraint hall, and 15.29% to
0.98% in the nave. Mean output luminance rises from 0.06643/0.09604/0.07080 to
0.10215/0.11712/0.10637. Joints, chips, textured surfaces and stone tone differences remain
visible; true fixture shadows remain. The rectangles include shared props and joints, so
these are comparison indicators, not material-only or physical luminance measurements.

Reproduce with the capture command above and `--modes=material-calibration`, then
`python3 content/environments/red_descent/review/floor_shader_fix_v1/measure_calibration.py`.
The parent inspected all three candidate images and approved these four defaults before production edits.

## Approved production defaults

`production/` captures the actual standard/clipped production shader resources, with no
runtime material override. The dungeon updater is active and 5/5/6 real shadow lights
are asserted on after warmup. The three views match the approved candidate, retaining
scanned grain, chipped edges, joints, varied stone tones and real shadows.

The only runtime-source difference is the four uniform defaults at the top of
`flagstone.gdshaderinc`. `production_identity.json` records the updated include hash and
verifies that floor-helper, geometry, dungeon and dressing hashes are unchanged. The
original 14 control image sets and baseline shader copy are unchanged since `93f49e6`.

`production_metrics.json` shows the same improvement as the candidate: floor-region
Y < 0.05 fractions are 0.92% / 8.82% / 0.98%, compared with the original
16.01% / 20.56% / 15.29% (chapel / restraint / nave). These do not claim every dark
speckle or genuine shadow has disappeared.

`production-import.txt` and `production-smoke.txt` pass with no script/shader errors.
Capture texture/ObjectDB and smoke ObjectDB teardown warnings remain recorded in logs.
The parent owns the final combined dressing/bridge checks and wider 14-view capture.

Reproduce production captures with the command above and `--modes=production`, then
`python3 content/environments/red_descent/review/floor_shader_fix_v1/measure_calibration.py production`.
