import Foundation

/// Per-model token usage extracted from a session's JSONL `usage` blocks.
/// Normalized to Anthropic's convention: `input` is *uncached* input; `cacheRead`
/// is cached/served input; `cacheCreate` is cache writes (Claude only).
struct ModelUsage: Hashable, Sendable, Identifiable {
    var id: String { model }
    let model: String
    var input: Int = 0
    var output: Int = 0
    var cacheRead: Int = 0
    var cacheCreate: Int = 0

    var total: Int { input + output + cacheRead + cacheCreate }
}

/// Estimated API cost. Rates per 1M tokens.
/// Claude — Claude API reference (cached 2026-06-04): Opus $5/$25, Sonnet $3/$15,
///   Haiku $1/$5, Fable $10/$50. Cache read ≈0.1× input, write ≈1.25× input.
/// GPT — openai/aggregators (fetched 2026-06): GPT-5.5 $5/$30, GPT-5.4 $2.50/$15,
///   GPT-5.4 mini $0.75/$4.50, GPT-5/codex $1.25/$10. Cached input ≈0.1× input.
/// Override any of these via ~/.config/agents-elements/pricing.json.
enum Pricing {
    struct Rate: Sendable { let input: Double; let output: Double }

    /// Built-in defaults, matched by substring (longest key wins).
    private static let defaults: [(key: String, rate: Rate)] = [
        ("gpt-5.5", Rate(input: 5, output: 30)),
        ("gpt-5.4-mini", Rate(input: 0.75, output: 4.50)),
        ("gpt-5.4-nano", Rate(input: 0.20, output: 1.25)),
        ("gpt-5.4", Rate(input: 2.50, output: 15)),
        ("gpt-5-codex", Rate(input: 1.25, output: 10)),
        ("gpt-5-mini", Rate(input: 0.25, output: 2)),
        ("gpt-5", Rate(input: 1.25, output: 10)),
        ("gpt", Rate(input: 5, output: 30)),
        ("fable", Rate(input: 10, output: 50)),
        ("mythos", Rate(input: 10, output: 50)),
        ("opus", Rate(input: 5, output: 25)),
        ("sonnet", Rate(input: 3, output: 15)),
        ("haiku", Rate(input: 1, output: 5)),
    ]

    /// User overrides loaded once from ~/.config/agents-elements/pricing.json
    /// (`{"rates": {"gpt-5.5": {"input": 5, "output": 30}, ...}}`).
    private static let overrides: [(key: String, rate: Rate)] = loadOverrides()

    private static func loadOverrides() -> [(key: String, rate: Rate)] {
        let url = Paths.home.appendingPathComponent(".config/agents-elements/pricing.json")
        guard let obj = FS.readJSON(url) as? [String: Any],
              let rates = obj["rates"] as? [String: Any] else { return [] }
        return rates.compactMap { key, v in
            guard let d = v as? [String: Any],
                  let i = (d["input"] as? NSNumber)?.doubleValue,
                  let o = (d["output"] as? NSNumber)?.doubleValue else { return nil }
            return (key.lowercased(), Rate(input: i, output: o))
        }
    }

    static func rate(for model: String) -> Rate {
        let m = model.lowercased()
        for (key, rate) in overrides.sorted(by: { $0.key.count > $1.key.count }) where m.contains(key) {
            return rate
        }
        for (key, rate) in defaults where m.contains(key) { return rate }
        return Rate(input: 5, output: 25)   // unknown → Opus-tier
    }

    static func cost(_ u: ModelUsage) -> Double {
        let r = rate(for: u.model)
        let cacheReadRate = r.input * 0.10
        let cacheWriteRate = r.input * 1.25
        return (Double(u.input) * r.input
                + Double(u.output) * r.output
                + Double(u.cacheRead) * cacheReadRate
                + Double(u.cacheCreate) * cacheWriteRate) / 1_000_000
    }

    static func cost(_ usage: [ModelUsage]) -> Double { usage.reduce(0) { $0 + cost($1) } }

    static func money(_ v: Double) -> String {
        if v >= 100 { return String(format: "$%.0f", v) }
        if v >= 1 { return String(format: "$%.2f", v) }
        if v > 0 { return String(format: "$%.3f", v) }
        return "$0"
    }

    /// Short, friendly model label, e.g. "opus 4.8" / "gpt-5.5".
    static func shortName(_ model: String) -> String {
        var s = model.replacingOccurrences(of: "claude-", with: "")
        if s.hasPrefix("gpt") { return s }   // keep gpt-5.5 as-is
        // collapse version hyphens between digits into dots: opus-4-8 -> opus 4.8
        var out = ""
        let chars = Array(s)
        for (i, c) in chars.enumerated() {
            if c == "-" {
                let prev = i > 0 ? chars[i - 1] : " "
                let next = i + 1 < chars.count ? chars[i + 1] : " "
                out.append(prev.isNumber && next.isNumber ? "." : " ")
            } else {
                out.append(c)
            }
        }
        s = out
        return s
    }
}
