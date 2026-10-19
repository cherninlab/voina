# SECHA interface

The title screen loops the supplied illustrated village video (`content/ui/secha-menu-background.ogv`, silent Theora at 12 fps). The branching white logo and four ivory serif choices occupy the clear purple left side; the swordsman remains unobstructed. The complete frame fits the viewport with black letterboxing where needed. Music is a separate looping MP3. The short source clip repeats directly; a seamless motion join is not claimed.

- Host game opens raider/round options and a Host game action.
- Join game opens the host address and Join game action. Enter submits the address.
- Back or Escape returns to the title. Settings opens the existing controls panel.
- Logo and navigation scale with viewport dimensions.
- An indeterminate connection loader with cancellation while awaiting the host and player spawn. It does not invent completion percentages or pretend to asynchronously load assets.
- Connection errors return to the lobby with the real status message.
- Escape opens a local pause menu. Resume recaptures the cursor; Controls opens the existing key/sensitivity/fisheye panel; Leave returns to the lobby. The host simulation and networking keep running.
- A compact health/stamina/poise HUD replaces the always-visible debug text. `--debug-hud` restores the previous detailed readout. Existing sword tuning remains accessible from the pause screen.

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
