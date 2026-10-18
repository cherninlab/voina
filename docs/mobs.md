# Optional PvE raiders

Enable **PvE · 3 hostile raiders** before choosing **Host game**. Joining players receive the host's encounter automatically, including a late join. PvP remains the default when the switch is off. In Terminal:

```sh
"$GODOT" --path . -- --host --pve
# Dedicated server also supports the encounter:
"$GODOT" --headless --path . -- --server --pve --port=7777
# Other players join normally; they do not need --pve.
"$GODOT" --path . -- --join=your-host-magicdns-name
```

There are three red-tinted humanoid raiders with **60 health** each. They approach visible players, stop to attack, and turn yellow during a **0.5 second windup**. Each committed attack deals **12 melee damage**, followed by **0.8 seconds recovery**. Move out of the attack cone, hold a front guard for reduced damage, or time a parry to stagger the raider. Player melee, beam and swept bolts all damage them through the existing combat paths. The player's simulated longsword also touches them directly: the host sweeps the blade segment against each raider's capsule every tick, and any contact faster than 1 m/s shoves the raider along the blade's travel with a visible lean and a splash of blood, hopping above 3 m/s. During an approved swing the same contact deals the swing's 25 damage once per target, and above 7 m/s at the touching point, or whenever the blow is lethal, it bisects the raider into two tumbling halves along the blade's plane. A swing whose cone reaches a raider before the blade geometrically touches it resolves through the same path with the blade's current motion, so every damaging swing gets the same feedback. Each damaging hit flashes the raider white, freezes its animation for 70 ms, paints an exaggerated red gash where the blade's plane crosses the body (riding on the nearest bone, up to six per raider), throws a fan of blood streaks within that plane along the blade's travel, and draws a short slash arc along the cut. Players walking into a raider push it along as well. Damage shares the swing's one-hit-per-target rule with the cone, so a swing never hits the same raider twice. Dead raiders disappear after 1.3 seconds and a replacement spawns 5 seconds later at the spawn point farthest from the players, so the encounter keeps three raiders in rotation; there are no waves.

Raider bodies are procedural on every peer, driven only by the host's existing reaction RPCs and health, with no new authority. Foot planting runs over every clip: a `MobFeet` modifier raycasts the static ground under each animated foot, keeps the foot's height above that ground, drops the hips so the lower foot reaches, lets an engine `TwoBoneIK3D` bend the legs, and then tilts each foot onto the slope, so raiders stand, jog and attack with planted feet on slopes and stones. Hits flex the body like a puppet. `MobPuppet` keeps underdamped angular springs on the pelvis, spine, neck, head and arms, layered over the animation. A blow spins every spring bone between the pelvis and the struck point by the torque the blade's travel exerts about that joint, the head and the other arm lag the other way, and everything swings back within about a second while the feet stay planted. Wounds follow the final, flexed pose. A death becomes a full ragdoll: the raider's own visual moves into the scene, pauses its clip and simulates fifteen jointed `PhysicalBone3D` parts (cone joints at the spine, hips, shoulders and neck, hinges at the knees and elbows) under a `PhysicalBoneSimulator3D`. It falls along the latest shove, lands on the terrain and stays for 8 seconds, outliving the raider node. A bisect bakes each vertex's distance to the cut plane into the mesh in the pose of the cut, then gives each half a ragdoll of the parts on its side. Parts whose jointed parent was cut away fall free, such as a forearm hanging below a waist cut, and bones left without a body ride on the nearest simulated part, so the cut edge stays on the body while the halves crumple. Ragdoll parts sit on collision layer 0 with mask 1: they land on the world and get shoved by actors, but block nobody and never collide with each other. `tests/mob_body_test.tscn` checks planting on a 20 degree slope, the hip drop, flex and settle, the death ragdoll outliving its raider, and the bisect splitting the parts between two jointed halves. `scripts/capture_mob_body.gd` renders staged frames: `"$GODOT" --path . -s scripts/capture_mob_body.gd -- --capture-dir=/tmp/mob_body`.

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
