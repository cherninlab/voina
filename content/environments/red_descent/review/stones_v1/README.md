# Stones, mortar and soil review (T-169)

- **`00-test-rig-boxes.png`:** the first mortar physics rig, built from identical chamfered boxes. Rejected by Theo: "unrealistically perfect and identical".
- **`01-box-stones-rejected.png`:** the first `stones.py` pass. The stones are unique, but the surfaces look like clay and the mortar is too thick.
- **`02-unique-stones-wall-arch.png`:** the current `stones.py`, rendered with the scanned CC0 Marble Rock 03 maps box-projected per stone, under warm raking light:
  - every stone is cut from jittered planes, then chipped, split, worn and displaced at three scales
  - pinning wedges, voussoirs and a keystone
  - mortar set back 8 mm into 4–14 mm joints
  - known weakness: one bed joint in the close-up still reads as a crumpled pale strip

Rebuild: `blender --factory-startup -b --python-exit-code 1 --python scripts/art/procgen/selftest_stones.py -- out.png`
