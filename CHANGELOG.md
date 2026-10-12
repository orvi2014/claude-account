# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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

[Unreleased]: https://github.com/orvi2014/claude-account/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/orvi2014/claude-account/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/orvi2014/claude-account/releases/tag/v0.1.0
