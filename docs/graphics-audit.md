# Graphics audit, 2026-10-19

This is a scoped audit of the grim village rendering and title path, not acceptance of all art or a claim of maximum optimisation. The generated red-sky/comic menu keyframes are references; the game still uses the native still background. No completed comic menu video is implemented.

## Alignment

At the first worktree inventory, main was a47ee88 and the playtest was 1ba6e54 (18 commits behind). Every local worktree's committed HEAD was an ancestor of origin/main; none had unpushed branch commits. Uncommitted church refinement, chapel import, haunted forest, and old terrain work remained with their owners. The forest/church/terrain owners continued shipping during this audit. Use the board and a fresh worktree inventory for current status; do not treat this historical snapshot as live state.

T-095 changes only its claimed files. It does not copy unfinished files out of other worktrees, change the renderer, modify physics, or rewrite the church/road/forest/mob work. Coordination notes are on T-095 and T-092. Village fixtures remain locally bounded because the Mobile renderer has an eight-omni-light limit per mesh; a single village-wide merged mesh would conflict with the road light-budget work.

## Verified issues fixed

- The opaque native title rendered the full 3D world underneath. It now disables 3D on that viewport while offline and hides the covered world fisheye/grade layers. The menu still uses its own shared grade material. Hosting/joining/connecting restore 3D before showing it; returning to the title disables it again. This does not pause network/game simulation.
- Lanterns and windows used 92 separate small meshes. Each fixture now merges its geometry into one two-material mesh: 12 mesh nodes in the checked scene, with the same shapes and normals and local light pairing. It does not merge distant fixtures or introduce instancing/LOD abstractions.
- Deferred village dressing overwrote the startup theme: Night requested fog 0.012 but ended up at 0.006. The dressing now reapplies the current theme after setup; Night's fog assertion passes. Material overrides are applied once per visual rather than repeatedly per underlying surface.
- A vertical bright line in the storm sky came from implicit mip selection across the spherical UV wrap. Explicit base-level panorama sampling removes the stripe in the matching real-render capture. No source-image repaint was needed.
- The audit camera initially used a controlled 75-degree projection under a wider fisheye remap. Final art captures now take their source FOV from the actual player camera. Controlled-view timings and live-projection captures are distinguished below.

## Measurement and evidence

Device: Apple M5 Max, Godot 4.7.2 Mobile/Metal, one 1600x1000 viewport, vsync off, engine cap removed. `scripts/grim_render_check.gd` warms 40 forced draws and samples 160. Numbers are wall-clock forced-render submission/wait samples, not GPU timestamps, gameplay FPS, input latency, sustained fullscreen performance, thermals, or base-M2 acceptance. Other headless checks may use CPU. The helper skips timings if another graphical Godot process exists before or after a sample; captures-only mode still allows functional/visual checks.

Initial same-run menu comparison (before optimisation): world on 5.40ms median / 6.04ms p95, 1822 draws; covered 3D disabled 0.23 / 0.27ms, 12 draws. This is evidence for removing covered work, not a whole-game speedup percentage.

A later integrated-content run showed menu world on 5.48 / 6.28ms, 1773 draws; off 0.14 / 0.28ms, 10 draws. That run was not an isolated before/after game benchmark: forest/church content had changed and other captures resumed around the run. Its frame timings are provisional. Geometry counts and transition assertions remain useful.

Sky ablation in the original fixed 75-degree view: dynamic 3.50 / 3.77ms versus static 3.51 / 3.74ms. No meaningful win was established, so the sky animation path was retained. The integrated actual-player-FOV view reported about 4.25 / 4.60ms, 1704 draws and 16.7m submitted primitives; that is an optimisation lead requiring clean hardware profiling, not performance acceptance. Avoid comparing it to the 75-degree view.

Import and combat/network smoke passed. Leave/rehost/authenticated reconnect passed. Real-render assertions cover the menu/host/leave transition, batched fixtures, storm material, dark haze, and sun selection excluding the lightning light. Separate headless Night-startup regression proves the deferred-theme fix. Final real-render captures were inspected for fixtures, haze, layout and sky seam. The earlier temporary capture harness's exit-resource warning did not recur with deferred quit/cleanup in the final check.

Commands:

```sh
"$GODOT" --headless --editor --path . --quit
python3 scripts/smoke_test.py "$GODOT"
python3 scripts/session_smoke_test.py "$GODOT"
"$GODOT" --headless --path . --script scripts/grim_render_check.gd --quit-after 150 -- --shading=Night --shading-ephemeral --audit-invariants-only
"$GODOT" --path . --script scripts/grim_render_check.gd -- --shading-ephemeral --audit-dir=/absolute/output
# Functional/capture check without timing load while other artists capture:
"$GODOT" --path . --script scripts/grim_render_check.gd -- --shading-ephemeral --audit-captures-only --audit-dir=/absolute/output
```

## Still not accepted

- Final menu art/character performance and a smoothly animated dark-comedy loop: only generated keyframes exist. Identical first/last PNGs do not establish seamless video motion.
- Full art match to the selected references. Mountain silhouettes, ground repetition, vegetation/prop quality, lighting contrast and the current player pose remain visibly different.
- Terrain seams, collision/material alignment and prop grounding are being audited by the terrain owner (T-097); church refinement/chapel and forest refinements remain in their owners' scopes. Their final combined acceptance is not implied by a clean import.
- A new clean, fixed-content performance baseline on the target lower-spec Macs, sustained native fullscreen motion, four-player load, GPU/CPU profiling, and thermal checks. The submitted primitive/draw counts merit further local batching/LOD work, guided by measurement and preserving Mobile light pairing.
- Manual trackpad/camera acceptance and a two-Mac Tailscale playtest. Headless suites and isolated frame samples do not prove these.
