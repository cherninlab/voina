# Procedural character and heavy sword

Hold **left click** (or the rebound melee key, **F** by default) and drag at least **36 screen pixels** to start an attack. **Camera look continues normally throughout the drag and swing.** One press produces one damaging swing; release before the next attack. A click alone does not attack. The first click after Esc only recaptures the cursor.

The longsword is a dragged pendulum, not a held weapon. Its tip is a point mass on a rigid rod from the hilt: gravity pulls it down every frame, the floor stops it with friction, and the hands only add momentum while the mouse is held and moving. Nobody can hold the blade up; at rest it lies on the ground behind one hip. A drag throws the tip around the front of the body, the host-approved cut adds a bounded impulse in the same direction, and the blade falls to the ground on the other side. The body blocks the blade from passing behind the back, so the next swing has to drag it back the other way; a drag into the blocked side rearms the gesture without spending stamina. Blocking is the one case where the arms brace the blade up, through a strong but finite spring.

The blade accelerates, lags behind the drag, carries momentum through reversals, and settles on release. A slower spring makes the hips and torso follow it. During an attack, the tip's horizontal travel produces a capped **1.8 m/s** movement contribution through the owner's existing `move_and_slide()` controller. Residual movement damps away after release; a correction, dash or stagger drops the grip and lets the blade keep falling. The camera has no swing turn-rate cap. E remains the test beam; Ctrl/right click blocks.

## Procedural pose

A `SkeletonModifier3D` generates the gameplay pose from the rig's rest transforms each frame:

- Pelvis and spine twist, lean and bob respond to the sword and stepping state; the hips drop with speed so the planted leg can reach; the head follows view pitch.
- Two-bone arm IK puts the wrists on the hilt in a hammer grip built from the rigs' measured hand axes: thumb side toward the blade, palm against the grip. Both hands grip while dragging; at rest the hand on the blade's side holds it. The hilt is constrained to arm reach; fingers curl.
- Two-bone leg IK reaches world-space planted ankle targets. A planted foot steps once it trails the hips by half a stride and lands where the hips will be when the step ends, so feet keep up at a run instead of trailing; ground rays provide contact height and normal, and airborne legs tuck.

Imported clips remain available for asset inspection, but runtime locomotion and sword posing use the procedural solver. Both rigs share this behavior. The locally generated longsword trails behind at rest and stays visible in first person while the body keeps its shadows-only behavior.

The owner predicts locally. Host-approved attack direction provides the initial impulse; ongoing yaw, pitch and held intent travel with owner movement synchronization so peers reconstruct the motion. Held intent is cosmetic and cannot authorize damage. Ownership, finite direction validation, stamina, cooldown, phases, hit resolution and the existing rewind logic remain with the host.

## Limits

Damage still uses the existing host-owned melee cone and cover checks; this is not blade-mesh collision. Angular inertia, body reaction and ground contact are a procedural approximation, not a ragdoll or physically simulated weapon. The blade can intersect walls/props. Foot targets follow ground height but do not move the collision capsule onto steps, solve moving-platform adhesion, or guarantee perfect contact on extreme terrain. No physics body or collision shape is scaled.

## Verification

```sh
"$GODOT" --headless --editor --path . --quit
python3 scripts/smoke_test.py "$GODOT"
"$GODOT" --headless --path . res://tests/sword_test.tscn
"$GODOT" --headless --path . res://tests/inertia_test.tscn
"$GODOT" --path . res://tests/sword_test.tscn
```

Checks cover gesture rearming, request ownership/validation/cooldown, prediction rejection, both hand grips, camera movement during drag (visible run), a blade that cannot be held up, a swing crossing the front and resting on the far side, the body block, release settling, 30/120 Hz consistency, bounded owner displacement, correction reset, and planted-foot targets on both rigs. Optional network mode uses two test-scene processes: `-- --sword-network --host --port=7788`, then `-- --sword-network --join=127.0.0.1 --port=7788`. Stop the host after the client reports `SWORD_NETWORK_OK`; this also checks host reconstruction of continuous aim and held intent.

Rendered poses and automated visible input checks are separate from manual acceptance. Trackpad feel, live camera readability, contact polish and two-Mac Tailscale play still need human testing. No latency, bandwidth or thermal measurements are claimed.

Implementation follows Godot's [SkeletonModifier3D callback and coordinate-space contract](https://docs.godotengine.org/en/stable/classes/class_skeletonmodifier3d.html).
