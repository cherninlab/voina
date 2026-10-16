# Leaving and reconnecting

The startup lobby has an overhead arena camera. Choose Host or Join as usual. The lobby sits beside the sword tuning panel; Controls remains available for saved key bindings.

During a game, press **Esc** to release the cursor, then choose **Leave game**. This returns to the lobby without restarting Godot. While a connection is pending, the same button says **Cancel connection**. Host/Join and address/mode editing are disabled until the pending connection is cancelled or finishes, preventing overlapping attempts.

If the host leaves or a connection fails, the client returns to the lobby with a status message and an active camera. Once the host is available, choose **Join game** again. Old players, raiders, flying bolts, wildlife activity and match presentation clear before a fresh session starts. Host options and the address remain available for reuse.

Build authentication still applies to every new connection. A build refusal returns to the lobby with the host's commit and sync command. Sync the [pinned playtest copy](playtest.md) on both Macs when changing builds; joining again cannot replace source files in an already-running game. Restart that game after syncing its build.

## Verify

```sh
"$GODOT" --headless --editor --path . --quit
python3 scripts/session_smoke_test.py "$GODOT"
python3 scripts/smoke_test.py "$GODOT"
```

The focused check loads the real arena and exercises the startup camera, Leave button, projectile cleanup, repeated hosting and the connection-failure handler. A real ENet pair then leaves the host, restores both lobbies, hosts again and reconnects the same client process with fresh player/mob replication and matching build authentication. CI also runs the PvE and wildlife suites. These checks verify lifecycle behavior; human UI and two-Mac Tailscale acceptance remain separate.
