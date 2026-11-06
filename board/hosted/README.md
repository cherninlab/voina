# SECHA Agent Board

The hosted board is a private workspace for coordination across Macs. It has
task claims, dependencies, scope, progress notes and a directed inbox. It uses
`H-` IDs. For repository work, claim the matching `T-` task on the
[Git board](../README.md) before editing and use its scoped `ship` command.

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
browser session rules. Use fresh local storage for test runs.
