# Masonry construction review — 2026-10-24

`before/` and `after/` contain fresh actual Godot 4.7.2 Mobile/Metal frames
at identical camera poses. These are runtime images, not ImageGen paintovers.
The before fingerprint is `3c83cc837bad`; the after fingerprint is
`218e4a846908`. Exact build labels and capture output are in the adjacent logs.

Compare `02-central-wall.png` for removal of complete rectangular window
panels, `08-nave-materials.png` for deep arched wall recesses and continuous
pilasters, and `06-descent-overlook.png` for the reveal's visible wall depth.

The change replaces complete window-bay, gothic/slit-window and wall-panel
GLBs laid over the facade with arched cavities constructed in the wall
facing. Room backs sit 0.82 m behind the original face. Shaft cavities retain
the existing solid core. Jambs, sills, curved soffits and narrow stone bands
join the surrounding wall. Each pilaster has one continuous shaft seated
between one base and one capital.

Only `build_room`, `build_vault`, `arch`, `arch_spandrel` and `stacked_pier`
changed in `red_descent_geometry.gd`. Route coordinates, slopes, collision
ribbons, bridge helpers, `build_path`, `beam`, `flush`, shaders and
`crypt_dungeon.gd` were preserved.

## Verification

- Editor import completed without script or shader errors.
- Focused geometry probe passed: original wall face, 0.82 m cavity, closed
  back, absence of pasted window/column meshes, continuous 20 m shaft.
- Construction audit passed: 23 fitted bearings, 648 framing/board members,
  four baked cloth pins, lower routes clear.
- Actual capsule traversal passed 1,276 m: descent, slopes, return, egress,
  four optional loops, both bridge lanes at +/-0.75 m and deep-floor recovery.
- Full smoke suite passed deterministic combat and real local ENet checks.
- Eight before and eight after captures passed the nonblank-frame checks.
  Capture metrics are retained as diagnostics, not a gameplay benchmark.

All windowed commands used `scripts/godot_bg.sh`. The construction audit
still reports one ObjectDB cleanup warning; captures report seven Texture
RIDs and one ObjectDB warning. The focused standalone probe reports two
ObjectDB cleanup warnings. These are retained in the logs, not hidden or
counted as shader errors.

## Remaining visual work

Small repeating brick texture, broad uniform plaster fields and the smooth
shaft silhouettes remain below the references. They need the separate
material response pass and later localized wear/stone relief, not pasted
window panels. Apertures deliberately use a limited coherent arch profile.
The existing bridge appearance remains the user's separate workstream.
No manual camera/input or two-machine Tailscale acceptance is claimed.

## Reproduce

```sh
"$GODOT" --headless --editor --path . --quit
"$GODOT" --headless --path . --script content/environments/dungeon_masonry_v1/check.gd --quit-after 120
"$GODOT" --headless --path . --script scripts/dungeon_structure_test.gd -- --report=/tmp/masonry-construction.json
python3 scripts/dungeon_traversal_test.py "$GODOT"
python3 scripts/smoke_test.py "$GODOT"
GODOT="$GODOT" scripts/godot_bg.sh --path . --script scripts/capture_dungeon.gd -- --dungeon --shading-ephemeral --capture-dir=/tmp/masonry-review
```
