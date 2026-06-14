import SwiftUI

struct OverviewView: View {
    @Bindable var store: ElementsStore
    @Binding var selection: Category

    var body: some View {
        ScrollView {
            OverviewContent(store: store, selection: $selection)
        }
    }
}

/// The scrollable body of the Overview, factored out so it can also be rendered
/// inside a fixed frame for offscreen snapshots (ScrollView renders blank there).
struct OverviewContent: View {
    @Bindable var store: ElementsStore
    @Binding var selection: Category

    private let columns = [GridItem(.adaptive(minimum: 168, maximum: 240), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            statGrid
            if !store.liveSessions.isEmpty { liveNow }
            HStack(alignment: .top, spacing: 14) {
                recentSessions
                healthColumn
            }
        }
        .padding(20)
    }

    // MARK: Stat grid

    private var statGrid: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(statCategories, id: \.self) { cat in
                StatCard(
                    title: cat.title,
                    value: "\(store.count(for: cat))",
                    systemImage: cat.systemImage,
                    tint: cat.tint,
                    subtitle: subtitle(for: cat),
                    action: { selection = cat }
                )
            }
        }
    }

    private var statCategories: [Category] {
        [.skills, .subagents, .commands, .plugins, .sessions, .projects, .hooks, .plans]
    }

    private func subtitle(for cat: Category) -> String? {
        switch cat {
        case .skills:
            let p = store.skills.filter { if case .personal = $0.source { return true } else { return false } }.count
            return "\(p) personal · \(store.skills.count - p) plugin"
        case .subagents:
            let withAll = store.subagents.filter(\.hasAllTools).count
            return withAll > 0 ? "\(withAll) with all tools" : "tool-scoped"
        case .plugins:
            return "\(store.plugins.filter(\.enabled).count) enabled · \(store.marketplaces.count) markets"
        case .sessions:
            return "\(store.liveSessions.count) live · \(Format.bytes(store.totalSessionBytes))"
        case .commands:
            return "across \(Set(store.commands.map(\.source.label)).count) sources"
        case .projects:
            return "\(store.projects.filter { $0.liveCount > 0 }.count) active"
        case .hooks:
            return "event automations"
        case .plans:
            return "\(store.tasks.count) bg tasks"
        default: return nil
        }
    }

    // MARK: Live now

    private var liveNow: some View {
        VStack(alignment: .leading, spacing: 10) {
            DeckSectionHeader(title: "Live now", systemImage: "dot.radiowaves.left.and.right", tint: Palette.live)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(store.liveSessions) { s in
                        liveCard(s)
                    }
                }
            }
        }
    }

    private func liveCard(_ s: Session) -> some View {
        Button { selection = .sessions } label: {
            HStack(spacing: 12) {
                if let fill = s.contextFill {
                    ContextRing(percent: fill, size: 44)
                } else {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.title3).foregroundStyle(.pink)
                        .frame(width: 44, height: 44)
                        .background(.pink.opacity(0.15), in: Circle())
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.name ?? s.projectName).font(.subheadline.weight(.semibold)).lineLimit(1)
                    HStack(spacing: 6) {
                        StateBadge(state: .live, status: s.status)
                        if let m = s.model { Pill(text: shortModel(m), color: .blue) }
                    }
                }
            }
            .padding(12)
            .frame(width: 280, alignment: .leading)
            .deckSurface(cornerRadius: 12, glow: Palette.live, glowStrength: 0.4)
        }
        .buttonStyle(.plain)
    }

    // MARK: Recent sessions

    private var recentSessions: some View {
        VStack(alignment: .leading, spacing: 10) {
            DeckSectionHeader(title: "Recent sessions", systemImage: "clock.arrow.circlepath", tint: Palette.accent2)
            Card(padding: 6) {
                VStack(spacing: 0) {
                    ForEach(Array(store.sessions.prefix(6).enumerated()), id: \.element.id) { idx, s in
                        Button { selection = .sessions } label: {
                            HStack(spacing: 10) {
                                Image(systemName: s.state.systemImage)
                                    .font(.caption).foregroundStyle(s.state.color).frame(width: 16)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(s.name ?? s.projectName).font(.callout.weight(.medium)).lineLimit(1)
                                    Text(s.lastPrompt ?? "—").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text(Format.relative(s.lastActivity)).font(.caption2).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                        if idx < min(6, store.sessions.count) - 1 { Divider().padding(.leading, 34) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Health

    private var healthColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            DeckSectionHeader(title: "Health", systemImage: "waveform.path.ecg", tint: Palette.accent)
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    healthRow("Storage used by sessions", Format.bytes(store.totalSessionBytes),
                              icon: "internaldrive", tint: .blue)
                    Divider()
                    healthRow("Stale sessions (>14d)", "\(store.staleSessions.count)",
                              icon: "clock.badge.xmark", tint: store.staleSessions.isEmpty ? .green : .orange,
                              hint: store.staleSessions.isEmpty ? nil : "cleanup candidates")
                    Divider()
                    let disabled = store.plugins.filter { !$0.enabled }.count
                    healthRow("Disabled plugins", "\(disabled)",
                              icon: "puzzlepiece.extension", tint: disabled == 0 ? .green : .secondary)
                    Divider()
                    healthRow("MCP servers", "\(store.mcp.count)",
                              icon: "server.rack", tint: store.mcp.isEmpty ? .secondary : .teal,
                              hint: store.mcp.isEmpty ? "none configured" : nil)
                }
            }
        }
        .frame(maxWidth: 320, alignment: .leading)
    }

    private func healthRow(_ title: String, _ value: String, icon: String, tint: Color, hint: String? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout)
                if let hint { Text(hint).font(.caption2).foregroundStyle(.tertiary) }
            }
            Spacer()
            Text(value).font(.callout.weight(.semibold).monospacedDigit())
        }
    }

    private func shortModel(_ m: String) -> String {
        m.replacingOccurrences(of: "claude-", with: "")
         .replacingOccurrences(of: "-20", with: " ’")
    }
}
