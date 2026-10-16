# Agent board

Many agents build this game at once: two machines (Theo and a colleague), several agent sessions per machine, some sharing one checkout. This folder says who is doing what. `origin/main` is the coordination point: every board change is pushed immediately and the first push wins.

All commands are `python3 scripts/board.py <command>`; mutating commands need `--agent NAME`.

## Loop

1. Pick a name once per session, `<person>-<tool>-<n>`: `theo-claude-2`, `alex-codex-1`. Reuse it for every command.
2. `list -v` syncs and prints tasks with their scopes.
3. `claim T-004 --agent NAME` **before** touching code. "Already claimed" means pick another. Work that is not on the board: `new "title" --scope paths --agent NAME`, then claim it.
4. Edit only files inside your task's `scope`. Need a file in another task's scope? `note` that task and wait for its owner, or ask the human.
5. Ship small working increments: run the AGENTS.md checks, then `ship --agent NAME -m "feat: ..." path/a.gd path/a.gd.uid`. It commits only those paths, merges `origin/main` safely and pushes.
6. `sync` before each new step. `note T-004 "progress" --agent NAME` at least every couple of hours: claims idle for 3 h show STALE and may be taken with `claim --steal` (logged in the task).
7. Finish with `done T-004 "summary"`, or `release` / `block T-004 "reason"`.

## Shared-checkout rules

Other agents' uncommitted work lives in the same working tree. Never run `git add -A`, `git add .`, `git commit -a`, `git stash`, `git reset --hard`, `git checkout -- .`, `git restore .`, `git clean`, `git rebase`, `git pull --rebase` or a force push there. Never edit, revert or commit files outside your task, even if they look finished.

New sessions should prefer a private worktree: `worktree --agent NAME` creates `../MultiPlayerProject-agents/NAME` on branch `agent/NAME`. The same commands work there (it rebases privately and pushes `HEAD` to `main`). Run the Godot import once inside a new worktree.

## Staying synced

Run one watcher per checkout: `watch` fetches every 60 s, fast-forwards or merges when that cannot touch uncommitted edits, and pushes committed work. It never commits. If it warns that local edits overlap remote changes, the agent editing those files must ship first.

## Task files

`board/tasks/T-NNN.md`: front matter (`status` is open, claimed, blocked or done; `scope` lists the paths the task may touch; `depends` lists task ids), then Goal, Done when and Log. Change status and owner only through the script; improve Goal and notes with a normal `ship`. Tasks owned by `human:<name>` are for people, not agents.
