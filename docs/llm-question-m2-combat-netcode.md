# Question: networked combat-state architecture for M2 (block/parry/dash/stamina) in Godot 4.7.2

I'm building a small 3D multiplayer melee + ranged arena game in **Godot 4.7.2 Standard, typed GDScript** (Mobile renderer, Metal, built-in Jolt, Apple Silicon MacBooks). 2–4 friends play over LAN or Tailscale (expected RTT ~10–80 ms, some jitter). Transport is `ENetMultiplayerPeer` with Godot's high-level API (`MultiplayerSpawner`, `MultiplayerSynchronizer`, `@rpc`). No addons (no netfox, no rollback library), and I don't want to build full-world rollback.

I'm about to start the next milestone and want the **best architecture before writing code**, because it's the hardest part to change later.

## What exists now (M1, working, covered by a headless loopback integration test)

- One `CharacterBody3D` per player, node named after its peer ID, `set_multiplayer_authority(peer_id)`. Spawned by peer 1 through a custom `MultiplayerSpawner.spawn_function`.
- **Movement is client-authoritative.** The owning peer runs input + `move_and_slide()` locally and writes `sync_position`, `sync_velocity`, `yaw`, `pitch`. A `MovementSync` synchronizer (authority = owning peer, 30 Hz, `REPLICATION_MODE_ALWAYS`) replicates them. Remote copies lerp `position` toward `sync_position` with `1 - exp(-20 * delta)`.
- **Host validates movement loosely**: every ≥0.25 s it checks the jump from the last accepted position against `20 m/s * elapsed + 2 m` and non-finite values; on violation it RPCs `correct_position` back to the owner.
- **Health is host-authoritative** in a *separate* `HealthSync` synchronizer whose authority is peer 1. Rule: client movement and host-owned state must never share a synchronizer.
- Attacks: the client calls `request_attack.rpc_id(1, ranged)`. The `any_peer` RPC on the host checks that `get_remote_sender_id()` equals the node's authority, applies a 0.5 s cooldown, broadcasts a cosmetic `attack_effect`, then:
  - hitscan: instant ray from the host's *current* view of the attacker's position/aim, 40 m;
  - melee: `await` a 0.15 s timer, then a 70° / 2.2 m cone + line-of-sight ray against every other player.
- Hits call `receive_hit(damage, direction)` on the host: subtract health, respawn at 0, and send knockback via `correct_position.rpc(position, impulse)`. The owning client applies the impulse to its own velocity (since it owns movement).
- Key excerpt:

```gdscript
add_sync("MovementSync", get_multiplayer_authority(), [^":sync_position", ^":sync_velocity", ^":yaw", ^":pitch"])
add_sync("HealthSync", 1, [^":health"])

@rpc("any_peer", "call_remote", "reliable")
func request_attack(ranged: bool) -> void:
	if not multiplayer.is_server(): return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority(): return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - last_attack < 0.5 or health <= 0: return
	last_attack = now
	attack_effect.rpc(ranged)
	if not ranged:
		await get_tree().create_timer(0.15).timeout
	# ...host-side ray / cone using host's current positions...
```

## What I need to add next (M2 "combat depth")

- **Stamina** (host-owned; spent by block, dash, attacks; regen delay).
- **Three-phase melee**: windup (telegraphed, interruptible, no hitbox) → active (hit detection, turn-rate clamped, small lunge) → recovery (vulnerable, cannot block).
- **Block** (hold): 80% damage reduction, drains stamina per hit. **Parry**: block pressed within the first ~0.18 s of an incoming melee swing (or slow projectile) → zero damage, attacker `STAGGERED` 0.8 s.
- **Dash**: 0.25 s directional burst along WASD, 0.15 s invulnerability vs ranged/AoE, costs 35% stamina.
- **Poise / stagger**, **hitstop** (~0.06 s, local cosmetic) and camera shake, knockback.
- Later (M3) server-spawned swept projectiles, and data-driven `AttackActionDef` resources — so the design should make actions describable as data (send IDs/primitives over the network, never `Resource` objects).

Hard constraints:
1. **Local movement and camera must stay zero-latency** for the owning player.
2. **Peer 1 must own all combat outcomes** (health, stamina, poise, stagger, parry results, i-frames as they affect damage). Clients must not be able to forge or skip costs.
3. `any_peer` RPCs must be sender-authenticated, clamped, and rate-limited.
4. Must run in a dedicated headless server mode too (peer 1 then has no player).
5. Small, readable code; no speculative subsystems. Friend-group fairness, not esports anti-cheat.

## The core tension I want you to resolve

Movement is owned by the client, but **dash and lunge move the body**, **stagger/recovery must restrict movement**, and **knockback is applied by the host**. Meanwhile the **host owns the combat state machine** that decides whether a block/parry/i-frame was active at the moment a hit lands — but the host learns about a client's block/dash input ~RTT/2 late, and sees the target's position ~RTT/2 + interpolation delay late.

## Questions

1. **Combat state machine ownership and replication.** Where should the per-player combat state (`IDLE / WINDUP / ACTIVE / RECOVERY / BLOCKING / DASHING / STAGGERED`, plus phase start time, action ID, stamina, poise) live and how should it be replicated? A third host-authority `MultiplayerSynchronizer`? Reliable RPC state-transition events with server timestamps? Both (events for transitions, synchronizer for continuous values like stamina)? What exactly should the client predict locally vs. wait for confirmation on, and how do I reconcile/rollback a mispredicted local transition (e.g. client started a dash, host rejects it for insufficient stamina)?

2. **Movement-affecting combat effects with client-owned movement.** How should dash, attack lunge, turn-rate clamp during active frames, and "cannot move while staggered" be enforced? Options I see: (a) client simulates them and host only validates envelopes (extend my 20 m/s check per state); (b) host sends impulses/locks via RPC like knockback today; (c) switch to host-authoritative movement for the duration of combat states only. Which is best here and why? How should the movement validation envelope change per combat state without false positives under jitter?

3. **Timing and latency fairness for block/parry/dash i-frames.** What clock should the host use to judge "block started within the parry window of an incoming swing"? Should clients send their local input timestamp (estimated server time via a clock-sync scheme) and the host accept a bounded rewind (e.g. `min(rtt/2, 100 ms)`), or should the host just use arrival time with a ping-padded window? Same question for dash i-frames vs hitscan. How do I clock-sync in Godot 4.7.2 cleanly (ENet `get_statistic(PEER_ROUND_TRIP_TIME)` vs a ping RPC with offset estimation)? Give a concrete, bounded policy that favors the defender/shooter reasonably and can't be abused by faking timestamps.

4. **Hit detection timing.** Replace `await create_timer()` with what? A host-side per-player phase timer driven by `_physics_process` ticks? Should melee active frames do a `ShapeCast3D` sweep per physics tick against targets' *current* host positions, or against a short position history (lag compensation) — and is a small history ring buffer (≈200 ms) worth it at this scale?

5. **Code structure.** Recommend the minimal node/script layout: e.g. a `CombatState` child node with its own synchronizer and RPCs vs. keeping it in `player_character.gd`. Show the key typed GDScript signatures (state enum, RPCs with `@rpc` annotations and channels/transfer modes, synchronizer configuration incl. `REPLICATION_MODE_ALWAYS` vs `ON_CHANGE`, and how host-side `request_action(action_id: int, client_time: float, aim: Vector3)` validates sender, rate limit, stamina, and state legality).

6. **Testing.** What headless, deterministic tests should prove this (two Godot processes on loopback)? E.g. parry inside/outside the window, dash i-frames vs hitscan, stamina underflow rejection, forged RPC through another player's node, state transition replicated to a third peer, staggered client trying to move. How to simulate added latency/jitter in a test without external tools?

Please answer with: a recommended architecture (one choice, with the reasoning for rejecting the alternatives), an authority/data-flow table (state → owner → replication mechanism → who predicts), a timeline diagram for a parry under ~60 ms RTT, the key typed GDScript code skeletons for Godot 4.7.x (verify API names against 4.x; avoid Godot 3 / early-4.x idioms like `rset`, `remote`, `master`, `puppet`, `get_tree().network_peer`), and the main pitfalls. Don't propose external addons or full rollback.
