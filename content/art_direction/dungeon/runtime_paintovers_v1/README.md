# Red Descent runtime paintovers, v1

Six native ImageGen edits over the actual engine captures shipped with fd9efd2. These are proposed end-state art targets, not screenshots of implemented graphics. The original runtime camera, room/route arrangement and actor staging are the preservation targets.

Source views: `content/environments/red_descent/review/final/01-high-crossing.png` through `06-descent-overlook.png`. Approved look references: `content/art_direction/dungeon/maps_v2/05-cutaway.png` and the user-supplied low bridge hall reference `codex-clipboard-9faf8953-c6ee-40a5-80ee-d1b763dbdfda.png`.

Each final image has a sibling exact `.prompt.txt`; `generation.json` records native outputs, source roles and SHA-256 hashes. No game code was changed by this art pass.

Review: the six views were inspected against their source captures. Primary compositions remain recognizable. Generated detail is not a measured geometry plan: distant galleries/rails, local niche shapes, a small central block in the choir and the far-left revealed crossings include drift. Use these as material, construction and lighting targets while retaining the authored game layout. All six are 1586 × 992. Art-only import and main smoke checks passed; existing standalone smoke processes still report shutdown instance-leak warnings.
