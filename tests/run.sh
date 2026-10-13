#!/usr/bin/env bash
# Self-contained tests: a throwaway HOME, a fake `claude`/`codex` that print
# their arguments, and synthetic session files. Nothing touches your real
# ~/.claude or Keychain.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/hatswap"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" CLAUDE_ACCOUNTS_DIR="$T/home/.claude-accounts"
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID CLAUDE_PID TMUX TMUX_PANE XDG_CONFIG_HOME ZDOTDIR
mkdir -p "$HOME/.claude/projects" "$HOME/.claude/sessions" "$T/fake" "$T/work"
echo '{}' > "$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude/agents"
echo '{"mcpServers":{"demo":{"command":"demo"}},"oauthAccount":{"emailAddress":"me@example.com"}}' > "$HOME/.claude.json"

cat > "$T/fake/claude" <<'F'
#!/bin/sh
if [ "$1" = "-p" ] || echo "$*" | grep -q -- " -p "; then
  cat > "$FAKE_LOG.stdin"
  echo "CONFIG=${CLAUDE_CONFIG_DIR-<unset>} ARGS=$*" > "$FAKE_LOG.brief"
  printf '# Handoff brief\n## Goal\nShip it\n## Next step\nRun tests\n'
  exit 0
fi
echo "CONFIG=${CLAUDE_CONFIG_DIR-<unset>} ARGS=$*"
echo "AUTHKEY=${ANTHROPIC_API_KEY-<unset>} OAUTH=${CLAUDE_CODE_OAUTH_TOKEN-<unset>}"
F
cat > "$T/fake/codex" <<'F'
#!/bin/sh
echo "CODEX_HOME=${CODEX_HOME-<unset>}"
echo "CODEX ARGS=$*"
F
cat > "$T/fake/gh" <<'F'
#!/bin/sh
echo '[{"number":42,"title":"Add widgets","headRefName":"feat/widgets","url":"https://example.com/pr/42"}]'
F
cat > "$T/fake/editor" <<'F'
#!/bin/sh
echo "EDITED-MARKER" >> "$1"
F
chmod +x "$T/fake/claude" "$T/fake/codex" "$T/fake/gh" "$T/fake/editor"
export PATH="$T/fake:$PATH" FAKE_LOG="$T/log"

pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1"; fi; }
if script --version >/dev/null 2>&1; then
  tty_run() { script -qec "$(printf '%q ' "$@")" /dev/null < /dev/null 2>&1 | tr -d '\r'; }
else
  tty_run() { script -q /dev/null "$@" < /dev/null 2>&1 | tr -d '\r' | sed 's/^\^D//'; }
fi
mode_of() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

cd "$T/work"
git init -q -b main . && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m "initial commit marker"
echo change > dirty.txt
PROJ="$HOME/.claude/projects/$(echo "$T/work" | sed 's/[^A-Za-z0-9]/-/g')"
mkdir -p "$PROJ"
mk_session() {
  python3 - "$PROJ/$1.jsonl" "$2" <<'P'
import json, sys
path, text = sys.argv[1], sys.argv[2]
rows = [
  {"type": "user", "uuid": "u1", "parentUuid": None, "message": {"content": "OLD: " + text}},
  {"type": "assistant", "uuid": "a1", "parentUuid": "u1", "message": {"content": [{"type": "text", "text": "kept-tail-marker PR #77 merged"}]}},
  {"type": "system", "subtype": "compact_boundary", "uuid": "b1", "parentUuid": None, "logicalParentUuid": "a1"},
  {"type": "user", "uuid": "s1", "parentUuid": "b1", "isCompactSummary": True, "message": {"content": "summary-marker: earlier work"}},
  {"type": "user", "uuid": "u2", "parentUuid": "s1", "message": {"content": [{"type": "text", "text": text + "<system-reminder>secret-reminder</system-reminder> password: Hunter2xyz key sk-ant-abcdefghijklmnopqrstu jwt eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcdefghijklmnop"}]}},
  {"type": "assistant", "uuid": "a2", "parentUuid": "u2", "message": {"content": [{"type": "tool_use", "name": "Bash", "input": {"command": "npm test"}}]}},
  {"type": "user", "uuid": "x9", "parentUuid": "u2", "isSidechain": True, "message": {"content": "sidechain-marker"}},
  {"type": "ai-title", "aiTitle": "Demo task"},
]
open(path, "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
P
}
mk_session 11111111-1111-1111-1111-111111111111 "first task"
sleep 1
mk_session 22222222-2222-2222-2222-222222222222 "second task"

# add / list
out="$("$BIN" add work --email w@example.com 2>&1)"
ok "add creates profile and calls auth login" '[[ -d "$CLAUDE_ACCOUNTS_DIR/work" && "$out" == *"ARGS=auth login --email w@example.com"* ]]'
ok "add links shared settings" '[[ -L "$CLAUDE_ACCOUNTS_DIR/work/settings.json" && -L "$CLAUDE_ACCOUNTS_DIR/work/agents" ]]'
ok "add copies MCP servers only" 'grep -q demo "$CLAUDE_ACCOUNTS_DIR/work/.claude.json" && ! grep -q me@example.com "$CLAUDE_ACCOUNTS_DIR/work/.claude.json"'
ok "add refuses duplicates" '! "$BIN" add work >/dev/null 2>&1'
ok "add refuses bad names" '! "$BIN" add "a b" >/dev/null 2>&1'
ok "add refuses reserved names" '! "$BIN" add codex >/dev/null 2>&1 && ! "$BIN" add main >/dev/null 2>&1'
ok "list shows main email" '[[ "$("$BIN" list)" == *"me@example.com"* ]]'
ok "list hides the briefs folder" '[[ "$("$BIN" list)" != *briefs* ]]'

# use / main
ok "use needs a terminal" '! "$BIN" use work >/dev/null 2>&1'
ok "use sets CLAUDE_CONFIG_DIR" '[[ "$(tty_run "$BIN" use work --continue)" == *"CONFIG=$CLAUDE_ACCOUNTS_DIR/work ARGS=--continue"* ]]'
ok "bare name works like use" '[[ "$(tty_run "$BIN" work)" == *"CONFIG=$CLAUDE_ACCOUNTS_DIR/work"* ]]'
ok "main runs with CLAUDE_CONFIG_DIR unset" '[[ "$(tty_run "$BIN" main)" == *"CONFIG=<unset>"* ]]'

# whoami / version
ok "whoami shows the main account by default" '[[ "$("$BIN" whoami)" == "main"*"me@example.com"* ]]'
ok "whoami follows CLAUDE_CONFIG_DIR" '[[ "$(CLAUDE_CONFIG_DIR="$CLAUDE_ACCOUNTS_DIR/work" "$BIN" whoami | head -1)" == work* ]]'
ok "--version prints the version" '[[ "$("$BIN" --version)" == "hatswap "[0-9]* ]]'
ok "remove without input does not crash" '"$BIN" remove work </dev/null >/dev/null 2>&1; [[ -d "$CLAUDE_ACCOUNTS_DIR/work" ]]'

# auth environment variables never override an account's login
out="$(ANTHROPIC_API_KEY=sk-test CLAUDE_CODE_OAUTH_TOKEN=tok tty_run "$BIN" use work)"
ok "use clears API key env vars for an account" '[[ "$out" == *"AUTHKEY=<unset> OAUTH=<unset>"* && "$out" == *"ignoring ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN so '"'"'work'"'"' uses its own login"* ]]'
ok "the key value is never printed" '[[ "$out" != *sk-test* ]]'
out="$(ANTHROPIC_API_KEY=sk-test CLAUDE_ACCOUNT_KEEP_AUTH_ENV=1 tty_run "$BIN" use work)"
ok "CLAUDE_ACCOUNT_KEEP_AUTH_ENV=1 keeps them" '[[ "$out" == *"AUTHKEY=sk-test"* && "$out" != *ignoring* ]]'
ok "main keeps the API key untouched" '[[ "$(ANTHROPIC_API_KEY=sk-test tty_run "$BIN" main)" == *"AUTHKEY=sk-test"* ]]'
ok "no note when nothing is set" '[[ "$(tty_run "$BIN" use work)" != *ignoring* ]]'
"$BIN" default work >/dev/null 2>&1
out="$(ANTHROPIC_API_KEY=sk-test bash -c "eval \"\$(\"$BIN\" shell-init bash)\"; claude hi" 2>&1)"
ok "shell hook clears the key on a default account" '[[ "$out" == *"CONFIG=$CLAUDE_ACCOUNTS_DIR/work ARGS=hi"* && "$out" == *"AUTHKEY=<unset>"* && "$out" == *"ignoring ANTHROPIC_API_KEY"* ]]'
ok "the shell hook does not unset the key in your shell" '[[ "$(ANTHROPIC_API_KEY=sk-test bash -c "eval \"\$(\"$BIN\" shell-init bash)\"; claude hi >/dev/null 2>&1; echo \$ANTHROPIC_API_KEY")" == sk-test ]]'
if command -v zsh >/dev/null; then
  ok "zsh hook clears the key too" '[[ "$(ANTHROPIC_API_KEY=sk-test zsh -fc "eval \"\$(\"$BIN\" shell-init zsh)\"; claude hi" 2>&1)" == *"AUTHKEY=<unset>"* ]]'
fi
if command -v fish >/dev/null; then
  ok "fish hook clears the key too" '[[ "$(ANTHROPIC_API_KEY=sk-test fish -c "\"$BIN\" shell-init fish | source; claude hi" 2>&1)" == *"CONFIG=$CLAUDE_ACCOUNTS_DIR/work"*"AUTHKEY=<unset>"* ]]'
fi
"$BIN" default main >/dev/null 2>&1

# sessions
ok "sessions lists newest first" '[[ "$("$BIN" sessions | sed -n 2p)" == *22222222* ]]'
ok "sessions shows first message" '[[ "$("$BIN" sessions)" == *"second task"* ]]'

# handoff (resume)
ok "handoff resumes newest on the target" '[[ "$(tty_run "$BIN" handoff work)" == *"CONFIG=$CLAUDE_ACCOUNTS_DIR/work ARGS=--resume 22222222-2222-2222-2222-222222222222"* ]]'
ok "handoff to main unsets CLAUDE_CONFIG_DIR" '[[ "$(tty_run "$BIN" handoff main 11111111-1111-1111-1111-111111111111)" == *"CONFIG=<unset> ARGS=--resume 11111111"* ]]'
ok "handoff --fork adds --fork-session" '[[ "$(tty_run "$BIN" handoff work --fork)" == *"--fork-session"* ]]'
ok "handoff rejects unknown session" '[[ "$(tty_run "$BIN" handoff work deadbeef)" == *"was not started in"* ]]'

# live session protection
sleep 600 & LIVE=$!
echo "{\"pid\":$LIVE,\"sessionId\":\"22222222-2222-2222-2222-222222222222\",\"cwd\":\"$T/work\"}" > "$HOME/.claude/sessions/$LIVE.json"
ok "sessions marks the open one live" '[[ "$("$BIN" sessions | grep 22222222)" == live* ]]'
ok "handoff refuses a live session" '[[ "$(tty_run "$BIN" handoff work)" == *"still open"* ]]'
kill $LIVE 2>/dev/null

# default account
ok "default starts as main" '[[ "$("$BIN" default)" == main ]]'
ok "default rejects unknown profile" '! "$BIN" default nope >/dev/null 2>&1'
"$BIN" default work >/dev/null 2>&1
ok "default sets the account" '[[ "$("$BIN" default)" == work && "$("$BIN" list | grep ^work)" == *"[default]"* ]]'
ok "shell hook runs plain claude on the default" '[[ "$(bash -c "eval \"\$(\"$BIN\" shell-init)\"; claude hi")" == *"CONFIG=$CLAUDE_ACCOUNTS_DIR/work ARGS=hi"* ]]'
ok "shell hook respects an explicit CLAUDE_CONFIG_DIR" '[[ "$(CLAUDE_CONFIG_DIR=/x bash -c "eval \"\$(\"$BIN\" shell-init)\"; claude hi")" == *"CONFIG=/x"* ]]'
"$BIN" default main >/dev/null 2>&1
ok "default main clears it" '[[ "$("$BIN" default)" == main && ! -e "$CLAUDE_ACCOUNTS_DIR/.default" ]]'
ok "shell hook falls back to main" '[[ "$(bash -c "eval \"\$(\"$BIN\" shell-init)\"; claude hi")" == *"CONFIG=<unset>"* ]]'
out="$(tty_run "$BIN" use work --default --continue)"
ok "use --default sets default and is not passed to claude" '[[ "$("$BIN" default)" == work && "$out" == *"ARGS=--continue"* && "$out" != *"ARGS=--default"* ]]'
"$BIN" default main >/dev/null 2>&1

# setup-shell
ok "setup-shell adds the hook to .zshrc" '"$BIN" setup-shell --shell zsh >/dev/null && grep -q "hatswap shell-init zsh" "$HOME/.zshrc"'
"$BIN" setup-shell --shell zsh >/dev/null
ok "setup-shell is idempotent" '[[ "$(grep -c ">>> hatswap >>>" "$HOME/.zshrc")" == 1 ]]'
"$BIN" default work >/dev/null 2>&1
if command -v zsh >/dev/null; then
  ok "installed hook makes plain claude follow the default" '[[ "$(PATH="$(dirname "$BIN"):$PATH" ZDOTDIR="$HOME" zsh -ic "claude hi" 2>/dev/null)" == *"CONFIG=$CLAUDE_ACCOUNTS_DIR/work ARGS=hi"* ]]'
fi
"$BIN" default main >/dev/null 2>&1
echo "keep-me" >> "$HOME/.zshrc"
"$BIN" setup-shell --shell zsh --remove >/dev/null
ok "setup-shell --remove takes out only the hook" '! grep -q hatswap "$HOME/.zshrc" && grep -q keep-me "$HOME/.zshrc"'
ok "setup-shell rejects unknown shells" '! "$BIN" setup-shell --shell tcsh >/dev/null 2>&1'
"$BIN" setup-shell --shell fish >/dev/null
ok "setup-shell for fish writes a conf.d file" 'grep -q "shell-init fish | source" "$HOME/.config/fish/conf.d/hatswap.fish"'
"$BIN" setup-shell --shell fish --remove >/dev/null
ok "fish hook file is removed when empty" '[[ ! -e "$HOME/.config/fish/conf.d/hatswap.fish" ]]'
if command -v fish >/dev/null; then
  "$BIN" default work >/dev/null 2>&1
  ok "fish hook follows the default" '[[ "$(fish -c "\"$BIN\" shell-init fish | source; claude hi")" == *"CONFIG=$CLAUDE_ACCOUNTS_DIR/work"* ]]'
  "$BIN" default main >/dev/null 2>&1
fi

# per-folder pin
mkdir -p "$T/work/sub/deeper"
hook_claude() { (cd "$1" && bash -c "eval \"\$(\"$BIN\" shell-init bash)\"; claude hi" 2>&1); }
out="$(cd "$T/work" && "$BIN" pin work 2>&1)"
ok "pin writes .hatswap" '[[ "$out" == *"Pinned"* ]] && grep -qx work "$T/work/.hatswap"'
ok "pin keeps the file out of git" 'grep -qx ".hatswap" "$T/work/.git/info/exclude" && [[ -z "$(cd "$T/work" && git status --short .hatswap)" ]]'
(cd "$T/work" && "$BIN" pin work >/dev/null 2>&1)
ok "pin adds the ignore line once" '[[ "$(grep -c "^.hatswap$" "$T/work/.git/info/exclude")" == 1 ]]'
ok "hook uses the pin in that folder" '[[ "$(hook_claude "$T/work")" == *"CONFIG=$CLAUDE_ACCOUNTS_DIR/work ARGS=hi"* ]]'
ok "hook uses the pin in subfolders" '[[ "$(hook_claude "$T/work/sub/deeper")" == *"CONFIG=$CLAUDE_ACCOUNTS_DIR/work"* ]]'
ok "hook ignores the pin outside the folder" '[[ "$(hook_claude "$T")" == *"CONFIG=<unset>"* ]]'
ok "explicit CLAUDE_CONFIG_DIR beats the pin" '[[ "$(cd "$T/work" && CLAUDE_CONFIG_DIR=/x bash -c "eval \"\$(\"$BIN\" shell-init bash)\"; claude hi")" == *"CONFIG=/x"* ]]'
"$BIN" default work >/dev/null 2>&1
(cd "$T/work/sub" && "$BIN" pin main >/dev/null 2>&1)
ok "a nearer pin wins, and main overrides the default" '[[ "$(hook_claude "$T/work/sub/deeper")" == *"CONFIG=<unset>"* ]]'
ok "outside any pin the default still applies" '[[ "$(hook_claude "$T")" == *"CONFIG=$CLAUDE_ACCOUNTS_DIR/work"* ]]'
"$BIN" default main >/dev/null 2>&1
ok "pin shows the nearest pin" '[[ "$(cd "$T/work/sub/deeper" && "$BIN" pin)" == "main  (pinned by "*"/work/sub/.hatswap)" ]]'
SHELL=/bin/zsh "$BIN" setup-shell --shell zsh >/dev/null
ok "whoami reports the pin" '[[ "$(cd "$T/work" && SHELL=/bin/zsh "$BIN" whoami 2>/dev/null)" == *"new '"'"'claude'"'"' sessions here: work (pinned by "* ]]'
ok "whoami flags a pin the shell hook cannot apply" '"$BIN" setup-shell --shell zsh --remove >/dev/null; [[ "$(cd "$T/work" && SHELL=/bin/zsh "$BIN" whoami 2>/dev/null)" == *"should be '"'"'work'"'"', pinned by"*"hook is missing"* ]]'
out="$(cd "$T/work" && tty_run "$BIN" refresh)"
ok "refresh in a pinned folder uses the pinned account" '[[ "$out" == *"CONFIG=$CLAUDE_ACCOUNTS_DIR/work ARGS=You are taking over"* ]]'
printf '# note\n\n  nope  \n' > "$T/work/sub/.hatswap"
ok "a pin naming an unknown account falls back to main with a warning" '[[ "$(hook_claude "$T/work/sub")" == *"no account '"'"'nope'"'"'"*"CONFIG=<unset>"* ]]'
ok "pin rejects unknown accounts" '! (cd "$T/work" && "$BIN" pin nope >/dev/null 2>&1)'
(cd "$T/work/sub" && "$BIN" pin --clear >/dev/null 2>&1)
ok "pin --clear removes the pin" '[[ ! -e "$T/work/sub/.hatswap" ]]'
if command -v fish >/dev/null; then
  ok "fish hook follows the pin" '[[ "$(cd "$T/work/sub/deeper" && fish -c "\"$BIN\" shell-init fish | source; claude hi")" == *"CONFIG=$CLAUDE_ACCOUNTS_DIR/work"* ]]'
fi
rm -f "$T/work/.hatswap"

# switch
ok "switch resumes a closed session on the target" '[[ "$(tty_run "$BIN" switch work)" == *"CONFIG=$CLAUDE_ACCOUNTS_DIR/work ARGS=--resume 22222222"* ]]'
ok "switch refuses codex" '! "$BIN" switch codex >/dev/null 2>&1'
sleep 600 & LIVE=$!
echo "{\"pid\":$LIVE,\"sessionId\":\"22222222-2222-2222-2222-222222222222\",\"cwd\":\"$T/work\"}" > "$HOME/.claude/sessions/$LIVE.json"
out="$(tty_run "$BIN" switch work --yes --default)"
ok "switch stops the live session and resumes it" '! kill -0 $LIVE 2>/dev/null && [[ "$out" == *"CONFIG=$CLAUDE_ACCOUNTS_DIR/work ARGS=--resume 22222222"* ]]'
ok "switch --default sets the default" '[[ "$("$BIN" default)" == work ]]'
rm -f "$HOME/.claude/sessions/$LIVE.json"; "$BIN" default main >/dev/null 2>&1

# switch in place (tmux)
cat > "$T/fake/tmux" <<'F'
#!/bin/bash
echo "TMUX $*" >> "$FAKE_LOG.tmux"
case "$1" in
  display) case "$*" in *pane_pid*) echo "$FAKE_PANE_PID" ;; *pane_start_command*) echo "$FAKE_START" ;; esac ;;
  run-shell) bash -c "$3" ;;
  respawn-pane) bash -c "${@: -1}" >> "$FAKE_LOG.tmux" 2>&1 ;;
esac
F
chmod +x "$T/fake/tmux"
export CLAUDE_ACCOUNT_SWITCH_DELAY=0
SID=22222222-2222-2222-2222-222222222222
sleep 600 & LIVE=$!
echo "{\"pid\":$LIVE,\"sessionId\":\"$SID\",\"cwd\":\"$T/work\",\"tmux\":\"s:@1.%9\"}" > "$HOME/.claude/sessions/$LIVE.json"
rm -f "$FAKE_LOG.tmux"
out="$(ANTHROPIC_API_KEY=sk-test FAKE_PANE_PID=$LIVE FAKE_START="claude --session-id $SID --keep-flag x" CLAUDE_CODE_SESSION_ID=$SID "$BIN" switch work 2>&1 </dev/null)"
ok "switch inside tmux restarts the pane in place" '[[ "$out" == *"This tab restarts"* ]] && grep -q "respawn-pane -k -t %9" "$FAKE_LOG.tmux"'
ok "in-place switch keeps the start flags and resumes on the target" 'grep -q "CONFIG=$CLAUDE_ACCOUNTS_DIR/work ARGS=--resume $SID --keep-flag x" "$FAKE_LOG.tmux"'
ok "in-place switch clears API key env vars" 'grep -q "AUTHKEY=<unset>" "$FAKE_LOG.tmux"'
rm -f "$FAKE_LOG.tmux"
FAKE_PANE_PID=$LIVE FAKE_START="claude --session-id $SID" CLAUDE_CODE_SESSION_ID=$SID "$BIN" switch main </dev/null >/dev/null 2>&1
ok "in-place switch to main unsets CLAUDE_CONFIG_DIR" 'grep -q "CONFIG=<unset> ARGS=--resume $SID" "$FAKE_LOG.tmux"'
ok "in-place switch leaves no job files" '[[ -z "$(ls -A "$CLAUDE_ACCOUNTS_DIR/.jobs")" ]]'
kill $LIVE 2>/dev/null; rm -f "$HOME/.claude/sessions/$LIVE.json"

# claude running under a shell in the pane
bash -c 'sleep 600 & echo $! > "$0"; wait' "$T/child" & SHELLPID=$!
sleep 0.5; LIVE=$(cat "$T/child")
echo "{\"pid\":$LIVE,\"sessionId\":\"$SID\",\"cwd\":\"$T/work\",\"tmux\":\"s:@1.%9\"}" > "$HOME/.claude/sessions/$LIVE.json"
rm -f "$FAKE_LOG.tmux"
FAKE_PANE_PID=$SHELLPID CLAUDE_CODE_SESSION_ID=$SID "$BIN" switch work </dev/null >/dev/null 2>&1
ok "switch under a pane shell stops claude and types the resume" '! kill -0 $LIVE 2>/dev/null && grep -q "send-keys -t %9 -l .*work --resume $SID" "$FAKE_LOG.tmux"'
kill $SHELLPID 2>/dev/null; rm -f "$HOME/.claude/sessions/$LIVE.json"

# no tmux: explain what to do
sleep 600 & LIVE=$!
echo "{\"pid\":$LIVE,\"sessionId\":\"$SID\",\"cwd\":\"$T/work\"}" > "$HOME/.claude/sessions/$LIVE.json"
out="$(CLAUDE_CODE_SESSION_ID=$SID "$BIN" switch work 2>&1 </dev/null)"
ok "switch without tmux or terminal explains the next step" '[[ "$out" == *"needs a terminal"* || "$out" == *"/exit"* || "$out" == *"normal terminal"* ]] && kill -0 $LIVE'
kill $LIVE 2>/dev/null; rm -f "$HOME/.claude/sessions/$LIVE.json"
rm -f "$T/fake/tmux"

# brief
out="$("$BIN" brief 2>/dev/null)"
ok "brief prints the model output" '[[ "$out" == *"# Handoff brief"* ]]'
ok "brief is saved privately" '[[ -n "$(ls "$CLAUDE_ACCOUNTS_DIR"/.briefs/*.md)" && "$(mode_of "$(ls "$CLAUDE_ACCOUNTS_DIR"/.briefs/*.md | head -1)")" == 600 ]]'
ok "brief input has summary, kept tail and new work" 'grep -q summary-marker "$FAKE_LOG.stdin" && grep -q kept-tail-marker "$FAKE_LOG.stdin" && grep -q "second task" "$FAKE_LOG.stdin" && grep -q "\[tool Bash\] npm test" "$FAKE_LOG.stdin"'
ok "brief input drops reminders and side chains" '! grep -q secret-reminder "$FAKE_LOG.stdin" && ! grep -q sidechain-marker "$FAKE_LOG.stdin"'
ok "brief input redacts secrets" '! grep -q -e Hunter2xyz -e sk-ant-abcdef -e eyJhbGci "$FAKE_LOG.stdin" && grep -q "password: \[redacted\]" "$FAKE_LOG.stdin"'
ok "brief replaces the system prompt, no tools" 'grep -q -- "--system-prompt" "$FAKE_LOG.brief" && grep -q -- "--tools" "$FAKE_LOG.brief"'
ok "brief asks for tried-and-rejected approaches" 'grep -q "## Tried and rejected" "$FAKE_LOG.brief"'
ok "brief for main bills main (unset)" 'grep -q "CONFIG=<unset>" "$FAKE_LOG.brief"'

# handoff --brief
out="$(tty_run "$BIN" handoff work --brief)"
ok "handoff --brief bills the target account" 'grep -q "CONFIG=$CLAUDE_ACCOUNTS_DIR/work" "$FAKE_LOG.brief"'
ok "handoff --brief starts fresh with the brief" '[[ "$out" == *"CONFIG=$CLAUDE_ACCOUNTS_DIR/work ARGS=You are taking over"* && "$out" == *"Ship it"* && "$out" != *"--resume"* ]]'
out="$(tty_run "$BIN" handoff codex)"
ok "handoff codex seeds codex with the brief" '[[ "$out" == *"CODEX ARGS=You are taking over"* ]]'

# repository state in the brief
"$BIN" brief >/dev/null 2>&1
ok "brief input includes repository state" 'grep -q "CURRENT REPOSITORY STATE" "$FAKE_LOG.stdin" && grep -q "Branch: main" "$FAKE_LOG.stdin" && grep -q "Uncommitted changes: 1 paths" "$FAKE_LOG.stdin" && grep -q "initial commit marker" "$FAKE_LOG.stdin"'
ok "brief input includes open PRs from gh" 'grep -q "#42 Add widgets (feat/widgets)" "$FAKE_LOG.stdin"'
"$BIN" brief --no-repo >/dev/null 2>&1
ok "--no-repo leaves repository state out" '! grep -q "CURRENT REPOSITORY STATE" "$FAKE_LOG.stdin"'

# --edit
out="$(EDITOR="$T/fake/editor" tty_run "$BIN" handoff work --brief --edit)"
ok "--edit opens the brief before launch" '[[ "$out" == *"EDITED-MARKER"* && "$out" == *"ARGS=You are taking over"* ]]'

# refresh
out="$(tty_run "$BIN" refresh)"
ok "refresh starts fresh on the same (default) account" '[[ "$out" == *"CONFIG=<unset> ARGS=You are taking over"* && "$out" != *"--resume"* ]]'
out="$(CLAUDE_CONFIG_DIR="$CLAUDE_ACCOUNTS_DIR/work" tty_run "$BIN" refresh)"
ok "refresh uses the account this shell runs under" '[[ "$out" == *"CONFIG=$CLAUDE_ACCOUNTS_DIR/work ARGS=You are taking over"* ]]'
sleep 600 & LIVE=$!
mkdir -p "$CLAUDE_ACCOUNTS_DIR/work/sessions"
echo "{\"pid\":$LIVE,\"sessionId\":\"22222222-2222-2222-2222-222222222222\",\"cwd\":\"$T/work\"}" > "$CLAUDE_ACCOUNTS_DIR/work/sessions/$LIVE.json"
out="$(tty_run "$BIN" refresh)"
ok "refresh follows the account that has the session open" '[[ "$out" == *"CONFIG=$CLAUDE_ACCOUNTS_DIR/work ARGS=You are taking over"* ]] && grep -q "CONFIG=$CLAUDE_ACCOUNTS_DIR/work" "$FAKE_LOG.brief"'
kill $LIVE 2>/dev/null; rm -f "$CLAUDE_ACCOUNTS_DIR/work/sessions/$LIVE.json"

# save-brief, briefs, --from
saved="$(printf '# Handoff brief\n## Goal\nFrom-marker goal\n' | "$BIN" save-brief)"
ok "save-brief stores stdin privately" '[[ -f "$saved" && "$(mode_of "$saved")" == 600 ]] && grep -q From-marker "$saved"'
ok "save-brief refuses empty input" '! "$BIN" save-brief </dev/null >/dev/null 2>&1'
ok "briefs lists saved briefs with their goal" '[[ "$("$BIN" briefs)" == *"From-marker goal"* ]]'
rm -f "$FAKE_LOG.brief"
out="$(tty_run "$BIN" handoff work --from "$saved")"
ok "handoff --from seeds a saved brief without regenerating" '[[ "$out" == *"CONFIG=$CLAUDE_ACCOUNTS_DIR/work ARGS=You are taking over"* && "$out" == *From-marker* && ! -e "$FAKE_LOG.brief" ]]'
out="$(tty_run "$BIN" handoff codex --from "$saved")"
ok "handoff codex --from works" '[[ "$out" == *"CODEX ARGS=You are taking over"* && "$out" == *From-marker* ]]'
out="$(tty_run "$BIN" refresh --from "$saved")"
ok "refresh --from restarts on the current account" '[[ "$out" == *"CONFIG=<unset> ARGS=You are taking over"* ]]'
ok "--from rejects a missing file" '[[ "$(tty_run "$BIN" handoff work --from /nope.md)" == *"not found"* ]]'

# install-command
"$BIN" install-command >/dev/null
ok "install-command writes /switch" 'grep -q "hatswap switch \$ARGUMENTS" "$HOME/.claude/commands/switch.md"'
ok "install-command writes /handoff" '[[ -f "$HOME/.claude/commands/handoff.md" ]] && grep -q "## Tried and rejected" "$HOME/.claude/commands/handoff.md" && grep -q "hatswap save-brief" "$HOME/.claude/commands/handoff.md" && grep -q "\$ARGUMENTS" "$HOME/.claude/commands/handoff.md"'
ok "install-command updates its own files" '"$BIN" install-command >/dev/null 2>&1'
ok "installed commands carry the template revision" 'grep -q "hatswap-commands:" "$HOME/.claude/commands/switch.md"'
sed -i.bak "/hatswap-commands:/d" "$HOME/.claude/commands/handoff.md"
ok "outdated commands are reported" '[[ "$("$BIN" list 2>&1)" == *"commands are out of date (/handoff)"* ]]'
"$BIN" install-command >/dev/null
ok "install-command clears the outdated note" '[[ "$("$BIN" list 2>&1)" != *"out of date"* ]]'
cp "$HOME/.claude/commands/switch.md" "$T/switch.keep"; echo "my own command" > "$HOME/.claude/commands/switch.md"
ok "install-command will not overwrite a foreign file" '! "$BIN" install-command >/dev/null 2>&1 && grep -q "my own command" "$HOME/.claude/commands/switch.md"'
cp "$T/switch.keep" "$HOME/.claude/commands/switch.md"
ok "install-command --force overwrites" '"$BIN" install-command --force >/dev/null'
tty_run "$BIN" use work >/dev/null
ok "/handoff reaches other accounts via the shared commands dir" '[[ -f "$CLAUDE_ACCOUNTS_DIR/work/commands/handoff.md" ]]'

# shared accounts never get a stray copy of history
"$BIN" add fresh >/dev/null 2>&1; rm -f "$CLAUDE_ACCOUNTS_DIR/fresh/projects"
out="$(tty_run "$BIN" handoff fresh 11111111-1111-1111-1111-111111111111)"
ok "handoff to a shared account links history instead of copying" '[[ -L "$CLAUDE_ACCOUNTS_DIR/fresh/projects" && "$out" != *"Copied"* && "$out" == *"ARGS=--resume 11111111"* ]]'

# private history
"$BIN" add client --private >/dev/null 2>&1
ok "add --private gives the account its own history" '[[ -d "$CLAUDE_ACCOUNTS_DIR/client/projects" && ! -L "$CLAUDE_ACCOUNTS_DIR/client/projects" && -e "$CLAUDE_ACCOUNTS_DIR/client/.private" && -L "$CLAUDE_ACCOUNTS_DIR/client/settings.json" ]]'
ok "list marks private accounts" '[[ "$("$BIN" list 2>/dev/null | grep ^client)" == *"[private]"* ]]'
tty_run "$BIN" use client >/dev/null
ok "use keeps a private account private" '[[ ! -L "$CLAUDE_ACCOUNTS_DIR/client/projects" ]]'
CPROJ="$CLAUDE_ACCOUNTS_DIR/client/projects/$(basename "$PROJ")"
mkdir -p "$CPROJ"
python3 - "$CPROJ/33333333-3333-3333-3333-333333333333.jsonl" <<'P'
import json, sys
open(sys.argv[1], "w").write(json.dumps({"type": "user", "uuid": "c1", "parentUuid": None, "message": {"content": "private client task"}}) + "\n")
P
ok "sessions include private conversations" '[[ "$("$BIN" sessions)" == *"private client task"* ]]'
ok "private conversations stay out of the shared history" '[[ ! -e "$PROJ/33333333-3333-3333-3333-333333333333.jsonl" ]]'
out="$(tty_run "$BIN" handoff work 33333333-3333-3333-3333-333333333333)"
ok "handing off a private conversation copies it to the target" '[[ "$out" == *"Copied this conversation"* && "$out" == *"ARGS=--resume 33333333"* && -e "$PROJ/33333333-3333-3333-3333-333333333333.jsonl" ]]'
ok "brief reads private conversations" '"$BIN" brief --no-repo 33333333-3333-3333-3333-333333333333 >/dev/null 2>&1 && grep -q "private client task" "$FAKE_LOG.stdin"'
ok "private --off refuses while it has history" '! "$BIN" private client --off >/dev/null 2>&1'
"$BIN" add spare >/dev/null 2>&1; "$BIN" private spare >/dev/null
ok "private converts an existing account" '[[ -e "$CLAUDE_ACCOUNTS_DIR/spare/.private" && ! -L "$CLAUDE_ACCOUNTS_DIR/spare/projects" ]]'
"$BIN" private spare --off >/dev/null
ok "private --off shares history again" '[[ -L "$CLAUDE_ACCOUNTS_DIR/spare/projects" && ! -e "$CLAUDE_ACCOUNTS_DIR/spare/.private" ]]'

# codex accounts
mkdir -p "$HOME/.codex"; echo 'model = "x"' > "$HOME/.codex/config.toml"
out="$("$BIN" codex-login work 2>&1)"
ok "codex-login uses the account's own CODEX_HOME" '[[ "$out" == *"CODEX_HOME=$CLAUDE_ACCOUNTS_DIR/work/codex"* && "$out" == *"ARGS=login"* ]]'
ok "codex homes share config, not logins" '[[ -L "$CLAUDE_ACCOUNTS_DIR/work/codex/config.toml" && ! -e "$CLAUDE_ACCOUNTS_DIR/work/codex/auth.json" ]]'
python3 - "$CLAUDE_ACCOUNTS_DIR/work/codex/auth.json" <<'P'
import base64, json, sys
b = lambda d: base64.urlsafe_b64encode(json.dumps(d).encode()).decode().rstrip("=")
tok = b({"alg": "none"}) + "." + b({"email": "work@openai.example"}) + ".sig"
json.dump({"tokens": {"id_token": tok, "access_token": "secret-access", "refresh_token": "secret-refresh"}}, open(sys.argv[1], "w"))
P
ok "list shows the Codex login" '[[ "$("$BIN" list 2>/dev/null | grep ^work)" == *"codex: work@openai.example"* ]] && ! "$BIN" list 2>/dev/null | grep -q secret-'
ok "codex <account> runs on its login" '[[ "$(tty_run "$BIN" codex work --help)" == *"CODEX_HOME=$CLAUDE_ACCOUNTS_DIR/work/codex"* ]]'
ok "codex main leaves CODEX_HOME unset" '[[ "$(tty_run "$BIN" codex main)" == *"CODEX_HOME=<unset>"* ]]'
ok "codex refuses an account without a Codex login" '! "$BIN" codex client >/dev/null 2>&1'
out="$(CLAUDE_CONFIG_DIR="$CLAUDE_ACCOUNTS_DIR/work" tty_run "$BIN" handoff codex 22222222-2222-2222-2222-222222222222)"
ok "handoff codex uses the session account's Codex login" '[[ "$out" == *"Codex account: work (work@openai.example)"* && "$out" == *"CODEX_HOME=$CLAUDE_ACCOUNTS_DIR/work/codex"* ]]'
out="$(tty_run "$BIN" handoff codex --as work)"
ok "handoff codex --as picks the Codex account" '[[ "$out" == *"CODEX_HOME=$CLAUDE_ACCOUNTS_DIR/work/codex"* ]]'
out="$(tty_run "$BIN" handoff codex)"
ok "handoff codex falls back to ~/.codex" '[[ "$out" == *"CODEX_HOME=<unset>"* ]]'
ok "handoff codex --as rejects accounts without Codex" '[[ "$(tty_run "$BIN" handoff codex --as client)" == *"no Codex login"* ]]'

# switch in Terminal.app / iTerm2 (macOS)
if [[ "$(uname)" == Darwin ]]; then
  mkdir -p "$T/term"
  cat > "$T/term/ps" <<'F'
#!/bin/bash
for a in "$@"; do [[ "$a" == tty= ]] && { echo ttys009; exit 0; }; done
exec /bin/ps "$@"
F
  cat > "$T/term/osascript" <<'F'
#!/bin/bash
echo "OSA $3 $4 ${5-}" >> "$FAKE_LOG.osa"
echo ok
F
  chmod +x "$T/term/ps" "$T/term/osascript"
  sleep 600 & LIVE=$!
  echo "{\"pid\":$LIVE,\"sessionId\":\"$SID\",\"cwd\":\"$T/work\"}" > "$HOME/.claude/sessions/$LIVE.json"
  rm -f "$FAKE_LOG.osa"
  out="$(PATH="$T/term:$PATH" CLAUDE_ACCOUNT_SWITCH_DELAY=0 CLAUDE_CODE_SESSION_ID=$SID "$BIN" switch work 2>&1 </dev/null)"
  for i in $(seq 1 50); do grep -q " type " "$FAKE_LOG.osa" 2>/dev/null && break; sleep 0.1; done
  ok "switch in a Terminal/iTerm tab restarts that tab" '[[ "$out" == *"This tab restarts"* ]] && grep -q "OSA /dev/ttys009 type .*work --resume $SID" "$FAKE_LOG.osa"'
  ok "terminal switch stops the old session" '! kill -0 $LIVE 2>/dev/null'
  kill $LIVE 2>/dev/null; rm -f "$HOME/.claude/sessions/$LIVE.json"
fi

# installer
mkdir -p "$T/ihome"
out="$(HOME="$T/ihome" SHELL=/bin/zsh ZDOTDIR= PATH="$T/fake:/usr/bin:/bin" CLAUDE_ACCOUNT_SOURCE="$BIN" bash "$ROOT/install.sh" 2>&1)"
ok "install.sh installs the script" '[[ -x "$T/ihome/.local/bin/hatswap" && "$out" == *"Installed hatswap "* ]]'
ok "install.sh keeps claude-account as an alias" '[[ "$(readlink "$T/ihome/.local/bin/claude-account")" == hatswap && "$("$T/ihome/.local/bin/claude-account" --version)" == "hatswap "* ]]'
ok "install.sh adds PATH and the default-account hook" 'grep -q "hatswap PATH" "$T/ihome/.zshrc" && grep -q ">>> hatswap >>>" "$T/ihome/.zshrc"'
ok "install.sh installs /handoff and /switch" '[[ -f "$T/ihome/.claude/commands/handoff.md" && -f "$T/ihome/.claude/commands/switch.md" ]]'
HOME="$T/ihome" SHELL=/bin/zsh PATH="$T/fake:/usr/bin:/bin" CLAUDE_ACCOUNT_SOURCE="$BIN" bash "$ROOT/install.sh" >/dev/null 2>&1
ok "install.sh is idempotent" '[[ "$(grep -c "hatswap PATH" "$T/ihome/.zshrc")" == 1 && "$(grep -c ">>> hatswap >>>" "$T/ihome/.zshrc")" == 1 ]]'
out="$(HOME="$T/ihome" SHELL=/bin/zsh CLAUDE_ACCOUNT_SOURCE="$BIN" bash "$ROOT/install.sh" --no-shell --no-commands --bin-dir "$T/ib" 2>&1)"
ok "install.sh --bin-dir --no-shell installs only the script" '[[ -x "$T/ib/hatswap" && "$out" == *"not on your PATH"* ]]'
mkdir -p "$T/oldbin"; echo "#!/bin/sh" > "$T/oldbin/claude-account"; chmod +x "$T/oldbin/claude-account"
out="$(HOME="$T/ihome" CLAUDE_ACCOUNT_SOURCE="$BIN" bash "$ROOT/install.sh" --no-shell --no-commands --bin-dir "$T/oldbin" 2>&1)"
ok "install.sh replaces an old claude-account with the alias" '[[ -L "$T/oldbin/claude-account" && "$out" == *"Replaced the old claude-account"* ]]'

# update (non-clone install, download stubbed)
cat > "$T/fake/curl" <<F
#!/bin/bash
while [[ \$# -gt 0 ]]; do [[ "\$1" == -o ]] && { cp "$BIN" "\$2"; exit 0; }; shift; done
F
chmod +x "$T/fake/curl"
mkdir -p "$T/ub"; sed 's/^VERSION=.*/VERSION=0.0.1/' "$BIN" > "$T/ub/claude-account"; chmod +x "$T/ub/claude-account"
out="$("$T/ub/claude-account" update 2>&1)"
ok "update from an old claude-account install moves it to hatswap" '[[ "$out" == *"Updated: hatswap 0.0.1 -> "* && "$out" == *"claude-account is now hatswap"* ]] && cmp -s "$BIN" "$T/ub/hatswap" && [[ "$(readlink "$T/ub/claude-account")" == hatswap ]]'
sed 's/^VERSION=.*/VERSION=0.0.2/' "$BIN" > "$T/ub/hatswap"
out="$("$T/ub/hatswap" update 2>&1)"
ok "update replaces hatswap in place" '[[ "$out" == *"Updated: hatswap 0.0.2 -> "* ]] && cmp -s "$BIN" "$T/ub/hatswap"'
rm -f "$T/fake/curl"

# the old name keeps working
ok "bin/claude-account runs hatswap" '[[ "$("$ROOT/bin/claude-account" --version)" == "hatswap "* ]]'
mkdir -p "$T/shim"; cp "$ROOT/bin/claude-account" "$T/shim/claude-account"
cat > "$T/fake/curl" <<F
#!/bin/bash
while [[ \$# -gt 0 ]]; do [[ "\$1" == -o ]] && { cp "$BIN" "\$2"; exit 0; }; shift; done
F
chmod +x "$T/fake/curl"
out="$(PATH="$T/fake:/usr/bin:/bin" "$T/shim/claude-account" --version 2>&1)"
ok "the stand-in answers --version without installing" '[[ "$out" == *"stand-in"* && ! -e "$T/shim/hatswap" ]]'
out="$(PATH="$T/fake:/usr/bin:/bin" "$T/shim/claude-account" list 2>&1)"
ok "the claude-account stand-in fetches hatswap on first use" '[[ "$out" == *"claude-account is now hatswap"* && "$out" == *"main "* && -x "$T/shim/hatswap" ]]'
rm -f "$T/fake/curl"
mkdir -p "$T/oldpin/sub"; echo work > "$T/oldpin/.claude-account"
ok "an old .claude-account pin is still honoured" '[[ "$(cd "$T/oldpin/sub" && bash -c "eval \"\$(\"$BIN\" shell-init bash)\"; claude hi" 2>&1)" == *"CONFIG=$CLAUDE_ACCOUNTS_DIR/work"* && "$(cd "$T/oldpin" && "$BIN" pin)" == work* ]]'
(cd "$T/oldpin" && "$BIN" pin main >/dev/null 2>&1)
ok "pinning again moves an old pin file to .hatswap" '[[ -e "$T/oldpin/.hatswap" && ! -e "$T/oldpin/.claude-account" ]]'
printf '# >>> claude-account >>>\nold hook\n# <<< claude-account <<<\nkeep\n' > "$HOME/.zshrc"
ok "an old hook block counts as installed" '[[ "$(SHELL=/bin/zsh "$BIN" setup-shell --shell zsh)" == *"already"* ]]'
"$BIN" setup-shell --shell zsh --remove >/dev/null
ok "setup-shell --remove takes out an old hook block" '! grep -q "old hook" "$HOME/.zshrc" && grep -q keep "$HOME/.zshrc"'
out="$(ANTHROPIC_API_KEY=sk-test HATSWAP_KEEP_AUTH_ENV=1 tty_run "$BIN" use work)"
ok "HATSWAP_KEEP_AUTH_ENV=1 keeps the key" '[[ "$out" == *"AUTHKEY=sk-test"* ]]'
ok "HATSWAP_DIR picks the data folder" '[[ "$(HATSWAP_DIR="$T/nowhere" "$BIN" list 2>/dev/null | wc -l | tr -d " ")" == 1 ]]'

# exec and shims: bots follow the default on every call
"$BIN" default main >/dev/null
mkdir -p "$T/bot"
ok "exec runs on main with no pin or default" '[[ "$(cd "$T/bot" && "$BIN" exec claude -p x </dev/null; cat "$FAKE_LOG.brief")" == *"CONFIG=<unset>"* ]]'
"$BIN" default work >/dev/null 2>&1
ok "exec follows a default set after the bot started" '[[ "$(cd "$T/bot" && "$BIN" exec claude hi)" == *"CONFIG=$CLAUDE_ACCOUNTS_DIR/work ARGS=hi"* ]]'
ok "exec ignores an inherited CLAUDE_CONFIG_DIR" '[[ "$(cd "$T/bot" && CLAUDE_CONFIG_DIR=/stale "$BIN" exec claude hi)" == *"CONFIG=$CLAUDE_ACCOUNTS_DIR/work "* ]]'
ok "exec clears an API key for a named account" '[[ "$(cd "$T/bot" && ANTHROPIC_API_KEY=sk-x "$BIN" exec claude hi 2>&1)" == *"AUTHKEY=<unset>"* ]]'
ok "HATSWAP_ACCOUNT fixes a bot to one account" '[[ "$(cd "$T/bot" && HATSWAP_ACCOUNT=main "$BIN" exec claude hi)" == *"CONFIG=<unset>"* ]]'
ok "exec --account picks one" '[[ "$(cd "$T/bot" && "$BIN" exec --account main claude hi)" == *"CONFIG=<unset>"* ]]'
ok "exec honours a folder pin" '[[ "$(cd "$T/oldpin" && "$BIN" exec claude hi)" == *"CONFIG=<unset>"* ]]'
ok "exec refuses an unknown account" '! HATSWAP_ACCOUNT=nope "$BIN" exec claude hi >/dev/null 2>&1'
ok "exec runs without a terminal" '[[ "$(cd "$T/bot" && "$BIN" exec claude hi </dev/null | cat)" == *"CONFIG=$CLAUDE_ACCOUNTS_DIR/work "* ]]'
out="$("$BIN" shim)"
ok "shim writes claude and codex wrappers" '[[ -x "$CLAUDE_ACCOUNTS_DIR/bin/claude" && -x "$CLAUDE_ACCOUNTS_DIR/bin/codex" && "$out" == *"no restart"* ]]'
ok "the claude shim follows the default and finds the real claude" '[[ "$(cd "$T/bot" && PATH="$CLAUDE_ACCOUNTS_DIR/bin:$PATH" claude hi)" == *"CONFIG=$CLAUDE_ACCOUNTS_DIR/work ARGS=hi"* ]]'
"$BIN" default main >/dev/null
ok "the shim picks up a changed default on the next call" '[[ "$(cd "$T/bot" && "$CLAUDE_ACCOUNTS_DIR/bin/claude" hi)" == *"CONFIG=<unset>"* ]]'
ok "the codex shim runs codex" '[[ "$(cd "$T/bot" && "$CLAUDE_ACCOUNTS_DIR/bin/codex" go)" == *"CODEX ARGS=go"* ]]'
ok "hatswap use is not hijacked by a shim on PATH" '[[ "$(PATH="$CLAUDE_ACCOUNTS_DIR/bin:$PATH" tty_run "$BIN" use work)" == *"CONFIG=$CLAUDE_ACCOUNTS_DIR/work"* ]]'
ok "list does not show the shim folder" '! "$BIN" list | grep -q "^bin "'
ok "bin is not a valid account name" '! "$BIN" add bin >/dev/null 2>&1 && ! "$BIN" default bin >/dev/null 2>&1'
"$BIN" shim --remove >/dev/null
ok "shim --remove deletes them" '[[ ! -e "$CLAUDE_ACCOUNTS_DIR/bin" ]]'

# shared rules, keybindings and output styles
mkdir -p "$HOME/.claude/rules" "$HOME/.claude/output-styles"; echo '{}' > "$HOME/.claude/keybindings.json"
tty_run "$BIN" use work >/dev/null 2>&1
ok "rules, output-styles and keybindings are shared" '[[ -L "$CLAUDE_ACCOUNTS_DIR/work/rules" && -L "$CLAUDE_ACCOUNTS_DIR/work/output-styles" && -L "$CLAUDE_ACCOUNTS_DIR/work/keybindings.json" ]]'

# usage: limits per account from the /usage endpoint (faked with a file)
work_svc="Claude Code-credentials-$(printf '%s' "$CLAUDE_ACCOUNTS_DIR/work" | shasum -a 256 | cut -c1-8)"
cat > "$T/fake/security" <<F
#!/bin/sh
case "\$*" in
  *"$work_svc"*) echo '{"claudeAiOauth":{"accessToken":"sk-ant-oat-SECRET","expiresAt":9999999999999}}' ;;
  *"-s Claude Code-credentials -a"*) echo '{"claudeAiOauth":{"accessToken":"sk-ant-oat-MAIN","expiresAt":1000}}' ;;
  *) exit 44 ;;
esac
F
chmod +x "$T/fake/security"
echo '{"five_hour":{"utilization":12.0,"resets_at":"2099-01-01T00:00:00+00:00"},"seven_day":{"utilization":40.4,"resets_at":"2099-01-05T00:00:00+00:00"}}' > "$T/usage.json"
export HATSWAP_FAKE_KEYCHAIN=1 HATSWAP_USAGE_URL="file://$T/usage.json"
out="$("$BIN" usage 2>&1)"
ok "usage shows each account's 5-hour and weekly use" '[[ "$out" == *"work"*"12%"*"40%"* ]]'
ok "usage says when a login token has expired" '[[ "$out" == *"main"*"expired"* ]]'
ok "usage never prints a token" '[[ "$out" != *SECRET* && "$out" != *sk-ant* ]]'
ok "usage --json for one account" '"$BIN" usage work --json | python3 -c "import json,sys;d=json.load(sys.stdin);assert d[0][\"account\"]==\"work\" and d[0][\"usage\"][\"five_hour\"][\"utilization\"]==12.0"'
echo '{"five_hour":{"utilization":99}}' > "$T/usage.json"
ok "usage is cached for a few minutes" '[[ "$("$BIN" usage work)" == *"12%"* ]]'
ok "the usage cache holds no tokens" '! grep -q sk-ant "$CLAUDE_ACCOUNTS_DIR/.usage-cache.json" && [[ "$(stat -f %Lp "$CLAUDE_ACCOUNTS_DIR/.usage-cache.json" 2>/dev/null || stat -c %a "$CLAUDE_ACCOUNTS_DIR/.usage-cache.json")" == 600 ]]'
ok "usage refuses an unknown account" '! "$BIN" usage nope >/dev/null 2>&1'
unset HATSWAP_FAKE_KEYCHAIN HATSWAP_USAGE_URL; rm -f "$T/fake/security"

# status line
python3 -c "import json;p='$HOME/.claude/settings.json';d=json.load(open(p));d['statusLine']={'type':'command','command':'echo theirs','padding':1};json.dump(d,open(p,'w'))"
out="$("$BIN" statusline --install)"
ok "statusline --install keeps an existing status line" '[[ "$out" == *"Keeping your status line"* ]] && python3 -c "import json;d=json.load(open(\"$HOME/.claude/settings.json\"));assert d[\"statusLine\"][\"command\"].endswith(\"hatswap statusline\") and d[\"statusLine\"][\"padding\"]==1"'
ok "statusline --install twice is a no-op" '[[ "$("$BIN" statusline --install)" == *"already"* ]]'
out="$(echo '{}' | CLAUDE_CONFIG_DIR="$CLAUDE_ACCOUNTS_DIR/work" "$BIN" statusline)"
ok "the status line shows the account, then the old line" '[[ "$out" == *"work"*"theirs"* ]]'
ok "the status line shows main and its email" '[[ "$(echo "{}" | "$BIN" statusline)" == *"main · me@example.com"* ]]'
"$BIN" statusline --remove >/dev/null
ok "statusline --remove restores the old one" 'python3 -c "import json;d=json.load(open(\"$HOME/.claude/settings.json\"));assert d[\"statusLine\"][\"command\"]==\"echo theirs\""'

# VS Code / Cursor extension
mkdir -p "$T/vs/.vscode"; git -C "$T/vs" init -q
echo '{"editor.tabSize":2,"claudeCode.environmentVariables":[{"name":"FOO","value":"1"}]}' > "$T/vs/.vscode/settings.json"
out="$(cd "$T/vs" && "$BIN" vscode work)"
ok "vscode points the extension at the account, keeping other settings" 'python3 -c "import json;d=json.load(open(\"$T/vs/.vscode/settings.json\"));e=d[\"claudeCode.environmentVariables\"];assert d[\"editor.tabSize\"]==2 and {\"name\":\"FOO\",\"value\":\"1\"} in e and {\"name\":\"CLAUDE_CONFIG_DIR\",\"value\":\"$CLAUDE_ACCOUNTS_DIR/work\"} in e"'
ok "vscode keeps the settings file out of git" 'grep -q ".vscode/settings.json" "$T/vs/.git/info/exclude"'
(cd "$T/vs" && "$BIN" vscode main >/dev/null)
ok "vscode main leaves CLAUDE_CONFIG_DIR unset" '! grep -q CLAUDE_CONFIG_DIR "$T/vs/.vscode/settings.json" && grep -q FOO "$T/vs/.vscode/settings.json"'
mkdir -p "$T/vs2/sub"; echo work > "$T/vs2/.hatswap"
(cd "$T/vs2/sub" && "$BIN" vscode >/dev/null)
ok "vscode with no name follows the folder pin" 'grep -q "$CLAUDE_ACCOUNTS_DIR/work" "$T/vs2/sub/.vscode/settings.json"'
(cd "$T/vs2/sub" && "$BIN" vscode --clear >/dev/null)
ok "vscode --clear removes it" '! grep -q CLAUDE_CONFIG_DIR "$T/vs2/sub/.vscode/settings.json"'
printf '{\n  // a comment\n  "a": 1\n}\n' > "$T/vs/.vscode/settings.json"
ok "vscode leaves a settings file with comments alone" '! (cd "$T/vs" && "$BIN" vscode work >/dev/null 2>&1) && grep -q "a comment" "$T/vs/.vscode/settings.json"'

# Claude Desktop
if [[ "$(uname)" == Darwin ]]; then
  printf '#!/bin/sh\necho "OPEN $*" >> "%s"\n' "$T/open.log" > "$T/fake/open"; chmod +x "$T/fake/open"
  out="$("$BIN" desktop work)"
  ok "desktop opens a separate Claude for the account" 'grep -q -- "-n -a Claude --args --user-data-dir=$CLAUDE_ACCOUNTS_DIR/work/desktop" "$T/open.log" && [[ "$out" == *"First time"* && -d "$CLAUDE_ACCOUNTS_DIR/work/desktop" ]]'
  "$BIN" desktop main >/dev/null
  ok "desktop main opens the normal app" '[[ "$(tail -1 "$T/open.log")" == "OPEN -a Claude" ]]'
  rm -f "$T/fake/open"
fi

# remove
ok "remove refuses main" '! "$BIN" remove main >/dev/null 2>&1'
echo y | "$BIN" remove work >/dev/null 2>&1
ok "remove deletes profile, keeps shared files" '[[ ! -d "$CLAUDE_ACCOUNTS_DIR/work" && -f "$HOME/.claude/settings.json" && -d "$HOME/.claude/agents" ]]'

echo; echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
