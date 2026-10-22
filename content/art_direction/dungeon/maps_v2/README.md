# Red Descent — winding vertical dungeon

This revision replaces the rejected flat, perpendicular arrangement in `../maps/`. The user requested branching rooms, tall/deep halls and overlapping bridges, then clarified that bridges and floors can slope, paths can hug a central wall, and the hall itself should have a complex outline.

`00-connected-map.png` is a route atlas. Its three colors group parts of a continuous descent, not three flat floors. `01-spatial-map.png` projects the same 3D route nodes; `02-upper-plan`, `03-middle-plan` and `04-lower-plan` provide separate detailed views. Every diagram has an editable SVG. `05-cutaway.png` is a built-in ImageGen interpretation using the diagrams and the user's two selected dungeon scenes as actual references. Its exact prompt is included. Keep the coordinate diagrams authoritative for relationships; generated architecture remains a visual target.

- A descends from 0 to −4 m through skewed timber spans and supported turning landings.
- B descends from −10 to −18 m, changing from short crossings into a ledge beside the irregular central wall.
- C descends from −23 to −28 m beneath earlier routes at different crossing points.
- The main hall has an irregular outline and continues into darkness to −48 m. Its roof is at +14 m. Side halls range from 14 to 22 m high; narrow passages provide contrast.
- The route passes the restraint hall, chapel, broken nave and low tunnel before reaching the deep choir. Side-room loops and a proposed return stair reconnect it. The return latch is a design proposal, not an implemented interaction.

`layout.json` contains design metre coordinates, route heights and room anchors. Turns represent masonry shoulders or braced timber platforms, not unsupported corners. Short pitches or steps between room thresholds must be resolved in the runtime build. The file records three projected bridge crossings with more than 8 m of separation; this is a static design check, not movement or camera validation.

PNG integrity and SVG XML were checked. `generation.json` records provenance and output hashes; `SHA256SUMS` records PNG checksums. All files remain under the art-direction `.gdignore`; they are excluded from runtime imports. The following implementation task will build and render the first playable version, derive further image studies from actual renders, improve textures and lighting, and test character traversal.
