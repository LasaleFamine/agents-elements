import Foundation
import Darwin

/// Canonical on-disk locations under ~/.claude that we inventory.
enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let claude = home.appendingPathComponent(".claude")
    static let skills = claude.appendingPathComponent("skills")
    static let agents = claude.appendingPathComponent("agents")
    static let commands = claude.appendingPathComponent("commands")
    static let projects = claude.appendingPathComponent("projects")
    static let sessions = claude.appendingPathComponent("sessions")
    static let plans = claude.appendingPathComponent("plans")
    static let tasks = claude.appendingPathComponent("tasks")
    static let plugins = claude.appendingPathComponent("plugins")
    static let settings = claude.appendingPathComponent("settings.json")
    static let claudeJSON = home.appendingPathComponent(".claude.json")
    static let installedPlugins = plugins.appendingPathComponent("installed_plugins.json")
    static let knownMarketplaces = plugins.appendingPathComponent("known_marketplaces.json")
    static let liveFill = claude.appendingPathComponent("token-optimizer/live-fill.json")

    // Codex (~/.codex)
    static let codex = home.appendingPathComponent(".codex")
    static let codexSkills = codex.appendingPathComponent("skills")
    static let codexSessions = codex.appendingPathComponent("sessions")
    static let codexConfig = codex.appendingPathComponent("config.toml")
    static let codexSessionIndex = codex.appendingPathComponent("session_index.jsonl")
    static let codexRules = codex.appendingPathComponent("rules")
    static let codexProcesses = codex.appendingPathComponent("process_manager/chat_processes.json")
}

/// Thin, forgiving filesystem helpers. All read-only except `trashItem`.
enum FS {
    static var fm: FileManager { .default }

    static func readString(_ url: URL) -> String? {
        if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        if let d = try? Data(contentsOf: url) { return String(decoding: d, as: UTF8.self) }
        return nil
    }

    static func readJSON(_ url: URL) -> Any? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: d)
    }

    static func dirExists(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    static func fileExists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }

    static func contents(_ url: URL) -> [URL] {
        (try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    /// Like `contents`, but includes dot-directories (e.g. Codex's `skills/.system`).
    static func contentsAll(_ url: URL) -> [URL] {
        ((try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )) ?? []).filter { $0.lastPathComponent != ".git" && $0.lastPathComponent != ".DS_Store" }
    }

    static func size(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// True if a process with this pid currently exists.
    static func processAlive(_ pid: Int) -> Bool {
        // signal 0 performs error checking only. 0 => alive; EPERM => alive but not ours.
        if kill(pid_t(pid), 0) == 0 { return true }
        return errno == EPERM
    }
}

/// Minimal YAML-frontmatter splitter (no external YAML dependency).
/// Handles the `---` fenced block at the top of skill/agent/command markdown.
struct Frontmatter {
    private(set) var fields: [String: String] = [:]
    private(set) var body: String = ""

    init(_ content: String) {
        let lines = content.components(separatedBy: "\n")
        var i = 0
        while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).isEmpty { i += 1 }
        guard i < lines.count, lines[i].trimmingCharacters(in: .whitespaces) == "---" else {
            body = content
            return
        }
        i += 1
        var fmLines: [String] = []
        var closed = false
        while i < lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" { i += 1; closed = true; break }
            fmLines.append(lines[i]); i += 1
        }
        guard closed else { body = content; return }
        body = i < lines.count ? lines[i...].joined(separator: "\n") : ""

        for line in fmLines {
            // top-level `key: value` only (ignore nested/indented list items)
            guard let colon = line.firstIndex(of: ":"),
                  let firstChar = line.first, firstChar != " ", firstChar != "-" else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let val = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { fields[key] = val }
        }
    }

    func string(_ key: String) -> String? {
        guard var v = fields[key], !v.isEmpty else { return nil }
        if (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")), v.count >= 2 {
            v = String(v.dropFirst().dropLast())
        }
        return v
    }

    func list(_ key: String) -> [String] {
        guard let v = string(key) else { return [] }
        if v == "*" { return ["*"] }
        var s = v
        if s.hasPrefix("[") && s.hasSuffix("]") { s = String(s.dropFirst().dropLast()) }
        return s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

extension String {
    /// First markdown body paragraph, with headings/frontmatter noise trimmed — for previews.
    func firstMeaningfulParagraph(limit: Int = 600) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(limit))
    }
}
