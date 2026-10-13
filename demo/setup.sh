#!/usr/bin/env bash
# Builds a throwaway sandbox for recording the demo: two example accounts,
# one conversation, a git repo with work in progress, and stand-ins for
# `claude` and `gh`. Nothing touches your real configuration.
set -euo pipefail
DEMO_ROOT="$(cd "$(dirname "$0")" && pwd)"
S="${1:-/tmp/hatswap-demo}"
rm -rf "${S:?}"; mkdir -p "$S/bin" "$S/home/.claude/projects" "$S/home/billing"
ln -s "$DEMO_ROOT/../bin/hatswap" "$S/bin/hatswap"
cp "$DEMO_ROOT/stub-claude" "$S/bin/claude"; cp "$DEMO_ROOT/stub-gh" "$S/bin/gh"; cp "$DEMO_ROOT/stub-codex" "$S/bin/codex"; chmod +x "$S/bin/"*
echo '{}' > "$S/home/.claude/settings.json"
echo '{"oauthAccount":{"emailAddress":"personal@example.com"}}' > "$S/home/.claude.json"
mkdir -p "$S/home/.claude-accounts/work"
echo '{"oauthAccount":{"emailAddress":"work@example.com"}}' > "$S/home/.claude-accounts/work/.claude.json"
mkdir -p "$S/home/.claude-accounts/acme"
echo '{"oauthAccount":{"emailAddress":"you@acme.example"}}' > "$S/home/.claude-accounts/acme/.claude.json"
# Example usage for the picker. The sandbox has no logins, so seed the cache
# hatswap reads from (valid for an hour, long enough to record).
python3 - "$S/home" <<'PY'
import json, sys, time, datetime
h = sys.argv[1]; now = datetime.datetime.now(datetime.timezone.utc)
def w(u, hrs): return {"utilization": u, "resets_at": (now + datetime.timedelta(hours=hrs)).isoformat()}
use = {f"{h}/.claude": (0, 100), f"{h}/.claude-accounts/work": (10, 27), f"{h}/.claude-accounts/acme": (64, 41)}
json.dump({k: {"at": time.time() + 3600, "data": {"five_hour": w(a, 3), "seven_day": w(b, 70)}} for k, (a, b) in use.items()},
          open(f"{h}/.claude-accounts/.usage-cache.json", "w"))
PY
mkdir -p "$S/home/.claude-accounts/work/codex"
python3 - "$S/home/.claude-accounts/work/codex/auth.json" <<'PY'
import base64, json, sys
b = lambda d: base64.urlsafe_b64encode(json.dumps(d).encode()).decode().rstrip("=")
json.dump({"tokens": {"id_token": b({"alg": "none"}) + "." + b({"email": "work@example.com"}) + ".demo"}}, open(sys.argv[1], "w"))
PY
cd "$S/home/billing"
git init -q -b fix/invoice-rounding
mkdir -p invoice credit && echo "// totals" > invoice/totals.js && echo "// totals" > credit/totals.js
git add . && git -c user.name=demo -c user.email=demo@example.com commit -qm "Fix rounding in invoice totals"
echo "// wip" >> credit/totals.js
P="$S/home/.claude/projects/$(echo "$S/home/billing" | sed 's/[^A-Za-z0-9]/-/g')"
mkdir -p "$P"
python3 - "$P" <<'PY'
import json, os, sys
p = sys.argv[1]
def sess(sid, text, reply):
    rows = [
        {"type": "user", "uuid": sid + "u", "parentUuid": None, "message": {"content": text}},
        {"type": "assistant", "uuid": sid + "a", "parentUuid": sid + "u", "message": {"content": [{"type": "text", "text": reply}]}},
    ]
    open(os.path.join(p, sid + ".jsonl"), "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
sess("4c1e9a2b-7d3f-4e8a-9b1c-2f6d8e0a5c3b", "Write the README for the billing API", "Done.")
sess("9f2d7c41-0b6e-4a53-8e2f-71c3d9a4b6e8", "Invoice totals are off by a cent when a discount applies", "Found it: rounding before the discount.")
PY
touch -t 202610110900 "$P/4c1e9a2b-7d3f-4e8a-9b1c-2f6d8e0a5c3b.jsonl"
cat > "$S/env.sh" <<ENV
export DEMO_ROOT="$DEMO_ROOT" HOME="$S/home" HATSWAP_DIR="$S/home/.claude-accounts"
export PATH="$S/bin:\$PATH" PS1='\[\e[38;5;108m\]\w\[\e[0m\] \$ '
export SHELL=/bin/bash
unset CLAUDE_CONFIG_DIR CLAUDECODE CLAUDE_CODE_SESSION_ID TMUX TMUX_PANE
eval "\$(hatswap shell-init bash)"
cd "$S/home/billing"
ENV
# Mark the shell hook as installed so `default` does not offer to add it.
printf '# >>> hatswap >>>\n# <<< hatswap <<<\n' > "$S/home/.bash_profile"
echo "$S"
