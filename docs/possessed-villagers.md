# Possessed villager bodies

The church yard villagers ([mobs.md](mobs.md) describes their brain) are the existing Quaternius male and female bodies, possessed on every peer by `MobPossession` (`gameplay/mobs/mob_possession.gd`). The host replicates only the mob id and the state. Each villager's distortion, stances, quirks and look are computed locally from those, so there is no new network traffic. They are the first enemies in the game, so everything stays mild: recently possessed villagers, not monsters.

## One distortion per villager

`MobPossession.configure(id)` picks a main kind from the id. Five consecutive ids (a wave and its replacements) show all five kinds. Small extras come from a 32-bit integer hash of the id (`hash32`, separate from `HostileMob.is_female`), so every kind appears on both bodies.

| Kind | What changes | Range |
| --- | --- | --- |
| Backward knees | knees bend backward (the knee pole goes behind the leg), hips lowered so the legs fold, stands on the balls of the feet | hips −3.5 to −5 cm, heels up 15–21° |
| Short legs, long arms | thighs and shins shortened, arms lengthened; sometimes backward knees too | legs ×0.87–0.90, arms ×1.12–1.17 |
| Crooked neck | longer neck, head tilted for good, one shoulder hiked and the other dropped | neck +3.5–4.5 cm, tilt 15–21° |
| Hunched, dangling arm | curled spine, one arm hanging limp and swinging, that shoulder dropped | hunch 23–28°, limp 0.8–0.9 |
| Long arms | longer arms that hang a little limp, slightly longer neck; sometimes backward knees | arms ×1.16–1.20 |

Every villager also gets a small head tilt (3–7°), a slight crouch and hunch, arms up to 5% longer, hooked claw fingers instead of the clips' fists, a skin tint (ashen, cold blue-grey, sickly or waxy), an eye glow colour, a bruise pattern, an amount of dried blood down the forearms and shins (sometimes none), and its own stutter and twitch rates.

## Stances for the host's states

`MobVisual.show_state` maps the replicated state to a clip and a `MobPossession.Mode`. Mode weights blend smoothly: rising is slow and uncanny, the leap snaps in.

- **IDLE**: the `Idle` clip, slowed and stuttering, with sway, twitches and occasional too-fast head snaps that drift back. The head half-follows the nearest player within 14 m.
- **MOVE**: the `Walk` clip, with playback speed matched to the measured ground speed (Walk covers 0.86 m/s at speed 1), so it stays a stuttering shamble. Above 1.9 m/s (a shove, say) it jogs.
- **STARE**: the clip almost frozen and the head tracking the nearest player slowly, at most 63°/s, with an extra crooked tilt. The stare keeps whatever stance it caught, so a crawler's short stops stay on all fours. An upright villager that keeps staring past 0.6 s sinks into the ghoul crouch: knees deep, weight forward, arms hanging toward the ground, head pushed forward on the neck.
- **CRAWL**: procedural all fours. The hips sit high and the chest is pitched down until the hands reach the ground with the arms nearly straight (this depends on the villager's arm length). The gait is a diagonal trot (each hand with the opposite foot, 60% stance) phased from the visual's measured ground speed, so planted limbs keep up with the body. The head stays level and stares ahead or at the player. Hands are planted by a second `TwoBoneIK3D` (`MobPossession.Hands`) with ground raycasts and palms laid on the ground normal. Feet go to gait goals through `MobFeet`. On slopes the hips and chest follow two ground probes.
- **ACT** (the pounce coil, the attack's telegraph): a deep crouch on planted hands with the knees out. Over the 0.5 s windup it rocks back onto the haunches, shrugs the shoulders, trembles more and more, and the eyes flare. There is no floating label any more: the body is the telegraph.
- **LEAP**: the body pitched forward, arms reaching out ahead with claws open, legs trailing and bent. On landing the hips dip and the villager stays crouched for the host's 0.7 s recovery before it slowly stands.
- **DEAD**: unchanged: a ragdoll, or a bisect into two halves.

A hit stagger plays `Hit_Chest` without leaving a low stance. The puppet springs still flex every pose.

## Staying physics safe

Limbs never scale. A longer or shorter limb moves each child bone along its parent: the pose translation of `lowerarm`, `hand`, `calf`, `foot` and `Head` is multiplied. Every bone transform therefore stays a pure rotation plus translation. The skin stretches across the joint, by up to about 5 cm at the elbow. The modifier stack under the skeleton runs in this order:

`Possession` → `FootPlanner` → `Puppet` → `LegIK` → `FootAligner` → `HandPlanner` → `ArmIK` → `HandAligner`

The cached final pose already holds the distortion, so the death ragdoll (`MobRagdoll.build`) and both bisect halves start from it. Their parts are sized from the posed child offset (`MobRagdoll.local_along`), so a long upper arm gets a long capsule. A death disables the possession stages along with the feet and puppet, so nothing is applied twice. `tests/mob_body_test.tscn` checks that every bone of a distorted pose and every ragdoll part (dying from a crawl, and the halves of a bisected short-legged villager) is orthonormal, with unscaled shapes. It also checks that the arm keeps its length in the ragdoll.

## Look

`gameplay/mobs/mob_overlay.gdshader`, the wound overlay pass, also paints the possession, so it costs no extra draw:

- **Skin**: the body's own texture, desaturated to the villager's chalky tint with deepened creases so it reads gaunt. It also gets darker bruised patches, sunken dark eye sockets (per-body UVs in `MobVisual.SOCKETS`) and thin dried streaks down the forearms and shins, placed in each bone's frame. Clothes keep their colour, because the overlay only covers the warm skin colours.
- **Eyes**: milky irises with pinprick pupils in greyed whites, with a faint emission that flares during the coil.
- **Bisect halves**: they get the same skin through a wound-free copy of the overlay. Each half discards the other side by the cut distance baked in `UV2`, and the caps keep their flesh. The halves skip the normal map, because the cut bake rewrote the tangents.

## Verify and capture

```sh
"$GODOT" --headless --path . --fixed-fps 60 res://tests/mob_body_test.tscn
"$GODOT" --path . -s scripts/capture_mob_body.gd -- --capture-dir=/tmp/villagers --lineup
"$GODOT" --path . -s scripts/capture_mob_body.gd -- --capture-dir=/tmp/villagers-dusk --lineup --dusk
```

Run the captures without `--headless`, on the Metal renderer. `--lineup` stands villagers 1 to 6 side by side (front, side and per-variant shots), then films each state: shamble, stare, crawl mid-stride and up a slope, crawl at rest, coil, leap and landing. `--dusk` renders under dim blue-grey fog. The real yard can be seen with `scripts/capture_church_encounter.gd -- --host`.

## Limitations

- The leap, crawl, coil and stare are procedural poses over the `Idle` clip. The UAL1 pack has no crawl or pounce clip.
- Lengthening without scale stretches the skin at the elbow, wrist, knee and ankle, and shortening folds it slightly. This is why the ranges stay small.
- A crawler's planted hands and feet follow the body when the host turns it on the spot (the stare's and the coil's turns), so they slide a little.
- The crawl's gait runs from the visual's measured speed. On a client it follows the interpolated motion, so a stalled or teleported body can briefly skate.
- Backward knees fold the skin at the back of the knee the other way. This reads as a hyperextended joint, not a separate digitigrade leg.
- Dried streaks use bone frames, so they are skipped on bisect halves.
- Cost: with 5 villagers, a headless frame on an M5 Max took about 0.7 ms of CPU (physics, animation, every modifier). Disabling the possession stages barely changed that. The GPU cost of the extra overlay maths was not measured. Thermal behaviour on battery was not measured either.
