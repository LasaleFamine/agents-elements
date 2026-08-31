# Changelog

All notable changes to this project are documented here.

## [Unreleased]

### Added
- **Configurable staleness** — pick how many days of inactivity make a session stale
  (1–90) from the Sessions filter bar. The choice is remembered and applied live, with no
  rescan, and the Overview health row follows it.
- **Batch delete** — ⌘/⇧-click (or *Select all*) to select several sessions and move them
  to the Trash in one step. The right-hand pane summarises what's selected (size, tokens,
  estimated cost, projects) before you confirm; live sessions are always held back.
- **Filter sessions by project** — scope the list to one project, keyed by working
  directory so same-named checkouts stay distinct.
- Right-click menu on the session list (Reveal in Finder / Move to Trash).
- `--selftest-sessions`, a read-only CLI check of the session filters and batch-delete targets.
- `--scan-detail`, a deterministic per-session dump for diffing scanner changes.

### Changed
- **Startup is ~100× faster.** Scanning the session corpus went from ~27s to ~0.2s on a
  400MB corpus. The JSONL parsers now work on raw UTF-8 bytes (`memchr`/`memmem`) instead
  of Swift `String` search — `range(of:)` and `contains` over hundreds of megabytes *were*
  the entire cost — and only the handful of lines carrying data we surface are parsed as
  JSON. Transcripts are also parsed in parallel across cores and read via memory mapping.
- **Loading is staged.** The light inventory (skills, subagents, commands, plugins, MCP,
  hooks, plans, tasks) is scanned and shown first, so the window has real content while the
  transcript corpus is still being read; the Sessions view says so while it waits.

## [1.0.1] — 2026-06-14

Docs and release tooling — no changes to app behavior.

### Added
- `Tools/release.sh` — one-command release: bumps the version, updates this changelog, tags,
  and pushes; CI then builds the `.app`, zips it, and publishes the GitHub Release.
- Tag-triggered release CI job that attaches `AgentsElements-<version>.zip` to the release.

### Changed
- Clearer first-launch / Gatekeeper instructions for macOS 15 (quarantine removal and the
  System Settings → Privacy & Security → Open Anyway path), in the README and on the release page.
- GitHub Releases now lead with install instructions (prepended to the changelog in CI).
- Bumped `actions/checkout` to v5 (Node 24).

## [1.0.0] — 2026-06-14

First public release. Designed and built end-to-end by an AI agent (Claude, in Claude Code).

### Added
- **Inventory** of every agent element across **Claude Code (`~/.claude`)** and
  **Codex (`~/.codex`)**: skills, subagents, slash commands, plugins, MCP servers, hooks.
- **Provider switcher** (All · Claude · Codex) and per-item provider badges.
- **Sessions** view — live / resumable / stale, with token usage, recall commands, Reveal
  in Finder, and guard-railed cleanup to the Trash.
- **Insights** — token & cost analytics across both agents (spend by project and model,
  Claude and GPT side by side) with an activity heatmap.
- **Hooks / automation audit** — hooks by event, Codex command rules, and `~/.claude`
  sweep markers.
- **Relationships** — "who can use what" across subagents, plugins, and projects.
- **Markdown previews** for SKILL.md / agent / command / plan bodies, with a Rendered/Raw toggle.
- **Manage plugins & skills** — enable/disable from the UI, path-locked and backed up.
- **Codex coverage** — config-driven trust levels, command rules, best-effort live detection,
  and `codex resume` recall.
- **Menu-bar extra**, **Welcome** and **Help/About** sheets, and a native app icon.
- Distribution: `./build.sh release --dist` produces a release zip.
