# claude-account

[![test](https://github.com/orvi2014/claude-account/actions/workflows/test.yml/badge.svg)](https://github.com/orvi2014/claude-account/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Multiple Claude Code accounts on one machine, with session handoff between them.

`claude-account` keeps each Claude Code account signed in at the same time and lets you move a task from one account to another — by resuming the conversation, or by starting a fresh session from a compact handoff brief. The same brief can seed an OpenAI Codex session.

It is a single Bash script with no daemon and no background process. It never copies or rewrites credentials.

---

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Command reference](#command-reference)
- [Handoff modes](#handoff-modes)
- [The handoff brief](#the-handoff-brief)
- [How it works](#how-it-works)
- [Security and privacy](#security-and-privacy)
- [Limitations](#limitations)
- [Development](#development)
- [License](#license)

---

## Features

- **Concurrent accounts.** Every account stays signed in. Run two accounts in two terminals at once.
- **Shared environment.** Settings, agents, skills, plugins, hooks, memory and conversation history are shared across accounts; only the login differs.
- **Session handoff.** Continue a conversation on another account with `--resume`, or fork a copy of it.
- **Brief handoff.** Start a fresh session from a structured summary of the old one, instead of replaying its full history.
- **Codex handoff.** Seed an OpenAI Codex session with the same brief.
- **Live-session protection.** Refuses to resume a conversation that is still open in another window.
- **Secret redaction.** Passwords, API keys, tokens and private keys are removed before a transcript is summarised.

## Requirements

- macOS or Linux
- Bash 3.2+ (the macOS default works) and Python 3
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`claude`) on your `PATH`
- [Codex CLI](https://github.com/openai/codex) (`codex`), only for `handoff codex`

## Installation

```sh
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/orvi2014/claude-account/main/bin/claude-account \
  -o ~/.local/bin/claude-account
chmod +x ~/.local/bin/claude-account
```

Make sure `~/.local/bin` is on your `PATH`.

## Quick start

```sh
# Add a second account; a browser window opens to sign in.
claude-account add work

# Confirm both accounts.
claude-account list
#   main   you@personal.com   (~/.claude)
#   work   you@company.com

# Start Claude Code on the second account.
claude-account use work

# Move your most recent conversation in this folder to the other account,
# starting fresh from a brief.
claude-account handoff work --brief
```

Your existing `~/.claude` setup is the `main` account and is never modified.

## Command reference

| Command | Description |
|---|---|
| `add <name> [--email <addr>] [--console]` | Create an account profile and sign in. `--console` uses Anthropic Console (API billing). |
| `use <name> [claude args…]` | Start Claude Code on an account. `claude-account <name>` is equivalent. |
| `main [claude args…]` | Start Claude Code on the default account. |
| `list` | List accounts and the email each is signed in as. |
| `login <name>` | Sign an account in again, for example after the login expires. |
| `remove <name>` | Sign out and delete a profile. Shared files are not affected. |
| `sessions [n]` | List recent conversations in the current folder and where each is open. |
| `handoff <target> [session-id] [--fork]` | Resume a conversation on another account. |
| `handoff <target> [session-id] --brief [--model <m>]` | Start a fresh session on another account from a brief. |
| `handoff codex [session-id] [--model <m>]` | Start a Codex session from a brief. |
| `brief [session-id] [--model <m>]` | Print a handoff brief without switching. |

`<target>` is an account name or `main`. When no session ID is given, the most recent conversation in the current folder is used. Session IDs are listed by `sessions`.

Interactive commands require a terminal. They will not run through Claude Code's `!` prefix, which has no TTY.

## Handoff modes

| | `--resume` (default) | `--fork` | `--brief` |
|---|---|---|---|
| New session starts with | the full conversation | a copy of the full conversation | a structured brief only |
| Context loaded | entire history | entire history | typically 1–3k tokens |
| Original session | must be closed | may stay open | may stay open |
| Targets | Claude Code | Claude Code | Claude Code or Codex |
| Fidelity | exact | exact | summarised |

Use `--resume` when you need exact continuity. Use `--brief` for long sessions, when the original is still running, or when moving to Codex. In testing, a 17 MB compacted session produced a brief of about 7 KB.

## The handoff brief

A brief is Markdown with fixed sections:

| Section | Contents |
|---|---|
| Goal | What the user asked for, in their words where possible |
| Done (verified) | Completed work with evidence: pull requests, commits, deploys, test results |
| In flight | The step in progress when the session stopped |
| Decisions and constraints | Choices and rules the user set, quoted when strict |
| Key pointers | Repositories, branches, files, commands, URLs and IDs |
| Open questions | Anything blocked or waiting on the user |
| Next step | One or two concrete first actions |

The receiving agent is instructed to verify the repository state before relying on the brief and to confirm with the user before any destructive or outward-facing action.

**Generation.** The transcript is condensed to what the model actually had in context: the latest compaction summary, the messages Claude Code retained verbatim at compaction, and everything after. It includes user messages, assistant replies, one-line tool calls and tool errors; side chains, system reminders and tool output are excluded. The condensed transcript is summarised with `claude -p` (default model `sonnet`) using a dedicated system prompt, with tools, MCP servers and project settings disabled. The cost is charged to the account you are handing off **to**.

Briefs are saved to `~/.claude-accounts/.briefs/` with mode `600`.

## How it works

- **Isolation.** Each account is a separate [`CLAUDE_CONFIG_DIR`](https://docs.anthropic.com/en/docs/claude-code/settings) under `~/.claude-accounts/<name>`. Claude Code stores one login per configuration directory (in the macOS Keychain, or in the directory itself on Linux), so accounts never overwrite each other. The default account runs with `CLAUDE_CONFIG_DIR` unset.
- **Sharing.** `settings.json`, `settings.local.json`, `CLAUDE.md`, `agents/`, `skills/`, `plugins/`, `commands/`, `hooks/` and `projects/` are symlinked from `~/.claude`. User-scope MCP servers are copied once, when the account is added.
- **Session discovery.** Conversations are read from the shared `projects/` directory. Open sessions are detected from each account's session registry and verified by process ID.

## Security and privacy

- No credentials are read, copied or modified; sign-in is handled by Claude Code itself.
- Before summarisation, labelled passwords, API keys (Anthropic, OpenAI, GitHub, Slack, AWS, Google), JWTs and private keys are replaced with `[redacted]`. Redaction is pattern-based; an unlabelled secret in free text may not be caught.
- Condensed transcripts are sent only to Claude, through your own Claude Code login.
- Because `projects/` is shared, every account can read every conversation. Do not use this layout where accounts must be kept strictly separate.

## Limitations

- **Terms of use.** Holding more than one account for your own use is common. Creating accounts to evade usage limits, or sharing or reselling accounts, is not permitted under Anthropic's policies. This tool does not switch accounts automatically and is not intended for that purpose.
- **Summaries are lossy.** A brief can omit detail. Review the first actions of a session started from a brief.
- **Unofficial.** Claude Code's on-disk session format is not a public interface and may change between versions.

## Development

```sh
bash tests/run.sh
```

The test suite is self-contained. It uses a temporary `HOME`, stub `claude` and `codex` executables and synthetic session files, and never touches your real configuration or credentials. CI runs it on Ubuntu and macOS.

Issues and pull requests are welcome.

## License

[MIT](LICENSE)
