# Voina

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
| Block / parry | Hold Shift or right click; parry during the first 0.18 s (plus up to 0.08 s latency grace) |
| Dash | Space + movement direction (forward if stationary) |
| Jump | C |
| First/third person | V, or pinch |
| Quick turn | R |
| Release cursor | Esc or focus loss |
| Recapture | Left click |

**E remains the test beam; Shift/right click blocks.** Release the cursor with Esc and click **Controls** to rebind keyboard actions or change sensitivity. Bindings persist locally in Godot's `user://controls.cfg`; duplicate keys are rejected. Left/right mouse bindings remain available. Camera switching currently snaps. Capsules use procedural placeholder geometry; no external assets or asset licenses are needed.

## Implemented

- 24 m greybox arena, four cover blocks, host/join overlay and health HUD.
- Up to four capsule players, peer-ID ownership, custom `MultiplayerSpawner` spawns and automatic late-join replication.
- Local movement and camera, 30 Hz synchronized motion, interpolated remote bodies, generous host movement checks.
- Separate **host-owned combat synchronizer** for health, stamina, poise, block and combat phase. Client movement authority cannot overwrite these values.
- Host-only hit resolution, sender ownership and cooldown checks, delayed 70-degree/2.2 m melee cone with wall check, 40 m hitscan, knockback and immediate respawn at zero health.
- Explicit host-timed 0.15 s windup → 0.12 s active → 0.25 s recovery. The host sweeps the cone every physics tick of the active window and hits each target at most once per swing; interruption, parry and respawn cancel pending swings.
- The owner predicts its own swing locally: 7 m/s forward lunge during active frames, slowed walking and a 4 rad/s turn-rate limit through active and recovery. The host repeats every check and cancels a prediction it rejects.
- 100 stamina, melee cost 18, beam cost 8, dash cost 35; 22/s regeneration after 0.7 s without spending or taking a hit, while idle and not blocking.
- Front-facing block reduces health damage by 80% and costs 20 stamina per hit. First 0.18 s (padded by the defender's ENet one-way latency, capped at 0.08 s) parries melee and staggers the attacker for 0.8 s. Back attacks bypass guard; exhausted guard breaks. Re-raising block is limited to once per 0.35 s.
- Directional 16 m/s dash for 0.25 s with 0.15 s of host-owned ranged immunity; melee remains effective. The owner starts the dash immediately from replicated stamina/phase; host rejection cancels it.
- Poise damage (melee 35, beam 15), stagger at zero, 18/s idle regeneration. Incoming hits interrupt melee windup.
- The host clamps a staggered player's horizontal drift to 2 m of knockback slack plus walking during that peer's measured round trip, so ignoring stagger locally is corrected.
- Confirmed-hit text, body flash, camera shake and 0.06 s visual hitstop; game/network time keeps running.
- 0.35 m camera shape cast gives 0.55× look sensitivity over a target. Projectile magnetism awaits projectile weapons.
- Third-person spring-arm exclusion and first-person body shadows; cursor release on focus loss.
- CLI hosting, joining, dedicated server and configurable port.

The host trusts client movement inside a generous envelope. This is a friend-group prototype, not competitive anti-cheat or historical lag compensation. Hitscan uses the host's current view of player position/aim. The test beam visual extends to maximum range, including through walls; damage still uses the first physics collision.

## Verify

```sh
"$GODOT" --headless --editor --path . --quit
python3 scripts/smoke_test.py "$GODOT"
```

The command first runs deterministic combat tests and a host-side stagger enforcement test (parry expiry and capped latency grace, directional guard, active-window sweep and per-target hit dedupe, guard break, resource costs/regeneration, dash immunity and interrupted swings), then starts host and client processes on loopback, checks both player spawns, fires a beam, checks replicated health, rejects an attack sent through another player's node, checks cooldown, lethal-hit respawn, one hit per multi-tick melee swing, replicated block/dash, cancellation of a rejected predicted dash, invalid vectors, forged block/dash ownership, and disconnect cleanup. Godot generates `.gd.uid` files during import; commit them.

Before calling this ready for friends, run two visible instances and verify walking, jumping, both cameras, cover occlusion, melee, beam, block/parry, stamina, directional dash, hit feedback, aim friction, saved key remapping, knockback, respawn, cursor release, late join and reconnect via restarting. Then repeat over Tailscale on two Macs. Automated tests do not establish trackpad feel, visual quality, WAN behavior or thermal performance.

## Collaborate

Install Git LFS before adding binary assets (`brew install git-lfs`, then `git lfs install`). The repository already tracks GLB, PNG, WebP, WAV and OGG through LFS. Never share a live working directory between editors; ignore `.godot/`, commit `.uid`, and use separate clones/branches.

See [roadmap](docs/roadmap.md), [original supplied brief](docs/original-brief.md), and [agent rules](AGENTS.md). The original brief is a design reference, not a verified inventory of implemented features.

Engine references: [Godot 4.7.2 release](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable), [MultiplayerSpawner](https://docs.godotengine.org/en/stable/classes/class_multiplayerspawner.html), [MultiplayerSynchronizer](https://docs.godotengine.org/en/stable/classes/class_multiplayersynchronizer.html).
