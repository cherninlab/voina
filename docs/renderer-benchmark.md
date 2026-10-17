# Renderer benchmark

`scripts/renderer_benchmark.py` measures what Forward+ effects would cost on the village before anyone changes `rendering_method` (still `mobile`). It loads only `gameplay/environment/village_arena.gd`, no players or networking, and runs it once per renderer through Godot's `--rendering-method` flag, so `project.godot` stays unchanged.

```bash
python3 scripts/renderer_benchmark.py "$GODOT"
```

Run it on a Mac you are sitting at, with the screen unlocked; it takes about 10 minutes. The window stays on top.

## How it measures

- Metal returns 0 from `viewport_get_measured_render_time_gpu`, so the script uses wall-clock frame time with vsync off.
- A single view is capped by display pacing (8.33 ms at 120 Hz, about 6.9 ms when uncapped). Each frame therefore renders the view in 20 offscreen 1600×1000 SubViewports (2× MSAA + FXAA, like the window), and the table divides by 20.
- macOS stops drawing windows that are covered, on a locked screen or a sleeping display. Frames then look fast because nothing renders. Every sample records the fraction of frames actually drawn, and the table prints `-` below 95 %.
- Configs: baseline (current ACES + distance fog), AgX + glow, then SSAO, SSIL, SSR, SDFGI and volumetric fog one at a time, then all of them. Three views: ground level in the square, by the houses, and overhead.

## Results so far (Apple M5 Max, Godot 4.7.2, main 95d3417, 2026-10-18)

Milliseconds of frame time per view, median. Only samples where at least 95 % of frames were drawn are listed.

| config | mobile | forward+ |
|---|---|---|
| baseline | 1.34 / 1.46 / 1.63 | 1.28 / 1.29 / 1.45 |
| AgX + glow | 2.10 / 1.71 / 1.81 | 1.41 / 1.44 / 1.73 |
| SSAO | not supported | 1.53 / 1.55 / 1.75 |
| SSIL | not supported | 1.58 / 1.61 / 2.17 |
| SSR, SDFGI, volumetric fog, all | not supported | not yet measured cleanly |

An earlier Forward+ run had about twice these times throughout: baseline 2.93, SSIL 3.7–4.1, SSR 3.6–4.0, volumetric fog 2.6. Other sessions on this Mac may have been using the GPU during either run, so the absolute values carry roughly 2× uncertainty. Comparisons within one run hold up better.

What this supports:

- On this scene and Mac, Forward+ with no extra effects costs about the same as Mobile. Switching the renderer alone is not the expensive part.
- The screen-space effects each add a few tenths of a millisecond per view at 1600×1000.
- SDFGI and volumetric fog, the two effects behind the Enshrouded look, still need an attended run, and so does Mike's MacBook Air. Do not quote these numbers as a frame budget for that machine.
