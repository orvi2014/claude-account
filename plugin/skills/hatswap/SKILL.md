---
name: hatswap
description: Use when the user asks which Claude account this session is on, wants to move this conversation to another of their Claude accounts (for example another client's), or asks for each account's usage, and the hatswap CLI is installed.
---

hatswap keeps several Claude Code accounts signed in on one machine, one per client or context.

- Which account this session is on: run `hatswap whoami`.
- Every account's email and 5-hour and weekly usage: run `hatswap usage`.
- Continue this conversation on another account: run `hatswap switch <account>` (or `main`), only when the user asked for it. Account names come from `hatswap list`.

If `command -v hatswap` finds nothing, say it needs the hatswap CLI (https://github.com/orvi2014/hatswap) and don't try to install it yourself. Never switch accounts on your own initiative, and don't suggest switching to get around usage limits.
