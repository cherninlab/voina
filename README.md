# MultiPlayerProject

A Godot **4.7.2 Standard / typed GDScript** multiplayer combat starter for 2–4 friends on MacBooks. Mobile renderer, native Metal, built-in Jolt; Git for collaboration and ENet over LAN/Tailscale for game traffic.

## Run

Open `project.godot` in Godot 4.7.2 and press **F5**. Choose **Host game** on one Mac, then enter its LAN IP or Tailscale MagicDNS hostname and choose **Join game** on the other. Both Macs need their own checkout. Allow incoming network traffic in the host's macOS firewall. Default port: **UDP 7777**.

Or launch from Terminal (set `GODOT` to your installed binary):

```sh
export GODOT=/Applications/Godot.app/Contents/MacOS/Godot
"$GODOT" --path . -- --host
"$GODOT" --path . -- --join=127.0.0.1
# Friend's Mac, with Tailscale connected:
"$GODOT" --path . -- --join=your-host-magicdns-name
# Headless server, four client slots:
"$GODOT" --headless --path . -- --server --port=7777
```

No export templates or third-party addons are required to run from the editor.

| Action | Control |
| --- | --- |
| Move / look | WASD / trackpad glide |
| Melee / hitscan | F or left click / E |
| Jump | C |
| First/third person | V, or pinch |
| Quick turn | R |
| Release cursor | Esc or focus loss |
| Recapture | Left click |

This milestone deliberately assigns **E to the test beam**. The full design's E/block, stamina, dash, weapon swap, aim assist, and match scoring are future work. Camera switching currently snaps. Capsules use procedural placeholder geometry; no external assets or asset licenses are needed.

## Implemented

- 24 m greybox arena, four cover blocks, host/join overlay and health HUD.
- Up to four capsule players, peer-ID ownership, custom `MultiplayerSpawner` spawns and automatic late-join replication.
- Local movement and camera, 30 Hz synchronized motion, interpolated remote bodies, generous host movement checks.
- Separate **host-owned health synchronizer**. Client movement authority cannot overwrite health.
- Host-only hit resolution, sender ownership and cooldown checks, delayed 70-degree/2.2 m melee cone with wall check, 40 m hitscan, knockback and immediate respawn at zero health.
- Third-person spring-arm exclusion and first-person body shadows; cursor release on focus loss.
- CLI hosting, joining, dedicated server and configurable port.

The host trusts client movement inside a generous envelope. This is a friend-group prototype, not competitive anti-cheat or historical lag compensation. Hitscan uses the host's current view of player position/aim. The test beam visual extends to maximum range, including through walls; damage still uses the first physics collision.

## Verify

```sh
"$GODOT" --headless --editor --path . --quit
python3 scripts/smoke_test.py "$GODOT"
```

The integration check starts host and client processes on loopback, checks both player spawns, fires a beam, checks replicated health, rejects an attack sent through another player's node, checks cooldown, lethal-hit respawn, delayed melee, and disconnect cleanup. Godot generates `.gd.uid` files during import; commit them.

Before calling this ready for friends, run two visible instances and verify walking, jumping, both cameras, cover occlusion, melee, beam, knockback, respawn, cursor release, late join and reconnect via restarting. Then repeat over Tailscale on two Macs. Automated tests do not establish trackpad feel, visual quality, WAN behavior or thermal performance.

## Collaborate

Install Git LFS before adding binary assets (`brew install git-lfs`, then `git lfs install`). The repository already tracks GLB, PNG, WebP, WAV and OGG through LFS. Never share a live working directory between editors; ignore `.godot/`, commit `.uid`, and use separate clones/branches.

See [roadmap](docs/roadmap.md), [original supplied brief](docs/original-brief.md), and [agent rules](AGENTS.md). The original brief is a design reference, not a verified inventory of implemented features.

Engine references: [Godot 4.7.2 release](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable), [MultiplayerSpawner](https://docs.godotengine.org/en/stable/classes/class_multiplayerspawner.html), [MultiplayerSynchronizer](https://docs.godotengine.org/en/stable/classes/class_multiplayersynchronizer.html).
