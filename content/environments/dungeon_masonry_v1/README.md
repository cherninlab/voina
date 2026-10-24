# Dungeon masonry construction

The runtime implementation remains in the five masonry functions of
`gameplay/environment/red_descent_geometry.gd`. It uses the existing level
materials and surface batches. The small original `pier.obj` adds a continuous
chamfered/tapered shaft with a shallow front rebate; no new texture or
external asset is required. The shaft remains one batch instance, with a
single base and capital. Projecting beveled voussoirs join the existing stone
surface batches, with no separate node or draw call for each stone.

Room walls are split at the actual recess edges. The arched crowns, jambs,
sills and closed backs occupy the wall thickness. A room recess has 0.82 m
between the original wall face and its back. Shaft recesses retain the
existing solid core and route openings. Pilasters have one continuous shaft,
one base and one capital rather than repeated complete column sculptures.

Rebuild `pier.obj` with `python3 scripts/art/build_dungeon_masonry.py`. The
generator uses Python's standard library, preserves normalized metre-unit
fitting bounds and checks that every mesh edge has two incident faces. This
is original procedural geometry; no third-party provenance is involved.

Run the focused geometry check with Godot 4.7.2:

```sh
"$GODOT" --headless --path . --script content/environments/dungeon_masonry_v1/check.gd --quit-after 120
```

It checks wall placement, actual blind-recess depth, the closed back, absence
of pasted window/column GLBs, an uninterrupted 20 m pilaster shaft and its
actual taper/rebate. Full
runtime captures, construction/traversal checks and limitations are recorded
in `content/environments/red_descent/review/masonry_v1/`.
