# Roadmap and decisions

## M1 — playable networking foundation

Implemented: greybox arena with imported props, trees, parked cars and capsule-based players; local movement and dual cameras; host/join/dedicated CLI; host-owned combat, spawning, respawn and knockback. Debug peers authenticate a source fingerprint before spawning. Movement sends every network frame at the 60 fps cap; remote display projects recent snapshots. Host-owned combat state uses a separate synchronizer.

Use the [pinned playtest workflow](playtest.md) when agents are pushing: each Mac gets its own clean playtest copy at the same commit. A successful import or loopback test does not establish two-Mac acceptance.

Still requires manual acceptance: two visible Mac instances, both camera modes, trackpad input, walls, melee/ranged/knockback/respawn, focus loss, late joins, a four-player session and two-Mac Tailscale play.

## M2 — combat depth

Implemented: host-owned stamina/poise and combat phases; directional block/parry with capped latency grace; owner-predicted dash and melee with host approval; per-tick melee cone sweeps with per-target deduplication; stagger/guard break and host correction; hit feedback, reticle sensitivity friction and persistent key remapping. Defaults are Ctrl/right click to block, Shift to dash, Space to jump, E for the beam and Q for the bolt. Saved bindings can differ; the in-game Controls panel shows them.

The host records position history and rewinds target capsules using measured round trip, capped at 0.2 seconds. Melee requests can receive up to 0.06 seconds of windup compensation. Beam/melee damage checks static cover. Swept bolts support cover, block, reflection by parry and dash pass-through. This is bounded compensation, with client-owned movement inside a generous host envelope; full rollback and competitive anti-cheat remain future work.

Automated checks cover timing, resources, hit resolution, projectile collisions, ownership, replication and respawn. Animated blade collision and projectile magnetism remain deferred. Human acceptance still requires two-Mac combat, trackpad play and sword/contact review.

## M3 — data-driven content

Implemented: the host-owned swept bolt and supplied character, animation and environment assets. Optional [hostile PvE raiders](mobs.md) can sense players, navigate around static cover, telegraph melee and receive existing weapon damage. [Ambient birds](creatures.md) perch, fly and flee; they have no combat or collision interface.

Introduce CharacterDef, WeaponDef, AttackActionDef and ArenaDef resources when a second kit needs them. Send IDs/primitives over the network, never Resource objects. A generic registry, additional kits, loot, enemy waves and broader creature simulation remain future work.

## M4 — character art

The supplied Quaternius male/female models are attached to players, with first-person shadow handling. Player runtime posing uses the procedural heavy-sword and body/hand/foot IK code described in [longsword instructions](longsword.md). The nine retargeted clips per model remain available for inspection and reuse; raider visuals still use full-body clip playback. See [character instructions](characters.md) and [animation/environment usage](animations-and-environments.md).

Remaining: human motion/contact acceptance and polish of the active procedural sword work. The older AnimationTree proposal on T-001 must be reconciled with that direction before replacing runtime posing. New weapons, aiming behavior and additional rigs need their own verified slices.

## M5 — settings and match flow

Implemented: optional [match flow](match.md), enabled by the host with the menu switch or `--match`: waiting, countdown, 90-second rounds, first to three wins, results and automatic rematch. The host owns time and scores. Combat is frozen between rounds; pending attacks are cancelled. See that guide for current timeout and kill-credit rules.

Remaining: countdown movement lock, kit selection and medieval/cyberpunk arenas. T-020 tracks the sudden-death ring; treat it as in progress until its shipped implementation and checks are recorded. Keep server time authoritative; do not use client `Engine.time_scale` for match logic.

## Current automated checks

```sh
"$GODOT" --headless --editor --path . --quit
python3 scripts/smoke_test.py "$GODOT"
python3 scripts/mob_smoke_test.py "$GODOT"
python3 gameplay/wildlife/tests/smoke_test.py "$GODOT"
```

The main suite covers combat, assets, hit resolution, bolts, remote motion, match flow, build authentication and real ENet pairs. The focused suites cover PvE and wildlife behavior, late joining, authority and cleanup. Run real-time suites separately when diagnosing timing assertions. CI runs the suites sequentially. These checks do not establish visual quality, WAN behavior or thermal performance.

## Networking beyond Tailscale

Transport creation is isolated now, but internet discovery, NAT traversal, platform authentication, lobby/invite lifecycle, disconnect policy and relay semantics need their own design and tests. A transport migration cannot responsibly be promised as an 80-line one-file change. Noray and Steam integrations must be checked against their current primary docs before selection. No relay or Steam dependency is included.

## Corrections and scoped departures from the brief

- CLI parsing uses OS.get_cmdline_user_args() for arguments after `--`.
- Health uses its own server-authority synchronizer; assigning player authority recursively to one combined synchronizer would let the player own health.
- Synced movement is distinct from interpolated display position; basic host checks use elapsed-time movement envelopes. Full rollback and lag compensation are deferred.
- No hard performance promises: FPS, thermals, input acceleration and gesture support must be measured on the target Macs.
- M1 uses a simple host-validated melee cone plus line-of-sight, not a swept animated weapon hitbox; three-phase combat with a per-tick active sweep and owner-predicted lunge is now implemented.
- Binary art and animation assets now require Git LFS; procedural arena geometry still provides the main playfield. Resource definitions, empty registries and unused folders are deferred until used.
