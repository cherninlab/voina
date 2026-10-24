# Dungeon masonry construction

The runtime implementation remains in the five masonry functions of
`gameplay/environment/red_descent_geometry.gd`. It uses the existing level
materials and batched primitives; no new mesh, texture or external asset is
required.

Room walls are split at the actual recess edges. The arched crowns, jambs,
sills and closed backs occupy the wall thickness. A room recess has 0.82 m
between the original wall face and its back. Shaft recesses retain the
existing solid core and route openings. Pilasters have one continuous shaft,
one base and one capital rather than repeated complete column sculptures.

Run the focused geometry check with Godot 4.7.2:

```sh
"$GODOT" --headless --path . --script content/environments/dungeon_masonry_v1/check.gd --quit-after 120
```

It checks wall placement, actual blind-recess depth, the closed back, absence
of pasted window/column GLBs, and an uninterrupted 20 m pilaster shaft. Full
runtime captures, construction/traversal checks and limitations are recorded
in `content/environments/red_descent/review/masonry_v1/`.
