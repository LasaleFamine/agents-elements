import SwiftUI

// MARK: - Generic list + detail scaffold

struct CatalogPane<Item: Identifiable & Hashable, Row: View, Detail: View>: View {
    let items: [Item]
    let searchableText: (Item) -> String
    var searchPrompt: String = "Search"
    @ViewBuilder let row: (Item) -> Row
    @ViewBuilder let detail: (Item) -> Detail

    @State private var selection: Item.ID?
    @State private var query = ""

    private var filtered: [Item] {
        guard !query.isEmpty else { return items }
        return items.filter { searchableText($0).localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(filtered, selection: $selection) { item in
                    row(item).tag(item.id)
                }
                .listStyle(.inset)
                .deckList()
                .searchable(text: $query, placement: .sidebar, prompt: searchPrompt)
            }
            .frame(minWidth: 270, idealWidth: 330, maxWidth: 460)

            Group {
                if let id = selection, let item = items.first(where: { $0.id == id }) {
                    detail(item)
                } else {
                    EmptyStateView(systemImage: "sidebar.left",
                                   title: items.isEmpty ? "Nothing here yet" : "Select an item",
                                   message: items.isEmpty ? nil : "Pick something on the left to see details.")
                }
            }
            .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { if selection == nil { selection = filtered.first?.id } }
    }
}

/// A compact two-line list row with a leading icon.
struct ItemRow<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    var tint: Color = .secondary
    var provider: Provider? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium)).lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let provider { ProviderBadge(provider: provider, compact: true) }
            trailing
        }
        .padding(.vertical, 3)
    }
}

extension ItemRow where Trailing == EmptyView {
    init(title: String, subtitle: String?, systemImage: String, tint: Color = .secondary, provider: Provider? = nil) {
        self.init(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint, provider: provider) { EmptyView() }
    }
}

private func detailScaffold<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    ScrollView {
        VStack(alignment: .leading, spacing: 18) { content() }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Skills

struct SkillsView: View {
    @Bindable var store: ElementsStore
    var body: some View {
        CatalogPane(items: store.skills,
                    searchableText: { "\($0.name) \($0.description) \($0.source.label)" },
                    searchPrompt: "Search skills") { s in
            ItemRow(title: s.name, subtitle: s.description, systemImage: "wand.and.stars",
                    tint: s.enabled ? .purple : .secondary, provider: s.provider) {
                if !s.enabled { Image(systemName: "pause.circle.fill").font(.caption2).foregroundStyle(.orange) }
                if s.source.isPlugin { Image(systemName: "puzzlepiece.extension.fill").font(.caption2).foregroundStyle(.orange) }
            }
        } detail: { s in
            detailScaffold {
                DetailHeader(systemImage: "wand.and.stars", tint: .purple, title: s.name) {
                    HStack(spacing: 8) {
                        if store.canToggle(skill: s) {
                            Pill(text: s.enabled ? "Enabled" : "Disabled",
                                 systemImage: s.enabled ? "checkmark.circle.fill" : "pause.circle",
                                 color: s.enabled ? .green : .orange)
                        }
                        SourceBadge(source: s.source)
                    }
                }
                if !s.description.isEmpty {
                    Text(s.description).font(.title3).foregroundStyle(.secondary)
                }
                HStack { if let l = s.license { Pill(text: l, systemImage: "checkmark.seal", color: .green) } }
                InfoRow(label: "Path", value: s.path, mono: true)
                SkillManageControl(store: store, skill: s)
                MarkdownPreview(text: s.body).frame(minHeight: 220)
            }
        }
    }
}

// MARK: - Subagents

struct SubagentsView: View {
    @Bindable var store: ElementsStore
    var body: some View {
        CatalogPane(items: store.subagents,
                    searchableText: { "\($0.name) \($0.scope ?? "") \($0.description) \($0.tools.joined(separator: " "))" },
                    searchPrompt: "Search subagents") { a in
            ItemRow(title: a.name,
                    subtitle: a.scope.map { "\($0) · \(a.description)" } ?? a.description,
                    systemImage: "person.2.fill", tint: .blue) {
                Pill(text: a.hasAllTools ? "all tools" : "\(a.tools.count)",
                     color: a.hasAllTools ? .orange : .blue)
            }
        } detail: { a in
            detailScaffold {
                DetailHeader(systemImage: "person.2.fill", tint: .blue, title: a.name, subtitle: a.scope) {
                    SourceBadge(source: a.source)
                }
                if !a.description.isEmpty {
                    Text(a.description).font(.title3).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Label("Tool access", systemImage: "wrench.and.screwdriver.fill").font(.headline)
                    if a.hasAllTools {
                        Pill(text: "All tools (*)", systemImage: "infinity", color: .orange)
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(a.tools, id: \.self) { Pill(text: $0, color: .blue) }
                        }
                    }
                }
                if let m = a.model { InfoRow(label: "Model", value: m, mono: true) }
                InfoRow(label: "Path", value: a.path, mono: true)
                MarkdownPreview(text: a.body).frame(minHeight: 200)
            }
        }
    }
}

// MARK: - Commands

struct CommandsView: View {
    @Bindable var store: ElementsStore
    var body: some View {
        CatalogPane(items: store.commands,
                    searchableText: { "\($0.name) \($0.description ?? "") \($0.source.label)" },
                    searchPrompt: "Search commands") { c in
            ItemRow(title: "/" + c.name.replacingOccurrences(of: "/", with: ":"),
                    subtitle: c.description, systemImage: "terminal.fill", tint: .green)
        } detail: { c in
            detailScaffold {
                DetailHeader(systemImage: "terminal.fill", tint: .green,
                             title: "/" + c.name.replacingOccurrences(of: "/", with: ":")) {
                    SourceBadge(source: c.source)
                }
                if let d = c.description { Text(d).font(.title3).foregroundStyle(.secondary) }
                if let h = c.argumentHint { InfoRow(label: "Arguments", value: h, mono: true) }
                InfoRow(label: "Path", value: c.path, mono: true)
                MarkdownPreview(text: c.body).frame(minHeight: 220)
            }
        }
    }
}

// MARK: - Plugins

struct PluginsView: View {
    @Bindable var store: ElementsStore
    var body: some View {
        CatalogPane(items: store.plugins,
                    searchableText: { "\($0.name) \($0.marketplace) \($0.description ?? "")" },
                    searchPrompt: "Search plugins") { p in
            ItemRow(title: p.name, subtitle: p.description ?? p.marketplace,
                    systemImage: "puzzlepiece.extension.fill", tint: .orange, provider: p.provider) {
                Circle().fill(p.enabled ? .green : .secondary).frame(width: 7, height: 7)
            }
        } detail: { p in
            detailScaffold {
                DetailHeader(systemImage: "puzzlepiece.extension.fill", tint: .orange, title: p.name,
                             subtitle: p.marketplace) {
                    Pill(text: p.enabled ? "Enabled" : "Disabled",
                         systemImage: p.enabled ? "checkmark.circle.fill" : "pause.circle",
                         color: p.enabled ? .green : .secondary)
                }
                if let d = p.description { Text(d).font(.title3).foregroundStyle(.secondary) }
                HStack(spacing: 10) {
                    contributionChip("Skills", p.skillCount, "wand.and.stars", .purple)
                    contributionChip("Agents", p.agentCount, "person.2.fill", .blue)
                    contributionChip("Commands", p.commandCount, "terminal.fill", .green)
                    contributionChip("Hooks", p.hookCount, "bolt.horizontal.fill", .yellow)
                }
                VStack(alignment: .leading, spacing: 6) {
                    if let v = p.version { InfoRow(label: "Version", value: v, mono: true) }
                    if let s = p.scope { InfoRow(label: "Scope", value: s) }
                    if let at = p.installedAt { InfoRow(label: "Installed", value: at, mono: true) }
                    if let ip = p.installPath { InfoRow(label: "Path", value: ip, mono: true) }
                }
                PluginManageControl(store: store, plugin: p)
                if !store.marketplaces.isEmpty {
                    Divider()
                    Label("Marketplaces", systemImage: "bag.fill").font(.headline)
                    ForEach(store.marketplaces) { m in
                        HStack {
                            Image(systemName: m.sourceType == "github" ? "link" : "folder")
                                .foregroundStyle(.orange).frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(m.name).font(.callout.weight(.medium))
                                Text(m.location).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Pill(text: "\(m.catalogCount) available", color: .secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func contributionChip(_ label: String, _ count: Int, _ icon: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(tint.opacity(count > 0 ? 1 : 0.35))
            Text("\(count)").font(.title3.weight(.bold).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Palette.surfaceHi, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - MCP (currently empty → informative empty state)

struct MCPView: View {
    @Bindable var store: ElementsStore
    var body: some View {
        if store.mcp.isEmpty {
            EmptyStateView(
                systemImage: "server.rack",
                title: "No MCP servers configured",
                message: "MCP servers extend your agents with external tools. When you add them globally or per-project, they’ll appear here with their scope and which projects can use them.",
                tint: .teal
            )
        } else {
            CatalogPane(items: store.mcp,
                        searchableText: { "\($0.name) \($0.scope)" },
                        searchPrompt: "Search MCP servers") { s in
                ItemRow(title: s.name, subtitle: s.scope, systemImage: "server.rack", tint: .teal, provider: s.provider)
            } detail: { s in
                detailScaffold {
                    DetailHeader(systemImage: "server.rack", tint: .teal, title: s.name, subtitle: s.scope)
                    if let t = s.type { InfoRow(label: "Type", value: t) }
                    if let c = s.command { InfoRow(label: "Command", value: c, mono: true) }
                }
            }
        }
    }
}

// MARK: - Plans

struct PlansView: View {
    @Bindable var store: ElementsStore
    var body: some View {
        CatalogPane(items: store.plans,
                    searchableText: { "\($0.title ?? "") \($0.name)" },
                    searchPrompt: "Search plans") { p in
            ItemRow(title: p.title ?? p.name, subtitle: p.name + " · " + Format.relative(p.modified),
                    systemImage: "doc.text.fill", tint: .indigo)
        } detail: { p in
            detailScaffold {
                DetailHeader(systemImage: "doc.text.fill", tint: .indigo, title: p.title ?? p.name,
                             subtitle: "\(Format.bytes(p.sizeBytes)) · \(Format.relative(p.modified))")
                InfoRow(label: "File", value: p.name, mono: true)
                MarkdownPreview(text: FS.readString(URL(fileURLWithPath: p.path)) ?? "").frame(minHeight: 320)
            }
        }
    }
}

// MARK: - Tasks

struct TasksView: View {
    @Bindable var store: ElementsStore
    var body: some View {
        CatalogPane(items: store.tasks,
                    searchableText: { $0.id },
                    searchPrompt: "Search tasks") { t in
            ItemRow(title: String(t.id.prefix(13)),
                    subtitle: "\(t.fileCount) files · \(Format.relative(t.modified))",
                    systemImage: "checklist", tint: .mint)
        } detail: { t in
            detailScaffold {
                DetailHeader(systemImage: "checklist", tint: .mint, title: "Background task",
                             subtitle: Format.relative(t.modified))
                InfoRow(label: "ID", value: t.id, mono: true)
                InfoRow(label: "Files", value: "\(t.fileCount)")
                InfoRow(label: "Path", value: t.path, mono: true)
                Button { revealInFinder(t.path) } label: { Label("Reveal in Finder", systemImage: "folder") }
            }
        }
    }
}

// MARK: - Projects

struct ProjectsView: View {
    @Bindable var store: ElementsStore
    var body: some View {
        CatalogPane(items: store.projects,
                    searchableText: { $0.name },
                    searchPrompt: "Search projects") { p in
            ItemRow(title: p.displayName, subtitle: p.name, systemImage: "folder.fill", tint: .brown, provider: p.provider) {
                if p.trustLevel != nil {
                    Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(.green)
                        .help("Trusted in Codex")
                }
                if p.liveCount > 0 {
                    Pill(text: "\(p.liveCount) live", color: .green)
                } else {
                    Text("\(p.sessionCount)").font(.caption).foregroundStyle(.secondary)
                }
            }
        } detail: { p in
            detailScaffold {
                DetailHeader(systemImage: "folder.fill", tint: .brown, title: p.displayName,
                             subtitle: p.name)
                HStack(spacing: 10) {
                    statTile("\(p.sessionCount)", "Sessions", .pink)
                    statTile("\(p.liveCount)", "Live", .green)
                    statTile("\(p.mcpServers.count)", "MCP", .teal)
                }
                InfoRow(label: "Last active", value: Format.relative(p.lastActivity))
                if let trust = p.trustLevel {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Trust").microLabel().foregroundStyle(Palette.textTertiary)
                            .frame(width: 96, alignment: .leading)
                        Pill(text: trust, systemImage: "checkmark.seal.fill", color: .green)
                        Spacer()
                    }
                }
                InfoRow(label: "Path", value: p.name, mono: true)
                if !p.mcpServers.isEmpty {
                    Label("MCP servers", systemImage: "server.rack").font(.headline)
                    FlowLayout(spacing: 6) { ForEach(p.mcpServers, id: \.self) { Pill(text: $0, color: .teal) } }
                }
                Button { revealInFinder(p.path) } label: { Label("Reveal session folder", systemImage: "folder") }
            }
        }
    }

    private func statTile(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(tint)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(Palette.surfaceHi, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Management controls (guard-railed enable/disable)

/// Enable/disable a plugin (Claude → settings.json, Codex → config.toml), behind a
/// confirmation dialog. Writes are backed up and re-scanned on success.
struct PluginManageControl: View {
    let store: ElementsStore
    let plugin: PluginInfo
    @State private var confirm = false
    @State private var errorMsg: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack {
                Label("Manage", systemImage: "switch.2").font(.headline)
                Spacer()
                Button { confirm = true } label: {
                    Label(plugin.enabled ? "Disable" : "Enable",
                          systemImage: plugin.enabled ? "pause.circle.fill" : "play.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(plugin.enabled ? .orange : .green)
                .controlSize(.small)
            }
            Text("Toggles \(file). A .agents-elements.bak backup is written first.")
                .font(.caption2).foregroundStyle(Palette.textTertiary)
        }
        .confirmationDialog("\(plugin.enabled ? "Disable" : "Enable") \(plugin.name)?",
                            isPresented: $confirm, titleVisibility: .visible) {
            Button(plugin.enabled ? "Disable" : "Enable") { apply(!plugin.enabled) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Edits \(file), then re-scans. A backup is saved alongside the file so you can revert.")
        }
        .alert("Couldn’t update plugin", isPresented: errBinding(errorMsg: $errorMsg)) {
            Button("OK") { errorMsg = nil }
        } message: { Text(errorMsg ?? "") }
    }

    private var file: String { plugin.provider == .claude ? "~/.claude/settings.json" : "~/.codex/config.toml" }

    private func apply(_ enabled: Bool) {
        do { try store.setEnabled(plugin: plugin, to: enabled); Task { await store.refresh() } }
        catch { errorMsg = error.localizedDescription }
    }
}

/// Enable/disable a Codex skill via `[[skills.config]]`. Claude skills are always on, so
/// this renders a short note instead of a control for them.
struct SkillManageControl: View {
    let store: ElementsStore
    let skill: Skill
    @State private var confirm = false
    @State private var errorMsg: String?

    var body: some View {
        if store.canToggle(skill: skill) {
            VStack(alignment: .leading, spacing: 6) {
                Divider()
                HStack {
                    Label("Manage", systemImage: "switch.2").font(.headline)
                    Spacer()
                    Button { confirm = true } label: {
                        Label(skill.enabled ? "Disable" : "Enable",
                              systemImage: skill.enabled ? "pause.circle.fill" : "play.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(skill.enabled ? .orange : .green)
                    .controlSize(.small)
                }
                Text("Toggles [[skills.config]] in ~/.codex/config.toml (backup written first).")
                    .font(.caption2).foregroundStyle(Palette.textTertiary)
            }
            .confirmationDialog("\(skill.enabled ? "Disable" : "Enable") \(skill.name)?",
                                isPresented: $confirm, titleVisibility: .visible) {
                Button(skill.enabled ? "Disable" : "Enable") { apply(!skill.enabled) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Edits ~/.codex/config.toml, then re-scans. A backup is saved alongside it.")
            }
            .alert("Couldn’t update skill", isPresented: errBinding(errorMsg: $errorMsg)) {
                Button("OK") { errorMsg = nil }
            } message: { Text(errorMsg ?? "") }
        }
    }

    private func apply(_ enabled: Bool) {
        do { try store.setEnabled(skill: skill, to: enabled); Task { await store.refresh() } }
        catch { errorMsg = error.localizedDescription }
    }
}

private func errBinding(errorMsg: Binding<String?>) -> Binding<Bool> {
    Binding(get: { errorMsg.wrappedValue != nil }, set: { if !$0 { errorMsg.wrappedValue = nil } })
}

// MARK: - Shared helpers

func revealInFinder(_ path: String) {
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
}
