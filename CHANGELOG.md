# Changelog

## 0.1.1 (2026-03-02)

### Bug Fixes

* Fix CLI binary resolution for .app bundles — gh, tmux, mutagen, pandoc now found via absolute path lookup instead of PATH-dependent /usr/bin/env
* Fix terminal dying after ~2 seconds on resume — reconciler was clearing tmuxLink on cards mid-launch before the tmux session was visible
* Fix cached terminal frame to avoid SIGWINCH on reparent (zero-frame resize)
* Fast activity refresh path for immediate hook event processing

## 0.1.0 (2026-03-01)

Initial release.

### Features

* Kanban board for managing Claude Code sessions
* Launch, resume, and monitor Claude Code agents from a visual board
* Automatic session discovery and linking
* Remote server support with mutagen file sync
* Claude Code hook integration for real-time session tracking
* Fork and checkpoint session management
* Deep search across session transcripts
* Worktree-aware branch detection
* System tray with session notifications
