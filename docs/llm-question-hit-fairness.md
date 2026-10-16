# Question: fair hit registration and host advantage in a 2–4 player listen-server game (Godot 4.7.2)

I'm building a small 3D multiplayer melee + ranged arena game in **Godot 4.7.2 Standard, typed GDScript** (Mobile renderer, Metal, built-in Jolt, Apple Silicon MacBooks). 2–4 friends play over LAN or Tailscale (RTT ~10–80 ms, some jitter). Usually one friend **hosts and plays** (listen server, peer 1). A headless dedicated server mode also exists. Transport is `ENetMultiplayerPeer` with Godot's high-level API. No addons, no rollback library, and no plan for full-world rollback.

The combat systems work and are tested. The problem I want solved now is **fairness**: who wins trades, what each player sees vs what the host decides, and how to stop the hosting friend from having a structural advantage.

## How hits are decided today

**Movement** is client-authoritative. Each player's machine runs `move_and_slide()` and replicates `sync_position`, `sync_velocity`, `yaw` and `pitch` through a `MultiplayerSynchronizer` (authority = owner, `replication_interval = 1/30`, `REPLICATION_MODE_ALWAYS`). On every other peer, including the host, the node's displayed `position` chases `sync_position` with `position.lerp(sync_position, 1 - exp(-20 * delta))`. `yaw` and `pitch` are applied raw. The host checks movement loosely (an elapsed-time speed envelope, plus a drift clamp while a player is staggered). `Engine.max_fps = 60`; default physics tick rate.

**Combat** is decided on peer 1 by a tick-driven `CombatController` state machine:
- **Melee:** windup 0.15 s → active 0.12 s → recovery 0.25 s. The owner predicts the swing locally, including a 7 m/s forward lunge and a 4 rad/s turn limit, and sends `request_attack` by RPC. The host starts its own windup when that RPC arrives. On every physics tick of its active window, the host tests a 70° / 2.2 m cone from the attacker's **host-side interpolated `global_position`** and **latest replicated `yaw`/`pitch`**, against each target's **host-side interpolated `global_position`**, plus a line-of-sight ray. Each target is hit at most once per swing.
- **Hitscan beam:** 40 m ray, resolved the instant the host accepts the request, using the same host-side positions and replicated aim.
- **Block/parry:** block reduces damage 80% from the front (defender's replicated yaw). Parry is block raised within 0.18 s of the hit, plus the defender's ENet one-way latency (RTT/2, capped at 0.08 s).
- **Dash:** 0.25 s at 16 m/s; immune to ranged hits for the first 0.15 s, judged by host clock from when the host accepted the dash.
- Knockback and respawn reach the owner via `correct_position(location, impulse)`. The owner applies the impulse to its own velocity.

Simplified host-side melee check:

```gdscript
var origin: Vector3 = global_position + Vector3.UP * 0.65          # attacker as the host currently displays it
var forward: Vector3 = Vector3.FORWARD.rotated(Vector3.RIGHT, pitch).rotated(Vector3.UP, yaw)
for other: CharacterBody3D in players:
	var offset: Vector3 = other.global_position - global_position     # target as the host currently displays it
	if offset.length() <= 2.2 and forward.dot(offset.normalized()) >= cos(deg_to_rad(35)):
		# line-of-sight ray, then combat.strike(peer_id) dedupe, then receive_hit(...)
```

## Why I think this is unfair (please verify or correct)

- **The host's own player** attacks with zero delay, using its exact local position, against targets the host sees with interpolation lag. Its own block, parry and dash windows also start with no delay.
- **A client attacker** aims at targets it sees with its own interpolation lag. Its request reaches the host one-way later. Its swing then resolves against where the host shows targets *at that moment*, from an attacker position the host itself displays late (owner one-way + up to 33 ms snapshot + lerp lag of roughly 50 ms). Beam shots that looked like hits on the client's screen can miss.
- **A client defender's** block, parry and dash inputs arrive one-way late, which is only partly offset by the parry grace.
- The swing lunge moves the attacker on its owner's machine immediately but on the host later, so the cone origin and attack timing are offset in time.
- Dedicated-server mode removes the host-player advantage but adds a hop for everyone.

## Constraints

1. Keep peer 1 authoritative for all combat outcomes; clients must not be able to claim hits freely. Friend-group level of trust, not esports anti-cheat, but clamped/bounded claims.
2. Keep owner movement and camera zero-latency.
3. No full rollback; small, readable, typed GDScript; no speculative subsystems. Must also work in headless dedicated mode.
4. Must remain testable headless with two or more Godot processes on loopback.
5. Later (M3) there will be server-spawned swept projectiles and more melee weapons, so the approach should extend to them.

## Questions

1. **Diagnosis.** Quantify the effective "what you saw vs what the host decided" offset for each case (host vs client, client vs client, client vs host), at 20 / 60 / 100 ms RTT, given 30 Hz snapshots and an exponential lerp with rate 20. Which inputs dominate: snapshot interval, lerp lag, or one-way latency?

2. **Remote-entity interpolation.** Should I replace the `lerp` chase with **buffered snapshot interpolation** (render remote players at `now - interp_delay` between two timestamped snapshots)? How do I get usable timestamps from `MultiplayerSynchronizer` in Godot 4.7.2: a replicated `sync_time` property, `delta_synchronized`/`synchronized` signals, or ENet-derived clock offset? What `interp_delay` is sensible at 30 Hz, and should I raise the rate to 60 Hz? How does this change interact with the host's movement validation?

3. **Lag compensation (rewind).** Is a small **host-side position history** (~250 ms ring buffer of each player's position and yaw per physics tick) worth it at this scale? If yes, specify:
   - how the host estimates the attacker's "view time" (client sends its render timestamp, or the host infers it from RTT/2 + interp delay);
   - the cap on rewind (e.g. 150–200 ms) and how to reject forged timestamps;
   - how to rewind for a cone + line-of-sight check without moving real physics bodies (pure math on stored positions vs temporary query shapes);
   - how rewind interacts with **block/parry/dash timing**: is the defender judged at the rewound time or the present? Address "shot behind cover" and "I blocked but still got hit" cases explicitly.

4. **Alternative: bounded shooter-favoring claims.** Compare rewind against the simpler pattern where the client sends `(target_peer_id, local_hit_point, aim_origin, aim_dir)` and the host accepts if the claim lies within a tolerance of the target's recent positions, with a line-of-sight check. Which is better for hitscan, and which for melee cones? Can one approach serve both, plus future projectiles?

5. **Melee timing alignment.** The owner predicts windup and lunge immediately, but the host starts windup when the RPC arrives. Should the host back-date the swing start by the attacker's one-way latency, with a cap? Should the active-window sweep use the attacker's replicated position (which includes the lunge) or a host-simulated lunge? How do I keep "parry → stagger" cancellation correct if the swing is back-dated?

6. **Host advantage specifically.** Concrete ways to neutralize the listen-server host's advantage: artificially delay the host player's own inputs by an average client latency, run the host's own attacks through the same rewind path, or simply recommend dedicated mode for fair matches. Which do friend-group games actually use, and what does each cost in feel?

7. **Code shape.** The minimal typed GDScript structures: a `PositionHistory` ring buffer (or similar), the RPC signature changes (`request_attack(ranged: bool, view_time_ms: int, ...)`), the clock sync piece, and where these live (player script vs a small `LagCompensation` node vs `NetworkManager`). Use `@rpc` modes correctly for Godot 4.x: host-to-client RPCs on a client-owned node must be `any_peer` with a sender == 1 check, not `"authority"`.

8. **Testing.** How to prove fairness headlessly: deterministic tests for the rewind math, plus a two-process loopback test with **artificial latency injected inside Godot** (e.g. delaying outgoing RPCs or snapshot application). What assertions show "a hit that was valid on the attacker's screen is accepted, and a forged one beyond the cap is rejected"?

Please answer with: one recommended design (with reasons for rejecting alternatives), a numeric latency budget table, a timeline for a client-vs-client melee trade at 60 ms RTT before and after the change, typed GDScript skeletons for Godot 4.7.x (verify API names against 4.x, avoid Godot 3 idioms like `rset`, `remote`, `master`, `puppet`), the abuse cases and their caps, and the main pitfalls. No external addons and no full rollback.
