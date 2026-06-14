import Foundation

/// Sidebar sections. Title + SF Symbol live here (Foundation-only); the accent color
/// is added as a SwiftUI extension in the theme layer.
enum Category: String, CaseIterable, Identifiable, Hashable {
    case overview, insights, skills, subagents, commands, plugins, mcp, hooks, sessions, plans, tasks, projects, relationships

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .insights: return "Insights"
        case .skills: return "Skills"
        case .subagents: return "Subagents"
        case .commands: return "Commands"
        case .plugins: return "Plugins"
        case .mcp: return "MCP Servers"
        case .hooks: return "Hooks"
        case .sessions: return "Sessions"
        case .plans: return "Plans"
        case .tasks: return "Tasks"
        case .projects: return "Projects"
        case .relationships: return "Relationships"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .insights: return "chart.bar.xaxis"
        case .skills: return "wand.and.stars"
        case .subagents: return "person.2.fill"
        case .commands: return "terminal.fill"
        case .plugins: return "puzzlepiece.extension.fill"
        case .mcp: return "server.rack"
        case .hooks: return "bolt.horizontal.fill"
        case .sessions: return "bubble.left.and.bubble.right.fill"
        case .plans: return "doc.text.fill"
        case .tasks: return "checklist"
        case .projects: return "folder.fill"
        case .relationships: return "point.3.connected.trianglepath.dotted"
        }
    }

    /// Whether this section shows a count badge in the sidebar.
    var showsCount: Bool { self != .overview && self != .relationships && self != .insights }
}

/// Which agent toolchain an element belongs to.
enum Provider: String, CaseIterable, Hashable, Sendable, Identifiable {
    case claude, codex

    var id: String { rawValue }
    var label: String { self == .claude ? "Claude" : "Codex" }
    var glyph: String { self == .claude ? "sparkle" : "chevron.left.forwardslash.chevron.right" }
}

/// Where an element comes from — drives the source badge in the UI.
enum Source: Hashable, Sendable {
    case personal
    case plugin(String)
    case builtin

    var label: String {
        switch self {
        case .personal: return "Personal"
        case .plugin(let n): return n
        case .builtin: return "Built-in"
        }
    }

    var isPlugin: Bool { if case .plugin = self { return true } else { return false } }
}

struct Skill: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String
    let source: Source
    let path: String
    let license: String?
    let body: String
    var enabled: Bool = true   // Codex can disable skills via config; Claude skills are always on
    var provider: Provider = .claude
}

struct Subagent: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String
    let tools: [String]
    let model: String?
    let source: Source
    let path: String
    let body: String
    let scope: String?        // project scope derived from filename, e.g. "lualtek/console"
    var provider: Provider = .claude

    /// `true` when the agent declares access to every tool (`tools: *` or unset).
    var hasAllTools: Bool { tools.isEmpty || tools.contains("*") }
}

struct SlashCommand: Identifiable, Hashable, Sendable {
    let id: String
    let name: String          // namespaced, e.g. "lualtek/console/plan-issue"
    let description: String?
    let source: Source
    let path: String
    let body: String
    let argumentHint: String?
    var provider: Provider = .claude
}

struct PluginInfo: Identifiable, Hashable, Sendable {
    let id: String            // "name@marketplace"
    let name: String
    let marketplace: String
    let description: String?
    let version: String?
    let enabled: Bool
    let scope: String?
    let installedAt: String?
    let installPath: String?
    let skillCount: Int
    let agentCount: Int
    let commandCount: Int
    let hookCount: Int
    var provider: Provider = .claude

    var contributes: Int { skillCount + agentCount + commandCount + hookCount }
}

struct MarketplaceInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let sourceType: String    // github / directory
    let location: String
    let lastUpdated: String?
    let catalogCount: Int
}

struct MCPServer: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let scope: String         // "global" or a project path
    let type: String?
    let command: String?
    var provider: Provider = .claude
}

struct HookInfo: Identifiable, Hashable, Sendable {
    let id: String
    let event: String
    let matcher: String?
    let command: String
    let source: Source
    var provider: Provider = .claude
}

/// A Codex command-approval guardrail from `~/.codex/rules/*.rules`
/// (`prefix_rule(pattern=[...], decision="allow")`). Codex's analogue to a hook.
struct CodexRule: Identifiable, Hashable, Sendable {
    let id: String
    let pattern: String       // matched command prefix, e.g. "git commit"
    let decision: String      // allow / deny / ask
    let file: String          // source .rules filename

    var allows: Bool { decision.lowercased() == "allow" }
}

enum SessionState: String, Sendable, Hashable {
    case live, resumable, stale
}

struct Session: Identifiable, Hashable, Sendable {
    let id: String            // session uuid
    let name: String?
    let cwd: String
    let projectDir: String    // encoded project dir name
    let projectName: String   // last path component of cwd
    let gitBranch: String?
    let version: String?
    let model: String?
    let messageCount: Int
    let firstActivity: Date?
    let lastActivity: Date
    let lastPrompt: String?
    let sizeBytes: Int
    let path: String
    var state: SessionState
    let pid: Int?
    let status: String?       // "busy"/"idle" when live
    let contextFill: Int?     // % when this is the active session
    let subagentRuns: Int     // nested subagent sidechain transcripts this session spawned
    let usage: [ModelUsage]   // token usage per model, aggregated from the transcript
    var provider: Provider = .claude

    var inputTokens: Int { usage.reduce(0) { $0 + $1.input } }
    var outputTokens: Int { usage.reduce(0) { $0 + $1.output } }
    var cacheReadTokens: Int { usage.reduce(0) { $0 + $1.cacheRead } }
    var cacheCreateTokens: Int { usage.reduce(0) { $0 + $1.cacheCreate } }
    var totalTokens: Int { usage.reduce(0) { $0 + $1.total } }
    var estimatedCost: Double { Pricing.cost(usage) }
}

/// A filesystem marker showing an automated sweep/cleanup of ~/.claude.
struct SweepMarker: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let owner: String         // inferred tool that writes it
    let path: String
    let timestamp: Date?
    let detail: String?
}

struct PlanDoc: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let title: String?
    let path: String
    let modified: Date
    let sizeBytes: Int
    var provider: Provider = .claude
}

struct BgTask: Identifiable, Hashable, Sendable {
    let id: String
    let path: String
    let modified: Date
    let fileCount: Int
    var provider: Provider = .claude
}

struct ProjectInfo: Identifiable, Hashable, Sendable {
    let id: String            // encoded dir
    let name: String          // cwd
    let path: String
    let sessionCount: Int
    let liveCount: Int
    let lastActivity: Date
    let mcpServers: [String]
    var trustLevel: String? = nil   // Codex per-project trust ("trusted"); nil for Claude
    var provider: Provider = .claude

    var displayName: String { (name as NSString).lastPathComponent }
}

/// One immutable scan result, produced off the main actor and handed to the store.
struct Snapshot: Sendable {
    var skills: [Skill] = []
    var subagents: [Subagent] = []
    var commands: [SlashCommand] = []
    var plugins: [PluginInfo] = []
    var marketplaces: [MarketplaceInfo] = []
    var mcp: [MCPServer] = []
    var hooks: [HookInfo] = []
    var sessions: [Session] = []
    var plans: [PlanDoc] = []
    var tasks: [BgTask] = []
    var projects: [ProjectInfo] = []
    var sweeps: [SweepMarker] = []
    var codexRules: [CodexRule] = []
}
