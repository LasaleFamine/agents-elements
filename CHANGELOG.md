# Changelog

All notable changes to this project are documented here.

## [1.0.1] — 2026-06-14

- 

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
