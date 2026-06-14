import Foundation
import Observation

/// Single source of truth for the UI. Scans off the main actor, exposes the snapshot
/// and computed rollups, and performs guard-railed session cleanup.
@MainActor
@Observable
final class ElementsStore {
    private(set) var snapshot = Snapshot()
    private(set) var isLoading = false
    private(set) var lastRefresh: Date?

    /// Active provider filter for the whole UI (nil = All).
    var providerFilter: Provider?

    private func scoped<T>(_ items: [T], _ provider: (T) -> Provider) -> [T] {
        guard let f = providerFilter else { return items }
        return items.filter { provider($0) == f }
    }

    // Convenience accessors (provider-filtered)
    var skills: [Skill] { scoped(snapshot.skills) { $0.provider } }
    var subagents: [Subagent] { scoped(snapshot.subagents) { $0.provider } }
    var commands: [SlashCommand] { scoped(snapshot.commands) { $0.provider } }
    var plugins: [PluginInfo] { scoped(snapshot.plugins) { $0.provider } }
    var marketplaces: [MarketplaceInfo] { snapshot.marketplaces }
    var mcp: [MCPServer] { scoped(snapshot.mcp) { $0.provider } }
    var hooks: [HookInfo] { scoped(snapshot.hooks) { $0.provider } }
    var sessions: [Session] { scoped(snapshot.sessions) { $0.provider } }
    var plans: [PlanDoc] { scoped(snapshot.plans) { $0.provider } }
    var tasks: [BgTask] { scoped(snapshot.tasks) { $0.provider } }
    var projects: [ProjectInfo] { scoped(snapshot.projects) { $0.provider } }
    var sweeps: [SweepMarker] { snapshot.sweeps }
    /// Codex command guardrails (hidden when the UI is filtered to Claude only).
    var codexRules: [CodexRule] { providerFilter == .claude ? [] : snapshot.codexRules }

    /// Providers that actually have data on disk (for the switcher).
    var availableProviders: [Provider] {
        Provider.allCases.filter { p in
            snapshot.skills.contains { $0.provider == p } || snapshot.sessions.contains { $0.provider == p }
        }
    }
    func sessionCount(for provider: Provider) -> Int { snapshot.sessions.filter { $0.provider == provider }.count }

    var liveSessions: [Session] { sessions.filter { $0.state == .live } }
    var staleSessions: [Session] { sessions.filter { $0.state == .stale } }
    var totalSessionBytes: Int { sessions.reduce(0) { $0 + $1.sizeBytes } }
    var activeFill: Int? { liveSessions.compactMap(\.contextFill).max() }

    // MARK: - Analytics rollups

    struct CostRow: Identifiable, Hashable {
        let id: String
        let label: String
        let cost: Double
        let tokens: Int
    }

    var totalCost: Double { sessions.reduce(0) { $0 + $1.estimatedCost } }
    var totalTokens: Int { sessions.reduce(0) { $0 + $1.totalTokens } }

    func cost(since days: Int) -> Double {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return sessions.filter { $0.lastActivity >= cutoff }.reduce(0) { $0 + $1.estimatedCost }
    }

    var costByProject: [CostRow] {
        var byProject: [String: (Double, Int)] = [:]
        for s in sessions {
            let key = s.projectName.isEmpty ? s.projectDir : s.projectName
            let cur = byProject[key] ?? (0, 0)
            byProject[key] = (cur.0 + s.estimatedCost, cur.1 + s.totalTokens)
        }
        return byProject.map { CostRow(id: $0.key, label: $0.key, cost: $0.value.0, tokens: $0.value.1) }
            .sorted { $0.cost > $1.cost }
    }

    var costByModel: [CostRow] {
        var byModel: [String: (Double, Int)] = [:]
        for s in sessions {
            for u in s.usage {
                let cur = byModel[u.model] ?? (0, 0)
                byModel[u.model] = (cur.0 + Pricing.cost(u), cur.1 + u.total)
            }
        }
        return byModel.map { CostRow(id: $0.key, label: Pricing.shortName($0.key), cost: $0.value.0, tokens: $0.value.1) }
            .sorted { $0.cost > $1.cost }
    }

    /// Tokens summed per calendar day (by last activity) — for the activity heatmap.
    var tokensByDay: [Date: Int] {
        var byDay: [Date: Int] = [:]
        let cal = Calendar.current
        for s in sessions where s.lastActivity > .distantPast {
            let day = cal.startOfDay(for: s.lastActivity)
            byDay[day, default: 0] += s.totalTokens
        }
        return byDay
    }

    func count(for category: Category) -> Int {
        switch category {
        case .overview: return 0
        case .insights: return 0
        case .skills: return skills.count
        case .subagents: return subagents.count
        case .commands: return commands.count
        case .plugins: return plugins.count
        case .mcp: return mcp.count
        case .hooks: return hooks.count
        case .sessions: return sessions.count
        case .plans: return plans.count
        case .tasks: return tasks.count
        case .projects: return projects.count
        case .relationships: return 0
        }
    }

    func refresh() async {
        isLoading = true
        let snap = await Task.detached(priority: .userInitiated) {
            ScannerEngine.scanEverything()
        }.value
        snapshot = snap
        lastRefresh = Date()
        isLoading = false
    }

    /// Synchronous load — used by the offscreen `--render` snapshot path.
    func loadSynchronously() {
        snapshot = ScannerEngine.scanEverything()
        lastRefresh = Date()
    }

    /// Loads a fully synthetic snapshot — used by `--render … --demo` so published
    /// screenshots never contain real ~/.claude or ~/.codex data.
    func loadDemo() {
        snapshot = DemoData.snapshot
        lastRefresh = Date()
    }

    // MARK: - Cleanup (guard-railed, recoverable via Trash)

    enum CleanupError: LocalizedError {
        case live, notAllowed, failed(String)
        var errorDescription: String? {
            switch self {
            case .live: return "Live sessions cannot be deleted."
            case .notAllowed: return "Refusing to delete a path outside ~/.claude/projects."
            case .failed(let m): return m
            }
        }
    }

    @discardableResult
    func trash(_ session: Session) throws -> Bool {
        guard session.state != .live else { throw CleanupError.live }
        let allowed = [Paths.projects.path + "/", Paths.codexSessions.path + "/"]
        guard allowed.contains(where: { session.path.hasPrefix($0) }), session.path.hasSuffix(".jsonl") else {
            throw CleanupError.notAllowed
        }
        do {
            try FS.fm.trashItem(at: URL(fileURLWithPath: session.path), resultingItemURL: nil)
            return true
        } catch {
            throw CleanupError.failed(error.localizedDescription)
        }
    }

    /// Moves the given sessions to the Trash. Returns count actually removed.
    @discardableResult
    func trash(_ targets: [Session]) -> Int {
        var removed = 0
        for s in targets where (try? trash(s)) == true { removed += 1 }
        return removed
    }

    // MARK: - Config mutations (enable/disable plugins & skills)

    /// The marketplace-qualified key Claude/Codex use in their config files.
    private func pluginKey(_ p: PluginInfo) -> String {
        p.marketplace.isEmpty ? p.name : "\(p.name)@\(p.marketplace)"
    }

    func setEnabled(plugin: PluginInfo, to enabled: Bool) throws {
        switch plugin.provider {
        case .claude: try Mutator.setClaudePluginEnabled(key: pluginKey(plugin), enabled: enabled)
        case .codex:  try Mutator.setCodexPluginEnabled(key: pluginKey(plugin), enabled: enabled)
        }
    }

    /// Only Codex supports a per-skill toggle (`[[skills.config]]`); Claude skills are always on.
    func canToggle(skill: Skill) -> Bool { skill.provider == .codex }

    func setEnabled(skill: Skill, to enabled: Bool) throws {
        guard skill.provider == .codex else { throw Mutator.MutationError.unsupported }
        try Mutator.setCodexSkillEnabled(path: skill.path, enabled: enabled)
    }
}
