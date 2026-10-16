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

`host` pins the exact commit it is about to host when that differs from the board, so the pin always names the build a running host plays. `join` follows the host: when it is refused for another build, it reads the host's commit from the refusal, syncs to it and rejoins (up to twice). Only a host running uncommitted edits (`+dirty`) cannot be followed. Never pass `--commit` unless you mean to override the host.

## Build check

Debug builds (the editor binary) refuse to play against a different build. On connect, both games compare a fingerprint of every script, scene and resource under `core/`, `gameplay/` and `ui/`, plus `project.godot`, during Godot's authentication step, so a mismatched player never spawns. Uncommitted edits change the fingerprint too; the displayed commit gets `+dirty`.

A refused joiner sees the host's commit and the exact command, e.g. `python3 scripts/playtest.py sync --commit 80dedc6`, then joins again. The host's HUD reports the refusal. `BUILD: <commit> [<fingerprint>]` is printed at startup. For a deliberate experiment, launch with `-- --allow-version-mismatch`.

## Monitor

Press **`** (the key left of 1; rebind it as "Net overlay" under Controls) for the net overlay:

- the role and build;
- per ENet peer, the round trip, jitter and packet loss;
- per remote player, movement snapshots per second (about 60 when healthy), display drift (how far the drawn body was from its latest snapshot; it fades out), and host corrections (times the host pulled that player back for impossible movement).

A small build label stays in the bottom-left corner. While connected, the same numbers go to the game's output every 5 s as `NET ...` lines. Keep the terminal output, or launch through `playtest.py` from a terminal, to diagnose a session afterwards. Rising drift and corrections at a steady round trip point to netcode; a rising round trip, jitter or loss points to the connection.

Movement replicates at 60 Hz. Remote bodies show their latest snapshot projected by the time since it arrived, and knockback is applied as velocity instead of a teleport. What remains behind the other player is network transit: about half the round trip when the other player is the host, a full round trip when another client's movement is relayed through the host.

## Working in parallel

- Never edit the playtest copy; `sync` refuses to move it if it has local edits. Agents keep using their own checkouts or `board.py worktree` copies.
- The playtest copy has its own `.godot` import cache, so agents' imports and test runs never disturb a running game, and syncing never touches agents' files.
- Games default to UDP 7777. Automated tests always pick free random ports, so they can run while people play.
- Pin a new commit between features, not in the middle of a session. Joining players who already run the game must restart through `playtest.py` after a re-pin.

## Verify

`scripts/smoke_test.py` runs a two-process pair with a deliberately different fingerprint (`--fake-build`). The joiner must be refused during authentication with the host's commit, and the host must never spawn it. All other pairs pass the same check with matching builds.
