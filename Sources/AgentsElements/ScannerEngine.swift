import Foundation

/// Pure, nonisolated filesystem scanners. Each returns Sendable value types so the
/// whole snapshot can be produced on a detached task and handed to the @MainActor store.
enum ScannerEngine {

    static func scanEverything() -> Snapshot {
        var snap = Snapshot()

        let (plugins, marketplaces) = scanPlugins()
        snap.plugins = plugins
        snap.marketplaces = marketplaces

        // (pluginName, installPath) for active plugin contributions.
        let installed: [(String, URL)] = plugins.compactMap {
            guard let p = $0.installPath else { return nil }
            return ($0.name, URL(fileURLWithPath: p))
        }

        var skills = scanSkillsIn(Paths.skills, source: .personal)
        for (name, ip) in installed { skills += scanSkillsIn(ip.appendingPathComponent("skills"), source: .plugin(name)) }
        snap.skills = skills.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        var agents = scanAgentsIn(Paths.agents, source: .personal)
        for (name, ip) in installed { agents += scanAgentsIn(ip.appendingPathComponent("agents"), source: .plugin(name)) }
        snap.subagents = agents.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        var cmds = scanCommandsIn(Paths.commands, source: .personal)
        for (name, ip) in installed { cmds += scanCommandsIn(ip.appendingPathComponent("commands"), source: .plugin(name)) }
        snap.commands = cmds.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        snap.hooks = scanHooks(installed: installed)
        snap.mcp = scanMCP()
        snap.plans = scanPlans()
        snap.tasks = scanTasks()
        snap.sweeps = scanSweeps()

        let (sessions, projects) = SessionScanner.scan()
        snap.sessions = sessions
        snap.projects = projects

        // Merge in Codex (~/.codex)
        let codex = CodexScanner.scan()
        snap.skills += codex.skills
        snap.plugins += codex.plugins
        snap.mcp += codex.mcp
        snap.sessions += codex.sessions
        snap.projects += codex.projects
        snap.codexRules = codex.codexRules
        snap.skills.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        snap.sessions.sort { $0.lastActivity > $1.lastActivity }
        snap.projects.sort { $0.lastActivity > $1.lastActivity }

        return snap
    }

    // MARK: - Skills

    static func scanSkillsIn(_ dir: URL, source: Source) -> [Skill] {
        guard FS.dirExists(dir) else { return [] }
        var out: [Skill] = []
        for sub in FS.contents(dir) where FS.dirExists(sub) {
            let skillMd = sub.appendingPathComponent("SKILL.md")
            guard FS.fileExists(skillMd), let content = FS.readString(skillMd) else { continue }
            let fm = Frontmatter(content)
            out.append(Skill(
                id: skillMd.path,
                name: fm.string("name") ?? sub.lastPathComponent,
                description: fm.string("description") ?? "",
                source: source,
                path: skillMd.path,
                license: fm.string("license"),
                body: fm.body
            ))
        }
        return out
    }

    // MARK: - Subagents

    static func scanAgentsIn(_ dir: URL, source: Source) -> [Subagent] {
        guard FS.dirExists(dir) else { return [] }
        var out: [Subagent] = []
        for md in FS.contents(dir) where md.pathExtension == "md" && FS.size(md) > 0 {
            guard let content = FS.readString(md) else { continue }
            let fm = Frontmatter(content)
            let stem = md.deletingPathExtension().lastPathComponent
            let name = fm.string("name") ?? stem
            out.append(Subagent(
                id: md.path,
                name: name,
                description: fm.string("description") ?? "",
                tools: fm.list("tools"),
                model: fm.string("model"),
                source: source,
                path: md.path,
                body: fm.body,
                scope: scopeFromFilename(stem: stem, name: name)
            ))
        }
        return out
    }

    /// Derives a project scope from an agent filename like `lualtek-console-<name>.md`
    /// (frontmatter `name` collides across projects, so the prefix disambiguates).
    private static func scopeFromFilename(stem: String, name: String) -> String? {
        let hyphenName = name.replacingOccurrences(of: " ", with: "-")
        guard stem != hyphenName, stem.hasSuffix(hyphenName) else { return nil }
        let prefix = String(stem.dropLast(hyphenName.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard !prefix.isEmpty else { return nil }
        return prefix.replacingOccurrences(of: "-", with: "/")
    }

    // MARK: - Commands (recursive, namespaced by relative path)

    static func scanCommandsIn(_ dir: URL, source: Source, base: URL? = nil) -> [SlashCommand] {
        guard FS.dirExists(dir) else { return [] }
        let root = base ?? dir
        var out: [SlashCommand] = []
        for item in FS.contents(dir) {
            if FS.dirExists(item) {
                out += scanCommandsIn(item, source: source, base: root)
            } else if item.pathExtension == "md", FS.size(item) > 0 {
                guard let content = FS.readString(item) else { continue }
                let fm = Frontmatter(content)
                let rel = item.path.replacingOccurrences(of: root.path + "/", with: "")
                out.append(SlashCommand(
                    id: item.path,
                    name: (rel as NSString).deletingPathExtension,
                    description: fm.string("description"),
                    source: source,
                    path: item.path,
                    body: fm.body,
                    argumentHint: fm.string("argument-hint")
                ))
            }
        }
        return out
    }

    // MARK: - Plugins & marketplaces

    static func scanPlugins() -> ([PluginInfo], [MarketplaceInfo]) {
        let installedJSON = FS.readJSON(Paths.installedPlugins) as? [String: Any]
        let pluginsMap = installedJSON?["plugins"] as? [String: Any] ?? [:]
        let settings = FS.readJSON(Paths.settings) as? [String: Any]
        let enabledMap = settings?["enabledPlugins"] as? [String: Any] ?? [:]

        var plugins: [PluginInfo] = []
        for (key, val) in pluginsMap {
            let parts = key.split(separator: "@", maxSplits: 1).map(String.init)
            let name = parts.first ?? key
            let marketplace = parts.count > 1 ? parts[1] : ""
            let first = (val as? [[String: Any]])?.first
            let installPath = first?["installPath"] as? String
            let enabled = (enabledMap[key] as? Bool) ?? ((enabledMap[key] as? NSNumber)?.boolValue ?? false)

            var desc: String?
            var sk = 0, ag = 0, cm = 0, hk = 0
            if let ip = installPath {
                let ipURL = URL(fileURLWithPath: ip)
                if let pj = FS.readJSON(ipURL.appendingPathComponent(".claude-plugin/plugin.json")) as? [String: Any] {
                    desc = pj["description"] as? String
                }
                sk = scanSkillsIn(ipURL.appendingPathComponent("skills"), source: .plugin(name)).count
                ag = scanAgentsIn(ipURL.appendingPathComponent("agents"), source: .plugin(name)).count
                cm = scanCommandsIn(ipURL.appendingPathComponent("commands"), source: .plugin(name)).count
                hk = countHooks(ipURL)
            }
            plugins.append(PluginInfo(
                id: key, name: name, marketplace: marketplace, description: desc,
                version: first?["version"] as? String, enabled: enabled,
                scope: first?["scope"] as? String, installedAt: first?["installedAt"] as? String,
                installPath: installPath, skillCount: sk, agentCount: ag, commandCount: cm, hookCount: hk
            ))
        }
        plugins.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        var marketplaces: [MarketplaceInfo] = []
        if let mpJSON = FS.readJSON(Paths.knownMarketplaces) as? [String: Any] {
            for (name, v) in mpJSON {
                let dict = v as? [String: Any]
                let source = dict?["source"] as? [String: Any]
                let stype = source?["source"] as? String ?? "unknown"
                let loc = (source?["repo"] as? String) ?? (source?["path"] as? String)
                    ?? (dict?["installLocation"] as? String) ?? ""
                var catalog = 0
                if let installLoc = dict?["installLocation"] as? String {
                    let manifest = URL(fileURLWithPath: installLoc).appendingPathComponent(".claude-plugin/marketplace.json")
                    if let mj = FS.readJSON(manifest) as? [String: Any], let ps = mj["plugins"] as? [[String: Any]] {
                        catalog = ps.count
                    }
                }
                marketplaces.append(MarketplaceInfo(
                    id: name, name: name, sourceType: stype, location: loc,
                    lastUpdated: dict?["lastUpdated"] as? String, catalogCount: catalog
                ))
            }
        }
        marketplaces.sort { $0.name < $1.name }
        return (plugins, marketplaces)
    }

    private static func countHooks(_ installPath: URL) -> Int {
        for candidate in ["hooks/hooks.json", "hooks.json"] {
            let url = installPath.appendingPathComponent(candidate)
            if let obj = FS.readJSON(url) as? [String: Any] {
                let block = (obj["hooks"] as? [String: Any]) ?? obj
                return block.values.reduce(0) { acc, v in acc + ((v as? [Any])?.count ?? 0) }
            }
        }
        return 0
    }

    // MARK: - Hooks

    static func scanHooks(installed: [(String, URL)]) -> [HookInfo] {
        var out: [HookInfo] = []
        if let settings = FS.readJSON(Paths.settings) as? [String: Any] {
            if let sl = settings["statusLine"] as? [String: Any], let cmd = sl["command"] as? String {
                out.append(HookInfo(id: "statusLine", event: "StatusLine", matcher: nil, command: cmd, source: .personal))
            }
            if let hooks = settings["hooks"] as? [String: Any] {
                out += parseHookBlock(hooks, source: .personal)
            }
        }
        for (name, ip) in installed {
            for candidate in ["hooks/hooks.json", "hooks.json"] {
                if let obj = FS.readJSON(ip.appendingPathComponent(candidate)) as? [String: Any] {
                    let block = (obj["hooks"] as? [String: Any]) ?? obj
                    out += parseHookBlock(block, source: .plugin(name))
                    break
                }
            }
        }
        return out
    }

    private static func parseHookBlock(_ hooks: [String: Any], source: Source) -> [HookInfo] {
        var out: [HookInfo] = []
        for (event, v) in hooks {
            guard let matchers = v as? [[String: Any]] else { continue }
            for m in matchers {
                let matcher = m["matcher"] as? String
                let inner = m["hooks"] as? [[String: Any]] ?? []
                for h in inner {
                    let cmd = (h["command"] as? String) ?? (h["type"] as? String) ?? "hook"
                    out.append(HookInfo(id: "\(source.label)-\(event)-\(out.count)",
                                        event: event, matcher: matcher, command: cmd, source: source))
                }
            }
        }
        return out
    }

    // MARK: - MCP servers

    static func scanMCP() -> [MCPServer] {
        var out: [MCPServer] = []
        guard let cj = FS.readJSON(Paths.claudeJSON) as? [String: Any] else { return out }
        if let g = cj["mcpServers"] as? [String: Any] {
            for (name, v) in g {
                let d = v as? [String: Any]
                out.append(MCPServer(id: "global-\(name)", name: name, scope: "global",
                                     type: d?["type"] as? String, command: d?["command"] as? String))
            }
        }
        if let projects = cj["projects"] as? [String: Any] {
            for (path, pv) in projects {
                guard let pmcp = (pv as? [String: Any])?["mcpServers"] as? [String: Any] else { continue }
                for (name, v) in pmcp {
                    let d = v as? [String: Any]
                    out.append(MCPServer(id: "\(path)-\(name)", name: name, scope: path,
                                         type: d?["type"] as? String, command: d?["command"] as? String))
                }
            }
        }
        return out.sorted { $0.name < $1.name }
    }

    // MARK: - Plans & background tasks

    static func scanPlans() -> [PlanDoc] {
        guard FS.dirExists(Paths.plans) else { return [] }
        return FS.contents(Paths.plans).filter { $0.pathExtension == "md" }.map { url in
            let content = FS.readString(url) ?? ""
            let title = content.components(separatedBy: "\n")
                .first { $0.hasPrefix("# ") }
                .map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
            return PlanDoc(id: url.path, name: url.lastPathComponent, title: title,
                           path: url.path, modified: FS.modified(url), sizeBytes: FS.size(url))
        }.sorted { $0.modified > $1.modified }
    }

    static func scanTasks() -> [BgTask] {
        guard FS.dirExists(Paths.tasks) else { return [] }
        return FS.contents(Paths.tasks).filter { FS.dirExists($0) }.map { dir in
            BgTask(id: dir.lastPathComponent, path: dir.path,
                   modified: FS.modified(dir), fileCount: FS.contents(dir).count)
        }.sorted { $0.modified > $1.modified }
    }

    // MARK: - Sweep / cleanup markers (automation audit)

    static func scanSweeps() -> [SweepMarker] {
        func iso(_ s: String?) -> Date? {
            guard let s else { return nil }
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        }
        var out: [SweepMarker] = []

        let lastCleanup = Paths.claude.appendingPathComponent(".last-cleanup")
        if let s = FS.readString(lastCleanup)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            out.append(SweepMarker(id: "last-cleanup", name: "Transcript cleanup", owner: "Claude Code",
                                   path: lastCleanup.path, timestamp: iso(s),
                                   detail: "Deletes old session transcripts under ~/.claude/projects."))
        }
        let sweep = Paths.plugins.appendingPathComponent(".last_inuse_sweep")
        if let s = FS.readString(sweep)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            out.append(SweepMarker(id: "inuse-sweep", name: "Plugin in-use sweep", owner: "Claude Code plugins",
                                   path: sweep.path, timestamp: iso(s),
                                   detail: "Marks plugins in use and prunes unused plugin caches."))
        }
        let upd = Paths.claude.appendingPathComponent(".last-update-result.json")
        if let obj = FS.readJSON(upd) as? [String: Any] {
            let from = obj["version_from"] as? String ?? "?"
            let to = obj["version_to"] as? String ?? "?"
            out.append(SweepMarker(id: "last-update", name: "Auto-update", owner: "Claude Code",
                                   path: upd.path, timestamp: iso(obj["timestamp"] as? String),
                                   detail: "Updated CLI \(from) → \(to)."))
        }
        return out.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
    }

    // MARK: - Diagnostics (CLI verification path)

    static func dumpAndExit() -> Never {
        let s = scanEverything()
        let personalSkills = s.skills.filter { if case .personal = $0.source { return true } else { return false } }.count
        print("── Agents Elements scan ──")
        print("Skills:     \(s.skills.count)  (personal \(personalSkills), plugin \(s.skills.count - personalSkills))")
        print("Subagents:  \(s.subagents.count)")
        print("Commands:   \(s.commands.count)")
        print("Plugins:    \(s.plugins.count) installed (\(s.plugins.filter { $0.enabled }.count) enabled) · \(s.marketplaces.count) marketplaces")
        print("MCP:        \(s.mcp.count)")
        print("Hooks:      \(s.hooks.count)")
        print("Sessions:   \(s.sessions.count)  (live \(s.sessions.filter { $0.state == .live }.count), stale \(s.sessions.filter { $0.state == .stale }.count))")
        print("Projects:   \(s.projects.count)")
        print("Plans:      \(s.plans.count)   Tasks: \(s.tasks.count)")
        let totalCost = s.sessions.reduce(0.0) { $0 + $1.estimatedCost }
        let totalTok = s.sessions.reduce(0) { $0 + $1.totalTokens }
        print("Tokens:     \(totalTok)  Est. cost: \(Pricing.money(totalCost))")
        print("Sweeps:     \(s.sweeps.count)")
        print("── by provider ──")
        for p in Provider.allCases {
            let sk = s.skills.filter { $0.provider == p }.count
            let se = s.sessions.filter { $0.provider == p }.count
            let mc = s.mcp.filter { $0.provider == p }.count
            let pl = s.plugins.filter { $0.provider == p }.count
            let pr = s.projects.filter { $0.provider == p }.count
            let cost = s.sessions.filter { $0.provider == p }.reduce(0.0) { $0 + $1.estimatedCost }
            print("  \(p.label): skills \(sk), sessions \(se), mcp \(mc), plugins \(pl), projects \(pr), cost \(Pricing.money(cost))")
        }
        let trusted = s.projects.filter { $0.trustLevel != nil }.count
        let disabledSkills = s.skills.filter { !$0.enabled }
        print("Codex rules: \(s.codexRules.count) command guardrails · \(trusted) trusted projects")
        print("Disabled skills: \(disabledSkills.count)\(disabledSkills.isEmpty ? "" : " — " + disabledSkills.map(\.name).joined(separator: ", "))")
        print("──────────────────────────")
        for sess in s.sessions.filter({ $0.state == .live }) {
            print("  LIVE  \(sess.id.prefix(8))  \(sess.name ?? sess.projectName)  pid=\(sess.pid ?? -1)  \(sess.status ?? "")")
        }
        exit(0)
    }
}
