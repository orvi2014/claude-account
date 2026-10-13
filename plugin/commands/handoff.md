---
description: Write a handoff brief of this session, then continue it on another account, in a fresh session, or in Codex
argument-hint: "[account | main | codex]"
---

If `command -v hatswap` finds nothing, do not run anything else: tell the user this needs the hatswap CLI, installed in a normal terminal with `curl -fsSL https://raw.githubusercontent.com/orvi2014/hatswap/main/install.sh | bash`, and stop.

Write a handoff brief so a fresh agent, with no access to this conversation, can continue the work.

First check the current repository state and treat it as ground truth: `git status --short`, `git branch --show-current`, `git log --oneline -8`, and `gh pr list --author @me --state open` if `gh` is available.

Use exactly these Markdown sections:

# Handoff brief
## Goal
## Done (verified)
## In flight
## Decisions and constraints
## Tried and rejected
## Key pointers
## Open questions / blockers
## Next step

Under "Tried and rejected", list approaches that were tried or considered and abandoned, each with why (the error, the failing test, the user's objection), so the next agent does not repeat them; write "None" if there were none.

Be specific and terse. Only state what actually happened in this session or what the repository shows. Quote the user for strict rules. Never include passwords, API keys or tokens.

Save it by running this command, with the brief as the heredoc body:

```
hatswap save-brief <<'BRIEF'
...the brief...
BRIEF
```

It prints the saved path. Then reply with one short message containing:
- the saved path;
- the command to continue, to be run in a normal terminal tab: `hatswap handoff $ARGUMENTS --from <path>`, or, if no account was given, `hatswap refresh --from <path>` (a fresh session on this account);
- a note that they can /exit this window first.
