# Question: driving character animation from networked, host-authoritative combat in Godot 4.7.2

I'm building a small 3D multiplayer melee + ranged arena game in **Godot 4.7.2 Standard, typed GDScript** (Mobile renderer, Metal, built-in Jolt, Apple Silicon MacBooks). 2–4 friends play over LAN or Tailscale (RTT ~10–80 ms). Transport is `ENetMultiplayerPeer` with Godot's high-level API (`MultiplayerSpawner`, `MultiplayerSynchronizer`, `@rpc`). No addons, no rollback library.

Combat networking (M2) is done and tested. Next is **character animation (M4)**. I want the best architecture before writing it, because animation has to sit on top of a split-authority netcode without becoming a source of gameplay truth.

## Current game (implemented, tested headless on two loopback processes)

**Player node** (`CharacterBody3D`, named after its peer ID, authority = owning peer), with children:
- `CapsuleShape3D` 0.4 m radius × 1.8 m; origin at capsule center.
- `Pivot` → `SpringArm3D` → `Camera3D` (third person 2.6 m over the shoulder; V toggles first person with arm length 0).
- `CharacterVisual` (`Node3D` wrapper): instantiates a Quaternius glTF model, rotated 180° to face -Z, feet at y = -0.9. Collects `MeshInstance3D`s and the `Skeleton3D`. It currently fakes a neutral pose by rotating `upperarm_l/r` with `set_bone_pose_rotation`, since the character pack has no clips. It provides `set_first_person(enabled)` (meshes become `SHADOWS_ONLY`) and `set_highlight(enabled, color)` (translucent `material_overlay` for block/hit flash).
- `Combat` (`CombatController`, authority = peer 1).
- `MovementSync` synchronizer (authority = owner, 30 Hz): `sync_position`, `sync_velocity`, `yaw`, `pitch`.
- `CombatSync` synchronizer (authority = peer 1, 30 Hz, `REPLICATION_MODE_ALWAYS`): `Combat:health`, `stamina`, `poise`, `blocking`, `phase`.

**Authority split:**
- The owner runs movement locally (`move_and_slide`). Remote copies lerp toward `sync_position` with `1 - exp(-20 * delta)`. The host checks movement against an elapsed-time envelope and clamps drift while a player is staggered.
- Peer 1 runs `CombatController` as a tick-driven state machine in `_physics_process`: `Phase { IDLE, WINDUP, ACTIVE, RECOVERY, STAGGERED, DASHING }` plus a `blocking` bool. Melee is windup 0.15 s → active 0.12 s → recovery 0.25 s. During active frames the host sweeps a 70° / 2.2 m cone every physics tick and hits each target at most once. Beam is an instant hitscan. Dash is 0.25 s at 16 m/s with 0.15 s of ranged immunity. Stagger lasts 0.8 s. Parry is block raised within 0.18 s (plus the defender's one-way latency, capped at 0.08 s). Respawn is immediate at 0 HP.
- The owner **predicts** dash and melee: it starts the dash or swing timeline locally from replicated stamina and phase. The swing includes a 7 m/s lunge during active frames and a 4 rad/s turn-rate limit through active and recovery. The host revalidates; a rejection RPC cancels the prediction. Reliable RPCs from peer 1 deliver one-shot events to every peer: `attack_effect(ranged)`, `dash_effect(direction)`, `hit_feedback(result, dealt)` with `HIT/BLOCK/PARRY`, and `correct_position(location, impulse)` for knockback and respawn.
- Hitstop (0.06 s), camera shake and body flash are cosmetic only; game and network time keep running.

So each peer sees three different "truths" for a player:
1. The **owner** knows its predicted dash/swing timeline immediately. Its replicated `phase` arrives ~RTT later.
2. The **host** has the authoritative phase with exact timings.
3. **Other clients** get `phase` at 30 Hz, plus reliable one-shot RPCs, both ~RTT/2 late with jitter. Their positions are interpolated.

## Animation assets available (both CC0, verified)

- **Characters:** Quaternius *Universal Base Characters [Standard]*, male and female glTF. 65-bone skeleton (`pelvis`, `spine_01`–`spine_03`, `Head`, `upperarm_l/r`, hands, fingers…), about 1.8 m tall, no clips.
- **Animations:** Quaternius *Universal Animation Library [Standard]*, `UAL1_Standard.glb`, the **in-place / no root motion** variant. Its skin uses the **same 65 bone names** as the characters (I checked the set: identical). 43 clips:
  `A_TPose, Crouch_Fwd_Loop, Crouch_Idle_Loop, Dance_Loop, Death01, Driving_Loop, Fixing_Kneeling, Hit_Chest, Hit_Head, Idle_Loop, Idle_Talking_Loop, Idle_Torch_Loop, Interact, Jog_Fwd_Loop, Jump_Land, Jump_Loop, Jump_Start, PickUp_Table, Pistol_Aim_Down, Pistol_Aim_Neutral, Pistol_Aim_Up, Pistol_Idle_Loop, Pistol_Reload, Pistol_Shoot, Punch_Cross, Punch_Jab, Push_Loop, Roll, Sitting_Enter, Sitting_Exit, Sitting_Idle_Loop, Sitting_Talking_Loop, Spell_Simple_Enter, Spell_Simple_Exit, Spell_Simple_Idle_Loop, Spell_Simple_Shoot, Sprint_Loop, Swim_Fwd_Loop, Swim_Idle_Loop, Sword_Attack, Sword_Idle, Walk_Formal_Loop, Walk_Loop`
- **Gaps:** no block/guard pose, no parry, no stagger loop (only `Hit_Chest` / `Hit_Head`), no strafe or backward locomotion, no dash (only `Roll`). Clip lengths do not match my gameplay phase timings.

## Constraints

1. **Animation is presentation only.** It must never drive health, collision, movement authority, damage timing or hit detection. The host's tick-driven phases stay the source of truth.
2. The owner's animation must react the same frame as input (it already predicts dash and swing). Remote players should look right despite 30 Hz state, jitter and late or reordered information.
3. Movement is 8-directional WASD at 6.5 m/s (3 m/s while blocking or swinging), with jump and gravity. Yaw comes from the trackpad; pitch is ±80°.
4. First person: the local body is `SHADOWS_ONLY`, so its shadow should still look right. No viewmodel exists yet.
5. Dedicated headless server (no player on peer 1) and headless tests must not pay for or depend on animation.
6. Small, readable code; no speculative subsystems; typed GDScript. Prefer `SkeletonModifier3D` over the deprecated `SkeletonIK3D`. Never non-uniformly scale bodies.
7. Later (M3) weapons and kits become data (`AttackActionDef` resources with windup/active/recovery). The animation mapping should be easy to make data-driven then, but don't build that registry now.

## Questions

1. **How to load the clips.** Best way in Godot 4.7.2 to use `UAL1_Standard.glb` clips on the separate character glTFs, given identical bone names. Options: an `AnimationLibrary` extracted at import (Advanced Import Settings → save animations to `.res`) and attached to an `AnimationPlayer` in `CharacterVisual`; retargeting with a `BoneMap` + `SkeletonProfileHumanoid`; or instancing the GLB's own `AnimationPlayer`. Which is the most robust choice, and what import settings and pitfalls apply (rest-pose differences, track paths such as `Skeleton3D:bone_name`, loop flags, the `A_TPose` clip)?

2. **AnimationTree structure.** Recommend a concrete tree: locomotion (idle/walk/jog, plus how to fake strafe and backward with only forward clips), an airborne state, an upper-body attack layer filtered to spine/arms (so you can walk while swinging), full-body overrides (dash/roll, stagger, death/respawn), and a block pose without a block clip (a frozen frame of some clip? a `SkeletonModifier3D` arm pose?). Name the nodes (`AnimationNodeStateMachine`, `BlendSpace2D`, `OneShot`, `Blend2`, `TimeScale`, filters) and the parameters I'd set from code.

3. **Matching gameplay timing.** My melee is 0.15 / 0.12 / 0.25 s, but `Sword_Attack` and `Punch_*` have their own lengths. How do I map gameplay phases onto clip segments: per-phase `TimeScale`, splitting a clip into windup/active/recovery sections, or seeking to phase-relative time each frame? The visual must not drift from host timing, and it must stay cancellable at any frame (parry → stagger).

4. **What each peer animates from.** For each viewer (owner, host, other clients), what should drive the tree: owner's prediction vs replicated `phase` vs one-shot RPCs vs locally derived velocity? How do I avoid double-triggering when prediction and confirmation both arrive, snapping when a late `phase` disagrees, and missing a short state (a 0.12 s active phase can fall between two 30 Hz snapshots)? Should I replicate a small `action_seq` counter or phase start time so remote viewers can reconstruct "what started when"? How do locomotion blend inputs come from interpolated remote velocity without jitter?

5. **Aim and look.** How to show pitch on remote players: an upper-body additive pitch blend between `Pistol_Aim_Up/Neutral/Down`, or a `SkeletonModifier3D` (`LookAtModifier3D` or a small custom modifier) on `spine_02/03` and `Head`? How does that interact with the swing turn-rate limit and with first-person shadows?

6. **Hitboxes later.** The roadmap defers "animated swept weapon hitboxes". If melee eventually sweeps a weapon-bone shape instead of a cone, how do I keep the host deterministic and headless-cheap? Run the same `AnimationTree` on the host with `callback_mode_process = MANUAL` and step it from the phase timer? Bake sampled weapon-socket trajectories per action at import? Or keep the cone permanently and treat the animation as decoration? Recommend one.

7. **Headless and performance.** How to skip animation work on a dedicated server and in tests (`DisplayServer.get_name() == "headless"`, or don't instantiate the tree), and what `AnimationTree` / `Skeleton3D` settings keep 4 animated 65-bone characters cheap on Apple Silicon with the Mobile renderer. Don't claim specific FPS numbers.

8. **Testing.** What can be tested headlessly: that every gameplay phase maps to a valid tree state, that clip names exist, that tree parameters change on phase transitions, and that a rejected prediction returns the visual to idle? What has to stay manual?

Please answer with: one recommended architecture (with reasons for rejecting the alternatives), the AnimationTree layout as a diagram, a table mapping `Phase` / `blocking` / velocity / RPC event to tree parameters for each viewer type, a timeline for a remote viewer watching a parried swing at ~60 ms RTT, typed GDScript skeletons for Godot 4.7.x (verify API names against 4.x; avoid Godot 3 idioms like `AnimationTreePlayer`, `rset` or `master`/`puppet`), the exact import steps, and the main pitfalls. No external addons, and no root motion driving gameplay.
