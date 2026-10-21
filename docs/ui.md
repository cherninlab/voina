# SECHA interface

The title screen loops the supplied illustrated village video (`content/ui/secha-menu-background.ogv`, silent Theora at 12 fps). The branching white logo and four ivory serif choices occupy the clear purple left side; the swordsman remains unobstructed. The complete frame fits the viewport with black letterboxing where needed. Music is a separate looping MP3. The short source clip repeats directly; a seamless motion join is not claimed.

- Host game opens raider/round options and a Host game action.
- Join game opens the host address and Join game action. Enter submits the address.
- Back or Escape returns to the title. Settings opens the existing controls panel.
- Logo and navigation scale with viewport dimensions.
- An indeterminate connection loader with cancellation while awaiting the host and player spawn. It does not invent completion percentages or pretend to asynchronously load assets.
- Connection errors return to the lobby with the real status message.
- Escape opens a local pause menu. Resume recaptures the cursor; Controls opens the existing key/sensitivity/fisheye panel; Leave returns to the lobby. The host simulation and networking keep running.
- A compact health/stamina/poise HUD replaces the always-visible debug text. `--debug-hud` restores the previous detailed readout. Existing sword tuning remains accessible from the pause screen: the sword, camera, shading and MPEG tweaks fold out down the top-right corner while paused, in a compact look (white 12 px type on a thin black wash, flat buttons; `GameUI.compact_theme`, T-116).

Mik's fisheye implementation, camera controls, combat authority and ENet transport are unchanged. The window, menu and HUD use the SECHA name. The existing application data directory is explicitly retained to preserve saved bindings, sensitivity, fisheye strength and sword tuning.

## Checks and captures

```sh
"$GODOT" --headless --editor --path . --quit
python3 scripts/session_smoke_test.py "$GODOT"
python3 scripts/smoke_test.py "$GODOT"
"$GODOT" --path . --script scripts/capture_ui.gd -- --port=7794 --capture-dir=/absolute/output/folder
```

The session check covers Escape pause/resume, controls, keeping simulation unpaused, the pending loader and its actual Cancel button, failure return, leave/rehost and authenticated two-process reconnect. The capture script saves lobby, connecting, failure-return, gameplay, pause and controls frames from the real game. Its failure-return capture deliberately exercises a failure state; it is not a recorded internet outage. Live trackpad usability and two-Mac Tailscale acceptance remain human checks.

Fullscreen panels use a viewport-height UI scale (900 logical pixels, capped at 2.5×), so setup, pause, settings, HUD and tuning controls remain readable on Retina displays. Title composition retains its video-relative placement. Original GUI styling uses dark plum surfaces, ivory text and muted crimson highlights inspired by the supplied references, without importing their artwork.

## Title screen

The boot splash is the user-supplied it'snotthat logo (`content/ui/itsnotthat_splash.png`, 1920x1080, logo centred at half height on black) on a black background, and the app icon (`content/ui/itsnotthat_icon.png`) is the same logo on a black rounded square instead of the Godot logo. The title screen that follows is plain black: the SECHA logo and the Host / Join / Settings / Quit choices share one centred column, placed in viewport-relative logical coordinates, with aged ivory text and amber selection rules. All menu and HUD type uses a sans-serif system font (Helvetica Neue, falling back to Helvetica, Arial, then the system sans). The soundtrack loop remains. The earlier character still `content/ui/secha-menu-grim.png` stays on disk but is no longer shown.

While the opaque title is visible offline, its viewport skips covered 3D drawing and hides the covered world fisheye/colour pass. Host/join/connecting transitions restore rendering, and leaving restores title culling. This is a presentation optimisation only; game/network clocks continue. See `docs/graphics-audit.md` for measured limits.

## Perf meter

A compact meter sits in the top-left corner from the start; F3 (fn+F3 on a Mac keyboard, where F3 alone is Mission Control; rebindable as "Perf Overlay" in Controls) hides and shows it (`ui/perf_meter.gd`, T-111, shown by default since T-116). A big FPS number, coloured by the verdict, sits above short caption lines:

- `fps · 1% <low> · <frame>/<budget> ms`: the 1 % low is the 99th-percentile frame of the last 300 frames (about 5 s). The budget comes from `Engine.max_fps` (60, set in `match_world.gd`).
- `cpu <sum>  scr / phy / rnd`: main-thread milliseconds per frame for scripts (all `_process` callbacks plus the deferred-call flush), physics (first `_physics_process` to the start of `_process`, so the Jolt step is included) and render CPU (`viewport_get_measured_render_time_cpu` plus frame setup).
- `gpu <ms>|n/a  wait <ms> idle <ms>`: GPU time from `viewport_get_measured_render_time_gpu`; `wait` is draw wall time (`frame_pre_draw` to `frame_post_draw`) minus render CPU, i.e. the main thread blocked on the GPU or swapchain; `idle` is from the end of drawing to the next iteration (the fps-cap sleep, input, audio). Together they add up to the frame time.
- `draws · obj · tris`: Performance render counters for the frame.
- Verdict: `under budget (capped at 60)` when neither side reaches 85 % of the budget; otherwise `GPU-bound` or `CPU-bound (scripts|physics|render)`, whichever is larger. A slow frame with no large term reads `over budget, cause unclear (OS / sync)`.

Limits:

- Godot 4.7.2's Metal driver returns 0 for GPU timestamps, so on Macs `gpu` reads n/a and the draw wait stands in for the GPU. It counts only while frames miss the cap, because at the cap that wait can be vsync, so a GPU close to its budget but still holding 60 fps reads "under budget".
- Timings are wall-clock microsecond stamps averaged over 0.5 s. The process delta is not used, because delta smoothing hides spikes. `Performance.TIME_PROCESS` is not used either: it is a once-per-second maximum that also includes drawing.
- Headless runs draw nothing, so there are no GPU, wait or render times.
- Hidden, the meter does no per-frame work: processing is off, the draw signals are disconnected and render-time measurement is switched off. `tests/perf_meter_test.tscn` checks this, together with the classification from fake timings.

Measured on this Apple M2 Mac in a 1152×720 window (2026-10-20, host offline, T-111): village about 31 fps (25.7 M triangles, about 860 draw calls), GPU-bound with cpu 4.3 ms and wait 27 ms. The haunted forest ran 39 fps (GPU-bound, wait 22 ms) to a capped 60 fps depending on the view. A forced 22 ms script busy-loop read `CPU-bound (scripts)`, and a heavy full-screen shader read `GPU-bound`.
