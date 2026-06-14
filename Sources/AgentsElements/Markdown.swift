import SwiftUI

/// A tiny, dependency-free Markdown block renderer for file previews.
///
/// Handles the block grammar that actually shows up in SKILL.md / agent / command /
/// plan files: ATX headings, fenced code, blockquotes, bullet + ordered lists,
/// horizontal rules, simple tables, and paragraphs. Inline emphasis/code/links are
/// delegated to `AttributedString`'s inline-only Markdown parser.
struct MarkdownView: View {
    let markdown: String

    var body: some View {
        let blocks = MarkdownBlock.parse(markdown)
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                block.view
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(Palette.accent2)
    }
}

// MARK: - Blocks

enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case code(language: String?, body: String)
    case bullets([String])
    case ordered([(marker: String, text: String)])
    case quote(String)
    case table([String])
    case rule

    @MainActor @ViewBuilder var view: some View {
        switch self {
        case .heading(let level, let text):
            MarkdownBlock.inline(text)
                .font(headingFont(level))
                .foregroundStyle(Palette.textPrimary)
                .padding(.top, level <= 2 ? 4 : 1)

        case .paragraph(let s):
            MarkdownBlock.inline(s)
                .font(.callout)
                .foregroundStyle(Palette.textPrimary.opacity(0.86))
                .lineSpacing(2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

        case .code(let language, let body):
            VStack(alignment: .leading, spacing: 4) {
                if let language, !language.isEmpty {
                    Text(language.lowercased()).microLabel().foregroundStyle(Palette.textTertiary)
                }
                Text(body)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Palette.textPrimary.opacity(0.92))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.stroke, lineWidth: 0.6))

        case .bullets(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(Palette.accent2).font(.callout)
                        MarkdownBlock.inline(item)
                            .font(.callout).foregroundStyle(Palette.textPrimary.opacity(0.86))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }

        case .ordered(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.marker + ".").foregroundStyle(Palette.accent2)
                            .font(.callout.monospacedDigit())
                        MarkdownBlock.inline(item.text)
                            .font(.callout).foregroundStyle(Palette.textPrimary.opacity(0.86))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }

        case .quote(let s):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(Palette.accent.opacity(0.7)).frame(width: 3)
                MarkdownBlock.inline(s)
                    .font(.callout.italic()).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

        case .table(let rows):
            Text(rows.joined(separator: "\n"))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Palette.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))

        case .rule:
            Rectangle().fill(Palette.stroke).frame(height: 1).padding(.vertical, 2)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2.weight(.bold)
        case 2: return .title3.weight(.bold)
        case 3: return .headline
        default: return .subheadline.weight(.semibold)
        }
    }

    /// Inline emphasis / code / links via the system inline-only Markdown parser.
    static func inline(_ s: String) -> Text {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attr = try? AttributedString(markdown: s, options: opts) {
            return Text(attr)
        }
        return Text(s)
    }

    // MARK: Parsing

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        func trimmedLeading(_ s: String) -> String {
            String(s.drop { $0 == " " || $0 == "\t" })
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // blank → spacing only
            if trimmed.isEmpty { i += 1; continue }

            // fenced code
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fence = String(trimmed.prefix(3))
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    body.append(lines[i]); i += 1
                }
                if i < lines.count { i += 1 } // consume closing fence
                blocks.append(.code(language: lang.isEmpty ? nil : lang, body: body.joined(separator: "\n")))
                continue
            }

            // horizontal rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.rule); i += 1; continue
            }

            // heading
            if let level = headingLevel(trimmed) {
                let txt = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: level, text: txt)); i += 1; continue
            }

            // blockquote (consecutive)
            if trimmed.hasPrefix(">") {
                var quoted: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    let q = lines[i].trimmingCharacters(in: .whitespaces)
                    quoted.append(String(q.dropFirst()).trimmingCharacters(in: .whitespaces)); i += 1
                }
                blocks.append(.quote(quoted.joined(separator: " "))); continue
            }

            // table (consecutive lines starting with |)
            if trimmed.hasPrefix("|") {
                var rows: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(lines[i].trimmingCharacters(in: .whitespaces)); i += 1
                }
                blocks.append(.table(rows)); continue
            }

            // bullet list (consecutive)
            if isBullet(trimmedLeading(line)) {
                var items: [String] = []
                while i < lines.count, isBullet(trimmedLeading(lines[i])) {
                    let t = trimmedLeading(lines[i])
                    items.append(String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)); i += 1
                }
                blocks.append(.bullets(items)); continue
            }

            // ordered list (consecutive)
            if let _ = orderedMarker(trimmedLeading(line)) {
                var items: [(String, String)] = []
                while i < lines.count, let m = orderedMarker(trimmedLeading(lines[i])) {
                    let t = trimmedLeading(lines[i])
                    let rest = String(t.dropFirst(m.count + 1)).trimmingCharacters(in: .whitespaces)
                    items.append((m, rest)); i += 1
                }
                blocks.append(.ordered(items)); continue
            }

            // paragraph (consecutive plain lines)
            var para: [String] = []
            while i < lines.count {
                let l = lines[i]
                let t = l.trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.hasPrefix("```") || t.hasPrefix("~~~") || t.hasPrefix(">")
                    || t.hasPrefix("|") || headingLevel(t) != nil
                    || t == "---" || t == "***" || t == "___"
                    || isBullet(trimmedLeading(l)) || orderedMarker(trimmedLeading(l)) != nil {
                    break
                }
                para.append(t); i += 1
            }
            if !para.isEmpty { blocks.append(.paragraph(para.joined(separator: " "))) }
        }
        return blocks
    }

    private static func headingLevel(_ line: String) -> Int? {
        var n = 0
        for c in line { if c == "#" { n += 1 } else { break } }
        guard (1...6).contains(n) else { return nil }
        let idx = line.index(line.startIndex, offsetBy: n)
        return idx < line.endIndex && line[idx] == " " ? n : nil
    }

    private static func isBullet(_ s: String) -> Bool {
        guard s.count >= 2 else { return false }
        let first = s.first!
        let second = s[s.index(after: s.startIndex)]
        return (first == "-" || first == "*" || first == "+") && second == " "
    }

    /// Returns the numeric marker (e.g. "3") if the line is an ordered list item `3. text`.
    private static func orderedMarker(_ s: String) -> String? {
        var digits = ""
        for c in s { if c.isNumber { digits.append(c) } else { break } }
        guard !digits.isEmpty else { return nil }
        let idx = s.index(s.startIndex, offsetBy: digits.count)
        guard idx < s.endIndex else { return nil }
        let sep = s[idx]
        guard sep == "." || sep == ")" else { return nil }
        let afterIdx = s.index(after: idx)
        guard afterIdx < s.endIndex, s[afterIdx] == " " else { return nil }
        return digits
    }
}

// MARK: - Preview container (Rendered / Raw toggle)

/// Styled, scrollable container that renders a markdown body — matching `BodyPreview`'s
/// look — with a Rendered/Raw toggle so you can still inspect the source.
struct MarkdownPreview: View {
    let text: String
    var showsToggle: Bool = true
    @State private var raw = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsToggle && !text.isEmpty {
                HStack {
                    Spacer()
                    Picker("", selection: $raw) {
                        Text("Rendered").tag(false)
                        Text("Raw").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    .frame(width: 168).controlSize(.small)
                }
            }
            ScrollView {
                Group {
                    if text.isEmpty {
                        Text("No content.").font(.callout).foregroundStyle(Palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if raw {
                        Text(text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Palette.textPrimary.opacity(0.85))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        MarkdownView(markdown: text)
                    }
                }
                .padding(14)
            }
            .background(Palette.canvasBottom.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.stroke, lineWidth: 0.7))
        }
    }
}
