# Projectiles (bolts)

**Q** fires a slow bolt; rebind it under **Controls** like any other key. Peer 1 decides every hit. The bolt can be dodged, blocked, and parried back at its shooter.

## How it works

- Everything lives in the `Projectiles` autoload (`gameplay/projectile/projectile_system.gd`). Its node path is identical on every peer, so player and world scenes need no hook.
- **Owner:** checks the replicated combat state, then aims from its chest at whatever the reticle covers. In third person the camera sits 0.55 m beside the body, so a bolt sent along the camera's facing from the chest would pass beside the crosshair. The owner draws a predicted bolt the same frame and sends `request_fire(seq, origin, direction)`.
- **Host validation:** the sender must own a player; vectors must be finite and the direction roughly unit length; the muzzle must be within 2.5 m of the shooter's latest replicated chest; at most 3 bolts per player may fly; `CombatController.begin_shot` requires idle, not blocking, 12 stamina and the attack cooldown shared with the beam (0.6 s after a bolt). A muzzle claimed behind a wall fires from the chest instead. A refusal sends `fire_rejected(seq)`, which removes the predicted bolt.
- **Flight:** closed form `origin + velocity·t + ½·gravity·t²` at 24 m/s, 4 m/s² drop, 0.15 m radius, 2 s life. The host sweeps the sphere along each physics tick (`cast_motion` + `get_rest_info`); a bolt released inside a target's capsule hits it.
- **Replication:** only reliable `spawned`, `reflected` and `ended` events; every peer evaluates the same curve. Clients age each event by their ENet round trip to the host ÷ 2. The host flies a client's bolt ahead by that client's one-way latency, capped at 0.1 s, so it matches the shooter's screen. Client visuals stop at walls; the host's end event removes them.
- **Hits:** dash ranged immunity lets the bolt pass through. A front block raised within the parry window (plus the defender's latency grace) **reflects** it along the defender's aim; the defender now owns it, so it can hit the original shooter, and the distant shooter is not staggered. Otherwise the existing `receive_hit` path applies 20 damage with block reduction, guard break, poise, knockback and feedback.
- **No rewind:** bolts are visible and dodgeable, so they are judged against where targets are now, not where the shooter saw them. Rewind stays with hitscan and melee (`hit_resolver.gd`). The 0.1 s fast-forward cap bounds the shooter's advantage.

## Deliberate limits

- One bolt kind with constants in the script. Add a `WeaponDef`/`AttackActionDef` when a second projectile or kit needs one; network messages already carry only ids and vectors.
- Players who join late do not see bolts already in flight (at most 2 s).
- Other players see a client's bolt appear up to (host advance + their own one-way latency) × 24 m/s ahead of the muzzle, roughly 1–2 m at 40–80 ms round trips.
- Bolts leave from the chest-height pivot, not a hand bone. The shooter plays its ranged clip when its visual offers `play_attack`.
- No projectile aim magnetism yet.

## Verify

```sh
"$GODOT" --headless --path . --fixed-fps 60 res://tests/projectile_test.tscn
python3 scripts/smoke_test.py "$GODOT"
```

The scene test covers hit, cover, request validation, the wall-muzzle clamp, shared cooldown, in-flight cap, lifetime, dash pass-through, block, parry reflection and disconnect cleanup. `tests/combat_test.gd` covers release cost and cooldown, blocking, parry window and grace, dash immunity and guard direction. The smoke test runs both, plus a second two-process ENet pair (`--projectile-smoke`) for refusals, prediction confirmation, cooldown and a host-decided hit replicated to the client.

Bolt readability, reflect feel and two-Mac latency behaviour are unmeasured and need manual play.
