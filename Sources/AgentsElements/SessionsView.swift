import SwiftUI
import AppKit

struct SessionsView: View {
    @Bindable var store: ElementsStore

    @State private var query = ""
    @State private var filter: SessionState?
    @State private var projectFilter: String?           // Session.projectKey; nil = every project
    @State private var selection: Set<Session.ID> = []
    @State private var confirmStaleCleanup = false
    @State private var confirmSelectionDelete = false
    /// Snapshot of what the open confirmation dialog is about to delete, so the
    /// prompt and the action can never disagree with each other.
    @State private var pendingDelete: [Session] = []
    @State private var pendingLiveCount = 0

    private var filtered: [Session] {
        store.sessions.filter { s in
            (filter == nil || s.state == filter)
            && (projectFilter == nil || s.projectKey == projectFilter)
            && (query.isEmpty
                || s.projectName.localizedCaseInsensitiveContains(query)
                || (s.name ?? "").localizedCaseInsensitiveContains(query)
                || (s.lastPrompt ?? "").localizedCaseInsensitiveContains(query)
                || (s.gitBranch ?? "").localizedCaseInsensitiveContains(query))
        }
    }

    /// Selection is intersected with what's on screen, so a row you filtered away
    /// can never be swept up in a batch delete.
    private var selected: [Session] { filtered.filter { selection.contains($0.id) } }
    private var deletable: [Session] { selected.filter { $0.state != .live } }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                filterBar
                Divider()
                if store.isScanningSessions && store.sessions.isEmpty {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Reading transcripts…").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filtered, selection: $selection) { s in
                        SessionRow(session: s).tag(s.id)
                    }
                    .contextMenu(forSelectionType: Session.ID.self) { ids in
                        rowMenu(for: ids)
                    }
                    .listStyle(.inset)
                    .deckList()
                }
                bottomBar
            }
            .frame(minWidth: 320, idealWidth: 380, maxWidth: 520)
            .confirmationDialog(deleteTitle, isPresented: $confirmSelectionDelete, titleVisibility: .visible) {
                Button("Move \(pendingDelete.count) to Trash", role: .destructive) { deletePending() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleteMessage)
            }

            Group {
                if selected.count > 1 {
                    BatchSelectionDetail(sessions: selected,
                                         deletable: deletable,
                                         onDelete: { beginDelete(selected) },
                                         onClear: { selection.removeAll() })
                } else if let s = selected.first {
                    SessionDetail(store: store, session: s, onDeleted: { selection.removeAll() })
                } else if store.isScanningSessions && store.sessions.isEmpty {
                    EmptyStateView(systemImage: "clock.arrow.circlepath",
                                   title: "Reading transcripts…",
                                   message: "The rest of your inventory is already loaded — sessions take a moment longer because every transcript has to be read.")
                } else {
                    EmptyStateView(systemImage: "bubble.left.and.bubble.right",
                                   title: "Select a session",
                                   message: "View its last prompt, token usage, and recall or clean-up options. ⌘-click or ⇧-click to select several and delete them in one go.")
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .confirmationDialog("Move \(store.staleSessions.count) stale sessions to Trash?",
                            isPresented: $confirmStaleCleanup, titleVisibility: .visible) {
            Button("Move \(store.staleSessions.count) to Trash", role: .destructive) {
                let stale = store.staleSessions
                store.trash(stale)
                selection.removeAll()
                Task { await store.refresh() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These transcripts haven’t changed in over \(store.staleDays) \(store.staleDays == 1 ? "day" : "days"). They’ll go to the macOS Trash and can be restored.")
        }
    }

    // MARK: Actions

    private var deleteTitle: String {
        pendingDelete.count == 1 ? "Move this session to Trash?" : "Move \(pendingDelete.count) sessions to Trash?"
    }

    private var deleteMessage: String {
        let size = Format.bytes(pendingDelete.reduce(0) { $0 + $1.sizeBytes })
        let live = pendingLiveCount > 0
            ? "\n\n\(pendingLiveCount) live \(pendingLiveCount == 1 ? "session" : "sessions") will be kept — live sessions can’t be deleted."
            : ""
        return "\(size) of transcripts go to the macOS Trash — recoverable.\(live)"
    }

    /// Pass the raw selection: live sessions are dropped here (and counted, so the
    /// prompt can say what it's holding back), and nothing downstream re-checks.
    private func beginDelete(_ targets: [Session]) {
        pendingDelete = targets.filter { $0.state != .live }
        pendingLiveCount = targets.count - pendingDelete.count
        guard !pendingDelete.isEmpty else { return }
        confirmSelectionDelete = true
    }

    private func deletePending() {
        guard !pendingDelete.isEmpty else { return }
        store.trash(pendingDelete)
        selection.removeAll()
        Task { await store.refresh() }
    }

    @ViewBuilder
    private func rowMenu(for ids: Set<Session.ID>) -> some View {
        let targets = filtered.filter { ids.contains($0.id) }
        if targets.isEmpty {
            Button("Select all") { selection = Set(filtered.map(\.id)) }
        } else {
            if targets.count == 1, let s = targets.first {
                Button("Reveal in Finder") { revealInFinder(s.path) }
                Divider()
            }
            let removable = targets.filter { $0.state != .live }
            Button(removable.count <= 1 ? "Move to Trash…" : "Move \(removable.count) to Trash…",
                   role: .destructive) {
                selection = ids
                beginDelete(targets)
            }
            .disabled(removable.isEmpty)
        }
    }

    // MARK: Filter bar

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                chip("All", nil, store.sessions.count, .secondary)
                chip("Live", .live, store.liveSessions.count, .green)
                chip("Resumable", .resumable, store.sessions.filter { $0.state == .resumable }.count, .blue)
                chip("Stale", .stale, store.staleSessions.count, .secondary)
                Spacer()
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
                TextField("Filter by project, branch, prompt…", text: $query).textFieldStyle(.plain)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Palette.surfaceHi, in: RoundedRectangle(cornerRadius: 7))
            HStack(spacing: 10) {
                projectMenu
                staleMenu
                Spacer()
                Button(selection.isEmpty ? "Select all" : "Clear") {
                    if selection.isEmpty { selection = Set(filtered.map(\.id)) } else { selection.removeAll() }
                }
                .buttonStyle(.link)
                .font(.caption)
                .disabled(filtered.isEmpty)
            }
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)
    }

    private func chip(_ label: String, _ value: SessionState?, _ count: Int, _ color: Color) -> some View {
        Button { filter = value } label: {
            HStack(spacing: 5) {
                if value == .live { Circle().fill(.green).frame(width: 6, height: 6) }
                Text(label).font(.caption.weight(.medium))
                Text("\(count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(filter == value ? color.opacity(0.2) : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(filter == value ? color.opacity(0.4) : Color(nsColor: .separatorColor), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    /// Scope the list to one project (keyed by cwd, so same-named dirs stay distinct).
    private var projectMenu: some View {
        Menu {
            Toggle("All projects · \(store.sessions.count)", isOn: projectBinding(nil))
            if !store.sessionProjects.isEmpty { Divider() }
            ForEach(store.sessionProjects) { p in
                Toggle("\(p.name) · \(p.count)", isOn: projectBinding(p.id))
            }
        } label: {
            menuLabel(icon: "folder", text: projectLabel, active: projectFilter != nil)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(projectFilter ?? "Show sessions from every project")
    }

    private func projectBinding(_ key: String?) -> Binding<Bool> {
        Binding(get: { projectFilter == key },
                set: { on in projectFilter = on ? key : nil })
    }

    private var projectLabel: String {
        guard let key = projectFilter else { return "All projects" }
        return store.sessionProjects.first { $0.id == key }?.name ?? (key as NSString).lastPathComponent
    }

    /// How old a transcript has to be before it counts as stale.
    private var staleMenu: some View {
        Menu {
            Picker("Stale after", selection: $store.staleDays) {
                ForEach(ElementsStore.staleDayOptions, id: \.self) { d in
                    Text(d == 1 ? "1 day" : "\(d) days").tag(d)
                }
            }
            .pickerStyle(.inline)
        } label: {
            menuLabel(icon: "clock.badge.xmark",
                      text: "Stale after \(store.staleDays)d",
                      active: store.staleDays != 14)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Sessions untouched for longer than this are marked stale")
    }

    private func menuLabel(icon: String, text: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption.weight(.medium)).lineLimit(1)
        }
        .foregroundStyle(active ? Palette.accent : Color.secondary)
    }

    // MARK: Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        if !selected.isEmpty {
            selectionBar
        } else if !store.staleSessions.isEmpty {
            staleBar
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent)
            Text("\(selected.count) selected · \(Format.bytes(selected.reduce(0) { $0 + $1.sizeBytes }))")
                .font(.caption).foregroundStyle(.secondary)
            if deletable.count < selected.count {
                Text("· \(selected.count - deletable.count) live kept")
                    .font(.caption).foregroundStyle(.green)
            }
            Spacer()
            Button("Delete \(deletable.count)…", role: .destructive) { beginDelete(selected) }
                .controlSize(.small)
                .disabled(deletable.isEmpty)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.bar)
    }

    private var staleBar: some View {
        HStack {
            Image(systemName: "clock.badge.xmark").foregroundStyle(.orange)
            Text("\(store.staleSessions.count) stale · \(Format.bytes(store.staleSessions.reduce(0) { $0 + $1.sizeBytes }))")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Clean up…") { confirmStaleCleanup = true }
                .controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.bar)
    }
}

// MARK: - Batch selection

/// Right-hand pane when several sessions are selected: what you're about to
/// remove, summed up, plus the one button that removes it.
struct BatchSelectionDetail: View {
    let sessions: [Session]
    let deletable: [Session]
    var onDelete: () -> Void
    var onClear: () -> Void

    private var bytes: Int { sessions.reduce(0) { $0 + $1.sizeBytes } }
    private var tokens: Int { sessions.reduce(0) { $0 + $1.totalTokens } }
    private var cost: Double { sessions.reduce(0) { $0 + $1.estimatedCost } }
    private var liveCount: Int { sessions.count - deletable.count }

    private var byProject: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for s in sessions { counts[s.projectName, default: 0] += 1 }
        return counts.map { (name: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DetailHeader(systemImage: "checklist", tint: Palette.accent,
                             title: "\(sessions.count) sessions selected",
                             subtitle: liveCount > 0
                                ? "\(deletable.count) can be deleted · \(liveCount) live"
                                : "All \(sessions.count) can be deleted") {
                    Button("Clear", action: onClear).controlSize(.small)
                }

                HStack(spacing: 10) {
                    tile("Sessions", "\(sessions.count)", .pink)
                    tile("Transcripts", Format.bytes(bytes), .orange)
                    tile("Total tok", Format.compact(tokens), Palette.accent)
                    tile("Est. cost", Pricing.money(cost), Color(hex: 0x6EE7B7))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Projects", systemImage: "folder").font(.headline)
                    FlowLayout(spacing: 6) {
                        ForEach(byProject, id: \.name) { p in
                            Pill(text: "\(p.name) · \(p.count)", color: Palette.textSecondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Selected", systemImage: "list.bullet").font(.headline)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(sessions.prefix(12)) { s in
                            HStack(spacing: 8) {
                                Image(systemName: s.state.systemImage)
                                    .font(.caption2).foregroundStyle(s.state.color).frame(width: 14)
                                Text(s.name ?? s.projectName).font(.caption).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(Format.bytes(s.sizeBytes))
                                    .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        if sessions.count > 12 {
                            Text("+ \(sessions.count - 12) more")
                                .font(.caption).foregroundStyle(.tertiary).padding(.top, 4)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.surfaceHi, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Divider()
                HStack {
                    Text("Deleted transcripts go to the macOS Trash — recoverable.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete \(deletable.count)", systemImage: "trash")
                    }
                    .disabled(deletable.isEmpty)
                }
            }
            .padding(20)
        }
    }

    private func tile(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(tint)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(Palette.surfaceHi, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Row

struct SessionRow: View {
    let session: Session
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: session.state.systemImage)
                .font(.caption).foregroundStyle(session.state.color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.name ?? session.projectName).font(.callout.weight(.medium)).lineLimit(1)
                    ProviderBadge(provider: session.provider, compact: true)
                    if session.subagentRuns > 0 {
                        Label("\(session.subagentRuns)", systemImage: "person.2")
                            .font(.caption2).foregroundStyle(.tertiary).labelStyle(.titleAndIcon)
                    }
                }
                Text(session.lastPrompt ?? "—").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.relative(session.lastActivity)).font(.caption2).foregroundStyle(.tertiary)
                Text("\(session.messageCount) msgs").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Detail

struct SessionDetail: View {
    @Bindable var store: ElementsStore
    let session: Session
    var onDeleted: () -> Void

    @State private var confirmDelete = false
    @State private var copied = false

    private var resumeCommand: String {
        switch session.provider {
        case .claude: return "(cd \"\(session.cwd)\" && claude --resume \(session.id))"
        case .codex: return "(cd \"\(session.cwd)\" && codex resume \(session.id))"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let prompt = session.lastPrompt {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Last prompt", systemImage: "text.quote").font(.headline)
                        Text(prompt)
                            .font(.callout).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Palette.surfaceHi, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                tokenSection
                metadata
                actions
            }
            .padding(20)
        }
        .confirmationDialog("Move this session to Trash?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                _ = try? store.trash(session)
                onDeleted()
                Task { await store.refresh() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(session.path)\n\nGoes to the macOS Trash — recoverable.")
        }
    }

    private var header: some View {
        DetailHeader(systemImage: "bubble.left.and.bubble.right.fill", tint: .pink,
                     title: session.name ?? session.projectName,
                     subtitle: session.cwd) {
            HStack(spacing: 10) {
                if let fill = session.contextFill { ContextRing(percent: fill, size: 42) }
                ProviderBadge(provider: session.provider)
                StateBadge(state: session.state, status: session.status)
            }
        }
    }

    @ViewBuilder
    private var tokenSection: some View {
        HStack(spacing: 10) {
            tokenTile("Messages", "\(session.messageCount)", .pink)
            tokenTile("Subagents", "\(session.subagentRuns)", Palette.accent2)
            tokenTile("Tokens out", Format.compact(session.outputTokens), .green)
            tokenTile("Total tok", Format.compact(session.totalTokens), Palette.accent)
            tokenTile("Est. cost", Pricing.money(session.estimatedCost), Color(hex: 0x6EE7B7))
            tokenTile("Size", Format.bytes(session.sizeBytes), .orange)
        }
    }

    private func tokenTile(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(tint)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(Palette.surfaceHi, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let b = session.gitBranch { InfoRow(label: "Branch", value: b, mono: true) }
            if let m = session.model { InfoRow(label: "Model", value: m, mono: true) }
            if let v = session.version { InfoRow(label: "CC version", value: v, mono: true) }
            if let f = session.firstActivity { InfoRow(label: "Started", value: Format.relative(f)) }
            InfoRow(label: "Last active", value: Format.relative(session.lastActivity))
            InfoRow(label: "Session ID", value: session.id, mono: true)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Label("Recall", systemImage: "arrow.uturn.backward.circle.fill").font(.headline)
            HStack {
                Text(resumeCommand)
                    .font(.caption.monospaced()).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.surfaceHi, in: RoundedRectangle(cornerRadius: 8))
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents(); pb.setString(resumeCommand, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
            }
            HStack {
                Button { revealInFinder(session.path) } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                Spacer()
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(session.state == .live)
                .help(session.state == .live ? "Live sessions can’t be deleted" : "Move transcript to Trash")
            }
        }
    }
}
