import Foundation
import Observation

/// Single source of truth for the UI. Scans off the main actor, exposes the snapshot
/// and computed rollups, and performs guard-railed session cleanup.
@MainActor
@Observable
final class ElementsStore {
    private(set) var snapshot = Snapshot()
    private(set) var isLoading = false
    /// True while the transcript corpus is still being read. The light inventory is
    /// already on screen by then, so views that need sessions can say so specifically.
    private(set) var isScanningSessions = false
    private(set) var lastRefresh: Date?

    /// Active provider filter for the whole UI (nil = All).
    var providerFilter: Provider?

    // MARK: - Staleness preference

    /// Thresholds offered in the UI.
    static let staleDayOptions = [1, 3, 7, 14, 30, 60, 90]
    private static let staleDaysKey = "ae.staleDays.v1"

    @ObservationIgnored
    private var _staleDays = (UserDefaults.standard.object(forKey: staleDaysKey) as? Int) ?? 14

    /// Days without activity before a session counts as stale. Persisted, and applied
    /// when sessions are *read* — changing it re-labels everything without a rescan.
    var staleDays: Int {
        get {
            access(keyPath: \.staleDays)
            return _staleDays
        }
        set {
            let clamped = max(1, newValue)
            withMutation(keyPath: \.staleDays) { _staleDays = clamped }
            UserDefaults.standard.set(clamped, forKey: Self.staleDaysKey)
        }
    }

    /// Re-labels resumable/stale against the current `staleDays`. Live is left alone —
    /// a running session is never stale, however old its transcript is.
    private func restaged(_ items: [Session]) -> [Session] {
        let cutoff = Date().addingTimeInterval(-Double(staleDays) * 86_400)
        return items.map { s in
            guard s.state != .live else { return s }
            var s = s
            s.state = s.lastActivity < cutoff ? .stale : .resumable
            return s
        }
    }

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
    var sessions: [Session] { restaged(scoped(snapshot.sessions) { $0.provider }) }
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
    var staleSessions: [Session] { staleSessions(olderThan: staleDays) }

    /// Stale against an arbitrary threshold — independent of the current preference,
    /// so callers can preview what another cut-off would select.
    func staleSessions(olderThan days: Int) -> [Session] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return sessions.filter { $0.state != .live && $0.lastActivity < cutoff }
    }
    var totalSessionBytes: Int { sessions.reduce(0) { $0 + $1.sizeBytes } }

    /// One entry per distinct project that has sessions — drives the Sessions project filter.
    struct SessionProject: Identifiable, Hashable, Sendable {
        let id: String        // Session.projectKey
        let name: String
        let count: Int
    }

    var sessionProjects: [SessionProject] {
        var byKey: [String: (name: String, count: Int)] = [:]
        for s in sessions {
            let cur = byKey[s.projectKey] ?? (s.projectName, 0)
            byKey[s.projectKey] = (cur.name, cur.count + 1)
        }
        return byKey
            .map { SessionProject(id: $0.key, name: $0.value.name, count: $0.value.count) }
            .sorted {
                $0.count == $1.count
                    ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    : $0.count > $1.count
            }
    }
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

    /// Two-stage scan. The light inventory (skills, agents, commands, plugins, MCP,
    /// hooks, plans, tasks) is config and small Markdown files and lands in milliseconds,
    /// so it is published on its own — the window has real content while the far larger
    /// JSONL transcript corpus is still being read on a second detached task.
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        isScanningSessions = true
        defer { isLoading = false; isScanningSessions = false }

        let light = await Task.detached(priority: .userInitiated) {
            ScannerEngine.scanLight()
        }.value
        var staged = light
        // Hold on to the sessions already on screen so a rescan doesn't blank them out.
        staged.sessions = snapshot.sessions
        staged.projects = snapshot.projects
        snapshot = staged

        let corpus = await Task.detached(priority: .userInitiated) {
            ScannerEngine.scanTranscripts()
        }.value
        snapshot.sessions = corpus.sessions
        snapshot.projects = corpus.projects
        lastRefresh = Date()
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

// MARK: - Diagnostics (CLI verification path)

extension ElementsStore {
    /// `--selftest-sessions`: read-only check of the Sessions filters — how each
    /// staleness threshold re-labels the real transcripts, the project rollup behind
    /// the project filter, and what a batch delete of everything would actually target.
    static func runSessionSelftestAndExit() -> Never {
        let store = ElementsStore()
        store.loadSynchronously()
        let all = store.sessions

        print("── Sessions selftest (read-only) ──")
        print("Sessions: \(all.count)  ·  live \(store.liveSessions.count)  ·  \(Format.bytes(store.totalSessionBytes))")

        print("Stale by threshold (current preference: \(store.staleDays)d):")
        for d in staleDayOptions {
            let stale = store.staleSessions(olderThan: d)
            let mark = d == store.staleDays ? " ←" : ""
            print(String(format: "  >%3dd → %3d stale · %@%@", d, stale.count,
                         Format.bytes(stale.reduce(0) { $0 + $1.sizeBytes }), mark))
        }

        let projects = store.sessionProjects
        print("Projects with sessions: \(projects.count)  (rollup covers \(projects.reduce(0) { $0 + $1.count })/\(all.count))")
        for p in projects.prefix(8) { print("  \(p.count)× \(p.name)") }
        if projects.count > 8 { print("  … \(projects.count - 8) more") }

        // Every session must land in exactly one project bucket.
        let keys = Set(projects.map(\.id))
        let orphans = all.filter { !keys.contains($0.projectKey) }
        print("Unbucketed sessions: \(orphans.count)\(orphans.isEmpty ? " ✓" : " ✗")")

        // A "select all → delete" never includes a live session.
        let deletable = all.filter { $0.state != .live }
        print("Select-all batch delete would target \(deletable.count) of \(all.count) " +
              "(\(all.count - deletable.count) live held back)\(deletable.contains { $0.state == .live } ? " ✗" : " ✓")")
        print("──────────────────────────")
        exit(0)
    }
}
