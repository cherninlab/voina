# Visible physics ageing, second pass (T-174)

Ageing levers:
- 1–4 boards rotted out per bridge.
- Rotten posts that already lean 3–7° and lean further in a tremor; rails and rope follow them.
- Failed rail ends that hang.
- Pulled nails curl board ends up 1.5–4 cm over the outer 35 cm.
- Uneven rope slack.
- Damped rails, so attempts settle in about 430 frames.

The lane check in Blender now samples exactly like `scripts/bridge_construction_test.gd`, against a copy of the collision ribbon. It caught an attempt where a loose board slid 59 cm and lay 5.5 cm proud on a lane; the earlier sampling had missed it. Missing-board footprints now cover the full gap, and the game test allows 3 cm around them.

Chosen attempts (`<route>.json` → `chosen_attempt`, `final`):
- **high_span** (attempt 2, aged): 4 missing boards, 4 loose, 2 leaning posts, 1 hanging rail, 8 curled ends.
- **low_span** (attempt 4, damaged): 4 missing + 2 knocked off, 15 loose, 2 leaning posts, 3 hanging rails, 33 curled ends.

Checks: bridge contract (2592 sweeps; decks within 0.013 m on 541 lane samples), 1276 m traversal, dungeon smoke, structure audit.

**Honest assessment:** the ageing is visible in close frames (`close/b4-low-bend.png` shows a missing board and sagging rope) but stays moderate at play distance. A rougher bridge is one `--pick` away (see `*_attempts.png`), as long as it stays walkable.
