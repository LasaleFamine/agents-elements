# Contributing

Thanks for your interest! A few things make this project unusual, so please read this first.

## This app was built by an AI agent

Agents Elements was designed and written end-to-end by **Claude, an AI agent**, working in
Claude Code, with a human providing direction and review. Contributions from humans and AI
agents are both welcome — please keep the code style, naming, and structure consistent with
what's already there.

## Building

No full Xcode required — the **Command Line Tools** are enough. There are **no third-party
dependencies**; it builds offline.

```bash
swift build -c release          # compile
./build.sh                      # wrap into AgentsElements.app
./build.sh release --dist       # also produce dist/AgentsElements-<version>.zip
open AgentsElements.app
```

During development:

```bash
swift run AgentsElements
```

## Project layout

| Area | Files |
|---|---|
| Support / models | `Support.swift`, `Models.swift`, `Pricing.swift` |
| Scanners (read-only) | `ScannerEngine.swift`, `SessionScanner.swift`, `CodexScanner.swift` |
| Mutations (the only writer) | `Mutations.swift` |
| Store | `ElementsStore.swift` |
| Views | `RootView`, `OverviewView`, `CatalogViews`, `SessionsView`, `InsightsView`, `HooksAuditView`, `RelationshipsView`, `OnboardingViews`, `MenuBarView`, `Markdown`, `Theme`, `Icon`, `FlowLayout` |

## Verification helpers (no GUI needed)

```bash
swift run AgentsElements -- --scan-dump            # print parsed counts, tokens, cost
swift run AgentsElements -- --selftest-mutations   # dry-run plugin/skill toggles (writes nothing)
swift run AgentsElements -- --render out.png [overview|insights|relationships|markdown|hero|welcome]
```

`--render` uses SwiftUI's `ImageRenderer`, so screenshots work without Screen-Recording
permission. Regenerate the README art with the `docs/*.png` targets.

## Regenerating the app icon

The icon is defined in code (`IconView` in `Icon.swift`) so it never drifts from the in-app
brand. To rebuild `AppIcon.icns`:

```bash
./Tools/make-icon.sh
```

## Safety rules for code that writes to disk

The app is read-only **except** two user-driven actions, and any change here must preserve
these invariants:

- **Session cleanup** routes only `~/.claude/projects/**/*.jsonl` and
  `~/.codex/sessions/**/*.jsonl` to the **Trash** (never a hard delete), never for live sessions.
- **Plugin/skill toggles** go through `Mutator`, which is **path-locked** to
  `~/.claude/settings.json` and `~/.codex/config.toml`, **backs the file up first**
  (`*.agents-elements.bak`), and only flips a boolean or appends a config entry.

Keep all filesystem reads off the main actor and returning `Sendable` value types.
