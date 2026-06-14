import Foundation

/// The only place that writes to disk. Every mutation is path-locked to a known config
/// file, backs the file up first (`*.agents-elements.bak`), and only flips a boolean or
/// appends a config entry — never deletes. Everything else in the app is read-only.
enum Mutator {
    enum MutationError: LocalizedError {
        case unsupported
        case fileMissing(String)
        case notFound(String)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupported: return "This element can't be toggled from here."
            case .fileMissing(let p): return "Config file not found: \(p)"
            case .notFound(let h): return "Couldn't find \(h) in the config file."
            case .writeFailed(let m): return "Write failed: \(m)"
            }
        }
    }

    /// Files this app is ever allowed to modify.
    private static var writable: [String] { [Paths.settings.path, Paths.codexConfig.path] }

    private static func guardWritable(_ url: URL) throws {
        guard writable.contains(url.path) else { throw MutationError.unsupported }
    }

    private static func backup(_ url: URL) throws {
        guard FS.fileExists(url) else { return }
        let bak = URL(fileURLWithPath: url.path + ".agents-elements.bak")
        try? FS.fm.removeItem(at: bak)
        try FS.fm.copyItem(at: url, to: bak)
    }

    // MARK: - Claude plugin (settings.json → enabledPlugins[key])

    static func setClaudePluginEnabled(key: String, enabled: Bool) throws {
        let url = Paths.settings
        try guardWritable(url)
        guard let data = try? Data(contentsOf: url),
              var obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { throw MutationError.fileMissing(url.path) }

        var ep = obj["enabledPlugins"] as? [String: Any] ?? [:]
        ep[key] = enabled
        obj["enabledPlugins"] = ep

        guard let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        else { throw MutationError.writeFailed("could not serialize settings.json") }
        try backup(url)
        do { try out.write(to: url, options: .atomic) }
        catch { throw MutationError.writeFailed(error.localizedDescription) }
    }

    // MARK: - Codex plugin (config.toml → [plugins."key"] enabled = bool)

    static func setCodexPluginEnabled(key: String, enabled: Bool) throws {
        let url = Paths.codexConfig
        try guardWritable(url)
        guard let lines = FS.readString(url)?.components(separatedBy: "\n") else {
            throw MutationError.fileMissing(url.path)
        }
        let edited = applyTOMLKey(lines, header: "[plugins.\"\(key)\"]",
                                  key: "enabled", value: enabled ? "true" : "false")
        try writeLines(edited, to: url)
    }

    // MARK: - Codex skill (config.toml → [[skills.config]] path/enabled)

    static func setCodexSkillEnabled(path: String, enabled: Bool) throws {
        let url = Paths.codexConfig
        try guardWritable(url)
        guard let lines = FS.readString(url)?.components(separatedBy: "\n") else {
            throw MutationError.fileMissing(url.path)
        }
        try writeLines(applySkillEnabled(lines, path: path, value: enabled ? "true" : "false"), to: url)
    }

    // MARK: - Pure line transforms (independently testable, no file IO)

    /// Sets `key = value` inside the section started by `header`, preserving every other
    /// line. Inserts the key (or appends the whole section) when missing.
    static func applyTOMLKey(_ input: [String], header: String, key: String, value: String) -> [String] {
        var lines = input
        guard let h = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == header }) else {
            if !(lines.last?.isEmpty ?? true) { lines.append("") }
            lines.append(contentsOf: [header, "\(key) = \(value)"])
            return lines
        }
        var k = h + 1
        var keyLine: Int?
        while k < lines.count {
            let t = lines[k].trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("[") { break }
            if t.hasPrefix(key),
               t.dropFirst(key.count).trimmingCharacters(in: .whitespaces).hasPrefix("=") { keyLine = k; break }
            k += 1
        }
        if let kl = keyLine { lines[kl] = "\(key) = \(value)" }
        else { lines.insert("\(key) = \(value)", at: h + 1) }
        return lines
    }

    /// Sets `enabled` on the `[[skills.config]]` block whose `path` matches; appends a new
    /// block when none matches.
    static func applySkillEnabled(_ input: [String], path: String, value: String) -> [String] {
        var lines = input
        var i = 0
        while i < lines.count {
            guard lines[i].trimmingCharacters(in: .whitespaces) == "[[skills.config]]" else { i += 1; continue }
            var j = i + 1
            var matches = false
            var enabledLine: Int?
            while j < lines.count {
                let t = lines[j].trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("[") { break }
                if t.hasPrefix("path"), CodexScanner.tomlQuoted(lines[j]) == path { matches = true }
                if t.hasPrefix("enabled") { enabledLine = j }
                j += 1
            }
            if matches {
                if let el = enabledLine { lines[el] = "enabled = \(value)" }
                else { lines.insert("enabled = \(value)", at: i + 1) }
                return lines
            }
            i = j
        }
        if !(lines.last?.isEmpty ?? true) { lines.append("") }
        lines.append(contentsOf: ["[[skills.config]]", "path = \"\(path)\"", "enabled = \(value)"])
        return lines
    }

    private static func writeLines(_ lines: [String], to url: URL) throws {
        try backup(url)
        do { try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8) }
        catch { throw MutationError.writeFailed(error.localizedDescription) }
    }

    // MARK: - Self-test (CLI: --selftest-mutations) — applies transforms in memory only

    static func runSelftestAndExit() -> Never {
        print("══ Mutation self-test — applies transforms in memory, writes NOTHING ══\n")

        if let toml = FS.readString(Paths.codexConfig) {
            let lines = toml.components(separatedBy: "\n")
            diff(lines, applyTOMLKey(lines, header: "[plugins.\"browser@openai-bundled\"]",
                                     key: "enabled", value: "false"),
                 "Codex plugin browser@openai-bundled → disable (in-place)")
            let sk = "/Users/altek/.codex/skills/codex-primary-runtime/spreadsheets/SKILL.md"
            diff(lines, applySkillEnabled(lines, path: sk, value: "true"),
                 "Codex skill spreadsheets → enable (flip existing block)")
            diff(lines, applySkillEnabled(lines, path: "/Users/altek/.codex/skills/demo/SKILL.md", value: "false"),
                 "Codex skill (unknown path) → disable (append new block)")
        } else { print("config.toml not found\n") }

        if let data = try? Data(contentsOf: Paths.settings),
           let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            let key = "token-optimizer@alexgreensh-token-optimizer"
            let before = obj["enabledPlugins"] as? [String: Any] ?? [:]
            var after = before; after[key] = false
            print("── Claude plugin \(key) → disable (settings.json) ──")
            print("     before: \(before)")
            print("     after:  \(after)\n")
        } else { print("settings.json not found\n") }

        exit(0)
    }

    /// Prints the minimal changed window (with 2 lines of leading context) between two
    /// line arrays — so the self-test shows exactly which lines a transform would touch.
    private static func diff(_ before: [String], _ after: [String], _ label: String) {
        print("── \(label) ──")
        var lo = 0
        while lo < before.count, lo < after.count, before[lo] == after[lo] { lo += 1 }
        var hi = 0
        while hi < before.count - lo, hi < after.count - lo,
              before[before.count - 1 - hi] == after[after.count - 1 - hi] { hi += 1 }
        for i in max(0, lo - 2)..<lo { print("     \(before[i])") }
        for l in before[lo..<(before.count - hi)] { print("  -  \(l)") }
        for l in after[lo..<(after.count - hi)] { print("  +  \(l)") }
        print("")
    }
}
