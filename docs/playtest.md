# Playtesting while agents keep pushing

Agents push to `main` every few minutes, so two people who "just pull and run" rarely have the same build, and agents' working copies hold half-finished edits. Mismatched builds encode positions differently, which looks like "we are not where we are". Playtests therefore use a **pinned commit** and a **separate playtest copy** on each machine.

## Play

On every machine, once: install Git LFS and Godot 4.7.2 Standard. If Godot is not in `/Applications`, run `git config playtest.godot /path/to/Godot.app/Contents/MacOS/Godot` (or export `GODOT`).

1. One person pins the build to test (the tip of `main` by default; any commit already on `main` works):
   ```sh
   python3 scripts/playtest.py pin --agent human-theo --note "bolts + netcode"
   ```
2. The host and every joiner run, from any checkout of the repo:
   ```sh
   python3 scripts/playtest.py host
   python3 scripts/playtest.py join theos-macbook-pro.taile99b36.ts.net
   ```
   Each command fetches, moves this machine's playtest copy (`<checkout>-playtest`, a detached worktree) to the pin, pulls LFS files, imports, and launches the game from there. Pass the address only, without `:7777`; use `--port` for another port.
3. `python3 scripts/playtest.py status` shows the pin and whether this machine's copy matches it.

## Build check

Debug builds (the editor binary) refuse to play against a different build. On connect, both games compare a fingerprint of every script, scene and resource under `core/`, `gameplay/` and `ui/`, plus `project.godot`, during Godot's authentication step, so a mismatched player never spawns. Uncommitted edits change the fingerprint too; the displayed commit gets `+dirty`.

A refused joiner sees the host's commit and the exact command, e.g. `python3 scripts/playtest.py sync --commit 80dedc6`, then joins again. The host's HUD reports the refusal. `BUILD: <commit> [<fingerprint>]` is printed at startup. For a deliberate experiment, launch with `-- --allow-version-mismatch`.

## Working in parallel

- Never edit the playtest copy; `sync` refuses to move it if it has local edits. Agents keep using their own checkouts or `board.py worktree` copies.
- The playtest copy has its own `.godot` import cache, so agents' imports and test runs never disturb a running game, and syncing never touches agents' files.
- Games default to UDP 7777. Automated tests always pick free random ports, so they can run while people play.
- Pin a new commit between features, not in the middle of a session. Joining players who already run the game must restart through `playtest.py` after a re-pin.

## Verify

`scripts/smoke_test.py` runs a two-process pair with a deliberately different fingerprint (`--fake-build`). The joiner must be refused during authentication with the host's commit, and the host must never spawn it. All other pairs pass the same check with matching builds.
