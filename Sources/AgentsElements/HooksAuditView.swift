import SwiftUI

enum HookAudit {
    /// Heuristic: does this hook command look like it mutates the filesystem?
    static func isMutating(_ command: String) -> Bool {
        let c = command.lowercased()
        return ["rm ", "rm -", "unlink", "trash", "rmdir", "--clear", "--delete",
                "cleanup", "sweep", "prune", "truncate", "> /"].contains { c.contains($0) }
    }
}

struct HooksAuditView: View {
    @Bindable var store: ElementsStore
    @State private var selection: String?

    private var grouped: [(event: String, hooks: [HookInfo])] {
        Dictionary(grouping: store.hooks, by: \.event)
            .map { (event: $0.key, hooks: $0.value) }
            .sorted { $0.event < $1.event }
    }

    var body: some View {
        HSplitView {
            List(selection: $selection) {
                ForEach(grouped, id: \.event) { group in
                    Section(header: Text(group.event).microLabel().foregroundStyle(Palette.textTertiary)) {
                        ForEach(group.hooks) { h in row(h).tag(h.id) }
                    }
                }
            }
            .listStyle(.inset)
            .deckList()
            .frame(minWidth: 300, idealWidth: 360, maxWidth: 520)

            Group {
                if let id = selection, let h = store.hooks.first(where: { $0.id == id }) {
                    hookDetail(h)
                } else {
                    automationOverview
                }
            }
            .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func row(_ h: HookInfo) -> some View {
        let mutating = HookAudit.isMutating(h.command)
        return HStack(spacing: 9) {
            Image(systemName: mutating ? "exclamationmark.triangle.fill" : "bolt.horizontal.fill")
                .font(.caption).foregroundStyle(mutating ? .orange : .yellow).frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(h.source.label).font(.callout.weight(.medium)).foregroundStyle(Palette.textPrimary).lineLimit(1)
                Text(h.command).font(.caption.monospaced()).foregroundStyle(Palette.textTertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Detail — single hook

    private func hookDetail(_ h: HookInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DetailHeader(systemImage: "bolt.horizontal.fill", tint: .yellow, title: h.event) {
                    SourceBadge(source: h.source)
                }
                if HookAudit.isMutating(h.command) {
                    Label("This hook may modify or delete files", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.medium)).foregroundStyle(.orange)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.orange.opacity(0.4), lineWidth: 0.7))
                }
                if let m = h.matcher, !m.isEmpty { InfoRow(label: "Matcher", value: m, mono: true) }
                InfoRow(label: "Event", value: h.event)
                DeckSectionHeader(title: "Command", systemImage: "chevron.left.forwardslash.chevron.right")
                BodyPreview(text: h.command).frame(minHeight: 120)
            }
            .padding(20)
        }
    }

    // MARK: Detail — default automation overview

    private var automationOverview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DetailHeader(systemImage: "gearshape.2.fill", tint: .yellow, title: "Automation audit",
                             subtitle: "\(store.hooks.count) hooks across \(grouped.count) events")

                DeckSectionHeader(title: "Sweeps of ~/.claude", systemImage: "trash.circle", tint: .orange)
                if store.sweeps.isEmpty {
                    Text("No cleanup markers found.").font(.callout).foregroundStyle(Palette.textTertiary)
                } else {
                    Text("Automated tools periodically prune ~/.claude. These markers record the last run of each — useful when files (like old session transcripts) disappear on their own.")
                        .font(.callout).foregroundStyle(Palette.textSecondary)
                    ForEach(store.sweeps) { s in sweepCard(s) }
                }

                if !store.codexRules.isEmpty {
                    DeckSectionHeader(title: "Codex command rules", systemImage: "hand.raised.fill", tint: Provider.codex.tint)
                    Text("Codex auto-approves matching command prefixes without prompting. These come from ~/.codex/rules.")
                        .font(.callout).foregroundStyle(Palette.textSecondary)
                    ForEach(store.codexRules) { r in ruleRow(r) }
                }

                let mutating = store.hooks.filter { HookAudit.isMutating($0.command) }
                DeckSectionHeader(title: "Flagged hooks", systemImage: "exclamationmark.triangle", tint: .orange)
                if mutating.isEmpty {
                    Text("No registered hooks reference deletion or cleanup keywords. (Note: a hook can still mutate files via a script it launches — the command string is all that's inspected here.)")
                        .font(.callout).foregroundStyle(Palette.textTertiary)
                } else {
                    ForEach(mutating) { h in
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(h.source.label) · \(h.event)").font(.callout.weight(.medium))
                                Text(h.command).font(.caption.monospaced()).foregroundStyle(Palette.textTertiary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(20)
        }
    }

    private func ruleRow(_ r: CodexRule) -> some View {
        let color: Color = r.decision.lowercased() == "deny" ? .red
            : (r.decision.lowercased() == "ask" ? .orange : .green)
        return HStack(spacing: 9) {
            Image(systemName: r.allows ? "checkmark.shield.fill" : "xmark.shield.fill")
                .font(.caption).foregroundStyle(color).frame(width: 16)
            Text(r.pattern).font(.callout.monospaced()).foregroundStyle(Palette.textPrimary)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 6)
            Pill(text: r.decision, color: color)
        }
        .padding(.vertical, 2)
    }

    private func sweepCard(_ s: SweepMarker) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "trash.fill").foregroundStyle(.orange)
                        .frame(width: 26, height: 26)
                        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.name).font(.headline).foregroundStyle(Palette.textPrimary)
                        Text(s.owner).font(.caption2).foregroundStyle(Palette.textTertiary)
                    }
                    Spacer()
                    if let t = s.timestamp {
                        Text(Format.relative(t)).font(.caption.monospacedDigit()).foregroundStyle(.orange)
                    }
                }
                if let d = s.detail {
                    Text(d).font(.callout).foregroundStyle(Palette.textSecondary)
                }
                Text(s.path).font(.caption2.monospaced()).foregroundStyle(Palette.textTertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
    }
}
