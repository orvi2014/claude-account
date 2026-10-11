# claude-account

Run several Claude Code accounts side by side, and hand a task from one to another — or to Codex — **without replaying the whole conversation**.

One bash file. No daemon, no token copying. macOS and Linux.

```
claude-account add work                  # sign a second account in (browser)
claude-account use work                  # start Claude on it
claude-account handoff work --brief      # move the current task there, fresh, from a 2k-token brief
claude-account handoff codex             # ...or continue it in Codex
```

## Why

Claude Code holds one login at a time; `/logout` → `/login` replaces it. Plenty of tools fix that ([claude-swap](https://github.com/realiti4/claude-swap), [clauth](https://github.com/uwuclxdy/clauth) and others). This one is about the moment you actually switch: **moving the work, not just the login.**

Resuming a long session on another account replays its history. A session that has been compacted a couple of times is still hundreds of thousands of tokens, and the new account spends a large share of its budget just re-reading. `handoff --brief` instead writes a short, structured brief of the session and starts a fresh agent from it:

| | Resume (`--resume`) | Brief (`--brief`) |
|---|---|---|
| Context the new session loads | the whole history | ~1–3k tokens |
| Works across tools | Claude only | Claude or Codex |
| Original session | must be closed first | can keep running |
| Fidelity | exact | summarised — the agent re-checks the repo before acting |

A real example: a 17 MB, twice-compacted session (dozens of PRs, deploys, open blockers) condensed to a 6.8 KB brief that kept the goal, every merged PR, the user's strict rules (quoted), the exact step in flight and the open blockers — and dropped the test password that appeared in the transcript.

## How it works

- **Accounts** are `CLAUDE_CONFIG_DIR` profiles under `~/.claude-accounts/<name>`. Claude Code keeps a separate login per config dir (macOS Keychain, or the dir itself on Linux), so accounts never overwrite each other. Your default `~/.claude` account is untouched.
- **Shared, not copied:** `settings.json`, agents, skills, plugins, commands, hooks and `projects/` (memory and conversation history) are symlinked from `~/.claude`, so every account behaves the same and can see the same conversations. User-scope MCP servers are copied once at `add`. Only the login differs.
- **Live-session safety:** `sessions` and `handoff` read every account's session registry and check the process is alive. A plain handoff refuses to resume a conversation that is still open somewhere (two writers corrupt it); `--fork` continues a copy, `--brief` starts fresh.
- **The brief** is built from what the model actually had in context: the latest compaction summary, the recent messages Claude Code kept word-for-word when it compacted, and everything after — your messages, assistant replies, one-line tool calls, tool errors. Side chains and system reminders are dropped. That goes to `claude -p` (default `sonnet`) with a replaced system prompt and no tools, billed to the account you are handing *to*. The brief has fixed sections: Goal · Done (verified) · In flight · Decisions and constraints · Key pointers · Open questions · Next step. Briefs are saved with mode 600 in `~/.claude-accounts/.briefs`.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/orvi2014/claude-account/main/bin/claude-account -o ~/.local/bin/claude-account
chmod +x ~/.local/bin/claude-account
```

Needs `bash`, `python3` and Claude Code (`claude`) on your PATH; `codex` only for `handoff codex`.

## Commands

| Command | What it does |
|---|---|
| `add <name> [--email you@x.com] [--console]` | Create a profile and sign it in. |
| `use <name> [claude args]` | Start Claude on that account. `claude-account <name>` is a shortcut. |
| `main [claude args]` | Start Claude on your default account. |
| `list` | Profiles and the email each is signed in as. |
| `login <name>` | Sign in again (expired login). |
| `remove <name>` | Log out and delete a profile; shared files are kept. |
| `sessions [n]` | Recent conversations in this folder, and which account has them open. |
| `handoff <account\|main> [id] [--fork]` | Resume a conversation on another account (newest in this folder by default). |
| `handoff <account\|main\|codex> [id] --brief [--model m]` | Start fresh on another account or in Codex from a brief. |
| `brief [id] [--model m]` | Just print the brief. |

Run interactive commands in a normal terminal tab. Through Claude Code's `!` prefix there is no TTY and `claude` would start in print mode, so the script stops with a clear message instead.

## Caveats

- **Read the terms.** Holding more than one account for your own use is common; creating accounts to evade limits, or sharing and reselling them, is what Anthropic's policies target. This tool does not rotate accounts automatically and is not meant for that.
- A brief is a summary. The seeded agent is told to verify the repo state before trusting it and to ask before anything destructive, but check its first steps.
- Shared `projects/` means every account sees every conversation. If you need hard separation (for example a client's account), don't use this layout for it.
- Unofficial; Claude Code's on-disk session format can change between versions.

## Tests

```sh
bash tests/run.sh
```

Self-contained: a throwaway `HOME`, fake `claude`/`codex` binaries and synthetic session files. Nothing touches your real config or Keychain.

## License

MIT
