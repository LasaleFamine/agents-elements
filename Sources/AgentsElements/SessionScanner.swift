import Foundation

/// Parses the session JSONL corpus cheaply: file stat + substring counting, decoding
/// only the handful of lines that actually carry the metadata we surface.
enum SessionScanner {

    struct LiveInfo: Sendable {
        let pid: Int
        let status: String?
        let name: String?
        let cwd: String?
    }

    private static let staleThreshold: TimeInterval = 14 * 86_400

    // MARK: - Live detection

    /// Maps live session-ids to their running process, plus the active session's context fill %.
    static func scanLive() -> (live: [String: LiveInfo], fill: [String: Int]) {
        var live: [String: LiveInfo] = [:]
        if FS.dirExists(Paths.sessions) {
            for f in FS.contents(Paths.sessions) where f.pathExtension == "json" {
                guard let obj = FS.readJSON(f) as? [String: Any],
                      let sid = obj["sessionId"] as? String,
                      let pid = obj["pid"] as? Int,
                      FS.processAlive(pid) else { continue }
                live[sid] = LiveInfo(pid: pid, status: obj["status"] as? String,
                                     name: obj["name"] as? String, cwd: obj["cwd"] as? String)
            }
        }
        var fill: [String: Int] = [:]
        if let lf = FS.readJSON(Paths.liveFill) as? [String: Any],
           let sid = lf["session_id"] as? String,
           let pct = lf["used_percentage"] as? Int {
            fill[sid] = pct
        }
        return (live, fill)
    }

    // MARK: - Full scan

    static func scan() -> (sessions: [Session], projects: [ProjectInfo]) {
        let (live, fill) = scanLive()

        var projectMCP: [String: [String]] = [:]
        if let cj = FS.readJSON(Paths.claudeJSON) as? [String: Any],
           let projects = cj["projects"] as? [String: Any] {
            for (path, pv) in projects {
                if let m = (pv as? [String: Any])?["mcpServers"] as? [String: Any], !m.isEmpty {
                    projectMCP[path] = Array(m.keys).sorted()
                }
            }
        }

        guard FS.dirExists(Paths.projects) else { return ([], []) }
        let now = Date()
        var sessions: [Session] = []
        for projDir in FS.contents(Paths.projects) where FS.dirExists(projDir) {
            for file in FS.contents(projDir) where file.pathExtension == "jsonl" {
                if let s = parseSession(file, projDir: projDir, live: live, fill: fill, now: now) {
                    sessions.append(s)
                }
            }
        }
        sessions.sort { $0.lastActivity > $1.lastActivity }

        var byProject: [String: [Session]] = [:]
        for s in sessions { byProject[s.projectDir, default: []].append(s) }
        var projects: [ProjectInfo] = byProject.map { dir, ss in
            let cwd = ss.first { !$0.cwd.isEmpty }?.cwd ?? decodeDir(dir)
            return ProjectInfo(
                id: dir, name: cwd, path: Paths.projects.appendingPathComponent(dir).path,
                sessionCount: ss.count, liveCount: ss.filter { $0.state == .live }.count,
                lastActivity: ss.map(\.lastActivity).max() ?? .distantPast,
                mcpServers: projectMCP[cwd] ?? []
            )
        }
        projects.sort { $0.lastActivity > $1.lastActivity }
        return (sessions, projects)
    }

    private static func parseSession(_ file: URL, projDir: URL,
                                     live: [String: LiveInfo], fill: [String: Int], now: Date) -> Session? {
        let sid = file.deletingPathExtension().lastPathComponent
        let size = FS.size(file)
        let mtime = FS.modified(file)
        guard let content = FS.readString(file), !content.isEmpty else { return nil }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)

        var msgCount = 0
        var cwd = ""
        var branch: String?
        var version: String?
        var firstTs: Date?
        var model: String?
        var metaFound = false
        var usageByModel: [String: ModelUsage] = [:]

        for line in lines {
            if line.contains("\"type\":\"user\"") || line.contains("\"type\":\"assistant\"") { msgCount += 1 }
            if !metaFound, line.contains("\"cwd\""), let d = decodeRaw(line) {
                cwd = d.cwd ?? ""
                branch = d.gitBranch
                version = d.version
                firstTs = parseDate(d.timestamp)
                metaFound = true
            }
            if model == nil, let r = line.range(of: "\"model\":\"") {
                let after = line[r.upperBound...]
                if let end = after.firstIndex(of: "\"") {
                    let m = String(after[..<end])
                    if m != "<synthetic>" && !m.isEmpty { model = m }
                }
            }
            if line.contains("\"output_tokens\""), let raw = decodeUsage(line), let u = raw.message?.usage {
                let key = raw.message?.model ?? model ?? "unknown"
                var bucket = usageByModel[key] ?? ModelUsage(model: key)
                bucket.input += u.input_tokens ?? 0
                bucket.output += u.output_tokens ?? 0
                bucket.cacheRead += u.cache_read_input_tokens ?? 0
                bucket.cacheCreate += u.cache_creation_input_tokens ?? 0
                usageByModel[key] = bucket
            }
        }

        var lastPrompt: String?
        var scanned = 0
        for line in lines.reversed() {
            guard line.contains("\"type\":\"user\"") else { continue }
            scanned += 1
            if let d = decodeRaw(line), let txt = d.message?.content?.displayText {
                let clean = txt.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty && !clean.hasPrefix("<") {
                    lastPrompt = String(clean.prefix(300))
                    break
                }
            }
            if scanned > 40 { break }
        }

        if cwd.isEmpty { cwd = decodeDir(projDir.lastPathComponent) }

        let subagentsDir = projDir.appendingPathComponent(sid).appendingPathComponent("subagents")
        let subagentRuns = FS.dirExists(subagentsDir)
            ? FS.contents(subagentsDir).filter { $0.pathExtension == "jsonl" }.count
            : 0

        var state: SessionState = .resumable
        if live[sid] != nil {
            state = .live
        } else if now.timeIntervalSince(mtime) > staleThreshold {
            state = .stale
        }

        return Session(
            id: sid, name: live[sid]?.name, cwd: cwd,
            projectDir: projDir.lastPathComponent, projectName: (cwd as NSString).lastPathComponent,
            gitBranch: branch, version: version, model: model, messageCount: msgCount,
            firstActivity: firstTs, lastActivity: mtime, lastPrompt: lastPrompt, sizeBytes: size,
            path: file.path, state: state, pid: live[sid]?.pid, status: live[sid]?.status,
            contextFill: fill[sid], subagentRuns: subagentRuns,
            usage: usageByModel.values.sorted { $0.total > $1.total }
        )
    }

    // MARK: - Line decoding helpers

    private struct UsageRaw: Decodable {
        struct Msg: Decodable {
            let model: String?
            let usage: Usage?
        }
        struct Usage: Decodable {
            let input_tokens: Int?
            let output_tokens: Int?
            let cache_read_input_tokens: Int?
            let cache_creation_input_tokens: Int?
        }
        let message: Msg?
    }

    private static func decodeUsage(_ line: Substring) -> UsageRaw? {
        guard let data = String(line).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(UsageRaw.self, from: data)
    }

    private struct Raw: Decodable {
        let type: String?
        let cwd: String?
        let gitBranch: String?
        let version: String?
        let timestamp: String?
        let message: RawMsg?
    }
    private struct RawMsg: Decodable {
        let role: String?
        let model: String?
        let content: RawContent?
    }

    private static func decodeRaw(_ line: Substring) -> Raw? {
        guard let data = String(line).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Raw.self, from: data)
    }

    private static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    /// Best-effort reverse of the project dir encoding (lossy: `/` and `-` both map to `-`).
    private static func decodeDir(_ encoded: String) -> String {
        var s = encoded
        if s.hasPrefix("-") { s.removeFirst() }
        return "/" + s.replacingOccurrences(of: "-", with: "/")
    }
}

/// JSONL `content` is either a plain string or an array of typed blocks.
enum RawContent: Decodable {
    case text(String)
    case blocks([RawBlock])
    case other

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .text(s) }
        else if let b = try? c.decode([RawBlock].self) { self = .blocks(b) }
        else { self = .other }
    }

    var displayText: String {
        switch self {
        case .text(let s): return s
        case .blocks(let bs): return bs.compactMap(\.text).joined(separator: " ")
        case .other: return ""
        }
    }
}

struct RawBlock: Decodable {
    let type: String?
    let text: String?
}
