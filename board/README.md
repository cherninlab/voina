# Agent board

Many agents build this game at once: two machines (Theo and a colleague), several agent sessions per machine, some sharing one checkout. This folder says who is doing what. `origin/main` is the coordination point: every board change is pushed immediately and the first push wins.

All commands are `python3 scripts/board.py <command>`; mutating commands need `--agent NAME`.

## Loop

1. Pick a name once per session, `<person>-<tool>-<n>`: `theo-claude-2`, `alex-codex-1`. Reuse it for every command.
2. `list -v` syncs and prints tasks with their scopes.
3. `claim T-004 --agent NAME` **before** touching code. A refused claim means pick another task: it is owned, waits for an unfinished `depends` task, or is reserved for a human. Work that is not on the board: `new "title" --scope paths --agent NAME` (add `--depends T-003,T-007` if it must wait), then claim it.
4. Edit only files inside your task's `scope`. Need a file in another task's scope? `note` that task and wait for its owner, or ask the human.
5. Ship small working increments: run the AGENTS.md checks, then `ship --agent NAME -m "feat: ..." path/a.gd path/a.gd.uid`. It commits only those paths, merges `origin/main` safely and pushes.
6. `sync` before each new step. `note T-004 "progress" --agent NAME` at least every couple of hours. Only the owner's own commands keep a claim fresh; notes from others do not. A claim idle for 3 h shows STALE and only then may be taken with `claim --steal` (logged in the task). Fresh claims cannot be stolen.
7. Finish with `done T-004 "summary"`, or `release` / `block T-004 "reason"`. Only the owner can finish, release or block a task; a blocked task stays with its owner.

## Shared-checkout rules

Other agents' uncommitted work lives in the same working tree. Never run `git add -A`, `git add .`, `git commit -a`, `git stash`, `git reset --hard`, `git checkout -- .`, `git restore .`, `git clean`, `git rebase`, `git pull --rebase` or a force push there. Never edit, revert or commit files outside your task, even if they look finished.

New sessions should prefer a private worktree: `worktree --agent NAME` creates `../MultiPlayerProject-agents/NAME` on branch `agent/NAME`. The same commands work there (it rebases privately and pushes `HEAD` to `main`). Run the Godot import once inside a new worktree.

## Watching as a human

`python3 scripts/board_web.py`, then open http://localhost:8777: a read-only page, live from origin/main: each agent with a stable colour, its claimed task, latest log line and pushes this hour; then unclaimed tasks, a folded done list and the playtest pin. Click a row for its scope and recent log. Unclaimed tasks say when they are for humans or wait for another task. It refreshes every 10 s, keeps expanded rows open, and never commits.

## Staying synced

Run one watcher per checkout: `watch` fetches, fast-forwards or merges when that cannot touch uncommitted edits, and pushes committed work. It never commits. If it warns that local edits overlap remote changes, the agent editing those files must ship first.

Every successful push also sends a UDP "main moved" poke (port 47777) to localhost, the LAN broadcast address and configured peers, so watchers sync within about 2 s instead of waiting for the 60 s poll. The poke carries no state: `origin/main` remains the only source of truth, so a lost poke only means waiting for the next poll. Tailscale does not carry broadcasts, so add each other machine once per checkout: `git config --add board.peer <magicdns-name>`. Allow incoming connections for python3 if macOS asks.

## Task files

`board/tasks/T-NNN.md`: front matter (`status` is open, claimed, blocked or done; `scope` lists the paths the task may touch; `depends` lists task ids), then Goal, Done when and Log. Change status and owner only through the script; improve Goal and notes with a normal `ship`. Tasks owned by `human:<name>`, or titled `Human: ...`, are for people: agents cannot claim them, and a person claims with `--agent human:theo`.
