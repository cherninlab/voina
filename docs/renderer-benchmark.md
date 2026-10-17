# Renderer benchmark

`scripts/renderer_benchmark.py` measures what Forward+ effects would cost on the village before anyone changes `rendering_method` (still `mobile`). It loads only `gameplay/environment/village_arena.gd`, no players or networking, and runs it once per renderer through Godot's `--rendering-method` flag, so `project.godot` stays unchanged.

```bash
python3 scripts/renderer_benchmark.py "$GODOT"
```

It takes about 10 minutes. It refuses to start while any other Godot process runs (tests, a playtest host, an editor) and stops itself if one starts: they skew its numbers, and its GPU load breaks timing-sensitive network tests.

## How it measures

- Metal returns 0 from `viewport_get_measured_render_time_gpu`, so the script uses wall-clock frame time.
- macOS skips the normal draw while the window counts as hidden: behind a full-screen app, in another Space, or on a locked screen. The script therefore forces each frame with `RenderingServer.force_draw` and never presents, which also removes display pacing (8.33 ms at 120 Hz).
- Each frame renders the view in 20 offscreen 1600×1000 SubViewports (2× MSAA + FXAA, like the window), and the table divides by 20.
- Configs: baseline (current ACES + distance fog), AgX + glow, then SSAO, SSIL, SSR, SDFGI and volumetric fog one at a time, then all of them. Three views: ground level in the square, by the houses, and overhead.

## Results

None are valid yet. Earlier runs on 95d3417 predate the current village (e97a2fb added assets and landscape). They also overlapped a live client and other agents' tests, and macOS stopped drawing the window partway through. Those numbers are withdrawn; do not quote them. The forced-draw version has not been run yet: other Godot processes were running the whole time.
