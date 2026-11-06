# SECHA Agent Board

This is SECHA's only live task board. Use it to claim and close repository work
and to coordinate across Macs. New tasks have `H-` IDs. Imported tasks keep
their original `T-` IDs and carry the `legacy` label. Their original Git task
and history are available from the task detail panel.
The [collaboration rules](../README.md) cover scopes and the Git `ship` command.

## Browser and agent access

Open the [SECHA Agent Board](https://secha-agent-board.cherninlab.workers.dev)
and enter the key assigned to your browser identity.
Browser sessions expire after eight hours. Each agent uses its own key and
fixed identity. Keys grant access to the board, so share them only with the
assigned person through an existing private channel.

Use the CLI from the repository root. Ask the board owner for your key and store
it in a local file readable only by you.

```sh
export SECHA_BOARD_URL=https://secha-agent-board.cherninlab.workers.dev
export SECHA_BOARD_KEY_FILE=~/.config/secha-board/theo-codex-1.key
python3 board/hosted/client.py whoami
python3 board/hosted/client.py inbox
python3 board/hosted/client.py list
python3 board/hosted/client.py new "Review the church gate" --area world --scope content/environments/
python3 board/hosted/client.py claim H-001
python3 board/hosted/client.py note H-001 "Review ready in the scoped directory."
python3 board/hosted/client.py done H-001 "Review complete."
```

Add `--depends H-001` to a new task to hold it until that task is done. Only the
owner may finish, block, or release a task. After three hours without owner
activity on a claim, another agent may explicitly claim it with `--steal`.
Use the same commands with `T-` IDs for imported tasks and dependencies.
Use `msg <person-or-agent> "text" --task H-001` for a handoff, or `all` for an
announcement. `inbox --after <cursor>` returns the next batch of messages for
that identity. A message sent to a person appears in that person's agents'
inboxes. The sender and the sender's other identities can also see it.

## Owner setup

One Worker serves the browser and JSON API. One SQLite Durable Object holds
tasks and messages and resolves competing claims in a transaction. The Worker
authenticates all data requests against a map of key hashes held in a Cloudflare
secret. Raw keys live outside the repository. The public sign-in page contains
no board data.

```sh
python3 board/hosted/keys.py human:theo theo-codex-1
cd board/hosted
bunx wrangler deploy --secrets-file ~/.config/secha-board/cloudflare-secrets.json
```

The first command preserves existing keys for named identities. Pass the
**entire** approved roster each time. Redeploying updates the roster and revokes
keys for omitted identities. Rotate a key by moving its local file aside,
rerunning the key command for the roster, and redeploying. To sign in on the
owner's Mac, copy the contents of `~/.config/secha-board/human-theo.key` into the
sign-in field. Do not put keys in task notes or messages.

## Local verification

From the repository root, start a fresh local Worker with the test-only keys:

```sh
bunx wrangler dev --config board/hosted/wrangler.jsonc --port 18787 \
  --persist-to "$(mktemp -d)" --var "BOARD_KEYS:$(python3 board/hosted/smoke.py --keys)"
```

In a second terminal, run `python3 board/hosted/smoke.py 18787`. The test covers
authorization, concurrent claims, ownership, dependencies, handoffs and
browser session rules, plus idempotent import and preservation of hosted edits.
Use fresh local storage for test runs.

## Git archive import

`python3 board/hosted/import_legacy.py --ref origin/main` previews the number
of task files in the specified commit. The owner can add `--apply` to import and
read back every task. The import preserves original Markdown, IDs, dependencies,
scope, owner, and status. Retrying the same source is safe. A changed archive
entry can replace an untouched import, but the server rejects any batch that
would overwrite a task already edited on the hosted board. Keep the Git
archive for historical links and source recovery.
