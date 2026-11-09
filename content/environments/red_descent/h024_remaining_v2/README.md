# Latest game review

[Current gallery and validation](cavity-final/review.html) · [Current repair report](cavity-final/README.md). This supersedes the intermediate cave/turn frames below. Fine seams and material transitions remain under review.

# Remaining passage repairs

## Cave striping: corrected rock-colour bake

Same-camera controls isolate the horizontal bands to baked vertex colour: they persist without live shadows and disappear without baked colour. Buried partition caps polluted the continuous rock AO bake. Continuous rock now retains its .8 tone, scanned texture AO and live shadows; individual masonry still uses vertex AO. The source bake excludes continuous rock from that vertex bake.

[Before, actual game inspection](../h024_tunnels_v1/current-inspection/cave_bypass_2-back.png) · [After, same camera and lighting](rock-after-inspection/cave_bypass_2-back.png). All 18 root/cave inspection views are retained in `rock-after-inspection/`, with four diagnostic controls in `cave-controls/`.

Eight existing GLBs were updated in place at their COLOR_0 bytes. The audit proves every non-colour byte identical, including geometry, indices, normals, UVs and collision. Nine growth reports were rebound to the colour-only source hashes; growth geometry did not change. [Byte audit](rock-colour-audit.json).

Editor import, core smoke and the generator regression passed. The regression generates a rock fixture through the real bake and verifies its tone and exclusion from the AO output. The previous capsule traversal remains applicable to the byte-identical collision. Capture shutdown still reports a Texture RID leak.

The first colour-only increment left the root-to-low-span turning interface, landing underside and masonry/threshold finishing open. The following increment addresses the turning interface and cave surface geometry; the builder remains under review.

The initial published generator test failed because a fresh-break brightness multiplier still applied to rock (.864 instead of .8). The follow-up excludes continuous rock from that multiplier as well. The corrected real-bake regression passes; the [initial failure](rock-selftest-initial-failure.txt) is retained. Generated game assets already had the intended .8 tone.


## Excavated walls and the root turning exit

The root and cave runs, and their served junctions, now have actual excavation relief in the render surface and matching backing core: deterministic world-space rock variation, sampled at <=.55 m, bounded to .33 m displacement, fading to the fixed walking-floor edge. This changes the surface geometry, not only its normal map. The current roughness/texture still needs art review; some joins remain conspicuous.

[All 18 inspection views, sheet 1](turn-carve-sheet-1.jpg) · [sheet 2](turn-carve-sheet-2.jpg). Original-resolution captures are in `turn-carve-inspection/`; the matching 18 normal-lighting game views are in `turn-carve-game/`. Inspection views add a neutral camera light. The blue unshaded, rock-only control in `carved-rock-control/` distinguishes genuine holes from roots or dark material: it shows continuous rock above the floor in the examined view.

The root exit now has a turning chamber behind the existing low-span bridge entry, a closed wall in the old void-facing direction, a bridge-facing masonry arch through the full wall depth, a single paving field and collision at the true walking floor. Route coordinates and bridge deck are unchanged. The displaced route torch is fitted within the chamber away from the route centreline. The earlier bare-reveal/old-torch attempt is retained in `iterations-turn-bare-reveal/`. Bright edges near the fixture, abrupt material transitions and broader shaft/bridge presentation remain visible review items.

Validation, inspected before shipment:

- [Real Jolt queries](turning-physics.txt): former void ray meets the chamber wall; bridge doorway open; floor Y=-23. [Executable fixture](turning_probe.gd).
- [Capsule traversal](turn-carve-traversal.txt): 1,234 m, all routes and both bridge lanes.
- [Construction audit](turn-carve-structure.txt), [editor import](turn-carve-import.txt), [smoke](turn-carve-smoke.txt), [actual generator regression](turn-carve-selftest.txt), and [torch/paving regression](turn-light-test.txt) pass.
- [Mesh export audit](turn-carve-audit.json): all 25 passage/landing exports have finite coordinates and require no Blender mesh repair.
- [Roof evidence](turn-carve-roof/probe.json): the four former missing-roof rays and control all meet render geometry; actual game frames retained alongside the JSON. These are ray observations, not a new complete roof survey.
- [31 protected assets](turn-carve-protected-assets.json) remain byte-identical.

Shutdown ObjectDB/Texture RID leak warnings remain in the logs. No manual input, two-Mac or performance acceptance is claimed. Landing underside facing and remaining material/threshold finishing are still open. This is a verified incremental repair, not whole-builder visual acceptance.


The nave support underside now has actual wedge-stone masonry. [Before/after and unchanged collision proof](landing-intrados/README.md).
