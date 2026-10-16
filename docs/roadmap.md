# Roadmap and decisions

## M1 — playable networking foundation

Implemented: procedural arena/capsules, local movement, interpolated remote motion, dual cameras, host/join/dedicated CLI, host-owned health and hit tests, attack cooldown and RPC ownership, respawn and knockback. See README for verification limits.

Still requires manual acceptance: two visible Mac instances, both camera modes, trackpad input, walls, melee/ranged/knockback/respawn, focus loss, late joins, a four-player session and two-Mac Tailscale play.

## M2 — combat depth

Implemented: host-owned stamina/poise and combat phases, timed directional block/parry, owner-predicted dash with host approval and ranged immunity, owner-predicted melee lunge and turn-rate limit, per-tick active melee sweep, latency-padded parry window, host-enforced stagger drift limit, stagger/guard break, visual hitstop/camera shake and hit feedback, reticle sensitivity friction, persistent keyboard remapping and sensitivity panel. Shift/right click blocks; E remains the test beam. Dash and swing start locally from replicated state; the host revalidates and cancels rejected predictions.

Automated acceptance covers combat timing/resource rules plus multi-process replication, request ownership, invalid dash vectors, cooldown and respawn. Human acceptance still requires two-Mac combat and trackpad play. Animated swept weapon hitboxes, host-side position history and projectile magnetism remain deferred until content/projectile work; no animation-quality claim is made for capsule tilts.

## M3 — data-driven content

Introduce CharacterDef, WeaponDef, AttackActionDef and ArenaDef resources when a second kit needs them. Move existing constants into resource instances; add server-spawned swept projectiles. Send IDs/primitives over the network, never Resource objects. Add a minimal content registry only as content requires it.

## M4 — character art

The supplied Quaternius Standard male/female models are now imported and attached as player visuals, with first-person shadow handling and nine retargeted gameplay clips per model from the supplied Universal Animation Library. See [character instructions](characters.md). The character archive itself has no clips; the separate animation pack is now integrated. The full modular FBX environment pack and four placed arena props are also included. See [animation/environment usage](animations-and-environments.md).

Remaining: AnimationTree upper-body layers, directional locomotion, weapons/viewmodels, compatible SkeletonModifier3D aiming, contact timing polish and human motion acceptance. The current version uses full-body clips and AnimationPlayer crossfades.

## M5 — settings and match flow

Medieval/cyberpunk kits and arenas, kit selection, first to three round wins, countdown, 90-second timer, sudden-death ring, results and rematch. Keep server time authoritative; do not use client Engine.time_scale for match logic.

## Networking beyond Tailscale

Transport creation is isolated now, but internet discovery, NAT traversal, platform authentication, lobby/invite lifecycle, disconnect policy and relay semantics need their own design and tests. A transport migration cannot responsibly be promised as an 80-line one-file change. Noray and Steam integrations must be checked against their current primary docs before selection. No relay or Steam dependency is included.

## Corrections and scoped departures from the brief

- CLI parsing uses OS.get_cmdline_user_args() for arguments after `--`.
- Health uses its own server-authority synchronizer; assigning player authority recursively to one combined synchronizer would let the player own health.
- Synced movement is distinct from interpolated display position; basic host checks use elapsed-time movement envelopes. Full rollback and lag compensation are deferred.
- No hard performance promises: FPS, thermals, input acceleration and gesture support must be measured on the target Macs.
- M1 uses a simple host-validated melee cone plus line-of-sight, not a swept animated weapon hitbox; three-phase combat with a per-tick active sweep and owner-predicted lunge is now implemented.
- Binary art and animation assets now require Git LFS; procedural arena geometry still provides the main playfield. Resource definitions, empty registries and unused folders are deferred until used.
