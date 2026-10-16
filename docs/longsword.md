# Longsword and hand IK

Hold **left click** (or the rebound melee key, **F** by default) and drag at least **36 screen pixels** to start a cut. Left/right, up/down and diagonal gestures set the sword's cut direction. One press produces one swing; release before the next attack. A click alone does not attack. The first click after Esc only recaptures the cursor.

Mouse motion controls the gesture while held, then returns to camera look on release. The threshold is independent of look sensitivity and aim friction. Esc, focus loss, camera changes, quick turn, block, dash, stagger and position corrections cancel an unfinished gesture. E remains the test beam. Shift/right click blocks.

Both existing character rigs carry a locally generated steel longsword with a crossguard, leather grip and pommel. At rest, the right hand carries it with the point near floor level behind the character; turns and travel add a damped trailing motion. During a swing or block, the other hand joins the hilt. A custom `SkeletonModifier3D` performs analytic two-bone arm IK after the existing animation playback, with elbow poles, reach clamping, wrist alignment and finger curl. The pulled locomotion clips remain in use. The sword remains visible in first person while the body retains its shadows-only behavior.

The owner predicts the sword motion immediately. The host validates request ownership and finite bounded directions, normalizes the cut, applies the existing stamina/cooldown/phase checks, then broadcasts the accepted direction. Rejection, stagger and correction cancel the visual swing. Damage, parries and movement authority remain with the existing controllers.

## Scope and limitations

The drag direction controls presentation; damage still uses the existing host-owned melee cone and cover checks. This is not blade-mesh collision or a freeform physics weapon. Blade trailing is cosmetic, uses the current flat-arena height, and can intersect walls or raised props. The IK targets hands; there is no terrain-aware foot IK. No external weapon assets or physics bodies were added.

## Verification

```sh
"$GODOT" --headless --editor --path . --quit
python3 scripts/smoke_test.py "$GODOT"
"$GODOT" --headless --path . res://tests/sword_test.tscn
```

The headless sword test checks gesture threshold/rearming/cancellation, host request validation, one charge per swing, prediction rejection, both rigs' grip reach and first-person visibility flags. Run the same test without `--headless` to additionally check cursor recapture, the actual input route and camera suppression; headless Godot cannot capture the mouse. Its optional network mode runs with two processes: start the same test scene with `-- --sword-network --host --port=7788`, then with `-- --sword-network --join=127.0.0.1 --port=7788`. Stop the host after the client reports `SWORD_NETWORK_OK`.

Rendered pose previews check idle and mid-swing presentation on both models. These checks do not establish manual trackpad feel, camera readability in motion or two-Mac Tailscale behavior. Those still require visible playtesting.

Implementation follows Godot's [SkeletonModifier3D callback and coordinate-space contract](https://docs.godotengine.org/en/stable/classes/class_skeletonmodifier3d.html).
