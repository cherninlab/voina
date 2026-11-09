# Natural cave ground and junction finishing

Latest actual-game review: [gallery](review.html). Inspection frames add a neutral camera lamp; game frames use ordinary game lighting. Both run Godot 4.7.2 Mobile/Metal on this Mac. These are game captures, not generated concepts. Builder acceptance remains with Theo. Sharply cut/dark portal side reveals are still visible and need further finishing; this pass does not claim every material transition is resolved.

## Changes

- Root/cave surfaces now have broader asymmetric excavation pockets as well as fine relief. Displacement enlarges the cavity; the walking-floor edge and shared interfaces remain fixed. The old symmetric run deformation is disabled on these natural passages.
- Natural run and bay cavities use the same 48-segment arch and allowance. Internal ownership caps are removed from the render skin after its closed backing is generated. Redundant backing is hidden only where a complete rock skin exists; structural collision remains.
- World-space three-axis rock texture blending removes stretched face projections. Lower normal strength and restrained wet roughness reduce the polished appearance.
- A deterministic world paving field places real sculpted flags with jittered shared edges, per-stone UVs and continuous masks. Earth can bury/remove paving, with raised irregular banks at wall bases, darker mud and shallow water in depressions. Source masks are shared across run/node boundaries.
- Timber heads are fitted to the finished carved rock. Growth is regenerated against the new surfaces; unmounted systems are pruned rather than exporting loose caps.

The earlier straight bright floor boundaries were a separate Mobile omni-light-list problem, fixed and pushed in `31136d12`: [light-budget evidence](../light_budget_v1/README.md). Six practical lights are selected with continuous energy fade; distant light pools are deliberately darker. Removing baked colour, shadows or normals alone did not solve that issue.

## Evidence and limits

[Field audit](field-audit.json) samples 1,375 corridor positions: 22.5% pass the bare-earth threshold and 6.2% the puddle threshold. Bypass earth samples are 52%, root samples 8.2%. These are sample fractions, not measured surface-area percentages. Puddles are shallow visual water with a small direct-light highlight; no reflection or fluid system is implied. Walking collision stays on the route floor while the visible earth undulates by centimetres.

[Rejected iterations](rejected-initial/) retain the early ground candidate, exposed-root failure, profile-only attempt and backing/cap diagnostics. The profile-only attempt did not remove every dark strip. Native pixel rays then identified structural mortar in front of the finished rock; hiding the duplicate render backing removed those slits. Cap removal removes duplicate ownership faces; it did not by itself eliminate every faceted strip. No rejected image is labelled final. A normal-only control subsequently isolated the faceted bright/blue strip to Boolean construction normals; eight GLBs receive shared area-weighted normals. The [byte audit](normal-byte-audit.json) proves every non-normal byte unchanged, including geometry and collision. The source generator applies the same normal rule.

Existing material provenance is reused: [mineral earth](../../../village_generated/provenance.json), existing dungeon rock PBR maps and existing per-stone face maps. No new external asset was introduced.

See the linked validation logs and source manifest in this folder. Thirty-one protected room/shaft/bridge assets remain byte-identical. Broad H-023 bridge and H-026 shaft redesign are outside this increment. Shutdown ObjectDB/Texture RID leak warnings remain. Manual camera/input, two-Mac/Tailscale and performance acceptance are not claimed. The final scoped root audit covers 196 roots: zero exposed terminal vertices, zero walking-corridor vertices and zero vertices more than 1 cm into the surface. The empty cave_bypass_2 growth is removed rather than leaving stale geometry. This is not a whole-scene intersection verdict.


## Verified checks

- [Generator](generator-test.txt): real export/bake policies, matching natural run/bay profile, shared ground field and removal of render partitions while retaining closed backing.
- [Traversal](traversal.txt): 1,234 m real capsule walking, all route loops and both bridge lanes; applies to final normal-only repair because all non-normal bytes, including collision, are proven identical.
- [Structure](structure.txt), [turning chamber](turning.txt), [coverage](coverage.txt), [six seam rays](seams.txt), [editor import](import.txt), [smoke/local ENet](smoke.txt) and [22 unchanged crawler controls](explorer-controls.txt).
- [Mesh audit](mesh-audit.json): 25 passage/landing exports finite and require no Blender mesh repair. [Protected assets](protected-assets.json): 31 unchanged hashes.
- [Five roof observations](roof/probe.json) all meet render geometry; four previously missing sites and one control. No new full survey is claimed.
- [Source manifest](source-manifest.json) identifies the actual captured source and generated files.
