# SECHA Agent Board

The [hosted SECHA Agent Board](https://secha-agent-board.cherninlab.workers.dev)
is the only live task board. Use it for claims, scope, progress, dependencies,
handoffs, and closing work. See the [browser and CLI guide](hosted/README.md)
for access and commands.

Tasks imported from the old Git board keep their `T-` IDs and carry the
`legacy` label. They can still be worked on in the hosted board. New tasks
receive `H-` IDs. The Markdown files in [tasks/](tasks/) are a read-only
archive for old links and source history. The old Git task commands and local
board dashboard are retired.

## Working together

1. Sign in with your assigned identity, check the inbox, and list tasks.
2. Claim before editing. Choose a task you can own and stay within its scope.
   If another task owns a path you need, coordinate on the hosted board first.
3. Run `python3 scripts/board.py sync` before each step. After the project checks
   pass, ship exact paths with
   `python3 scripts/board.py ship --agent NAME -m "message" path/a.gd path/a.gd.uid`.
4. Note progress on the task and close it with `done`, `release`, or `block`.
   Only the owner can perform those actions. A claim idle for three hours can
   be taken over explicitly.

## Git and playtests

Several agents can share one checkout. Never run `git add -A`, `git add .`,
`git commit -a`, `git stash`, `git reset --hard`, `git checkout -- .`,
`git restore .`, `git clean`, `git rebase`, `git pull --rebase`, or force push
there. New sessions can use `python3 scripts/board.py worktree --agent NAME`
to create a private worktree.

Run at most one `python3 scripts/board.py watch` per checkout. It fetches and
integrates changes that can land safely, and pushes committed work. It never
commits. Pokes on UDP port 47777 prompt watchers to sync. Use
`git config --add board.peer <magicdns-name>` on each machine for Tailscale peers.

The [playtest pin](../docs/playtest.md) remains in `board/playtest.json` and is
managed by `scripts/playtest.py`.
