#!/usr/bin/env bash
# Self-contained tests: a throwaway HOME, a fake `claude`/`codex` that print
# their arguments, and synthetic session files. Nothing touches your real
# ~/.claude or Keychain.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/claude-account"
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
F
cat > "$T/fake/codex" <<'F'
#!/bin/sh
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
ok "--version prints the version" '[[ "$("$BIN" --version)" == "claude-account "[0-9]* ]]'
ok "remove without input does not crash" '"$BIN" remove work </dev/null >/dev/null 2>&1; [[ -d "$CLAUDE_ACCOUNTS_DIR/work" ]]'

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
ok "setup-shell adds the hook to .zshrc" '"$BIN" setup-shell --shell zsh >/dev/null && grep -q "claude-account shell-init zsh" "$HOME/.zshrc"'
"$BIN" setup-shell --shell zsh >/dev/null
ok "setup-shell is idempotent" '[[ "$(grep -c ">>> claude-account >>>" "$HOME/.zshrc")" == 1 ]]'
"$BIN" default work >/dev/null 2>&1
if command -v zsh >/dev/null; then
  ok "installed hook makes plain claude follow the default" '[[ "$(PATH="$(dirname "$BIN"):$PATH" ZDOTDIR="$HOME" zsh -ic "claude hi" 2>/dev/null)" == *"CONFIG=$CLAUDE_ACCOUNTS_DIR/work ARGS=hi"* ]]'
fi
"$BIN" default main >/dev/null 2>&1
echo "keep-me" >> "$HOME/.zshrc"
"$BIN" setup-shell --shell zsh --remove >/dev/null
ok "setup-shell --remove takes out only the hook" '! grep -q claude-account "$HOME/.zshrc" && grep -q keep-me "$HOME/.zshrc"'
ok "setup-shell rejects unknown shells" '! "$BIN" setup-shell --shell tcsh >/dev/null 2>&1'
"$BIN" setup-shell --shell fish >/dev/null
ok "setup-shell for fish writes a conf.d file" 'grep -q "shell-init fish | source" "$HOME/.config/fish/conf.d/claude-account.fish"'
"$BIN" setup-shell --shell fish --remove >/dev/null
ok "fish hook file is removed when empty" '[[ ! -e "$HOME/.config/fish/conf.d/claude-account.fish" ]]'
if command -v fish >/dev/null; then
  "$BIN" default work >/dev/null 2>&1
  ok "fish hook follows the default" '[[ "$(fish -c "\"$BIN\" shell-init fish | source; claude hi")" == *"CONFIG=$CLAUDE_ACCOUNTS_DIR/work"* ]]'
  "$BIN" default main >/dev/null 2>&1
fi

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
out="$(FAKE_PANE_PID=$LIVE FAKE_START="claude --session-id $SID --keep-flag x" CLAUDE_CODE_SESSION_ID=$SID "$BIN" switch work 2>&1 </dev/null)"
ok "switch inside tmux restarts the pane in place" '[[ "$out" == *"This tab restarts"* ]] && grep -q "respawn-pane -k -t %9" "$FAKE_LOG.tmux"'
ok "in-place switch keeps the start flags and resumes on the target" 'grep -q "CONFIG=$CLAUDE_ACCOUNTS_DIR/work ARGS=--resume $SID --keep-flag x" "$FAKE_LOG.tmux"'
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
ok "install-command writes /switch" 'grep -q "claude-account switch \$ARGUMENTS" "$HOME/.claude/commands/switch.md"'
ok "install-command writes /handoff" '[[ -f "$HOME/.claude/commands/handoff.md" ]] && grep -q "## Tried and rejected" "$HOME/.claude/commands/handoff.md" && grep -q "claude-account save-brief" "$HOME/.claude/commands/handoff.md" && grep -q "\$ARGUMENTS" "$HOME/.claude/commands/handoff.md"'
ok "install-command will not overwrite" '! "$BIN" install-command >/dev/null 2>&1'
ok "install-command --force overwrites" '"$BIN" install-command --force >/dev/null'
tty_run "$BIN" use work >/dev/null
ok "/handoff reaches other accounts via the shared commands dir" '[[ -f "$CLAUDE_ACCOUNTS_DIR/work/commands/handoff.md" ]]'

# remove
ok "remove refuses main" '! "$BIN" remove main >/dev/null 2>&1'
echo y | "$BIN" remove work >/dev/null 2>&1
ok "remove deletes profile, keeps shared files" '[[ ! -d "$CLAUDE_ACCOUNTS_DIR/work" && -f "$HOME/.claude/settings.json" && -d "$HOME/.claude/agents" ]]'

echo; echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
