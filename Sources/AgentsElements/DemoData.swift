import Foundation

/// A fully synthetic snapshot used only to render the README screenshots, so published
/// art never contains anything from a real ~/.claude or ~/.codex. Nothing here touches the
/// filesystem. Invoked via `--render <png> <mode> --demo`.
enum DemoData {
    private static func daysAgo(_ d: Double) -> Date { Date().addingTimeInterval(-d * 86_400) }

    private static func use(_ model: String, _ input: Int, _ output: Int, _ cacheRead: Int) -> ModelUsage {
        ModelUsage(model: model, input: input, output: output, cacheRead: cacheRead, cacheCreate: 0)
    }

    // Fictional projects — no resemblance to anything real.
    private static let projects = ["acme-storefront", "nimbus-weather", "inkwell-blog",
                                   "ledger-cli", "atlas-dashboard"]

    private static func sess(_ id: String, _ name: String?, _ project: String, _ model: String,
                             msgs: Int, days: Double, input: Int, output: Int, cacheRead: Int,
                             prompt: String, state: SessionState = .resumable, fill: Int? = nil,
                             provider: Provider = .claude) -> Session {
        let cwd = "/Users/dev/code/\(project)"
        return Session(
            id: id, name: name, cwd: cwd, projectDir: project, projectName: project,
            gitBranch: "main", version: "1.0.0", model: model, messageCount: msgs,
            firstActivity: daysAgo(days + 0.1), lastActivity: daysAgo(days),
            lastPrompt: prompt, sizeBytes: msgs * 4_200,
            path: "\(cwd)/.session/\(id).jsonl",
            state: state, pid: state == .live ? 4242 : nil,
            status: state == .live ? (fill != nil ? "busy" : "idle") : nil,
            contextFill: fill, subagentRuns: msgs / 9,
            usage: [use(model, input, output, cacheRead)], provider: provider)
    }

    static let snapshot: Snapshot = {
        var s = Snapshot()

        // Skills — one rich Markdown body so the markdown poster has something to show.
        let releaseBody = """
        # Release Notes Generator

        Generate clean, grouped release notes straight from your merged pull requests.

        ## Usage

        Run it right after tagging a release:

        ```bash
        release-notes --since v1.2.0 --out CHANGELOG.md
        ```

        ## What it does

        1. Collects PRs merged since the last tag.
        2. Groups them by label — `feat`, `fix`, `chore`.
        3. Writes Markdown with a section per group.

        - Understands **Conventional Commits**
        - Links every entry back to its PR
        - Skips `chore:` and `ci:` noise by default

        > Tip: pass `--draft` to preview the notes without writing the file.
        """
        s.skills = [
            Skill(id: "d1", name: "release-notes", description: "Draft release notes from merged PRs.",
                  source: .personal, path: "~/.claude/skills/release-notes/SKILL.md",
                  license: "MIT", body: releaseBody, enabled: true, provider: .claude),
            Skill(id: "d2", name: "api-scaffold", description: "Scaffold a typed REST endpoint with tests.",
                  source: .plugin("devkit"), path: "skills/api-scaffold/SKILL.md",
                  license: nil, body: "# api-scaffold\n\nScaffold an endpoint, handler, and test.",
                  enabled: true, provider: .claude),
            Skill(id: "d3", name: "commit-helper", description: "Write Conventional Commit messages.",
                  source: .personal, path: "skills/commit-helper/SKILL.md",
                  license: nil, body: "# commit-helper", enabled: true, provider: .claude),
            Skill(id: "d4", name: "spreadsheets", description: "Read and edit spreadsheets.",
                  source: .builtin, path: "~/.codex/skills/spreadsheets/SKILL.md",
                  license: nil, body: "# spreadsheets", enabled: false, provider: .codex),
            Skill(id: "d5", name: "image-gen", description: "Generate images from a prompt.",
                  source: .builtin, path: "~/.codex/skills/image-gen/SKILL.md",
                  license: nil, body: "# image-gen", enabled: true, provider: .codex),
            Skill(id: "d6", name: "test-writer", description: "Generate unit tests for changed files.",
                  source: .plugin("devkit"), path: "skills/test-writer/SKILL.md",
                  license: nil, body: "# test-writer", enabled: true, provider: .claude),
        ]

        // Subagents — varied tool access for the Relationships poster.
        s.subagents = [
            Subagent(id: "a1", name: "code-reviewer", description: "Reviews diffs against house style.",
                     tools: ["Read", "Grep", "Glob"], model: nil, source: .personal,
                     path: "agents/code-reviewer.md", body: "", scope: nil),
            Subagent(id: "a2", name: "docs-writer", description: "Drafts and updates documentation.",
                     tools: ["Read", "Write", "Edit"], model: nil, source: .plugin("devkit"),
                     path: "agents/docs-writer.md", body: "", scope: nil),
            Subagent(id: "a3", name: "perf-profiler", description: "Profiles hot paths and suggests fixes.",
                     tools: [], model: "claude-opus-4-8", source: .personal,
                     path: "agents/perf-profiler.md", body: "", scope: "atlas-dashboard"),
            Subagent(id: "a4", name: "migration-runner", description: "Plans and runs schema migrations.",
                     tools: ["Read", "Bash", "Edit"], model: nil, source: .personal,
                     path: "agents/migration-runner.md", body: "", scope: "ledger-cli"),
            Subagent(id: "a5", name: "release-captain", description: "Coordinates a tagged release.",
                     tools: ["Read", "Bash"], model: nil, source: .plugin("shipit"),
                     path: "agents/release-captain.md", body: "", scope: nil),
        ]

        s.commands = [
            SlashCommand(id: "c1", name: "review", description: "Run a structured code review.",
                         source: .plugin("devkit"), path: "commands/review.md", body: "", argumentHint: "[path]"),
            SlashCommand(id: "c2", name: "ship/release", description: "Cut a release.",
                         source: .plugin("shipit"), path: "commands/ship/release.md", body: "", argumentHint: nil),
            SlashCommand(id: "c3", name: "scaffold", description: "Scaffold a module.",
                         source: .personal, path: "commands/scaffold.md", body: "", argumentHint: "<name>"),
        ]

        s.plugins = [
            PluginInfo(id: "devkit@community", name: "devkit", marketplace: "community",
                       description: "Scaffolding, review and test skills.", version: "2.3.0",
                       enabled: true, scope: "user", installedAt: "2026-05-02", installPath: "~/.claude/plugins/devkit",
                       skillCount: 3, agentCount: 1, commandCount: 1, hookCount: 2, provider: .claude),
            PluginInfo(id: "shipit@community", name: "shipit", marketplace: "community",
                       description: "Release automation.", version: "1.1.0",
                       enabled: true, scope: "user", installedAt: "2026-05-20", installPath: "~/.claude/plugins/shipit",
                       skillCount: 0, agentCount: 1, commandCount: 1, hookCount: 0, provider: .claude),
            PluginInfo(id: "browser@openai-bundled", name: "browser", marketplace: "openai-bundled",
                       description: "In-app browser control.", version: nil,
                       enabled: true, scope: "user", installedAt: nil, installPath: nil,
                       skillCount: 0, agentCount: 0, commandCount: 0, hookCount: 0, provider: .codex),
            PluginInfo(id: "documents@openai-primary", name: "documents", marketplace: "openai-primary",
                       description: "Read and write documents.", version: nil,
                       enabled: false, scope: "user", installedAt: nil, installPath: nil,
                       skillCount: 0, agentCount: 0, commandCount: 0, hookCount: 0, provider: .codex),
        ]

        s.mcp = [
            MCPServer(id: "m1", name: "filesystem", scope: "global", type: "stdio", command: "mcp-fs", provider: .claude),
            MCPServer(id: "m2", name: "github", scope: "global", type: "stdio", command: "mcp-github", provider: .claude),
            MCPServer(id: "m3", name: "serena", scope: "global", type: "stdio", command: "serena", provider: .codex),
        ]

        s.hooks = [
            HookInfo(id: "h1", event: "PreToolUse", matcher: "Bash", command: "guard.sh", source: .plugin("devkit"), provider: .claude),
            HookInfo(id: "h2", event: "PostToolUse", matcher: "Edit", command: "format.sh", source: .personal, provider: .claude),
            HookInfo(id: "h3", event: "Stop", matcher: nil, command: "notify.sh", source: .plugin("shipit"), provider: .claude),
        ]

        s.codexRules = [
            CodexRule(id: "r1", pattern: "git add", decision: "allow", file: "default.rules"),
            CodexRule(id: "r2", pattern: "git commit", decision: "allow", file: "default.rules"),
            CodexRule(id: "r3", pattern: "rm -rf", decision: "ask", file: "default.rules"),
        ]

        // Sessions across projects, models and days (drives Insights + heatmap + Overview).
        s.sessions = [
            sess("s1", "Checkout refactor", "acme-storefront", "claude-opus-4-8",
                 msgs: 48, days: 0.02, input: 180_000, output: 42_000, cacheRead: 1_200_000,
                 prompt: "Refactor the checkout flow into smaller steps", state: .live, fill: 62),
            sess("s2", "Forecast widget", "nimbus-weather", "gpt-5.5",
                 msgs: 31, days: 0.05, input: 90_000, output: 28_000, cacheRead: 600_000,
                 prompt: "Add a 7-day forecast widget to the home screen", state: .live, fill: 38, provider: .codex),
            sess("s3", "Dark mode", "inkwell-blog", "claude-sonnet-4-6",
                 msgs: 22, days: 1, input: 70_000, output: 19_000, cacheRead: 400_000,
                 prompt: "Add a dark mode toggle and persist the choice"),
            sess("s4", "Flaky tests", "ledger-cli", "claude-opus-4-8",
                 msgs: 64, days: 2, input: 220_000, output: 55_000, cacheRead: 1_500_000,
                 prompt: "Track down and fix the flaky balance tests"),
            sess("s5", "Charts pass", "atlas-dashboard", "claude-opus-4-8",
                 msgs: 40, days: 3, input: 150_000, output: 38_000, cacheRead: 900_000,
                 prompt: "Polish the analytics charts and tooltips"),
            sess("s6", "API pagination", "acme-storefront", "gpt-5.5",
                 msgs: 27, days: 5, input: 80_000, output: 21_000, cacheRead: 500_000,
                 prompt: "Add cursor pagination to the products API", provider: .codex),
            sess("s7", "Migration", "ledger-cli", "claude-sonnet-4-6",
                 msgs: 18, days: 6, input: 60_000, output: 14_000, cacheRead: 300_000,
                 prompt: "Write the migration for the new accounts table"),
            sess("s8", "Onboarding", "atlas-dashboard", "claude-opus-4-8",
                 msgs: 52, days: 9, input: 170_000, output: 44_000, cacheRead: 1_100_000,
                 prompt: "Build the first-run onboarding flow"),
            sess("s9", "SEO meta", "inkwell-blog", "claude-sonnet-4-6",
                 msgs: 14, days: 12, input: 40_000, output: 9_000, cacheRead: 220_000,
                 prompt: "Generate SEO meta tags per post"),
            sess("s10", "CLI colors", "ledger-cli", "claude-opus-4-8",
                 msgs: 20, days: 16, input: 90_000, output: 22_000, cacheRead: 500_000,
                 prompt: "Add colored output and a --no-color flag", state: .stale),
            sess("s11", "Cart bug", "acme-storefront", "claude-opus-4-8",
                 msgs: 33, days: 20, input: 120_000, output: 30_000, cacheRead: 700_000,
                 prompt: "Fix the cart total rounding bug", state: .stale),
        ]

        // Projects derived from the sessions.
        var byProject: [String: [Session]] = [:]
        for sess in s.sessions { byProject[sess.projectName, default: []].append(sess) }
        s.projects = projects.compactMap { name in
            guard let ss = byProject[name] else { return nil }
            return ProjectInfo(id: name, name: "/Users/dev/code/\(name)", path: "/Users/dev/code/\(name)",
                               sessionCount: ss.count, liveCount: ss.filter { $0.state == .live }.count,
                               lastActivity: ss.map(\.lastActivity).max() ?? Date(),
                               mcpServers: name == "atlas-dashboard" ? ["filesystem", "github"] : [],
                               trustLevel: name == "ledger-cli" ? "trusted" : nil,
                               provider: name == "nimbus-weather" ? .codex : .claude)
        }

        s.plans = [
            PlanDoc(id: "p1", name: "checkout-redesign.md", title: "Checkout redesign",
                    path: "~/.claude/plans/checkout-redesign.md", modified: daysAgo(1), sizeBytes: 4_800),
            PlanDoc(id: "p2", name: "migration-plan.md", title: "Accounts migration",
                    path: "~/.claude/plans/migration-plan.md", modified: daysAgo(6), sizeBytes: 3_100),
        ]

        s.sweeps = [
            SweepMarker(id: "w1", name: "Transcript cleanup", owner: "Claude Code",
                        path: "~/.claude/.last-cleanup", timestamp: daysAgo(1),
                        detail: "Deletes old session transcripts under ~/.claude/projects."),
            SweepMarker(id: "w2", name: "Auto-update", owner: "Claude Code",
                        path: "~/.claude/.last-update-result.json", timestamp: daysAgo(4),
                        detail: "Updated CLI 0.9.0 → 1.0.0."),
        ]

        return s
    }()
}
