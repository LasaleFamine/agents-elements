import SwiftUI

struct RelationshipsView: View {
    @Bindable var store: ElementsStore

    enum Lens: String, CaseIterable, Identifiable {
        case agents = "Subagents → Tools"
        case plugins = "Plugins → Contributions"
        case projects = "Projects → Resources"
        var id: String { rawValue }
    }
    @State private var lens: Lens = .agents

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Who can use what")
                    .font(.title2.weight(.bold))
                Text("Trace which tools, contributions, and resources each element exposes.")
                    .font(.callout).foregroundStyle(.secondary)
                Picker("", selection: $lens) {
                    ForEach(Lens.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(spacing: 10) {
                    switch lens {
                    case .agents: agentsLens
                    case .plugins: pluginsLens
                    case .projects: projectsLens
                    }
                }
                .padding(20)
            }
        }
    }

    // MARK: Subagents → tools

    private var agentsLens: some View {
        ForEach(store.subagents) { a in
            NodeCard(icon: "person.2.fill", tint: .blue,
                     title: a.scope.map { "\(a.name)  ·  \($0)" } ?? a.name,
                     badge: SourceBadge(source: a.source)) {
                if a.hasAllTools {
                    Pill(text: "All tools (*)", systemImage: "infinity", color: .orange)
                } else if a.tools.isEmpty {
                    Text("No tools declared").font(.caption).foregroundStyle(.tertiary)
                } else {
                    FlowLayout(spacing: 6) { ForEach(a.tools, id: \.self) { Pill(text: $0, color: .blue) } }
                }
            }
        }
    }

    // MARK: Plugins → contributions

    private var pluginsLens: some View {
        ForEach(store.plugins) { p in
            NodeCard(icon: "puzzlepiece.extension.fill", tint: .orange, title: p.name,
                     badge: Pill(text: p.enabled ? "Enabled" : "Disabled",
                                 color: p.enabled ? .green : .secondary)) {
                FlowLayout(spacing: 6) {
                    if p.skillCount > 0 { Pill(text: "\(p.skillCount) skills", systemImage: "wand.and.stars", color: .purple) }
                    if p.agentCount > 0 { Pill(text: "\(p.agentCount) agents", systemImage: "person.2.fill", color: .blue) }
                    if p.commandCount > 0 { Pill(text: "\(p.commandCount) commands", systemImage: "terminal.fill", color: .green) }
                    if p.hookCount > 0 { Pill(text: "\(p.hookCount) hooks", systemImage: "bolt.horizontal.fill", color: .yellow) }
                    if p.contributes == 0 { Text("No bundled elements").font(.caption).foregroundStyle(.tertiary) }
                }
            }
        }
    }

    // MARK: Projects → resources

    private var projectsLens: some View {
        ForEach(store.projects) { p in
            let cmds = matchedCommands(for: p)
            NodeCard(icon: "folder.fill", tint: .brown, title: p.displayName,
                     badge: p.liveCount > 0 ? Pill(text: "\(p.liveCount) live", color: .green) : nil) {
                FlowLayout(spacing: 6) {
                    Pill(text: "\(p.sessionCount) sessions", systemImage: "bubble.left.and.bubble.right.fill", color: .pink)
                    ForEach(p.mcpServers, id: \.self) { Pill(text: $0, systemImage: "server.rack", color: .teal) }
                    ForEach(cmds.prefix(8), id: \.id) { c in
                        Pill(text: "/" + ((c.name as NSString).lastPathComponent), systemImage: "terminal.fill", color: .green)
                    }
                    if p.mcpServers.isEmpty && cmds.isEmpty {
                        Text("No project-scoped commands or MCP").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    /// Heuristically links namespaced commands to a project by matching the command's
    /// namespace (e.g. "lualtek/console") against the project's path.
    private func matchedCommands(for project: ProjectInfo) -> [SlashCommand] {
        let path = project.name.lowercased()
        return store.commands.filter { c in
            let comps = c.name.split(separator: "/").dropLast()
            guard !comps.isEmpty else { return false }
            return path.contains(comps.joined(separator: "/").lowercased())
        }
    }
}

/// A relationship "node": titled card with a trailing badge and a body of connected chips.
struct NodeCard<Badge: View, Content: View>: View {
    let icon: String
    let tint: Color
    let title: String
    var badge: Badge?
    @ViewBuilder var content: Content

    init(icon: String, tint: Color, title: String, badge: Badge?, @ViewBuilder content: () -> Content) {
        self.icon = icon; self.tint = tint; self.title = title; self.badge = badge; self.content = content()
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: icon).foregroundStyle(tint)
                        .frame(width: 28, height: 28)
                        .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
                    Text(title).font(.headline)
                    Spacer()
                    if let badge { badge }
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.turn.down.right").font(.caption).foregroundStyle(.tertiary)
                        .padding(.top, 3)
                    content
                }
            }
        }
    }
}
