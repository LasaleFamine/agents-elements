import SwiftUI

/// Public project links — surfaced in Help and the README.
enum Project {
    static let repo = URL(string: "https://github.com/LasaleFamine/agents-elements")!
    static let license = URL(string: "https://github.com/LasaleFamine/agents-elements/blob/main/LICENSE")!
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}

/// Shared UI chrome so the Help/Welcome sheets can be opened from the menu bar,
/// the toolbar, and on first launch.
@MainActor @Observable final class AppChrome {
    static let shared = AppChrome()
    var showHelp = false
    var showWelcome = false
}

// MARK: - Shared bits

/// The attribution the project is explicit about: this app was built by an AI agent.
struct AIBuiltBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
            Text("Built entirely by an AI agent")
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Palette.accent.opacity(0.16), in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.accent.opacity(0.45), lineWidth: 0.7))
        .foregroundStyle(Palette.accent)
    }
}

/// The Command Deck grid mark — same shape as the app icon, sized for UI.
struct BrandMark: View {
    var size: CGFloat = 44
    var body: some View {
        Image(systemName: "square.grid.2x2.fill")
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Palette.brand, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .shadow(color: Palette.accent.opacity(0.6), radius: size * 0.26, y: 2)
    }
}

// MARK: - Welcome (first launch)

struct WelcomeSheet: View {
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                BrandMark(size: 78)
                VStack(spacing: 7) {
                    Text("Welcome to Agents Elements")
                        .font(.title.weight(.bold)).foregroundStyle(Palette.textPrimary)
                    Text("One control center for everything your AI coding agents install — across Claude Code and Codex.")
                        .font(.callout).foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 430)
                }
                AIBuiltBadge()
            }
            .padding(.top, 38).padding(.bottom, 28).frame(maxWidth: .infinity)
            .background(
                ZStack {
                    Palette.surface
                    LinearGradient(colors: [Palette.accent.opacity(0.22), .clear],
                                   startPoint: .top, endPoint: .bottom)
                }
            )

            VStack(alignment: .leading, spacing: 15) {
                feature("square.grid.2x2.fill", Palette.accent, "Inventory every element",
                        "Skills, subagents, commands, plugins, MCP servers and hooks — in one searchable place.")
                feature("bubble.left.and.bubble.right.fill", .pink, "See live sessions & recall them",
                        "Spot what's running, copy a resume command, or clean up stale transcripts (safely, to Trash).")
                feature("chart.bar.xaxis", .green, "Track tokens & cost",
                        "Estimated spend by project and model — Claude and GPT side by side.")
                feature("switch.2", .orange, "Manage plugins & skills, safely",
                        "Enable or disable from the UI — every write is path-locked and backed up first.")
            }
            .padding(22)

            Divider()
            HStack {
                Label("Open source · MIT", systemImage: "checkmark.seal")
                    .font(.caption).foregroundStyle(Palette.textTertiary)
                Spacer()
                Button("Get started") { onDismiss() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
        }
        .frame(width: 540)
        .background(Palette.surface)
        .preferredColorScheme(.dark)
    }

    private func feature(_ icon: String, _ tint: Color, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                Text(body).font(.caption).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Help & About

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    block("What it does",
                          "Agents Elements scans ~/.claude and ~/.codex and shows every element your coding agents install — plus live sessions, token spend, and the automation that runs behind your back. Use the provider switcher in the sidebar to view Claude, Codex, or both.")
                    sectionsGuide
                    block("Your data stays on your Mac",
                          "Everything is read locally; nothing is uploaded. The app is read-only except two user-driven actions: moving sessions to the Trash, and toggling plugins/skills — both path-locked, and toggles back up the config file first.")
                    aiBuilt
                    links
                }
                .padding(24)
            }
            Divider()
            HStack {
                Button { AppChrome.shared.showWelcome = true; dismiss() } label: {
                    Label("Replay welcome", systemImage: "sparkles")
                }
                .buttonStyle(.link)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
        }
        .frame(width: 560, height: 640)
        .background(Palette.surface)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 14) {
            BrandMark(size: 60)
            VStack(alignment: .leading, spacing: 5) {
                Text("Agents Elements").font(.title2.weight(.bold)).foregroundStyle(Palette.textPrimary)
                Text("Version \(Project.version) · macOS 14+").font(.caption).foregroundStyle(Palette.textTertiary)
                AIBuiltBadge()
            }
            Spacer()
        }
    }

    private func block(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            DeckSectionHeader(title: title, systemImage: "circle.fill")
            Text(text).font(.callout).foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sectionsGuide: some View {
        VStack(alignment: .leading, spacing: 9) {
            DeckSectionHeader(title: "The sections", systemImage: "sidebar.left")
            ForEach(Category.allCases) { c in
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: c.systemImage).foregroundStyle(c.tint).frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.title).font(.callout.weight(.medium)).foregroundStyle(Palette.textPrimary)
                        Text(helpText(c)).font(.caption).foregroundStyle(Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var aiBuilt: some View {
        VStack(alignment: .leading, spacing: 7) {
            DeckSectionHeader(title: "Built by an AI agent", systemImage: "sparkles", tint: Palette.accent)
            Text("Every part of this app — the architecture, the Swift/SwiftUI code, the Command Deck visual design, the app icon, and this documentation — was written by Claude, an AI agent, working in Claude Code. A human set the direction and gave feedback; the agent did the building.")
                .font(.callout).foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.accent.opacity(0.3), lineWidth: 0.7))
        }
    }

    private var links: some View {
        HStack(spacing: 16) {
            Link(destination: Project.repo) { Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
            Link(destination: Project.license) { Label("MIT License", systemImage: "checkmark.seal") }
            Spacer()
        }
        .font(.callout).tint(Palette.accent2)
    }

    private func helpText(_ c: Category) -> String {
        switch c {
        case .overview: return "At-a-glance counts, what's live now, recent sessions, and health flags."
        case .insights: return "Token & cost analytics — spend by project and model, plus an activity heatmap."
        case .skills: return "Installed skills with their source and rendered SKILL.md. Codex skills can be toggled."
        case .subagents: return "Subagents and exactly which tools each one can use."
        case .commands: return "Slash commands, namespaced by project/plugin."
        case .plugins: return "Installed plugins, what they contribute, and enable/disable controls."
        case .mcp: return "MCP servers and their scope (global or per-project)."
        case .hooks: return "Hooks grouped by event, Codex command rules, and ~/.claude sweep markers."
        case .sessions: return "Live / resumable / stale sessions — recall, reveal, or clean up."
        case .plans: return "Saved plan documents, rendered as Markdown."
        case .tasks: return "Background task working directories."
        case .projects: return "Projects with session counts, MCP access, and Codex trust levels."
        case .relationships: return "Who can use what — agents → tools, plugins → contributions, projects → resources."
        }
    }
}
