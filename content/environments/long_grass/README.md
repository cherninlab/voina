# Long Grass horizon pines

`horizon_pines.png` is a 1536 × 768 atlas of three pine sprites (512 × 768 cells, trunk foot centred on each cell's bottom edge). Long Grass draws each horizon tree as three crossed quads showing one of the three cells (`gameplay/environment/horizon_pines.gdshader`).

## Provenance

Source: a 2000 × 667 transparent sprite sheet of three pines supplied by the project owner (mike) in a Claude Code session on 2026-10-22, for use as these horizon trees. Its origin and licence were not stated: **confirm both before any public or commercial release**, and replace the atlas if they do not allow redistribution.

Processing (no painting or generation): the three trees were found by their alpha columns, cropped, the remaining white blend un-mixed from the soft edges, scaled to fit 504 px wide or 764 px tall with Lanczos, and placed foot-down in their cells.
