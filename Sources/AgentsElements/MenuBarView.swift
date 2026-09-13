import SwiftUI
import AppKit
import Combine

/// Compact menu-bar popover. Its one job is the question you have when you sit back down:
/// *which of these is waiting on me?* Sessions that need an answer lead, longest-waiting
/// first; the ones still working are collapsed to a count, because there is nothing to do
/// about them.
struct MenuBarView: View {
    @Bindable var store: ElementsStore

    @Environment(\.openWindow) private var openWindow

    /// Statuses are re-read on a short cadence while the popover is open. This only reads
    /// the handful of small live-session files, never the transcript corpus, so it is far
    /// cheaper than a refresh and can run this often.
    private let tick = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    /// Beyond this the popover stops being glanceable; the overflow gets a count.
    private static let maxRows = 6

    private var needsYou: [Session] { store.sessionsNeedingYou }
    private var working: [Session] { store.liveSessions.filter { $0.attention == .working } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            divider
            attentionSummary
            divider
            sortRow
            if needsYou.isEmpty {
                Text(store.liveSessions.isEmpty
                     ? "No live sessions"
                     : "Nothing waiting on you — every live session is busy.")
                    .microLabel().foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            } else {
                VStack(spacing: 2) {
                    ForEach(needsYou.prefix(Self.maxRows)) { sessionRow($0) }
                    // Recency ordering can push every blocked session past the cut — which
                    // is the right default, but the band above still says "5 stopped", so
                    // the overflow has to account for them rather than swallow them.
                    if needsYou.count > Self.maxRows {
                        let hidden = needsYou.dropFirst(Self.maxRows)
                        let stopped = hidden.filter { $0.attention == .blocked }.count
                        Text(stopped > 0
                             ? "+\(hidden.count) more · \(stopped) stopped"
                             : "+\(hidden.count) more waiting")
                            .microLabel()
                            .foregroundStyle(stopped > 0 ? Attention.blocked.color.opacity(0.8)
                                                         : Palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8).padding(.top, 4)
                            .help(stopped > 0
                                  ? "Switch to “Longest waiting” to bring the stopped sessions to the top"
                                  : "Open the dashboard to see them all")
                    }
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
        .onAppear {
            store.refreshLiveStatus()
            store.startLiveStatusPolling()
        }
        .onReceive(tick) { _ in store.refreshLiveStatus() }
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

    /// One line that answers the question without reading any rows.
    private var attentionSummary: some View {
        let blocked = needsYou.filter { $0.attention == .blocked }.count
        let turn = needsYou.count - blocked
        return HStack(spacing: 8) {
            Image(systemName: blocked > 0 ? "hand.raised.fill" : "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(blocked > 0 ? Attention.blocked.color : Palette.live)
            Text(summaryText(blocked: blocked, turn: turn))
                .font(.caption.weight(.medium)).foregroundStyle(Palette.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .background(blocked > 0 ? Attention.blocked.color.opacity(0.12) : Color.clear)
    }

    /// Which end of the list you care about depends on why you're looking: picking up
    /// where you left off, or sweeping up what you walked away from.
    @ViewBuilder
    private var sortRow: some View {
        if !needsYou.isEmpty || !working.isEmpty {
            HStack(spacing: 6) {
                if needsYou.count > 1 {
                    Button { store.needsYouRecentFirst.toggle() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: store.needsYouRecentFirst
                                  ? "clock.arrow.circlepath" : "hourglass")
                                .font(.system(size: 8, weight: .bold))
                            Text(store.needsYouRecentFirst ? "Recent first" : "Longest waiting")
                                .font(.caption2.weight(.medium))
                        }
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Palette.surfaceHi, in: Capsule())
                        .foregroundStyle(Palette.textSecondary)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Switch between what you touched most recently and what has been waiting longest")
                }
                Spacer()
                if !working.isEmpty {
                    Text("\(working.count) working").microLabel().foregroundStyle(Palette.textTertiary)
                }
            }
            .padding(.horizontal, 11).padding(.top, 8).padding(.bottom, 1)
        }
    }

    private func summaryText(blocked: Int, turn: Int) -> String {
        switch (blocked, turn) {
        case (0, 0): return store.liveSessions.isEmpty ? "Nothing running" : "All clear"
        case (0, let t): return "\(t) waiting for your next prompt"
        case (let b, 0): return "\(b) stopped, waiting on you"
        case (let b, let t): return "\(b) stopped · \(t) awaiting a prompt"
        }
    }

    private func sessionRow(_ s: Session) -> some View {
        Button { openDashboard() } label: {
            HStack(spacing: 9) {
                if s.attention == .blocked {
                    Circle().fill(Attention.blocked.color).frame(width: 7, height: 7)
                } else {
                    PulseDot(size: 7)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.displayTitle).font(.callout.weight(.medium))
                        .foregroundStyle(Palette.textPrimary).lineLimit(1)
                    HStack(spacing: 5) {
                        if let a = s.attention {
                            AttentionChip(attention: a, since: s.statusSince)
                        }
                        Text(s.projectName).microLabel().foregroundStyle(Palette.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(s.waitingFor.map { "Blocked: \($0)" } ?? s.cwd)
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
