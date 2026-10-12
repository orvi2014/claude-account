#!/usr/bin/env bash
# Installs claude-account in one step:
#   curl -fsSL https://raw.githubusercontent.com/orvi2014/claude-account/main/install.sh | bash
# Options (after `bash -s --` when piped):
#   --no-shell      do not touch shell startup files (PATH line, default-account hook)
#   --no-commands   do not install the /handoff and /switch Claude Code commands
#   --bin-dir DIR   install into DIR instead of ~/.local/bin
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/orvi2014/claude-account/${CLAUDE_ACCOUNT_REF:-main}"
BIN_DIR="$HOME/.local/bin"
shell_edits=1
commands=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-shell) shell_edits=0; shift ;;
    --no-commands) commands=0; shift ;;
    --bin-dir) BIN_DIR="${2:?}"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

for need in python3 claude; do
  command -v "$need" >/dev/null || echo "Note: '$need' is not on your PATH; claude-account needs it." >&2
done

dest="$BIN_DIR/claude-account"
if [[ -L "$dest" ]]; then
  echo "$dest is a symlink (installed from a clone?). Update it with: claude-account update" >&2
  exit 1
fi
mkdir -p "$BIN_DIR"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
# CLAUDE_ACCOUNT_SOURCE: install from a local file instead (used by the tests).
if [[ -n "${CLAUDE_ACCOUNT_SOURCE:-}" ]]; then
  cp "$CLAUDE_ACCOUNT_SOURCE" "$tmp"
else
  curl -fsSL "$REPO_RAW/bin/claude-account" -o "$tmp"
fi
bash -n "$tmp" || { echo "Downloaded script is not valid; nothing installed." >&2; exit 1; }
chmod 755 "$tmp"
mv "$tmp" "$dest"
trap - EXIT
echo "Installed $("$dest" --version) to ${dest/#$HOME/~}"

shell="$(basename "${SHELL:-bash}")"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    if [[ "$shell_edits" == 1 ]]; then
      case "$shell" in
        zsh) rc="${ZDOTDIR:-$HOME}/.zshrc" ;;
        bash) [[ "$(uname)" == Darwin ]] && rc="$HOME/.bash_profile" || rc="$HOME/.bashrc" ;;
        fish) rc="" ;;
        *) rc="" ;;
      esac
      if [[ "$shell" == fish ]]; then
        fish -c "fish_add_path -U $(printf %q "$BIN_DIR")" 2>/dev/null && echo "Added ${BIN_DIR/#$HOME/~} to your fish PATH"
      elif [[ -n "$rc" ]]; then
        if ! grep -qF "# claude-account PATH" "$rc" 2>/dev/null; then
          printf '\nexport PATH="%s:$PATH"  # claude-account PATH\n' "$BIN_DIR" >> "$rc"
          echo "Added ${BIN_DIR/#$HOME/~} to PATH in ${rc/#$HOME/~}"
        fi
      else
        echo "Add ${BIN_DIR} to your PATH." >&2
      fi
    else
      echo "Note: ${BIN_DIR} is not on your PATH." >&2
    fi
    ;;
esac

if [[ "$shell_edits" == 1 ]]; then
  "$dest" setup-shell || true
fi
if [[ "$commands" == 1 ]]; then
  "$dest" install-command || true
fi

cat <<EOF

Next:
  claude-account list           your current login shows up as "main"
  claude-account add work       add another account (sign in when the browser opens)
  claude-account switch work    move the conversation you are in to it

Open a new terminal (or source your shell profile) to pick up the changes.
EOF
