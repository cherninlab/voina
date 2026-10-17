# Procedural character and heavy sword

Hold **left click** (or the rebound melee key, **F** by default) and drag at least **36 screen pixels** to start an attack. **Camera look continues normally throughout the drag and swing.** One press produces one damaging swing; release before the next attack. A click alone does not attack. The first click after Esc only recaptures the cursor.

The sword uses exaggerated angular inertia. An ordinary cut picks the blade up above the head and launches a broad arc, then gravity drives it into the ground. A downward cut from an already raised blade chops immediately; from the ground it first lifts. Mouse movement while held adds steering and lift. **Stopping the mouse allows follow-through without pulling the blade back toward the camera.** Each gesture is limited to about 140 degrees from its starting heading, with braking near the end, so a held gesture cannot turn into an endless orbit. Release and press again to start the next damaging swing from the current blade position.

Heading and elevation are integrated separately from the hands and body. Moving the grip, stepping, or correcting the rod length cannot add energy to the blade. The blade has bounded angular speed and elevation, and ground contact dissipates its motion. These are deliberate game-feel constraints, not a free rigid-body simulation.

The torso follows the blade with a damped, capped turn. A cut gives the owner one short movement pulse in the launch direction, capped at **1.8 m/s** for a **0.45 s** envelope; it does not chase the rotating tip. This breaks the previous sword/body feedback loop that could produce spiralling. Lean emphasizes the pickup, lateral swing and downward impact. Looking without dragging leaves the sword's landing in place. Walking away first stretches the arms, then drags the grounded tip; resistance applies only while moving away from it. Blocking deliberately raises the guard toward the view. The camera remains free throughout. The test beam input is disabled; Ctrl/right click blocks.

## Procedural pose

A `SkeletonModifier3D` generates the gameplay pose from the rig's rest transforms each frame:

- The hips stay dropped for a half-bent stance and lower further at speed; lean and bob respond to the sword and stepping state; the spine and head turn toward the view.
- Two-bone arm IK puts the wrists on the hilt in a hammer grip built from the rigs' measured hand axes: thumb side toward the blade, palm against the grip. Both hands grip while dragging or while the blade stands ahead; a blade left off to one side is held by the hand on that side. The hilt is constrained to arm reach; fingers curl.
- Two-bone leg IK reaches world-space planted ankle targets. A planted foot steps once it trails the hips by half a stride and lands where the hips will be when the step ends, so feet keep up at a run instead of trailing; ground rays provide contact height and normal, and airborne legs tuck.

Imported clips remain available for asset inspection, but runtime locomotion and sword posing use the procedural solver. Both rigs share this behavior. The locally generated longsword rests at its last landing and stays visible in first person while the body keeps its shadows-only behavior.

The owner predicts locally. Host-approved attack direction provides the initial impulse; ongoing yaw, pitch and held intent travel with owner movement synchronization so peers reconstruct the motion. Held intent is cosmetic and cannot authorize damage. Ownership, finite direction validation, stamina, cooldown, phases, hit resolution and the existing rewind logic remain with the host.

## Raiders

The host sweeps each player's simulated blade against hostile raiders every physics tick while a swing is approved (`gameplay/player/blade_contact.gd`). The blade point that touches moves with the tip scaled by its position along the blade; above 3 m/s it shoves the raider along that direction with a hop and a lean, deals the swing's damage once per target, and above 10 m/s it bisects the raider: the mob dies and two rigid halves, clipped by a plane through the contact that contains the blade and its travel, tumble away with exposed flesh. This is host-only and cosmetic between players; see [mobs](mobs.md).

## Tuning

Release the cursor with Esc and open **Sword tweaks** (below the Controls button) for live sliders over the angular motion: gesture drive and damping, body follow and turn cap, cut kick, air damping, gravity, mouse lift, floor drag and landing brake, reach and hilt heights, anchor pull-back and swing follow-through. Values persist per machine in `user://sword_tweaks.cfg`, control local motion (the host reconstructs the blade for raider contact), and **Print values** writes the current set to the console for copying into the defaults. Existing saved values still load; use **Defaults** to evaluate the current baseline. The underlying `follow_spring` setting controls gesture force. Saved values remain compatible; arc and elevation limits are fixed to keep high settings from causing runaway motion.

## Limits

Damage still uses the existing host-owned melee cone and cover checks; this is not blade-mesh collision. Angular inertia, body reaction and ground contact are a stylized procedural approximation, not a ragdoll or free rigid-body weapon. The exaggerated pickup and bounded arc deliberately prioritize readability and control. The blade can intersect walls/props. Foot targets follow ground height but do not move the collision capsule onto steps, solve moving-platform adhesion, or guarantee perfect contact on extreme terrain. No physics body or collision shape is scaled.

## Verification

```sh
"$GODOT" --headless --editor --path . --quit
python3 scripts/smoke_test.py "$GODOT"
"$GODOT" --headless --path . res://tests/sword_test.tscn
"$GODOT" --headless --path . res://tests/inertia_test.tscn
"$GODOT" --path . res://tests/sword_test.tscn
```

Checks cover gesture rearming, request ownership/validation/cooldown, prediction rejection, both hand grips, camera movement during drag (visible run), a blade that cannot be held up, arm stretch and anchor drag with owner resistance, the body facing the blade, a mouse-driven swing, left/right carry-through without reversal while held or released at 30/60/120 Hz, overhead lift, persistent landings and return cuts, bounded held-input arcs, coupled owner movement without spirals, rapid alternating cuts, release settling, moving-gesture consistency at 30/60/120 Hz, bounded owner displacement, correction reset, and planted-foot targets on both rigs. Optional network mode uses two test-scene processes: `-- --sword-network --host --port=7788`, then `-- --sword-network --join=127.0.0.1 --port=7788`. Stop the host after the client reports `SWORD_NETWORK_OK`; this also checks host reconstruction of continuous aim and held intent.

Rendered poses and automated visible input checks are separate from manual acceptance. Trackpad feel, live camera readability, contact polish and two-Mac Tailscale play still need human testing. No latency, bandwidth or thermal measurements are claimed.

Implementation follows Godot's [SkeletonModifier3D callback and coordinate-space contract](https://docs.godotengine.org/en/stable/classes/class_skeletonmodifier3d.html).
