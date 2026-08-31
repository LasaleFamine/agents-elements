import Foundation

/// Resolving "what is this session about?" from what the CLIs already wrote to disk.
///
/// Neither transcript format has a single title field, but both agents generate one and
/// persist it — Claude Code as `ai-title` / `custom-title` sidecar records inside the JSONL,
/// Codex as a row in its own SQLite catalog. Deriving a title ourselves is the last resort,
/// not the first move, so the precedence below deliberately mirrors what Claude Code's own
/// resume picker does: a name the user chose beats one a model generated, which beats
/// anything we reconstruct from prompt text.
enum SessionTitle {

    /// The candidates a scanner collects while it walks a transcript. All optional — a
    /// session may carry none of them.
    struct Candidates {
        var agentName: String?
        var customTitle: String?
        var generated: String?    // Claude `aiTitle`, or Codex `display_title`
        var firstPrompt: String?
        var lastPrompt: String?
    }

    /// Resolve to the best available title and record where it came from.
    ///
    /// Everything gets condensed, including the CLI's own fields: accepting a plan can write
    /// the whole plan preamble into `customTitle`, and Codex will store a 300-character
    /// prompt as a thread title. Condensing is a no-op on anything already title-shaped.
    static func resolve(_ c: Candidates) -> (title: String?, source: TitleSource) {
        if let t = clean(c.customTitle) { return (condense(t), .custom) }
        if let t = clean(c.agentName) { return (condense(t), .agentName) }
        if let t = clean(c.generated) { return (condense(t), .generated) }
        if let t = clean(c.firstPrompt) { return (condense(t), .firstPrompt) }
        if let t = clean(c.lastPrompt) { return (condense(t), .lastPrompt) }
        return (nil, .none)
    }

    /// Trim and reject empties, so a present-but-blank field can't win the precedence.
    private static func clean(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    /// Squash a raw prompt into something title-shaped: first meaningful line, collapsed
    /// whitespace, cut at a word boundary. Codex in particular will happily store a
    /// 300-character prompt as a thread title.
    static func condense(_ s: String, limit: Int = 72) -> String {
        let line = s.split(whereSeparator: \.isNewline)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map(String.init) ?? s
        let flat = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard flat.count > limit else { return flat }
        let cut = String(flat.prefix(limit))
        // Prefer breaking on a space so we don't slice a word in half.
        if let sp = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: sp) > limit / 2 {
            return String(cut[..<sp]) + "…"
        }
        return cut + "…"
    }

    // MARK: - Prompt noise

    /// Wrappers the CLI injects into the `user` channel that are not things you typed.
    /// A transcript's literal first user message is usually one of these.
    private static let noisePrefixes = [
        "<command-name", "<command-message", "<command-args", "<local-command",
        "<task-notification", "<system-reminder", "<user-prompt-submit",
        "<bash-input", "<bash-stdout", "<bash-stderr", "Caveat:",
        // Synthetic markers the CLI writes into the user channel on an interruption.
        "[Request interrupted",
    ]

    /// True when a prompt is CLI plumbing rather than something the user typed.
    static func isNoise(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        return noisePrefixes.contains { t.hasPrefix($0) }
    }

    // MARK: - Signal

    /// Titles generated from an opening prompt are only as specific as that prompt was, and
    /// plenty of sessions open with "continue" or "what's the status?". Those produce real
    /// but useless titles ("Continue coding session", "Plan next steps"), which is worth
    /// knowing: it is the signal for offering to regenerate one, and it should never be
    /// mistaken for a title the user chose.
    private static let vagueWords: Set<String> = [
        "continue", "continued", "continuing", "proceed", "resume", "resumed", "next",
        "steps", "step", "session", "coding", "work", "working", "task", "run", "started",
        "start", "test", "testing", "something", "stuff", "changes", "change", "update",
        "review", "check", "status", "later", "minor", "misc", "general", "project", "the",
        "and", "with", "for", "from", "this", "that", "a", "an", "of", "to", "on", "in",
    ]

    /// A rough "does this tell me anything?" score. Low-signal means every meaningful word
    /// is generic filler, or there is almost nothing to go on.
    static func isLowSignal(_ title: String) -> Bool {
        let words = title.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 }
        if words.count < 2 { return true }
        return words.allSatisfy { vagueWords.contains($0) }
    }
}
