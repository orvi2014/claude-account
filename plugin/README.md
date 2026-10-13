# hatswap plugin for Claude Code

Slash commands for [hatswap](https://github.com/orvi2014/hatswap), which keeps every client's Claude Code account signed in at once.

| Command | What it does |
|---|---|
| `/hatswap:switch <account>` | Continue this conversation on another account |
| `/hatswap:handoff [account\|codex]` | Write a handoff brief, then continue on another account, in a fresh session, or in Codex |
| `/hatswap:accounts` | Every account's email and 5-hour and weekly usage |

The plugin needs the hatswap CLI. Install it in a terminal:

    curl -fsSL https://raw.githubusercontent.com/orvi2014/hatswap/main/install.sh | bash

Then, in Claude Code:

    /plugin marketplace add orvi2014/hatswap
    /plugin install hatswap@hatswap
