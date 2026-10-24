# Physics-aged bridges, first pass (T-169)

Each bridge ran 8 attempts in parallel with `scripts/art/bake_bridges.py`, ranging from calm to violent, some with a stone ball. Each attempt was classified (see `<route>.json` → `attempts`).

- **high_span:** 2 untouched, 1 aged, 2 damaged, 2 collapsed, 1 unwalkable. The aged attempt 4 was chosen: 14 loose boards, 1 hanging rail.
- **low_span:** 2 untouched, 1 aged, 1 damaged, 1 collapsed, 3 unwalkable. The aged attempt 2 was chosen: 4–5 loose boards, 1 missing.

The bridge contract holds: no sideways falls, and the deck is within 1.4 cm of the walking surface with the missing board skipped.

**Honest assessment:** in game frames (`close/`, `wide/`) the ageing is barely visible. Boards shifted 1–3 cm don't read at play distance. The next pass targets visible ageing within lane safety: lifted board ends, missing boards, leaning posts, broken rails, uneven rope slack.

Two more problems:
- The contact sheets use a broken preview colour and frame the damage poorly.
- Swinging rails keep attempts from settling, so each attempt takes 10–18 minutes.
