# T-173 room floor integration

All 11 Red Descent rooms now use the shipped `FlagstoneFloor.cover()` helper, seed 165.
The old flat room polygon remains collision-only. Horizontal route-top visuals are clipped
against room outlines at the same elevation; sloped tops, original collision triangles,
route sides/undersides, open guards and bridge assets retain their previous behavior.

The native polygon-difference operation is `Geometry2D.clip_polygons()`:
https://docs.godotengine.org/en/stable/classes/class_geometry2d.html#class-geometry2d-method-clip-polygons

## Placement contract

Each floor is `Architecture/Floor_<room id>`, an identity-transform `Node3D` in group
`flagstone_room_floors`. Metadata: `room_id`, `floor_y`, `family`, `module_count`.
The existing helper consumes world x/z coordinates, so these parents stay untransformed.
All room polygons are convex (4 or 8 edges), fitting the shader's 12 clip-plane limit,
including the two extra kerb mitre planes.

| Room | Family | Modules |
| --- | --- | ---: |
| entry | laid | 35 |
| antechamber | coursed | 26 |
| restraint | coursed | 52 |
| cells | coursed | 24 |
| chapel | coursed | 68 |
| nave | coursed | 74 |
| ossuary | laid | 52 |
| bones | laid | 30 |
| window | laid | 19 |
| bell | coursed | 58 |
| choir | coursed | 58 |
| total | | 496 |

There are 2,976 mesh nodes, 992 at each LOD. Individual module bounds/culling and the
helper's 0–14, 14–32, 32–90 m visibility ranges remain intact. Floors receive lighting and
shadows, but do not cast shadows: joint AO is baked and the floor relief is at most 2.1 cm.
The 0.5 m kerb is visual geometry at the existing walking plane, with no new collision.

## Evidence

- `before/`: actual match-world views at untouched base `59d25b3`, build fingerprint
  `d59db394d862`.
- `with-floor-shadows/`: same six views with integrated floors and the helper's original
  shadow-casting setting, fingerprint `3a8e1a4f6efc`.
- `after/`: final floor integration, shadow casting disabled, fingerprint `7101ecb18d41`.
- `audit.json`: 11 floors / 496 modules, all LOD ranges verified, zero horizontal legacy
  floor overlap, zero floor shadow casters.
- `baseline.json`: original full architecture collision digest. Baseline and final are
  byte-identical: 221,748 vertices, SHA-256
  `4f909a6e2ffe26bc4e130f387ce74f79a033348b941b96380bacd75072df3fc6`.
  This snapshot applies to the base above; later authorized architecture/bridge changes
  require a fresh baseline comparison.
- `verification.json` and `checks/`: exact commands, results and logs for import, floor audit,
  bridge, structure, traversal, dungeon smoke and main smoke.
- `geometry-diff.txt`: preserved implementation diff before any board integration.

Removing the old room surface and clipping the retained route tops reduces same-height
legacy overlap from 3,366.44913483 m² (3,302.5 m² of room floors plus 63.94913483 m² of route
thresholds) to zero. No physics faces were replaced by the visual floor meshes.

Fresh entry, antechamber, nave and cells views were inspected: thresholds meet the room kerbs
without legacy floor patches or visual holes. Nave and chapel far-floor views remain filled
across the room and preserve the existing distance LODs. These are scripted rendering
checks, not a manual camera/input or two-machine playtest.

## Shadow cost comparison

Identical cameras, 1440×900, native Mobile/Metal, existing lighting/reflections. Counts include
the whole rendered scene and its passes. All capture medians stay near the configured 60 Hz
cap (16.5–16.8 ms); they do not establish uncapped frame time or thermal performance.

| View | Floor shadows on: draws / primitives | Final: draws / primitives | Primitive reduction |
| --- | ---: | ---: | ---: |
| entry threshold | 1,495 / 5,363,379 | 1,468 / 2,505,231 | 53.3% |
| antechamber threshold | 1,306 / 5,745,965 | 1,282 / 2,788,920 | 51.5% |
| nave threshold | 238 / 2,310,408 | 204 / 646,062 | 72.0% |
| cells threshold | 604 / 2,954,878 | 604 / 1,162,198 | 60.7% |
| nave far floor | 194 / 2,345,634 | 188 / 687,140 | 70.7% |
| chapel far floor | 1,006 / 2,472,382 | 955 / 1,105,551 | 55.3% |

The new floor geometry still costs more than the original flat planes; exact before/final
counts are retained in the adjacent `metrics.json` files. Combined dressing should be
measured in T-162's final scene.

## Reproduce

From the checkout root, with `GODOT` pointing to Godot 4.7.2:

```sh
"$GODOT" --headless --editor --path . --quit
"$GODOT" --headless --path . --script res://content/environments/red_descent/review/floor_integration_v1/audit_floors.gd
scripts/godot_bg.sh --path . --script res://content/environments/red_descent/review/floor_integration_v1/capture_thresholds.gd -- --host --dungeon --port=27832 --output=after
"$GODOT" --headless --path . --script res://scripts/bridge_construction_test.gd
"$GODOT" --headless --path . --script res://scripts/dungeon_structure_test.gd
python3 scripts/dungeon_traversal_test.py "$GODOT"
python3 scripts/dungeon_smoke_test.py "$GODOT"
python3 scripts/smoke_test.py "$GODOT"
```

The baseline and final direct-dungeon checks share an existing ObjectDB cleanup warning;
the before/after match-world captures share the same texture-RID shutdown warning. Neither
produces script/runtime errors, and neither warning is introduced by the floor integration.
