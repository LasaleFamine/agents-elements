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

        // (transcript, its project dir) — collected first so the parse can fan out.
        let files: [(file: URL, projDir: URL)] = FS.contents(Paths.projects)
            .filter { FS.dirExists($0) }
            .flatMap { projDir in
                FS.contents(projDir)
                    .filter { $0.pathExtension == "jsonl" }
                    .map { (file: $0, projDir: projDir) }
            }

        let collected = Collector<Session>(reserving: files.count)
        parallelFor(files.count) { i in
            let (file, projDir) = files[i]
            if let s = parseSession(file, projDir: projDir, live: live, fill: fill, now: now) {
                collected.add(s)
            }
        }
        // Tie-break on id so a parallel scan still produces a stable order.
        var sessions = collected.all
        sessions.sort { $0.lastActivity == $1.lastActivity ? $0.id < $1.id : $0.lastActivity > $1.lastActivity }

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

    // Needles, held as bytes so the hot loop never builds a String.
    private static let pUser = Bytes.pattern("\"type\":\"user\"")
    private static let pAssistant = Bytes.pattern("\"type\":\"assistant\"")
    private static let pCwd = Bytes.pattern("\"cwd\"")
    private static let pModel = Bytes.pattern("\"model\":\"")
    private static let pOutputTokens = Bytes.pattern("\"output_tokens\"")
    private static let pUsage = Bytes.pattern("\"usage\":")

    private static func parseSession(_ file: URL, projDir: URL,
                                     live: [String: LiveInfo], fill: [String: Int], now: Date) -> Session? {
        let sid = file.deletingPathExtension().lastPathComponent
        let size = FS.size(file)
        let mtime = FS.modified(file)
        guard let data = FS.readData(file), !data.isEmpty else { return nil }

        var msgCount = 0
        var cwd = ""
        var branch: String?
        var version: String?
        var firstTs: Date?
        var model: String?
        var usageByModel: [String: ModelUsage] = [:]
        var lastPrompt: String?

        data.withUnsafeBytes { raw in
            let buf = Bytes.Buf(raw)
            let ranges = Bytes.lineRanges(buf)
            var metaFound = false

            for r in ranges {
                let line = Bytes.slice(buf, r)
                if Bytes.contains(line, pUser) || Bytes.contains(line, pAssistant) { msgCount += 1 }

                if !metaFound, Bytes.contains(line, pCwd), let d = decodeRaw(line) {
                    cwd = d.cwd ?? ""
                    branch = d.gitBranch
                    version = d.version
                    firstTs = parseDate(d.timestamp)
                    metaFound = true
                }

                if model == nil, let m = Bytes.quoted(line, after: pModel),
                   m != "<synthetic>", !m.isEmpty {
                    model = m
                }

                if Bytes.contains(line, pOutputTokens), let u = usage(in: line) {
                    let key = Bytes.quoted(line, after: pModel) ?? model ?? "unknown"
                    var bucket = usageByModel[key] ?? ModelUsage(model: key)
                    bucket.input += u["input_tokens"] as? Int ?? 0
                    bucket.output += u["output_tokens"] as? Int ?? 0
                    bucket.cacheRead += u["cache_read_input_tokens"] as? Int ?? 0
                    bucket.cacheCreate += u["cache_creation_input_tokens"] as? Int ?? 0
                    usageByModel[key] = bucket
                }
            }

            var scanned = 0
            for r in ranges.reversed() {
                let line = Bytes.slice(buf, r)
                guard Bytes.contains(line, pUser) else { continue }
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

    /// The `usage` object on an assistant line. Fast path lifts just that sub-object out
    /// of what can be a multi-megabyte line; if the first `"usage":` turns out to be
    /// something else (it can appear in message content), fall back to parsing the line.
    private static func usage(in line: Bytes.Buf) -> [String: Any]? {
        if let slice = Bytes.object(line, after: pUsage), let obj = Bytes.json(slice),
           obj["output_tokens"] != nil || obj["input_tokens"] != nil {
            return obj
        }
        guard let obj = Bytes.json(line),
              let msg = obj["message"] as? [String: Any] else { return nil }
        return msg["usage"] as? [String: Any]
    }

    // MARK: - Line decoding helpers

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

    private static func decodeRaw(_ line: Bytes.Buf) -> Raw? {
        try? JSONDecoder().decode(Raw.self, from: Data(line))
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
