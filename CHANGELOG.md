# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.4.0] - 2026-10-12

### Added
- Per-folder accounts: `pin <name|main>` writes a `.claude-account` file, and
  plain `claude` in that folder or any subfolder starts on that account. The
  nearest pin wins; precedence is `CLAUDE_CONFIG_DIR`, pin, default, `main`.
  Inside a git repository the file is added to `.git/info/exclude`. `pin`
  shows the active pin and `pin --clear` removes it.
- `whoami`, `refresh` and `handoff codex` follow the folder's pin.
- CI installs fish and zsh on Linux so the shell-hook tests run for all three
  shells.

## [0.3.0] - 2026-10-12

### Added
- Codex per account: `codex-login <name>`, `codex <name>`, `add --codex`.
  Each account gets its own `CODEX_HOME` with shared configuration;
  `handoff codex` uses the session's account's Codex login (or `--as <name>`),
  and `list` shows each Codex email.
- Private history: `add --private` and `private <name> [--off]`. A private
  account keeps its conversations and memory to itself; handing one off
  deliberately copies it to the target and says so.
- `switch` restarts the session in its own tab in Terminal.app and iTerm2
  (macOS), not only in tmux.
- One-line installer (`install.sh`): installs the script, adds `PATH`, the
  default-account hook and the slash commands; `--no-shell`, `--no-commands`,
  `--bin-dir`.
- `update`: updates the script (or `git pull` for a clone) and the slash
  commands.
- Outdated `/handoff` and `/switch` are detected and flagged; `install-command`
  now updates its own files without `--force`.

### Fixed
- A conversation that existed in two histories was listed twice and broke
  `brief`/`handoff` for it.
- The second confirmation prompt in `switch` no longer appears after the
  first was answered, and no longer crashes without input.

## [0.2.0] - 2026-10-12

### Added
- `switch <account|main> [id]`: continue the current conversation on another
  account. Inside tmux (including desktop apps that host tabs in tmux) the same
  tab restarts in place with its original flags, hooks and MCP config;
  otherwise the open session is closed and resumed in the calling terminal.
- `/switch <account>` slash command, installed by `install-command`.
- `default [name|main]`, plus `--default` on `use` and `switch`: choose the
  account plain `claude` starts on.
- `setup-shell [--remove] [--shell zsh|bash|fish]` and `shell-init`: a guarded
  hook that makes plain `claude` follow the default. Offered automatically the
  first time a default is set; the default is read on every call, so changing
  it needs no reload.
- "Tried and rejected" section in handoff briefs (`brief`, `handoff --brief`,
  `refresh`, `/handoff`): approaches that were dropped, with the reason, so the
  next session or Codex does not repeat them.
- `whoami`: the account the current shell or Claude session is on, and the one
  new sessions start on.
- `--version`.

### Fixed
- `help` crashed when `$EDITOR` was unset.
- `remove` crashed when its confirmation prompt got no input.
- A failed in-place switch now cleans up its temporary restart scripts.

## [0.1.0] - 2026-10-11

### Added
- Multiple Claude Code accounts side by side, each with its own login;
  settings, skills, plugins, MCP servers, memory and history shared.
- `add`, `use`, `main`, `login`, `list`, `remove`, `sessions`.
- `handoff <account|main> [--fork]`: resume a conversation on another account,
  refusing while it is still open.
- `handoff <account|main|codex> --brief`, `refresh` and `brief`: start a fresh
  session from a compact, repository-aware handoff brief, with `--edit`,
  `--from`, `--model` and `--no-repo`.
- `/handoff` slash command via `install-command`; `save-brief`, `briefs`.
- Secret redaction in condensed transcripts.

[Unreleased]: https://github.com/orvi2014/claude-account/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/orvi2014/claude-account/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/orvi2014/claude-account/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/orvi2014/claude-account/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/orvi2014/claude-account/releases/tag/v0.1.0
