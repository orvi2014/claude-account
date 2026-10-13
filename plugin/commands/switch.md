---
description: Continue this conversation on another Claude account
argument-hint: "<account | main> [--default]"
---

If `command -v hatswap` finds nothing, do not run anything else: tell the user this needs the hatswap CLI, installed in a normal terminal with `curl -fsSL https://raw.githubusercontent.com/orvi2014/hatswap/main/install.sh | bash`, and stop.

Otherwise run exactly this one command with the Bash tool, and nothing else:

```
hatswap switch $ARGUMENTS
```

Then reply with its output in one short line. If it says this tab restarts, add nothing more.
