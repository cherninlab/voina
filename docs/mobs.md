# Optional PvE raiders

Enable **PvE · 3 hostile raiders** before choosing **Host game**. Joining players receive the host's encounter automatically, including a late join. PvP remains the default when the switch is off. In Terminal:

```sh
"$GODOT" --path . -- --host --pve
# Dedicated server also supports the encounter:
"$GODOT" --headless --path . -- --server --pve --port=7777
# Other players join normally; they do not need --pve.
"$GODOT" --path . -- --join=your-host-magicdns-name
```

There are three red-tinted humanoid raiders with **60 health** each. They approach visible players, stop to attack, and turn yellow during a **0.5 second windup**. Each committed attack deals **12 melee damage**, followed by **0.8 seconds recovery**. Move out of the attack cone, hold a front guard for reduced damage, or time a parry to stagger the raider. Player melee, beam and swept bolts all damage them through the existing combat paths. The player's simulated longsword also touches them directly: during an approved swing the host sweeps the blade segment against each raider's capsule, a contact shoves the raider in the blade's direction (with a hop and a visible lean) and deals the swing's 25 damage once per target, and a contact faster than 10 m/s at the touching point bisects the raider in one shot into two tumbling halves. Damage shares the swing's one-hit-per-target rule with the cone, so a swing never hits the same raider twice. Dead raiders disappear after 1.3 seconds. This encounter has no waves or automatic mob respawns; restart the session for another encounter.

The visual is a placeholder made from the already imported CC0 Quaternius male model and retargeted animation library. No additional asset pack or license is needed. Model and animation provenance remain in `content/characters/quaternius/` and `content/animations/quaternius/`.

## Ownership and behavior

Peer 1 owns mob spawning, movement, perception, attack timing, health and death. Clients display synchronized snapshots; there is no client mob-damage or mob-spawn request RPC. Mob bodies expose the same combat interface as players, so bolts, block, parry and poise reuse the current rules. Player swing hit IDs use negative mob IDs because every mob has the same server authority.

The brain separates perception from action execution: idle, move and act, plus a dead state. It checks sight every 0.2 seconds within 14 metres. Static cover blocks sight; a hidden player's last seen position is remembered for three seconds. An attack commits its facing at the start of windup, then checks range, cone and cover again at impact. Stagger cancels the action.

Godot's `AStarGrid2D` provides ground-plane paths on a shared 0.5 metre grid. The host samples static collisions once when the encounter starts with clearance wider than the mob capsule. Routes refresh every 0.4 seconds; physics prevents bodies passing through actors and walls. This is for the current flat arena: no jumping, climbing, multi-floor paths, dynamic obstacle rebuilding or sophisticated crowd avoidance. Three actors are the intended first slice.

Design references: Jeff Orkin's [Three States and a Plan: The A.I. of F.E.A.R.](https://www.gamedevs.org/uploads/three-states-plan-ai-of-fear.pdf), GDC 2006, informed the separation of goal choice from small execution states. The supplied *Cunning Lords: Tactical AI and Troop Control for Mount & Blade II: Bannerlord* dissertation (Joaquim Quadrado, October 2021, `86455-Joaquim-Quadrado-dissertacao.pdf`) informed the choice to reuse existing engine and combat systems. This starter does not implement GOAP, squad tactics or Bannerlord troop control. The papers are references, not imported code or bundled assets.

## Verification

```sh
"$GODOT" --headless --editor --path . --quit
python3 scripts/mob_smoke_test.py "$GODOT"
python3 scripts/smoke_test.py "$GODOT"
```

The focused scene checks pathfinding around cover, sight and memory, actual pursuit, windup, one hit per attack, player block/parry, committed-facing misses, per-mob melee deduplication, beam and bolt damage, death and corpse removal. A real ENet host then runs its mobs before a client joins; the client verifies current positions and health, replicated damage to a player, refusal of local client damage/spawn attempts, and host-driven death/despawn. CI runs both suites. Two-Mac Tailscale play and human animation/input acceptance remain manual checks.

## Future environmental creatures

Passive ambient animals are a separate future slice: wandering within an area, idling, fleeing nearby players and returning home, with suitable licensed creature models and clips. They should share only the ownership/spawning conventions they need. A full planner, wildlife combat, loot and ecosystem simulation are not part of this encounter.
