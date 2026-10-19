# SECHA interface

T-035 adds native Godot controls. T-072 makes the theme strictly black and white (black fills, white hairlines and text, hover inverts) and puts the SECHA logo above the lobby panel:

- The logo (`content/ui/secha_logo.png`, white with alpha, cut from the supplied white-on-black artwork) scales with the window: up to 62% of its width or 900 px, shrinking so logo plus panel fit the window height, never under 220 px.
- A centered host/join menu with host address, existing raider/round switches and Controls.
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
