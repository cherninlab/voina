# Dungeon visual exploration — 21 October 2026

Status: all four proposals below were rejected by the user on 21 October 2026. They do not look like SECHA, are not scary, and do not align with the supplied horror references. Preserve them as rejected explorations, not candidates to implement. The revised reference-led target is in `folk_horror/`; it is still awaiting human review.

All four images were created using built-in Codex ImageGen from original text prompts, without input images or imported art. Exact prompts are preserved beside the images. They are concept references, not textures or meshes. `.gdignore` keeps this exploration out of Godot imports and exports.

| Image | Direction | Spatial idea |
| --- | --- | --- |
| `01-descending-ossuary.png` | Descending ossuary | Stairs, lower ring, upper return gallery and a central burial monument |
| `02-drowned-reliquary.png` | Drowned reliquary | Raised main causeway and a side route around a flooded basin |
| `03-ash-furnace.png` | Ash furnace crypt | Central bell/furnace landmark, curved floor route and side gallery |
| `04-root-sanctuary.png` | Root-broken sanctuary | Overhead root, tight asymmetric chamber, stairs and low underpass |

The images suggest readable routes and human-scale spaces, but generated geometry and dimensions still need interpretation and validation in Godot. A static concept does not establish combat feel, camera clearance, material availability, rendering feasibility or performance.

Camera bug T-129 remains separate: the third-person camera passes through walls instead of being pushed inward by solid geometry. No camera or map code changed during this image pass.
