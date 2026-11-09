# Remaining passage repairs

## Cave striping: corrected rock-colour bake

Same-camera controls isolate the horizontal bands to baked vertex colour: they persist without live shadows and disappear without baked colour. Buried partition caps polluted the continuous rock AO bake. Continuous rock now retains its .8 tone, scanned texture AO and live shadows; individual masonry still uses vertex AO. The source bake excludes continuous rock from that vertex bake.

[Before, actual game inspection](../h024_tunnels_v1/current-inspection/cave_bypass_2-back.png) · [After, same camera and lighting](rock-after-inspection/cave_bypass_2-back.png). All 18 root/cave inspection views are retained in `rock-after-inspection/`, with four diagnostic controls in `cave-controls/`.

Eight existing GLBs were updated in place at their COLOR_0 bytes. The audit proves every non-colour byte identical, including geometry, indices, normals, UVs and collision. Nine growth reports were rebound to the colour-only source hashes; growth geometry did not change. [Byte audit](rock-colour-audit.json).

Editor import, core smoke and the generator regression passed. The regression generates a rock fixture through the real bake and verifies its tone and exclusion from the AO output. The previous capsule traversal remains applicable to the byte-identical collision. Capture shutdown still reports a Texture RID leak.

Root-to-low-span turning interface, landing underside and masonry/threshold finishing remain in progress; this increment is not whole-builder acceptance.
