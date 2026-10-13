# Changelog

hatswap was called **claude-account** until 0.5.0.

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed
- `use <name> --default` typed with `!` inside Claude now saves the default and
  tells you to run `switch`, instead of refusing without doing anything.

## [0.6.0] - 2026-10-13

### Added
- `hatswap exec [--account <name|main>] <command> [args]` runs a command on the
  account a new session would get at that moment (`--account`, then
  `HATSWAP_ACCOUNT`, then the folder pin, then the default). Bots and scripts
  that start `claude -p` per job now follow `hatswap default` without being
  restarted; before, only `claude` typed in a terminal did, through the shell hook.
- `hatswap shim` writes `claude` and `codex` wrappers to
  `~/.claude-accounts/bin` that do the same, for bots that call a fixed path or
  search `PATH`. `shim --remove` deletes them.
- `HATSWAP_ACCOUNT=<name>` keeps one bot on one account.
- `hatswap usage [name…] [--json]`: every account's 5-hour and weekly limits
  and reset times, from the endpoint Claude's `/usage` reads. Read-only, cached
  for 3 minutes; tokens are never printed, stored or refreshed.
- `hatswap statusline --install`: the account and email in Claude Code's status
  line, ahead of any status line you already had (`--remove` restores it).
- `hatswap vscode [name|main|--clear]`: the Claude extension in VS Code or
  Cursor uses that account in this folder, through
  `claudeCode.environmentVariables` in `.vscode/settings.json`.
- `hatswap desktop [name|main]`: Claude Desktop signed in to that account, in
  its own window, with its own profile folder (macOS).
- `rules/`, `output-styles/` and `keybindings.json` are now shared across
  accounts like the rest of `~/.claude`.

### Changed
- `bin` is no longer accepted as an account name (the shims live there), and
  `usage`, `statusline`, `vscode` and `desktop` are reserved.

## [0.5.0] - 2026-10-12

### Changed
- **Renamed to hatswap** (repository `orvi2014/hatswap`, command `hatswap`), to
  avoid confusion with an unrelated project also called claude-account. Old
  GitHub links redirect.
- New names: `.hatswap` pin files, `HATSWAP_DIR`, `HATSWAP_KEEP_AUTH_ENV`,
  `HATSWAP_SWITCH_DELAY`, `HATSWAP_SOURCE`/`HATSWAP_REF` (installer), and
  `# >>> hatswap >>>` / `# hatswap PATH` markers.
- `/handoff` and `/switch` now call `hatswap`; existing copies are flagged as
  outdated until `hatswap install-command` is run.

### Kept compatible
- `claude-account` keeps working: the installer adds it as an alias, and
  `bin/claude-account` in the repository is a stand-in that runs hatswap
  (fetching it once if needed), so `claude-account update` on older installs
  moves them to hatswap.
- The data folder stays `~/.claude-accounts`: Claude Code ties each account's
  Keychain login to that path, so moving it would sign every account out.
- `.claude-account` pins, `CLAUDE_ACCOUNTS_DIR`, `CLAUDE_ACCOUNT_*` variables
  and old hook blocks are still honoured; re-pinning converts a pin file.

### Added
- README sections: upgrading from claude-account, and how hatswap differs from
  other account switchers.
- Demo GIF and how-it-works diagram updated for the new name.

## [0.4.2] - 2026-10-12

### Fixed
- An exported `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN` or
  `CLAUDE_CODE_OAUTH_TOKEN` overrode the account's own login, so every account
  silently used that key. They are now cleared, with a one-line note, whenever
  Claude starts on a named account: `use`, `switch` (including in-place
  restarts), `handoff`, `refresh`, brief writing, and the shell hook for
  defaults and pins. Your shell keeps them; `main` is untouched;
  `CLAUDE_ACCOUNT_KEEP_AUTH_ENV=1` opts out.

## [0.4.1] - 2026-10-12

### Fixed
- Handing off or switching to a shared account whose history link was missing
  (for example, added before `~/.claude/projects` existed) copied the
  conversation into a separate, unmarked history. It now links the shared
  history first.
- "Codex account: main ((not signed in))" double brackets.
- `pin` shows `~` paths.

### Changed
- Demo GIF re-recorded: `list` with Codex logins, `whoami`, `switch`, `pin`
  (inside and outside the pinned folder) and `handoff codex` on the pinned
  account's Codex login.

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

[Unreleased]: https://github.com/orvi2014/hatswap/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/orvi2014/hatswap/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/orvi2014/hatswap/compare/v0.4.2...v0.5.0
[0.4.2]: https://github.com/orvi2014/hatswap/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/orvi2014/hatswap/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/orvi2014/hatswap/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/orvi2014/hatswap/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/orvi2014/hatswap/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/orvi2014/hatswap/releases/tag/v0.1.0
