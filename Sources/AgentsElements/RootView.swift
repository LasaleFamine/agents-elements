import SwiftUI

struct RootView: View {
    @Bindable var store: ElementsStore
    @State private var selection: Category = .overview
    @Bindable private var chrome = AppChrome.shared
    @AppStorage("ae.hasSeenWelcome.v1") private var hasSeenWelcome = false

    var body: some View {
        NavigationSplitView {
            Sidebar(store: store, selection: $selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 290)
        } detail: {
            ZStack {
                DeckBackground()
                DetailRouter(store: store, category: $selection)
            }
            .navigationTitle(selection.title)
            .toolbar { toolbarContent }
        }
        .tint(Palette.accent)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $chrome.showWelcome) {
            WelcomeSheet { hasSeenWelcome = true; chrome.showWelcome = false }
        }
        .sheet(isPresented: $chrome.showHelp) { HelpView() }
        .task {
            if store.lastRefresh == nil { await store.refresh() }
            if !hasSeenWelcome { chrome.showWelcome = true }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            if let last = store.lastRefresh {
                Text("synced \(Format.relative(last))")
                    .microLabel().foregroundStyle(Palette.textTertiary)
            }
        }
        ToolbarItem(placement: .automatic) {
            Button { chrome.showHelp = true } label: { Image(systemName: "questionmark.circle") }
                .help("Help & About")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(store.isLoading ? 360 : 0))
                    .animation(store.isLoading ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                               value: store.isLoading)
            }
            .help("Rescan ~/.claude")
            .disabled(store.isLoading)
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @Bindable var store: ElementsStore
    @Binding var selection: Category

    private let elements: [Category] = [.skills, .subagents, .commands, .plugins, .mcp, .hooks]
    private let workspace: [Category] = [.sessions, .projects, .plans, .tasks]

    var body: some View {
        List(selection: $selection) {
            Section {
                row(.overview)
                row(.insights)
                row(.relationships)
            }
            Section(header: sectionLabel("Elements")) {
                ForEach(elements) { row($0) }
            }
            Section(header: sectionLabel("Workspace")) {
                ForEach(workspace) { row($0) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(DeckBackground())
        .safeAreaInset(edge: .top) { header }
        .safeAreaInset(edge: .bottom) { footer }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).microLabel().foregroundStyle(Palette.textTertiary)
    }

    private func row(_ category: Category) -> some View {
        Label {
            Text(category.title).foregroundStyle(Palette.textPrimary)
        } icon: {
            Image(systemName: category.systemImage).foregroundStyle(category.tint)
        }
        .badge(category.showsCount ? store.count(for: category) : 0)
        .tag(category)
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 11) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Palette.brand, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .shadow(color: Palette.accent.opacity(0.6), radius: 10, y: 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Agents Elements").font(.headline).foregroundStyle(Palette.textPrimary)
                    Text(rootLabel).font(.caption2.monospaced()).foregroundStyle(Palette.textTertiary)
                }
                Spacer()
            }
            if store.availableProviders.count > 1 { providerSwitcher }
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 9)
        .background(DeckBackground())
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.stroke).frame(height: 1) }
    }

    private var rootLabel: String {
        switch store.providerFilter {
        case .none: return "all agents"
        case .codex: return "~/.codex"
        case .claude: return "~/.claude"
        }
    }

    private var providerSwitcher: some View {
        Picker("", selection: $store.providerFilter) {
            Text("All").tag(Provider?.none)
            ForEach(store.availableProviders) { p in
                Text(p.label).tag(Provider?.some(p))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .tint(store.providerFilter?.tint ?? Palette.accent)
    }

    @ViewBuilder
    private var footer: some View {
        let live = store.liveSessions.count
        HStack(spacing: 8) {
            if live > 0 { PulseDot(size: 7) } else { Circle().fill(Palette.textTertiary).frame(width: 7, height: 7) }
            Text(live > 0 ? "\(live) live" : "idle").microLabel().foregroundStyle(Palette.textSecondary)
            Spacer()
            if let fill = store.activeFill {
                Text("\(fill)% ctx").font(.caption2.monospaced()).foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(DeckBackground())
        .overlay(alignment: .top) { Rectangle().fill(Palette.stroke).frame(height: 1) }
    }
}

// MARK: - Detail router

struct DetailRouter: View {
    @Bindable var store: ElementsStore
    @Binding var category: Category

    var body: some View {
        Group {
            switch category {
            case .overview: OverviewView(store: store, selection: $category)
            case .insights: InsightsView(store: store)
            case .skills: SkillsView(store: store)
            case .subagents: SubagentsView(store: store)
            case .commands: CommandsView(store: store)
            case .plugins: PluginsView(store: store)
            case .mcp: MCPView(store: store)
            case .hooks: HooksAuditView(store: store)
            case .sessions: SessionsView(store: store)
            case .plans: PlansView(store: store)
            case .tasks: TasksView(store: store)
            case .projects: ProjectsView(store: store)
            case .relationships: RelationshipsView(store: store)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
