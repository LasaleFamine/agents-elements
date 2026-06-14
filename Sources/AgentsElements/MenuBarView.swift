import SwiftUI
import AppKit

/// Compact menu-bar popover: live sessions at a glance + quick counts.
struct MenuBarView: View {
    @Bindable var store: ElementsStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            divider
            if store.liveSessions.isEmpty {
                Text("No live sessions").microLabel().foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            } else {
                VStack(spacing: 2) {
                    ForEach(store.liveSessions) { liveRow($0) }
                }
                .padding(8)
            }
            divider
            countsRow
            divider
            footer
        }
        .frame(width: 308)
        .background(DeckBackground())
        .tint(Palette.accent)
        .preferredColorScheme(.dark)
    }

    private var divider: some View { Rectangle().fill(Palette.stroke).frame(height: 1) }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Palette.brand, in: RoundedRectangle(cornerRadius: 7))
                .shadow(color: Palette.accent.opacity(0.6), radius: 8)
            Text("Agents Elements").font(.headline).foregroundStyle(Palette.textPrimary)
            Spacer()
            if let fill = store.activeFill { ContextRing(percent: fill, size: 28) }
        }
        .padding(11)
    }

    private func liveRow(_ s: Session) -> some View {
        Button { openDashboard() } label: {
            HStack(spacing: 9) {
                PulseDot(size: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.name ?? s.projectName).font(.callout.weight(.medium))
                        .foregroundStyle(Palette.textPrimary).lineLimit(1)
                    Text(s.status ?? "running").microLabel().foregroundStyle(Palette.textTertiary)
                }
                Spacer()
                if let m = s.model {
                    Text(m.replacingOccurrences(of: "claude-", with: ""))
                        .font(.caption2.monospaced()).foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var countsRow: some View {
        HStack {
            count("Skills", store.skills.count)
            count("Agents", store.subagents.count)
            count("Cmds", store.commands.count)
            count("Sessions", store.sessions.count)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
    }

    private func count(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.system(.headline, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
            Text(label).microLabel().foregroundStyle(Palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            Button { openDashboard() } label: { Label("Open dashboard", systemImage: "macwindow") }
                .buttonStyle(.borderedProminent).controlSize(.small)
            Spacer()
            Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).foregroundStyle(Palette.textSecondary)
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(.borderless).foregroundStyle(Palette.textSecondary)
        }
        .padding(11)
    }

    private func openDashboard() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
