# T-175 flagstone shading investigation

The black/noisy per-stone floor patches remain unresolved. **No production shader,
geometry, GLB, collision, floor placement, clipping, lighting or UI grading changed.**
This is an evidence-only increment, not a visual fix or acceptance claim.

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
No evidence supports changing geometry, tangents, baked AO, procedural noise, specular,
roughness or shadows to repair this symptom. The isolated sensitivity is to ALBEDO,
which could still be material/light response rather than bad source data. Brightening or
flattening the material would hide the symptom; that was not applied as a purported fix.

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
