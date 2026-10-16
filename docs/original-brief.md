### Upfront Calls: Where to Push Back on Your Plan

Before diving into the architecture, three parts of your premise need a hard course-correction so you do not lose your first weekend to fighting the engine or your hardware:

1. **Never use a Tailscale-shared folder for simultaneous project editing—use Git + Git LFS.** Sharing a live working directory over SMB/Taildrive while two instances of the Godot editor are open will corrupt your project within an hour. Godot constantly writes to `.godot/` caches, updates `.import` timestamps, and since Godot 4.4+, generates `.uid` sidecar files for every script. Two editors fighting over those files will trigger infinite re-import loops and broken scene references. Use **Git + Git LFS** for code and assets, and use **Tailscale strictly for UDP game traffic** (and optionally hosting a lightweight local Gitea/Forgejo instance if you want zero cloud dependencies).
2. **Drop Force Touch and two-finger pan for combat controls.** First, Godot's `DisplayServerMacOS` maps `InputEventMouseMotion.pressure` to stylus/tablet hardware (`NSEventTypeTabletPoint`), **not** MacBook Force Touch stage-2 trackpad pressure (`NSEventTypePressure`)—reading Force Touch requires a custom Objective-C++ GDExtension. Second, even if you bridged it, physically pressing down on a glass trackpad while sliding your index finger to track a moving 3D target introduces massive finger friction and ruins your aim. In a fast 3D action game on a MacBook, **your right hand should glide weightlessly on the trackpad exclusively for 3D camera look**, while **keyboard keys (`J` / `K` / `L` or `F` / `R` / `Space`) act as your combat triggers**.
3. **Godot 4.7.2 vs. AI Training Data Flags:** Most LLMs default to Godot 4.1–4.3 idioms. In **Godot 4.7.2**, watch out for five major shifts:
* **Jolt Physics is the built-in default 3D physics engine** (made default in 4.6). Tell your AI assistant **not** to install the old third-party `godot-jolt` plugin, and **never apply non-uniform scale** (e.g., `scale = Vector3(1, 2, 1)`) to `CollisionShape3D` nodes—resize the shape resource dimensions instead, or Jolt will throw warnings and miscalculate contacts.
* **Universal `.uid` files (4.4+):** Every `.gd` script and `.gdshader` has a companion `.uid` file (e.g., `player.gd.uid`). Always commit `*.uid` files to Git. When your AI assistant creates scripts from the terminal, open the Godot editor once before committing so Godot generates their `.uid` files.
* **Native Metal Backend (4.4+, HDR in 4.7):** Set `rendering/rendering_device/driver.macos` to `"metal"` (not `"vulkan"`/MoltenVK) for native Apple Silicon performance.
* **`SkeletonModifier3D` / `LookAtModifier3D` / `IKModifier3D` (4.4–4.6+):** `SkeletonIK3D` is deprecated. Any procedural upper-body pitch aiming must subclass or use `SkeletonModifier3D` nodes (`LookAtModifier3D` or `IKModifier3D`).
* **Typed Dictionaries (4.4+):** GDScript natively supports `var loadout: Dictionary[StringName, WeaponResource] = {}`. Enforce this in your AI rules so the LLM writes type-safe data lookups.



---

## 1. Game Design

### Core Loop, Match Flow, and Win Conditions

Keep the wrapper tight so you can test combat inside 5 seconds of launching:

* **Format:** Best-of-5 rounds (`First to 3 Round Wins`), 90-second round timer. If the timer expires, a shrinking hazard zone ("Sudden Death Ring") closes in on the arena center over 15 seconds.
* **Match Flow State Machine:**
1. `LOBBY_SELECT` (10s): Players pick their **Character**, **Primary Weapon**, **Secondary Weapon**, and **Arena** (host picks Arena) from a flat UI overlay.
2. `ROUND_COUNTDOWN` (3s): Players spawn at opposite `Marker3D` spawn points; movement is locked, camera look is active.
3. `COMBAT_ACTIVE`: Real-time fight until only one player (or team) has `health` greater than `0`.
4. `ROUND_OVER` (3s): Slow-motion (`Engine.time_scale = 0.3` locally or via server tick dilation), score banner updates, arena resets dynamic props/projectiles.
5. `MATCH_OVER`: Victory screen with an instant **"Rematch (`R`)"** or **"Swap Kit (`Tab`)"** button.



### 3D Combat Model (Setting-Agnostic)

To make a medieval broadsword vs. a cyberpunk plasma pistol feel equally fair and readable, unify all combat under a **Stamina + Posture/Poise + Health** triangle:

| Mechanic | How It Works Across Settings | Parameters in Resource |
| --- | --- | --- |
| **Melee (3-Phase State)** | Every melee swing has explicit **Windup** (telegraphed, interruptible, no hitbox), **Active** (hitbox enabled or swept shape-cast active, turn-rate clamped), and **Recovery** (vulnerable, cannot block). | `windup_sec`, `active_sec`, `recovery_sec`, `hitbox_size`, `lunge_impulse` |
| **Ranged (Hybrid)** | Support both **Hitscan** (instant server raycast for lasers/revolvers) and **Physical Projectiles** (server-stepped `Area3D` or `ShapeCast3D` sweep per physics tick for arrows, rockets, thrown pies). | `delivery_type` (`HITSCAN` or `PROJECTILE`), `projectile_speed`, `gravity_scale`, `spread_deg` |
| **Block / Parry** | Holding **Block** drains stamina on hit and negates 80% of damage. Pressing Block within the first `0.18s` (`parry_window_sec`) of an incoming melee swing or slow projectile triggers a **Parry**: zero damage, attacker enters `STAGGERED` state for `0.8s`, and slow projectiles reflect along the defender's camera forward vector. | `block_damage_mult`, `parry_window_sec`, `stamina_cost` |
| **Dodge / Dash** | Directional burst along current WASD input vector (`0.25s` duration, `0.15s` invulnerability frames against ranged/AOE, costs 35% Stamina). Prevents ranged kiting from dominating melee builds. | `dash_speed`, `dash_duration`, `i_frame_sec`, `dash_stamina_cost` |
| **Hitstop & Knockback** | On hit confirmation, apply `0.06s` of local animation freeze (hitstop) + camera shake + velocity impulse along the hit normal. Makes food fights and sword clashes feel equally punchy. | `knockback_force`, `hitstop_sec`, `poise_damage` |

#### Camera Choice: Support Both from Day One, Default to Third-Person

* **Build both into the rig on Day 1** (it is only 35 lines of code to toggle between a `HeadPitch/EyesFP` node and a `HeadPitch/SpringArm3D/CameraTP` node), **but make Third-Person Over-the-Shoulder the default (`V` to toggle).**
* **Why Third-Person Default:** In a hybrid melee/ranged game, first-person melee suffers from "face-hugging blindness"—when someone dashes past your shoulder, you lose spatial awareness of your own swing arc and footwork. Over-the-shoulder third-person lets you read your character's windup silhouette, dodge distance, and flankers immediately.
* **Making Melee Read in Both Modes:**
* **Third-Person:** Use exaggerated upper-body anticipation poses during `Windup` and a bright procedural ribbon/mesh trail attached to the weapon socket during `Active`.
* **First-Person:** Never tie the first-person camera to the third-person head bone (it causes motion sickness during melee swings). Instead, add a subtle procedural roll (`1.5 deg` camera tilt toward swing direction) during `Windup`, FOV punch (`+5 deg` for `0.1s`) on lunge, and a wide horizontal weapon trail across the screen center.



### Content Kit Architecture (`Resource`-Driven)

Everything swappable is a custom `Resource` (`class_name` registered) saved as a `.tres` file. No combat logic lives inside character or arena scenes.

* **`CharacterDef` (`character_def.gd`):**
* `id: StringName`, `display_name: String`
* `visual_scene: PackedScene` (purely the `Node3D` with `Skeleton3D` + meshes + `AnimationPlayer`—zero gameplay scripts)
* `max_health: float = 100.0`, `max_stamina: float = 100.0`, `move_speed: float = 6.5`, `jump_velocity: float = 5.5`, `dash_speed: float = 16.0`
* `hurtbox_radius: float = 0.4`, `hurtbox_height: float = 1.8`


* **`WeaponDef` (`weapon_def.gd`):**
* `id: StringName`, `display_name: String`
* `tp_mesh_scene: PackedScene` (attached to `BoneAttachment3D` on right hand)
* `fp_viewmodel_scene: PackedScene` (attached to first-person camera rig)
* `primary_action: AttackActionDef` (Resource defining melee swing OR ranged shot parameters)
* `secondary_action: AttackActionDef` (Resource defining block/parry, ADS zoom, alt-fire, or heavy attack)
* `anim_library_override: AnimationLibrary` (swaps attack animations cleanly per weapon)


* **`ArenaDef` (`arena_def.gd`):**
* `id: StringName`, `display_name: String`
* `scene: PackedScene` (must contain a `SpawnPoints` node with child `Marker3D` nodes and a `WorldEnvironment`)
* `gravity_multiplier: float = 1.0`



### MacBook Trackpad Control Scheme

On a MacBook keyboard + trackpad, your left hand rests on `WASD` and your right hand rests on the trackpad. Clicking the trackpad with your aiming finger causes cursor jitter; two-finger right-click on a trackpad cannot be held simultaneously with left-click (so traditional Mouse1 + Mouse2 ADS/Block breaks completely on a laptop).

**Solution: "Pure Glide" Hybrid Scheme (Default) + Classic Trackpad Fallback**

| Action | Default Mapping (Trackpad + Left/Thumb Keys) | Alternative / External Mouse Mapping |
| --- | --- | --- |
| **Move** | `W`, `A`, `S`, `D` | `W`, `A`, `S`, `D` |
| **3D Look / Aim** | **1-Finger Trackpad Glide** (`MOUSE_MODE_CAPTURED`) | Mouse Move (`MOUSE_MODE_CAPTURED`) |
| **Primary Attack (Swing / Shoot)** | **`F`** or **1-Finger Tap/Click** (`MOUSE_BUTTON_LEFT`) | Left Click (`MOUSE_BUTTON_LEFT`) |
| **Secondary (Block / Parry / ADS)** | **`Left Shift`** or **`E`** (hold to block/aim, tap to parry) | Right Click (`MOUSE_BUTTON_RIGHT`) |
| **Dash / Dodge** | **`Space`** (Tap) | `Left Shift` |
| **Jump** | **`C`** or **`Space`** (configurable; or Double-Tap `Space`) | `Space` |
| **Weapon Swap** | **`Q`** or **2-Finger Vertical Swipe** (`InputEventPanGesture`) | `Q` or Scroll Wheel |
| **Camera Toggle (FP / TP)** | **`V`** or **2-Finger Pinch** (`InputEventMagnifyGesture`) | `V` |
| **180° Quick-Turn** | **`R`** (rotates yaw 180° over `0.12s`—essential on small trackpads) | `R` |

* **Trackpad Aim Feel Tweaks:**
* **Disable custom exponential acceleration in Godot:** macOS already applies its own battle-tested trackpad acceleration curve to `InputEventMouseMotion.screen_relative`. Multiply `event.screen_relative` by a flat scalar (`0.0025` rad/px) plus an optional subtle low-velocity smoothing filter (`lerp` over 2 frames max) so micro-adjustments don't feel stepped.
* **Friction Aim Assist (Crucial for Trackpad):** Cast a thick `ShapeCast3D` (`SphereShape3D` radius `0.35m`) along the camera forward vector out to weapon range. When the shape cast intersects an enemy hurtbox, multiply horizontal/vertical trackpad look sensitivity by `0.55` ("reticle slowdown") and apply up to `1.5 deg` of projectile magnetism toward the target's chest. This single feature makes trackpad aiming feel like a Bungie controller setup.



---

## 2. Godot 4.7.2 Technical Architecture

### Language Recommendation: 100% GDScript (Static Typed)

Use **GDScript with strict static typing enabled**, not C#.

* **Why for AI-Assisted Dev on macOS:**
1. **Zero compile step & instant hot-reload:** When you vibe-code with Claude Code, you want to save a file and see the change in 0.5 seconds. C# requires the `.NET` build of Godot and MSBuild compilation cycles.
2. **Built-in Multiplayer & Resource Ergonomics:** `@rpc`, `MultiplayerSynchronizer` property paths, and custom `Resource` exports work with zero boilerplate in GDScript.
3. **Enforcing AI Quality:** In `Project Settings -> Debug -> GDScript`, set **Untyped Declaration** to **Error** (or **Warning**). Putting `# strict typing required` in `CLAUDE.md` forces the LLM to write `func apply_damage(amount: float, hit_normal: Vector3) -> void:`, eliminating 90% of hallucinated property bugs.



### Player Controller & Dual-Camera Rig (`CharacterBody3D`)

Use a single `PlayerCharacter` scene (`CharacterBody3D`) with a clean separation between the **Third-Person World Model** and the **First-Person ViewModel**:

```text
PlayerCharacter (CharacterBody3D) [script: player_character.gd]
├── CollisionShape3D (CapsuleShape3D: radius 0.4, height 1.8)
├── RollbackSynchronizer / MultiplayerSynchronizer (syncs state)
├── InputSynchronizer (MultiplayerSynchronizer - authority: peer_id)
├── WorldModelPivot (Node3D) [rotates on Y with character yaw]
│   └── CharacterVisualRoot (Node3D) [instantiated from CharacterDef]
│       └── Skeleton3D
│           ├── BodyMesh (MeshInstance3D)
│           └── RightHandSocket (BoneAttachment3D)
│               └── WeaponWorldMesh (Node3D)
└── CameraRig (Node3D) [positioned at neck height: y = 1.55]
    └── PitchPivot (Node3D) [rotates on X: clamped -80° to +80°]
        ├── FPCameraMarker (Marker3D) [offset: Vector3(0, 0.05, -0.15)]
        │   └── FPViewModelRoot (Node3D) [ONLY visible in FP to local player]
        ├── TPSpringArm (SpringArm3D) [length = 2.6, margin = 0.2, shape = SphereShape3D(0.2)]
        │   └── TPCameraMarker (Marker3D) [offset: Vector3(0.55, 0.2, 0) for over-the-shoulder]
        ├── ActiveCamera (Camera3D) [interpolates transform between FPCameraMarker and TPCameraMarker]
        └── AimRay (RayCast3D) / AimAssistCast (ShapeCast3D)

```

* **How First-Person vs. Third-Person Visibility Works (No Shadow Disappearing Bug):**
* **For Remote Players (`not is_multiplayer_authority()`):** `FPViewModelRoot.visible = false`. `BodyMesh` renders normally (`cast_shadow = SHADOW_CASTING_SETTING_ON`).
* **For the Local Player in Third-Person Mode:** `FPViewModelRoot.visible = false`. `BodyMesh` renders normally. `ActiveCamera` smoothly interpolates (`Transform3D.interpolate_with`) to `TPCameraMarker.global_transform`.
* **For the Local Player in First-Person Mode:** `ActiveCamera` snaps/interpolates to `FPCameraMarker.global_transform`. `FPViewModelRoot.visible = true`. On `BodyMesh` (and `WeaponWorldMesh`), set `cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY`. This hides your own third-person head/torso from clipping into your camera while **preserving your full body shadow on the ground**.


* **SpringArm3D Collision Exclusion:** In `_ready()`, always call `tp_spring_arm.add_excluded_object(self.get_rid())` so the third-person camera never collides with the player's own capsule.

### Animation Setup & Placeholder 3D Assets

* **Placeholder Rigged Characters & Animations:**
* **Best Choice for Godot 4.7.2:** **KayKit Character Packs + KayKit Prototype Bits** (by Kay Lousberg, CC0) or **Quaternius Universal Base Characters** (CC0). Both import cleanly as `.glb` files, share a single standardized humanoid skeleton, and include ready-to-use melee swings, ranged shoots, blocks, dashes, and locomotion clips.
* Configure every `.glb` character in Godot's **Advanced Import Settings -> Skeleton3D -> Retarget -> Bone Map** using a shared `SkeletonProfileHumanoid`. Because all characters share the `SkeletonProfileHumanoid`, any `AnimationLibrary` works on any character mesh!


* **AnimationTree Architecture:**
* Use an `AnimationTree` with an `AnimationNodeBlendTree` at the root:
1. **Locomotion `BlendSpace2D`:** Driven by normalized local velocity (`Vector2(vel_right, vel_forward)`), blending `Idle`, `Run_Forward`, `Run_Backward`, `Strafe_Left`, `Strafe_Right`.
2. **UpperBody `OneShot` Node (Filtered to Spine, Chest, Shoulders, Arms, Head):** Fires attack swings, ranged recoil, and block poses on top of running legs so players can move while attacking.
3. **FullBody `StateMachine` Override (for Dash, Stagger, Death):** Overrides the entire skeleton when airborne, dashing, staggered, or dead.


* **Upper-Body Aim Pitch (`LookAtModifier3D`):** Place a `LookAtModifier3D` node (child of `Skeleton3D`, targeting the `UpperChest` bone in `SkeletonProfileHumanoid`) pointed at a `Marker3D` 10 meters down the `PitchPivot` forward vector. When a player looks up or down, their torso and weapon tilt naturally in third-person.



### Multiplayer Architecture (Server Authority + Pragmatic 2–4 Player Netcode)

Use Godot's **High-Level Multiplayer API** (`MultiplayerSpawner`, `MultiplayerSynchronizer`, and `@rpc`) backed by `ENetMultiplayerPeer` in Phase 1. **Do not write custom raw packet netcode from scratch**, and **do not build complex full-world rollback from scratch on Day 1**.

Here is the exact authority and lag-compensation split that feels responsive for 2–4 players without turning into a 6-month networking engine project:

1. **Server Authority Split (Recommended for Vibe Coding):**
* **Movement Authority:** For a casual/friend-group 2–4 player game, **Client-Authoritative Movement with Server Sanity Validation** (or using the `netfox` addon's `RollbackSynchronizer` if you want strict server-authoritative prediction later) is massively faster to build. Specifically: each player peer has authority over their own `CharacterBody3D.global_position`, `velocity`, and `look_angles` via a `MultiplayerSynchronizer` (`replication_interval = 0.033` / 30 Hz, `delta_interval = 0.016`). This gives **zero local input lag** on movement and camera look out of the box.
* **Combat & Health Authority (100% Server / Host ID `1`):** Only peer `1` (the server) can modify `health`, spawn projectiles, validate melee hits, or change round states.


2. **Remote Player Interpolation:**
* Never bind a `MultiplayerSynchronizer` directly to `CharacterBody3D.global_position` without smoothing, or remote players will stutter at the network tick rate.
* Instead, sync `sync_position: Vector3`, `sync_velocity: Vector3`, and `sync_yaw: float`. On non-authority peers (`not is_multiplayer_authority()`), interpolate `global_position = global_position.lerp(sync_position, 1.0 - exp(-20.0 * delta))` inside `_process(delta)`.


3. **Hit Registration & Lag Compensation (2-Player Pragmatic Approach):**
* **Melee & Parry:** When Player A presses attack, Player A immediately plays the local windup animation and sends `@rpc("any_peer", "call_local", "reliable") func request_attack(action_id: StringName, aim_origin: Vector3, aim_dir: Vector3)`. Because melee has a `0.15s–0.25s` windup, an RPC over Tailscale (`10–40ms` ping) arrives well before the active swing phase! During the active frames, the **Server** runs a `ShapeCast3D` sweep from the attacker's weapon socket. If the target has `is_blocking` active within `parry_window_sec + (peer_rtt_ms / 2000.0)` (generous ping-padded parry window), the server awards the parry.
* **Ranged Hitscan:** Favor the shooter within reason. When a client fires a hitscan weapon, they pass `(aim_origin, aim_dir, target_peer_id, local_hit_point)`. The server checks that `aim_origin` is within `1.5m` of the shooter's server position and that `local_hit_point` is within a generous tolerance (`0.75m` radius—accounting for ~100ms of movement) of the target's current position, plus a line-of-sight wall check. For 2–4 players, this "bounded shooter-favoring validation" takes 20 lines of code and feels instantaneous without needing a 60-tick historical ring-buffer rewind system.



### Trackpad Input in Godot 4.7.2 on macOS

Handle trackpad events explicitly inside `_unhandled_input(event: InputEvent)`:

```gdscript
extends Node3D

@export var look_sensitivity: float = 0.0024
@export var pan_weapon_threshold: float = 1.5
@export var pinch_camera_threshold: float = 0.15

var _pan_accum: float = 0.0
var yaw: float = 0.0
var pitch: float = 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Godot 4.4+ / 4.7 macOS: accumulate_input is true by default, keep it true
	Input.use_accumulated_input = true

func _unhandled_input(event: InputEvent) -> void:
	# 1. Single-finger glide -> 3D Camera Look
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		# Use screen_relative so macOS native retina/DPI scaling stays consistent
		var sens_mult: float = _get_aim_assist_multiplier()
		yaw -= motion.screen_relative.x * look_sensitivity * sens_mult
		pitch = clampf(pitch - motion.screen_relative.y * look_sensitivity * sens_mult, deg_to_rad(-80.0), deg_to_rad(80.0))
		return

	# 2. Two-finger swipe -> Quick Weapon Swap
	if event is InputEventPanGesture:
		var pan := event as InputEventPanGesture
		_pan_accum += pan.delta.y
		if absf(_pan_accum) > pan_weapon_threshold:
			_cycle_weapon(signi(int(_pan_accum)))
			_pan_accum = 0.0
		return

	# 3. Two-finger pinch -> Toggle First-Person / Third-Person Camera
	if event is InputEventMagnifyGesture:
		var mag := event as InputEventMagnifyGesture
		if mag.factor < (1.0 - pinch_camera_threshold):
			set_camera_mode(CameraMode.THIRD_PERSON)
		elif mag.factor > (1.0 + pinch_camera_threshold):
			set_camera_mode(CameraMode.FIRST_PERSON)

```

* **macOS Caveats to Flag:**
* **Three-finger swipe mission control:** Tell both players to keep 3-finger gestures for macOS Mission Control, and only bind 1-finger motion and 2-finger pan/pinch in-game.
* **Esc / Focus Loss:** Always listen for `NOTIFICATION_WM_WINDOW_FOCUS_OUT` to set `Input.mouse_mode = Input.MOUSE_MODE_VISIBLE`, and recapture on left-click inside the window. Never trap a Mac user's cursor when they `Cmd+Tab` to Claude Code!



### Rendering on Apple Silicon (MacBook Air vs. MacBook Pro)

Apple Silicon uses a **Tile-Based Deferred Renderer (TBDR)** GPU architecture. Heavy full-screen post-processing passes that thrash tile memory (like high-sample screen-space ambient occlusion, SSR, and volumetric fog) are what cause a fanless **MacBook Air** to thermally throttle after 10 minutes.

* **Which Renderer to Pick:** Use the **`mobile` renderer (`rendering/renderer/rendering_method = "mobile"`)** on the **native `"metal"` driver**!
* **Why `mobile` over `forward_plus` on Apple Silicon:** Despite the name, Godot's `mobile` renderer is specifically engineered for **TBDR GPUs** (which is what every M1/M2/M3/M4 chip is). It keeps lighting passes inside fast on-chip tile memory, supports MSAA 4x practically for free on Apple Silicon, and uses half the wattage of `forward_plus`. In Godot 4.7.2, both `AreaLight3D` and macOS HDR output work on the `mobile` renderer.


* **Quality Preset Matrix (Auto-Selected or Toggled in Settings):**

| Setting | MacBook Air Profile (Default / Thermal-Safe) | MacBook Pro Profile (High Refresh) |
| --- | --- | --- |
| **Rendering Driver / Method** | `metal` / `mobile` | `metal` / `mobile` (or `forward_plus`) |
| **Frame Rate Cap (`Engine.max_fps`)** | **`60` FPS** (Crucial: capping at 60 prevents thermal throttling on fanless Airs) | **`120` FPS** (ProMotion) |
| **3D Resolution Scale (`scaling_3d/scale`)** | `0.75` (with `FSR 1.0` or Bilinear on Retina displays—looks razor sharp at 2x HiDPI) | `1.0` |
| **Anti-Aliasing** | `MSAA 2x` (Tile-memory native on Metal) | `MSAA 4x` |
| **Directional Shadow Size** | `2048`, Soft Low, 2 Splits | `4096`, Soft Medium, 4 Splits |
| **Glow / Bloom** | Enabled (Low cost) | Enabled |
| **SSAO / SSR / SDFGI** | **Disabled** (Not needed; use baked `LightmapGI` or simple `ReflectionProbe`) | Optional |

### Headless Server & Apple Silicon Export Setup

* **Running a Local Headless Server on macOS:**
Create an alias or shell script pointing to the binary inside your `Godot.app`:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -- --server --port=7777

```


In your main startup script, parse `OS.get_cmdline_user_args()` (everything after `--`). If `"--server"` is present, automatically call `NetworkManager.start_Dedicated_server(7777)` and skip initializing audio/camera effects.
* **Exporting & Sharing Builds Between Two Macs (No $99 Apple Developer Account Required):**
1. In `Project -> Export -> Add -> macOS`, set **Architecture** to `arm64` (no need for universal `x86_64` fat binaries while testing on M-series Macs).
2. Set **CodeSign -> Identity** to `"-" (Ad-hoc signing)` (default in Godot on macOS).
3. Export as a `.zip` or `.dmg`. When your friend downloads the build over Tailscale or GitHub Releases, macOS Gatekeeper will quarantine it only if transferred via a browser. Have your friend run once in Terminal:
```bash
xattr -cr /path/to/YourGame.app

```


Or transfer via `tailscale file cp YourGame.zip friend-mac:` (Taildrop does not set the browser quarantine bit in the same way, or `xattr -cr` strips it instantly).



---

## 3. AI-Friendly Project Setup

### Folder Structure & Naming Conventions

LLMs perform dramatically better when every system is isolated by domain and file paths are predictable:

```text
res://
├── CLAUDE.md                        # AI architecture & Godot 4.7.2 rules
├── project.godot
├── .gitattributes                   # Git LFS rules for .glb, .png, .wav, .ogg
├── core/                            # Autoload singletons & network transport
│   ├── game_manager.gd              # Match state machine & round flow
│   ├── network_manager.gd           # Abstracted transport (ENet now, Relay later)
│   └── content_registry.gd          # Auto-loads CharacterDef, WeaponDef, ArenaDef
├── defs/                            # Resource class definitions (.gd)
│   ├── character_def.gd
│   ├── weapon_def.gd
│   ├── attack_action_def.gd
│   └── arena_def.gd
├── content/                         # Data instances (.tres) & 3D assets (.glb)
│   ├── characters/                  # knight.tres, cyber_bandit.tres, meshes/
│   ├── weapons/                     # broadsword.tres, plasma_pistol.tres, pie.tres
│   └── arenas/                      # courtyard.tres, neon_rooftop.tres
├── gameplay/                        # Core runtime scenes & scripts
│   ├── match_world.tscn             # Root container for Arena + Players + Projectiles
│   ├── player/
│   │   ├── player_character.tscn
│   │   ├── player_character.gd
│   │   ├── player_camera_rig.gd
│   │   └── player_combat_controller.gd
│   └── combat/
│       ├── projectile_base.tscn
│       ├── projectile_base.gd
│       └── hitbox_sweeper.gd
├── ui/                              # HUD & lobby menus (built mostly via code/small scenes)
│   ├── hud.tscn
│   └── lobby_overlay.tscn
└── scripts/                         # Bash helpers for local/Tailscale testing
    └── test_multiplayer.sh

```

### Drop-In `CLAUDE.md` for Your Repository Root

Save this directly as `CLAUDE.md` in the root of your project so Claude Code never writes outdated Godot 3/4.0 code:

```markdown
# Project Rules for AI Coding Agent (Godot 4.7.2 macOS)

## Engine & Environment
- **Engine:** Godot 4.7.2 (Standard build, GDScript, macOS Apple Silicon).
- **Renderer:** `mobile` rendering method on the native `metal` driver.
- **Physics:** Built-in **Jolt Physics 3D** (default in Godot 4.6/4.7).
  - NEVER install external `godot-jolt` addons.
  - NEVER apply non-uniform `scale` to `CollisionShape3D` or physics bodies. Modify shape resource properties (`radius`, `height`, `size`) directly.

## GDScript Coding Standards
- **Strict Static Typing:** Every variable, parameter, return type, and dictionary MUST be explicitly typed.
  - Use Godot 4.4+ typed dictionaries: `var items: Dictionary[StringName, WeaponDef] = {}`
  - Use typed arrays: `var spawn_points: Array[Marker3D] = []`
- **UID Files:** Godot 4.4+ creates `.uid` sidecar files for `.gd` and `.gdshader` files. Never delete `*.uid` files. Prefer `load("res://path/to/file.tres")` over hardcoded `uid://` strings when authoring `.tscn` or `.gd` files from CLI.
- **Skeletons & IK:** Never use deprecated `SkeletonIK3D`. Use `LookAtModifier3D` or `IKModifier3D` (`SkeletonModifier3D`).

## Scene & Merge Hygiene
- Keep `.tscn` files minimal and shallow. Prefer creating sub-components or UI layouts programmatically in GDScript or in small, single-purpose `.tscn` files.
- Never embed inline scripts or large sub-resources inside `.tscn` files; always save scripts as external `.gd` files and data as external `.tres` files.

## Multiplayer Architecture Rules
- **Authority Split:**
  - Each player's `CharacterBody3D` has `set_multiplayer_authority(peer_id)` for responsive local movement and look.
  - Peer `1` (Server) has sole authority over `MatchWorld`, health mutations, hit confirmation, projectile spawning, and round state transitions.
- **Network Abstraction:** Never reference `ENetMultiplayerPeer` outside `core/network_manager.gd`. All gameplay code interacts only with `multiplayer.get_unique_id()`, `is_multiplayer_authority()`, and `@rpc` methods.
- **Verification CLI:** Run syntax/headless checks after edits using:
  `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit`

```

### Keeping `.tscn` / `.tres` Merge-Friendly Between Two Developers

1. **Never embed sub-resources in `.tscn`:** When you create a `CapsuleShape3D` or `StandardMaterial3D` inside a `.tscn`, Godot generates random sub-resource IDs (`SubResource("CapsuleShape3D_8x9a2")`). If two people edit the same `.tscn`, those IDs collide. Either keep one owner per `.tscn`, or build collision shapes/materials in `_ready()` via GDScript.
2. **Data-Driven Ownership:** One friend can build `content/weapons/plasma_pistol.tres` and `content/characters/cyber_bandit.tres` while the other edits `gameplay/player/player_combat_controller.gd`—zero shared files touched.
3. **Configure `.gitattributes` on Day 1:**
```gitattributes
# Binary assets -> Git LFS
*.glb filter=lfs diff=lfs merge=lfs -text
*.png filter=lfs diff=lfs merge=lfs -text
*.webp filter=lfs diff=lfs merge=lfs -text
*.wav filter=lfs diff=lfs merge=lfs -text
*.ogg filter=lfs diff=lfs merge=lfs -text

# Godot text scenes/resources -> Force LF line endings
*.tscn text eol=lf
*.tres text eol=lf
*.gd text eol=lf
*.uid text eol=lf

```



### Fast Local & Tailscale Testing Workflow

1. **Built-In Editor Multi-Instance (Local Testing on 1 Mac):**
In the Godot Editor top menu, go to **Debug -> Customize Run Instances...**, check **Enable Multiple Instances**, set count to **2**, and pass launch arguments:
* Instance 1 Launch Arguments: `--host --window-left`
* Instance 2 Launch Arguments: `--join=127.0.0.1 --window-right`
Now pressing `Cmd+B` (Run Project) immediately spawns both the Host window and Client window side-by-side on your MacBook and connects them automatically!


2. **Zero-Config Tailscale Auto-Discovery / Connect:**
In `network_manager.gd`, parse `--join=<ip_or_magicdns>`. Because Tailscale provides **MagicDNS**, you don't even need to type raw `100.x.y.z` IPs—your friend can connect to `--join=macbook-pro-theo` (or whatever your Tailscale machine hostname is), as `IP.resolve_hostname("macbook-pro-theo")` resolves your Tailscale IPv4 directly!

---

## 4. Milestone Plan & Phase 2 Networking Lock-Ins

### Milestone 1: Two Capsules Moving & Hitting Over Tailscale (Step-by-Step)

1. **Initialize Repo, Jolt, and Metal Mobile Settings:** Takes ~10 minutes.
Create a new Godot 4.7.2 project. Verify in **Project Settings**:

* `rendering/renderer/rendering_method` = `"mobile"`
* `rendering/rendering_device/driver.macos` = `"metal"`
* `physics/3d/physics_engine` = `"Jolt Physics"` (default in 4.7.2)
* `debug/gdscript/warnings/untyped_declaration` = `2` (Error)
Commit `project.godot`, `.gitignore` (ignoring `.godot/`), `.gitattributes`, and `CLAUDE.md`.


2. **Build NetworkManager Autoload with CLI Argument Parsing:**
Have your AI assistant generate `core/network_manager.gd` registered as an Autoload:

* Exposes `host_game(port: int = 7777)` and `join_game(address: String, port: int = 7777)` using `ENetMultiplayerPeer`.
* Reads `OS.get_cmdline_args()` on startup: if `--host` is passed, auto-hosts; if `--join=<host>` is passed, resolves the hostname via `IP.resolve_hostname()` and connects.
* Emits `player_connected(peer_id: int)` and `player_disconnected(peer_id: int)`.


3. **Create Greybox Arena & MultiplayerSpawner:**
Prompt the AI to create `gameplay/match_world.tscn`:

* Add a `CSGBox3D` floor (`24m x 1m x 24m` with `use_collision = true`) and four low cover blocks.
* Add a `DirectionalLight3D` and `WorldEnvironment` (procedural sky).
* Add a `Players` `Node3D` container and a `MultiplayerSpawner` configured to watch `Players` with `player_character.tscn` in its Auto Spawn List, using a custom `spawn_function` that sets `player.name = str(peer_id)` and `player.set_multiplayer_authority(peer_id)`.


4. **Build Dual-Camera Capsule Controller with Trackpad Input:**
Prompt the AI to create `gameplay/player/player_character.tscn` (`CharacterBody3D`):

* Add a `CollisionShape3D` (`CapsuleShape3D`), a visible `MeshInstance3D` (`CapsuleMesh` colored blue for host, red for client), and a "nose" box mesh so facing direction is obvious.
* Implement the `CameraRig` with `FPCameraMarker`, `TPSpringArm` (`SpringArm3D`), and `ActiveCamera` (`Camera3D`). Press `V` or 2-finger pinch to toggle FP/TP.
* Add a `MultiplayerSynchronizer` syncing `sync_position`, `sync_velocity`, `yaw`, `pitch`, and `health` (with `health` synced from Server `1`, and transform synced from `peer_id`).


5. **Add Server-Validated Melee Lunge & Ranged Raycast:**
Add two test attacks to `player_character.gd`:

* **Left Click / `F` (Melee):** Plays a quick scale/color telegraph (`0.15s`), applies forward lunge impulse, and sends `@rpc("any_peer", "call_local", "reliable") func request_melee_hit()`. Server checks if any enemy `CharacterBody3D` is within `2.2m` and inside a `70 deg` forward cone; if so, subtracts `25` health and applies knockback velocity via RPC.
* **`E` (Hitscan Beam):** Draws a temporary 3D line cylinder and sends `request_hitscan(origin, dir)` to the server. Server casts a ray and subtracts `15` health on hit.
* When `health` reaches `0`, teleport the capsule back to a random spawn point and restore `health = 100`.


6. **Test Local Dual-Instance, Then Connect Over Tailscale:**
1. Run two instances locally via **Debug -> Customize Run Instances** (`--host` and `--join=127.0.0.1`). Verify both capsules see each other move smoothly, toggle FP/TP cameras, and deal knockback/damage.
2. Push to Git. Have your friend pull, open Godot, and run with `--join=<your-tailscale-hostname>`. Fight in the greybox!


---

### Subsequent Milestones to a Multi-Setting Prototype

| Milestone | Goal | Key Deliverables |
| --- | --- | --- |
| **M2: Combat Depth & Trackpad Polish** | Make capsule-vs-capsule combat genuinely tactical before adding art. | Add **Stamina**, **Block/Parry (`Left Shift`)**, **Directional Dash (`Space`)**, **Hitstop + Camera Shake**, and **Trackpad Reticle Friction Aim Assist** (`ShapeCast3D`). |
| **M3: Resource Content Kit Pipeline** | Decouple stats, weapons, and arenas from player code. | Implement `CharacterDef`, `WeaponDef`, `AttackActionDef`, and `ArenaDef` Resources. Build `ContentRegistry` autoload that scans `res://content/` on boot. Add projectile spawner for non-hitscan weapons. |
| **M4: Humanoid Rigs & AnimationTree** | Replace capsules with rigged 3D characters and third/first-person weapons. | Import KayKit/Quaternius `.glb` characters with `SkeletonProfileHumanoid`. Wire `AnimationTree` (`BlendSpace2D` legs + `OneShot` upper body + `LookAtModifier3D` spine pitch). Set `SHADOWS_ONLY` on local body in FP mode. |
| **M5: Two Swappable Settings & Match Loop** | Prove the "any matchup" architecture with two contrasting kits + round flow. | **Kit 1 (Medieval):** Knight + Broadsword (cleave melee + parry) + Crossbow (gravity projectile) + Courtyard Arena. **Kit 2 (Cyberpunk):** Cyber Bandit + Plasma Pistol (hitscan + overheat) + Katana (fast dash-slash) + Neon Rooftop Arena. Add Best-of-5 round UI & 10-second kit selector overlay. |

---

### Decisions to Lock In Now for Phase 2 Networking (Leaving Tailscale)

So that migrating from Tailscale (`ENetMultiplayerPeer`) to internet play requires **modifying only `core/network_manager.gd` (under 80 lines of code)** and zero gameplay files, lock in these four rules right now:

1. **Isolate Transport Creation in `NetworkManager`:**
Godot's `MultiplayerAPI` is completely transport-agnostic. Whether `multiplayer.multiplayer_peer` is an `ENetMultiplayerPeer` (UDP over Tailscale), a `WebRTCDataChannel` peer (via **Noray** open-source NAT punchthrough/relay for Godot), or `SteamMultiplayerPeer` (via **GodotSteam**), all of your `MultiplayerSpawner`, `MultiplayerSynchronizer`, and `@rpc` calls stay 100% identical.
2. **Never Use IP Addresses as Player Identifiers:**
Always key player dictionaries, scores, and spawn ownership by `peer_id: int` (`multiplayer.get_unique_id()`), never by IP/port strings.
3. **Keep Sync Bandwidth Under 15 KB/s Per Player:**
In your `MultiplayerSynchronizer` nodes, sync only minimal primitives (`Vector3` position, `Vector3` velocity, `float` yaw/pitch, `int` state enum). Never pass `Resource` objects or node paths over `@rpc`—always pass their `StringName` ID (e.g., `&"plasma_pistol"`) and resolve the `WeaponDef` locally via `ContentRegistry.get_weapon(id)`. This ensures relay servers (like Noray or Steam Relay) never choke on packet size.
4. **Pick Your Phase 2 Path Early:**
* If you want **free self-hosted NAT punchthrough + fallback relay** without Steam: use **Noray** (a lightweight single-binary Go server made specifically for Godot 4 that runs on a €4/mo Hetzner VPS and handles NAT punchthrough + relay seamlessly).
* If you might put the game on Steam for friends: drop in **GodotSteam's `SteamMultiplayerPeer**`, which gives you Valve's global SDR relay network and friend-invite lobbies for free with zero server hosting costs.