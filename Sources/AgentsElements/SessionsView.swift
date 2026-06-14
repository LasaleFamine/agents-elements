import SwiftUI
import AppKit

struct SessionsView: View {
    @Bindable var store: ElementsStore

    @State private var query = ""
    @State private var filter: SessionState?
    @State private var selection: Session.ID?
    @State private var confirmBulk = false

    private var filtered: [Session] {
        store.sessions.filter { s in
            (filter == nil || s.state == filter)
            && (query.isEmpty
                || s.projectName.localizedCaseInsensitiveContains(query)
                || (s.name ?? "").localizedCaseInsensitiveContains(query)
                || (s.lastPrompt ?? "").localizedCaseInsensitiveContains(query)
                || (s.gitBranch ?? "").localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                filterBar
                Divider()
                List(filtered, selection: $selection) { s in
                    SessionRow(session: s).tag(s.id)
                }
                .listStyle(.inset)
                .deckList()
                if !store.staleSessions.isEmpty {
                    bulkBar
                }
            }
            .frame(minWidth: 320, idealWidth: 380, maxWidth: 520)

            Group {
                if let id = selection, let s = store.sessions.first(where: { $0.id == id }) {
                    SessionDetail(store: store, session: s, onDeleted: { selection = nil })
                } else {
                    EmptyStateView(systemImage: "bubble.left.and.bubble.right",
                                   title: "Select a session",
                                   message: "View its last prompt, token usage, and recall or clean-up options.")
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .confirmationDialog("Move \(store.staleSessions.count) stale sessions to Trash?",
                            isPresented: $confirmBulk, titleVisibility: .visible) {
            Button("Move \(store.staleSessions.count) to Trash", role: .destructive) {
                let stale = store.staleSessions
                store.trash(stale)
                Task { await store.refresh() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These transcripts haven’t changed in over 14 days. They’ll go to the macOS Trash and can be restored.")
        }
    }

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

    private var bulkBar: some View {
        HStack {
            Image(systemName: "clock.badge.xmark").foregroundStyle(.orange)
            Text("\(store.staleSessions.count) stale · \(Format.bytes(store.staleSessions.reduce(0) { $0 + $1.sizeBytes }))")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Clean up…") { confirmBulk = true }
                .controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.bar)
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
