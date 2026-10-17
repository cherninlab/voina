# Woodland village arena

T-032 replaces the flat car-and-block test yard with an original procedural 56 m woodland village. Uneven terrain with blended earth/stone/grass paths, eight colored timber cottages, layered thatch roofs, four market stalls, a well, a ramp-connected lookout, wooden cover, grass borders, distant hills, and a blue clouded sky are built by `gameplay/environment/village_arena.gd`.

The center spawn axis remains clear, and the original four inner cover footprints are retained for combat spacing. House shells, cover, barrels, perimeter, lookout landing and ramp have static collision. Terrain uses a concave triangle collider with upward-facing triangles; regression checks catch inverted floor winding. Hills and foliage beyond the fence are cosmetic. Existing spawning, combat authority, match timing, networking and character controls are unchanged.

## Assets and provenance

Geometry is authored here using Godot primitives; it does not contain meshes extracted from the supplied commercial Village House Kit. Three original ImageGen base-color candidates are stored in `content/environments/village_generated/` with provenance. Existing trees retain their repository provenance. The commercial armor and audio packs are not included. Generated textures remain prototype art: repetition and fine material work need a later art pass.

## Runtime screenshots and geometry check

Run the actual Metal-rendered world and host a local session on an unused port:

```sh
"$GODOT" --path . --script scripts/capture_village.gd -- --host --port=7793 --capture-dir=/absolute/output/folder
```

This checks collision under the spawn floor, ramp midpoint and lookout landing, drops the actual player at four terrain locations and requires it to land, then saves three 1600 × 1000 frames from the running game with its HUD and build identity. It never substitutes a concept render for a game screenshot. The last two views inspect the court and lookout. The free capture camera is only in this explicit script; normal gameplay still uses the player camera.

## Verification and limits

Run the editor import and `python3 scripts/smoke_test.py "$GODOT"`. Runtime collision probes and loopback checks do not establish human camera/input feel, four-player acceptance, Tailscale behavior, or performance/thermal guarantees. Buildings are closed decorative shells; interiors, commercial armor, foley integration and the proposed GUI redesign are not implemented by this change.

## Valhalla integration increment (2026-10-17)

Selected user-authorized KitBash Valhalla cottages, well, wagon, barrels, shield, training dummy and rocks replace several procedural placeholders. Source geometry is exported through `scripts/export_valhalla.py`, with shared PBR textures capped at 2048 pixels; provenance is recorded in `content/environments/valhalla/provenance.json`. Full source Blender files are not included.

Buildings form asymmetric clusters and angled palisades bound connected clearings. The collision terrain remains continuous within its existing 56 m extent. This is an integration increment: primitive stalls, lookout, horizon scenery and lighting still need visual refinement. Mik's fisheye shader is unchanged.

Validation: real rendered capture checks the spawn floor, ramp and lookout, plus actual player landings at four terrain locations. Screenshots are captured outside the repository. Headless import and smoke checks cover parsing and combat/network regressions; two-Mac and visual acceptance remain separate.
