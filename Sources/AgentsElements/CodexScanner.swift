import Foundation

// MARK: - Minimal TOML parser (no dependency)

/// Parses the subset of TOML used by Codex's config.toml: dotted/quoted section
/// headers, `key = value`, strings, bools, numbers, and string arrays.
enum TOML {
    static func parse(_ text: String) -> [String: Any] {
        var root: [String: Any] = [:]
        var section: [String] = []
        for raw in text.components(separatedBy: "\n") {
            let line = stripComment(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                section = keyPath(String(line.dropFirst().dropLast()))
                ensure(&root, section)
            } else if let eq = line.firstIndex(of: "=") {
                let key = keyPath(String(line[..<eq]).trimmingCharacters(in: .whitespaces))
                let val = parseValue(String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces))
                set(&root, section + key, val)
            }
        }
        return root
    }

    private static func stripComment(_ s: String) -> String {
        var inQuote = false
        for (i, c) in s.enumerated() {
            if c == "\"" { inQuote.toggle() }
            if c == "#" && !inQuote { return String(s.prefix(i)) }
        }
        return s
    }

    /// Splits a dotted key path, respecting `"quoted.segments"`.
    private static func keyPath(_ s: String) -> [String] {
        var parts: [String] = []
        var cur = ""
        var inQuote = false
        for c in s {
            if c == "\"" { inQuote.toggle(); continue }
            if c == "." && !inQuote { parts.append(cur.trimmingCharacters(in: .whitespaces)); cur = ""; continue }
            cur.append(c)
        }
        if !cur.isEmpty { parts.append(cur.trimmingCharacters(in: .whitespaces)) }
        return parts
    }

    private static func parseValue(_ s: String) -> Any {
        if s.hasPrefix("\"") {
            // string (handles a trailing inline quote)
            if let end = s.dropFirst().firstIndex(of: "\"") {
                return String(s[s.index(after: s.startIndex)..<end])
            }
            return String(s.dropFirst())
        }
        if s == "true" { return true }
        if s == "false" { return false }
        if s.hasPrefix("[") {
            let inner = String(s.dropFirst().dropLast(s.hasSuffix("]") ? 1 : 0))
            return splitArray(inner).map { parseValue($0.trimmingCharacters(in: .whitespaces)) }
        }
        if let i = Int(s) { return i }
        if let d = Double(s) { return d }
        return s
    }

    private static func splitArray(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var inQuote = false
        for c in s {
            if c == "\"" { inQuote.toggle() }
            if c == "," && !inQuote { out.append(cur); cur = ""; continue }
            cur.append(c)
        }
        if !cur.trimmingCharacters(in: .whitespaces).isEmpty { out.append(cur) }
        return out
    }

    private static func ensure(_ root: inout [String: Any], _ path: [String]) {
        guard !path.isEmpty else { return }
        var node = root[path[0]] as? [String: Any] ?? [:]
        if path.count == 1 { root[path[0]] = node; return }
        ensure(&node, Array(path.dropFirst()))
        root[path[0]] = node
    }

    private static func set(_ root: inout [String: Any], _ path: [String], _ value: Any) {
        guard let head = path.first else { return }
        if path.count == 1 { root[head] = value; return }
        var node = root[head] as? [String: Any] ?? [:]
        set(&node, Array(path.dropFirst()), value)
        root[head] = node
    }
}

// MARK: - Codex scanner

enum CodexScanner {
    private static let staleThreshold: TimeInterval = 14 * 86_400

    static func scan() -> Snapshot {
        var snap = Snapshot()
        guard FS.dirExists(Paths.codex) else { return snap }

        let config = (FS.readString(Paths.codexConfig)).map { TOML.parse($0) } ?? [:]
        let configModel = config["model"] as? String ?? "gpt-5.5"

        snap.skills = scanSkills()
        snap.mcp = scanMCP(config)
        snap.plugins = scanPlugins(config)
        snap.codexRules = scanRules()

        let (sessions, projects) = scanSessions(model: configModel, config: config)
        snap.sessions = sessions
        snap.projects = projects
        return snap
    }

    // MARK: Skills (same SKILL.md format as Claude, but nested)

    static func scanSkills() -> [Skill] {
        scanSkillsRecursive(Paths.codexSkills, states: scanSkillConfig())
    }

    private static func scanSkillsRecursive(_ dir: URL, states: [String: Bool]) -> [Skill] {
        guard FS.dirExists(dir) else { return [] }
        var out: [Skill] = []
        for item in FS.contentsAll(dir) where FS.dirExists(item) {
            let skillMd = item.appendingPathComponent("SKILL.md")
            if FS.fileExists(skillMd), let content = FS.readString(skillMd) {
                let fm = Frontmatter(content)
                let builtin = skillMd.path.contains("/.system/") || skillMd.path.contains("primary-runtime")
                out.append(Skill(
                    id: skillMd.path,
                    name: fm.string("name") ?? item.lastPathComponent,
                    description: fm.string("description") ?? "",
                    source: builtin ? .builtin : .personal,
                    path: skillMd.path, license: fm.string("license"), body: fm.body,
                    enabled: states[skillMd.path] ?? true,
                    provider: .codex
                ))
            }
            out += scanSkillsRecursive(item, states: states)
        }
        return out
    }

    /// Reads `[[skills.config]]` path→enabled from config.toml. The generic TOML parser
    /// doesn't model array-of-tables, so this scans the blocks directly.
    static func scanSkillConfig() -> [String: Bool] {
        guard let content = FS.readString(Paths.codexConfig) else { return [:] }
        let lines = content.components(separatedBy: "\n")
        var out: [String: Bool] = [:]
        var i = 0
        while i < lines.count {
            guard lines[i].trimmingCharacters(in: .whitespaces) == "[[skills.config]]" else { i += 1; continue }
            var j = i + 1
            var path: String?
            var enabled = true
            while j < lines.count {
                let t = lines[j].trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("[") { break }
                if t.hasPrefix("path"), let v = tomlQuoted(t) { path = v }
                if t.hasPrefix("enabled") { enabled = t.contains("true") }
                j += 1
            }
            if let p = path { out[p] = enabled }
            i = j
        }
        return out
    }

    /// Returns the first double-quoted value on a TOML line.
    static func tomlQuoted(_ line: String) -> String? {
        guard let f = line.firstIndex(of: "\"") else { return nil }
        let after = line[line.index(after: f)...]
        guard let e = after.firstIndex(of: "\"") else { return nil }
        return String(after[..<e])
    }

    // MARK: MCP servers (config.toml [mcp_servers.*])

    static func scanMCP(_ config: [String: Any]) -> [MCPServer] {
        guard let servers = config["mcp_servers"] as? [String: Any] else { return [] }
        return servers.compactMap { name, v in
            guard let t = v as? [String: Any] else { return nil }
            return MCPServer(id: "codex-mcp-\(name)", name: name, scope: "global",
                             type: "stdio", command: t["command"] as? String, provider: .codex)
        }.sorted { $0.name < $1.name }
    }

    // MARK: Plugins (config.toml [plugins."name@marketplace"])

    static func scanPlugins(_ config: [String: Any]) -> [PluginInfo] {
        guard let plugins = config["plugins"] as? [String: Any] else { return [] }
        return plugins.compactMap { key, v in
            let t = v as? [String: Any]
            let enabled = (t?["enabled"] as? Bool) ?? false
            let parts = key.split(separator: "@", maxSplits: 1).map(String.init)
            return PluginInfo(
                id: "codex-\(key)", name: parts.first ?? key,
                marketplace: parts.count > 1 ? parts[1] : "codex",
                description: nil, version: nil, enabled: enabled, scope: "user",
                installedAt: nil, installPath: nil,
                skillCount: 0, agentCount: 0, commandCount: 0, hookCount: 0, provider: .codex
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Command rules (~/.codex/rules/*.rules — Codex's guardrails)

    static func scanRules() -> [CodexRule] {
        guard FS.dirExists(Paths.codexRules) else { return [] }
        var out: [CodexRule] = []
        for file in FS.contents(Paths.codexRules) where file.pathExtension == "rules" {
            guard let content = FS.readString(file) else { continue }
            let fname = file.lastPathComponent
            for line in content.components(separatedBy: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix("prefix_rule(") else { continue }
                let pattern = capturePattern(t)
                guard !pattern.isEmpty else { continue }
                out.append(CodexRule(id: "\(fname)#\(out.count)", pattern: pattern,
                                     decision: captureString(t, after: "decision=") ?? "allow",
                                     file: fname))
            }
        }
        return out.sorted { $0.pattern.localizedCaseInsensitiveCompare($1.pattern) == .orderedAscending }
    }

    /// Joins the quoted segments of `pattern=["git", "commit"]` into `git commit`.
    private static func capturePattern(_ s: String) -> String {
        guard let start = s.range(of: "pattern=[") else { return "" }
        let rest = s[start.upperBound...]
        guard let end = rest.firstIndex(of: "]") else { return "" }
        var parts: [String] = []
        var cur = ""
        var inQuote = false
        for c in rest[..<end] {
            if c == "\"" { if inQuote { parts.append(cur); cur = "" }; inQuote.toggle(); continue }
            if inQuote { cur.append(c) }
        }
        return parts.joined(separator: " ")
    }

    /// Reads the string value of e.g. `decision="allow"`.
    private static func captureString(_ s: String, after marker: String) -> String? {
        guard let r = s.range(of: marker + "\"") else { return nil }
        let rest = s[r.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    // MARK: Live processes (best-effort — process_manager/chat_processes.json)

    /// Maps live Codex session-id → pid. The schema is undocumented, so this walks the
    /// JSON defensively for any UUID-shaped id paired with a pid. Empty when nothing runs.
    static func scanLiveProcesses() -> [String: Int] {
        guard let root = FS.readJSON(Paths.codexProcesses) else { return [:] }
        var out: [String: Int] = [:]
        func walk(_ node: Any) {
            if let dict = node as? [String: Any] {
                let pid = (dict["pid"] as? Int) ?? (dict["processId"] as? Int)
                    ?? (dict["process_id"] as? Int) ?? (dict["pid"] as? NSNumber)?.intValue
                let id = (dict["session_id"] as? String) ?? (dict["sessionId"] as? String)
                    ?? (dict["conversation_id"] as? String) ?? (dict["thread_id"] as? String)
                    ?? (dict["id"] as? String)
                if let id, let pid, uuid(in: id) != nil { out[id] = pid }
                for v in dict.values { walk(v) }
            } else if let arr = node as? [Any] {
                for v in arr { walk(v) }
            }
        }
        walk(root)
        return out
    }

    /// Extracts a UUID substring (rollout filenames embed it; pure-UUID ids match too).
    private static func uuid(in s: String) -> String? {
        let pat = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
        guard let r = s.range(of: pat, options: .regularExpression) else { return nil }
        return String(s[r])
    }

    // MARK: Sessions (rollout JSONL) + projects

    static func scanSessions(model configModel: String,
                             config: [String: Any]) -> (sessions: [Session], projects: [ProjectInfo]) {
        // session_index.jsonl → friendly thread names
        var names: [String: String] = [:]
        if let idx = FS.readString(Paths.codexSessionIndex) {
            for line in idx.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let data = String(line).data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = obj["id"] as? String else { continue }
                names[id] = obj["thread_name"] as? String
            }
        }

        // config.toml [projects."path"] trust_level
        var trust: [String: String] = [:]
        if let projs = config["projects"] as? [String: Any] {
            for (path, v) in projs {
                if let t = (v as? [String: Any])?["trust_level"] as? String { trust[path] = t }
            }
        }

        let live = scanLiveProcesses()

        guard FS.dirExists(Paths.codexSessions) else { return ([], trustedOnlyProjects(trust, known: [])) }
        let now = Date()
        var sessions: [Session] = []
        for file in allJSONL(Paths.codexSessions) {
            if let s = parseRollout(file, names: names, live: live, configModel: configModel, now: now) {
                sessions.append(s)
            }
        }
        sessions.sort { $0.lastActivity > $1.lastActivity }

        var byProject: [String: [Session]] = [:]
        for s in sessions { byProject[s.cwd, default: []].append(s) }
        var projects: [ProjectInfo] = byProject.map { cwd, ss in
            ProjectInfo(id: "codex:\(cwd)", name: cwd, path: cwd,
                        sessionCount: ss.count, liveCount: ss.filter { $0.state == .live }.count,
                        lastActivity: ss.map(\.lastActivity).max() ?? .distantPast,
                        mcpServers: [], trustLevel: trust[cwd], provider: .codex)
        }
        // Trusted projects from config that have no recorded sessions yet.
        projects += trustedOnlyProjects(trust, known: Set(projects.map(\.name)))
        projects.sort { $0.lastActivity > $1.lastActivity }

        return (sessions, projects)
    }

    /// Projects that are trusted in config.toml but have no session transcripts.
    private static func trustedOnlyProjects(_ trust: [String: String], known: Set<String>) -> [ProjectInfo] {
        trust.filter { !known.contains($0.key) }.map { path, level in
            ProjectInfo(id: "codex:\(path)", name: path, path: path,
                        sessionCount: 0, liveCount: 0, lastActivity: .distantPast,
                        mcpServers: [], trustLevel: level, provider: .codex)
        }
    }

    private static func allJSONL(_ dir: URL) -> [URL] {
        var out: [URL] = []
        for item in FS.contents(dir) {
            if FS.dirExists(item) { out += allJSONL(item) }
            else if item.pathExtension == "jsonl" { out.append(item) }
        }
        return out
    }

    private static func parseRollout(_ file: URL, names: [String: String], live: [String: Int],
                                     configModel: String, now: Date) -> Session? {
        guard let content = FS.readString(file), !content.isEmpty else { return nil }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        let mtime = FS.modified(file)
        let size = FS.size(file)

        // Default to the UUID embedded in the rollout filename so `codex resume <id>`
        // always gets a valid id even if session_meta is missing; payload.id overrides below.
        var sid = uuid(in: file.lastPathComponent) ?? file.deletingPathExtension().lastPathComponent
        var cwd = ""
        var version: String?
        var model = configModel
        var msgCount = 0
        var usage = ModelUsage(model: configModel)

        for line in lines {
            if line.contains("\"role\":\"user\"") || line.contains("\"role\":\"assistant\"") { msgCount += 1 }
            if cwd.isEmpty, line.contains("\"session_meta\""),
               let obj = decodeJSON(line), let payload = obj["payload"] as? [String: Any] {
                cwd = payload["cwd"] as? String ?? ""
                version = payload["cli_version"] as? String
                if let id = payload["id"] as? String { sid = id }
            }
            if let r = line.range(of: "\"model\":\"") {
                let after = line[r.upperBound...]
                if let end = after.firstIndex(of: "\"") {
                    let m = String(after[..<end])
                    if m.hasPrefix("gpt") { model = m }
                }
            }
            if line.contains("\"total_token_usage\""), let obj = decodeJSON(line) {
                if let u = findTokenUsage(obj) {
                    let cached = u["cached_input_tokens"] as? Int ?? 0
                    let inTok = u["input_tokens"] as? Int ?? 0
                    usage.input = max(0, inTok - cached)
                    usage.cacheRead = cached
                    usage.output = u["output_tokens"] as? Int ?? 0
                }
            }
        }
        usage = ModelUsage(model: model, input: usage.input, output: usage.output,
                           cacheRead: usage.cacheRead, cacheCreate: 0)

        // Live if a running process claims this session id; else recency-based.
        var state: SessionState = now.timeIntervalSince(mtime) > staleThreshold ? .stale : .resumable
        var pid: Int?
        if let p = live[sid], FS.processAlive(p) { state = .live; pid = p }
        let projectName = cwd.isEmpty ? "—" : (cwd as NSString).lastPathComponent

        return Session(
            id: sid, name: names[sid], cwd: cwd, projectDir: cwd, projectName: projectName,
            gitBranch: nil, version: version, model: model, messageCount: msgCount,
            firstActivity: nil, lastActivity: mtime, lastPrompt: names[sid], sizeBytes: size,
            path: file.path, state: state, pid: pid, status: pid != nil ? "running" : nil,
            contextFill: nil, subagentRuns: 0,
            usage: usage.total > 0 ? [usage] : [], provider: .codex
        )
    }

    /// total_token_usage may sit at the top level or under info/payload.
    private static func findTokenUsage(_ obj: [String: Any]) -> [String: Any]? {
        if let u = obj["total_token_usage"] as? [String: Any] { return u }
        for v in obj.values {
            if let d = v as? [String: Any] {
                if let u = d["total_token_usage"] as? [String: Any] { return u }
                if let u = findTokenUsage(d) { return u }
            }
        }
        return nil
    }

    private static func decodeJSON(_ line: Substring) -> [String: Any]? {
        guard let data = String(line).data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
