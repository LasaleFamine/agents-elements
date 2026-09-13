import Foundation

/// Parses the session JSONL corpus cheaply: file stat + substring counting, decoding
/// only the handful of lines that actually carry the metadata we surface.
enum SessionScanner {

    struct LiveInfo: Sendable {
        let pid: Int
        let status: String?
        let name: String?
        let cwd: String?
        let waitingFor: String?
        let statusSince: Date?
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
                // `waitingFor` is only written while a dialog is up, and names it
                // ("dialog open"). `statusUpdatedAt` is epoch milliseconds and is what
                // makes the state actionable: blocked for a minute is normal, blocked
                // since last Tuesday is a session you have forgotten about.
                let since = (obj["statusUpdatedAt"] as? Double) ?? (obj["updatedAt"] as? Double)
                live[sid] = LiveInfo(pid: pid, status: obj["status"] as? String,
                                     name: obj["name"] as? String, cwd: obj["cwd"] as? String,
                                     waitingFor: obj["waitingFor"] as? String,
                                     statusSince: since.map { Date(timeIntervalSince1970: $0 / 1000) })
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
    private static let pToolResult = Bytes.pattern("\"tool_result\"")

    // Sidecar title records. Claude Code re-appends these on almost every turn and treats
    // them as last-wins, so a mid-session /rename correctly overrides an earlier value.
    private static let pAiTitle = Bytes.pattern("\"aiTitle\":\"")
    private static let pCustomTitle = Bytes.pattern("\"customTitle\":\"")
    private static let pAgentName = Bytes.pattern("\"agentName\":\"")
    private static let pLastPromptKey = Bytes.pattern("\"lastPrompt\":\"")

    /// Sidecar records are tiny — the longest observed across a 180MB corpus is 348 bytes.
    /// Checking length before reaching for them keeps the extra needles off the multi-megabyte
    /// message lines that dominate a scan, so they cost effectively nothing.
    private static let sidecarMaxBytes = 512

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
        var humanTurns = 0
        var cand = SessionTitle.Candidates()

        data.withUnsafeBytes { raw in
            let buf = Bytes.Buf(raw)
            let ranges = Bytes.lineRanges(buf)
            var metaFound = false

            for r in ranges {
                let line = Bytes.slice(buf, r)
                let isUser = Bytes.contains(line, pUser)
                if isUser || Bytes.contains(line, pAssistant) { msgCount += 1 }

                // The `user` channel carries tool results as well as typed prompts, and on a
                // tool-heavy session the latter are a rounding error — 9 of 498 in one
                // transcript here. Counting them apart is what makes the number mean anything.
                if isUser, !Bytes.contains(line, pToolResult) { humanTurns += 1 }

                if r.count <= sidecarMaxBytes {
                    if let t = Bytes.quoted(line, after: pCustomTitle) { cand.customTitle = t }
                    if let t = Bytes.quoted(line, after: pAgentName) { cand.agentName = t }
                    if let t = Bytes.quoted(line, after: pLastPromptKey) { cand.lastPrompt = t }
                    // One distinct value per session in practice, so first hit is enough.
                    if cand.generated == nil, let t = Bytes.quoted(line, after: pAiTitle) {
                        cand.generated = t
                    }
                }

                if !metaFound, Bytes.contains(line, pCwd), let d = decodeRaw(line) {
                    cwd = d.cwd ?? ""
                    branch = d.gitBranch
                    version = d.version
                    firstTs = Timestamps.parse(d.timestamp)
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

            // The CLI writes `last-prompt` itself and it is present in every current
            // transcript, so this walk is only for older ones. Skipping tool-result
            // envelopes before decoding is what makes the budget meaningful: it used to be
            // spent entirely on them, which is why some sessions showed no prompt at all.
            if cand.lastPrompt == nil {
                cand.lastPrompt = firstHumanText(in: ranges.reversed(), buf)
            }

            // Only needed when the CLI generated no title of its own (pre-2.1.235).
            if cand.customTitle == nil, cand.agentName == nil, cand.generated == nil {
                cand.firstPrompt = firstHumanText(in: ranges, buf)
            }
        }

        lastPrompt = cand.lastPrompt.map { String($0.prefix(300)) }
        let resolved = SessionTitle.resolve(cand)

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
            waitingFor: live[sid]?.waitingFor, statusSince: live[sid]?.statusSince,
            contextFill: fill[sid], subagentRuns: subagentRuns,
            usage: usageByModel.values.sorted { $0.total > $1.total },
            title: resolved.title, titleSource: resolved.source, humanTurns: humanTurns
        )
    }

    /// First line in `order` that holds something the user actually typed, decoding only
    /// plausible candidates: tool-result envelopes share the `user` type but are filtered on
    /// a byte needle, and CLI wrappers are rejected after decoding. Bounded, because a
    /// session that opens with a long run of machine traffic shouldn't cost a full parse.
    private static func firstHumanText<S: Sequence<Range<Int>>>(in order: S, _ buf: Bytes.Buf) -> String? {
        var scanned = 0
        for r in order {
            let line = Bytes.slice(buf, r)
            guard Bytes.contains(line, pUser), !Bytes.contains(line, pToolResult) else { continue }
            scanned += 1
            // isMeta marks CLI-injected content (slash-command expansions and the like),
            // which reads like a prompt but isn't one the user wrote.
            if let d = decodeRaw(line), d.isMeta != true,
               let txt = d.message?.content?.displayText, !SessionTitle.isNoise(txt) {
                return txt.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if scanned > 40 { break }
        }
        return nil
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
        let isMeta: Bool?
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
