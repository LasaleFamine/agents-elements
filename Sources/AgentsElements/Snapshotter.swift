import SwiftUI
import AppKit

/// Offscreen self-rendering for verification (`AgentsElements --render out.png`).
/// Uses ImageRenderer so it needs no Screen-Recording permission. A faux sidebar
/// (plain stacks instead of `List`) is used because `List` does not render offscreen.
enum Snapshotter {
    @MainActor
    static func render(to path: String, mode: String) -> Never {
        let store = ElementsStore()
        // `--demo` renders from a synthetic snapshot so published art leaks nothing real.
        if CommandLine.arguments.contains("--demo") {
            store.loadDemo()
        } else {
            store.loadSynchronously()
        }

        let content: AnyView
        switch mode {
        case "relationships": content = AnyView(RelationshipsPoster(store: store))
        case "insights": content = AnyView(InsightsPoster(store: store))
        case "markdown": content = AnyView(MarkdownPoster(store: store))
        case "welcome": content = AnyView(WelcomeSheet(onDismiss: {}).padding(40).background(DeckBackground()))
        case "hero": content = AnyView(HeroBanner(store: store))
        default: content = AnyView(SnapshotPoster(store: store))
        }

        let size: CGSize = mode == "hero" ? CGSize(width: 1280, height: 640) : CGSize(width: 1240, height: 860)
        let poster = content
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: poster)
        renderer.scale = 2
        if let img = renderer.nsImage,
           let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            FileHandle.standardError.write(Data("rendered \(path)\n".utf8))
        } else {
            FileHandle.standardError.write(Data("render failed\n".utf8))
        }
        exit(0)
    }

    // MARK: - Product tour (writes numbered frames; Tools/make-demo-video.sh encodes them)

    @MainActor
    static func renderTour(to dir: String) -> Never {
        let store = ElementsStore()
        store.loadDemo()
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let size = CGSize(width: 1240, height: 860)
        let scale: CGFloat = 1.5

        func png(_ view: AnyView) -> Data? {
            let r = ImageRenderer(content: view.frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .dark))
            r.scale = scale
            guard let img = r.nsImage, let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) else { return nil }
            return rep.representation(using: .png, properties: [:])
        }

        let scenes: [AnyView] = [
            AnyView(TourTitle()),
            AnyView(captioned(SnapshotPoster(store: store), "Everything your agents installed — in one place")),
            AnyView(captioned(InsightsPoster(store: store), "Token & cost — Claude and GPT, side by side")),
            AnyView(captioned(RelationshipsPoster(store: store), "Who can use what")),
            AnyView(captioned(MarkdownPoster(store: store), "Rendered Markdown previews")),
            AnyView(TourOutro()),
        ]
        let stills = scenes.map { png($0) }

        var idx = 1
        func emit(_ data: Data?) {
            guard let data else { return }
            try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "frame_%04d.png", idx)))
            idx += 1
        }

        let titleHold = 16, hold = 22, outroHold = 26, cross = 6
        for _ in 0..<titleHold { emit(stills[0]) }
        for i in 0..<scenes.count - 1 {
            for s in 1...cross {
                let t = Double(s) / Double(cross + 1)
                emit(png(AnyView(ZStack { scenes[i].opacity(1 - t); scenes[i + 1].opacity(t) })))
            }
            let h = (i + 1 == scenes.count - 1) ? outroHold : hold
            for _ in 0..<h { emit(stills[i + 1]) }
        }
        FileHandle.standardError.write(Data("rendered \(idx - 1) tour frames to \(dir)\n".utf8))
        exit(0)
    }

    /// Overlays a lower-third caption on a scene.
    @MainActor
    private static func captioned(_ content: some View, _ text: String) -> some View {
        ZStack(alignment: .bottomLeading) {
            content
            Text(text)
                .font(.system(size: 27, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 22).padding(.vertical, 13)
                .background(.black.opacity(0.62), in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.accent.opacity(0.7), lineWidth: 1.2))
                .shadow(color: .black.opacity(0.6), radius: 16, y: 4)
                .padding(36)
        }
        .frame(width: 1240, height: 860)
    }
}

private struct TourTitle: View {
    var body: some View {
        ZStack {
            DeckBackground()
            VStack(spacing: 22) {
                BrandMark(size: 112)
                Text("Agents Elements")
                    .font(.system(size: 66, weight: .bold)).foregroundStyle(Palette.textPrimary)
                Text("One control center for everything your AI coding agents\ninstall — across Claude Code and Codex.")
                    .font(.title2).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
                AIBuiltBadge().scaleEffect(1.45).padding(.top, 6)
            }
        }
    }
}

private struct TourOutro: View {
    var body: some View {
        ZStack {
            DeckBackground()
            VStack(spacing: 20) {
                BrandMark(size: 100)
                Text("Agents Elements")
                    .font(.system(size: 56, weight: .bold)).foregroundStyle(Palette.textPrimary)
                AIBuiltBadge().scaleEffect(1.35)
                VStack(spacing: 7) {
                    Text("Open source · MIT · macOS 14+")
                        .font(.title3).foregroundStyle(Palette.textSecondary)
                    Text("github.com/LasaleFamine/agents-elements")
                        .font(.title3.monospaced()).foregroundStyle(Palette.accent2)
                }
                .padding(.top, 10)
            }
        }
    }
}

/// Poster for the "who can use what" Relationships view (agents → tools lens).
private struct RelationshipsPoster: View {
    let store: ElementsStore
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            FauxSidebar(store: store, selected: .relationships).frame(width: 236, height: 860)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                Text("Who can use what").font(.title2.weight(.bold))
                Text("Trace which tools, contributions, and resources each element exposes.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    ForEach(["Subagents → Tools", "Plugins → Contributions", "Projects → Resources"], id: \.self) { t in
                        Text(t).font(.caption.weight(.medium))
                            .foregroundStyle(t.hasPrefix("Subagents") ? Palette.textPrimary : Palette.textSecondary)
                            .padding(.vertical, 5).frame(maxWidth: .infinity)
                            .background(t.hasPrefix("Subagents") ? Palette.accent.opacity(0.3) : Color.clear)
                    }
                }
                .background(Palette.surfaceHi, in: RoundedRectangle(cornerRadius: 7))
                .frame(width: 520)
                ForEach(store.subagents.prefix(5)) { a in
                    NodeCard(icon: "person.2.fill", tint: .blue,
                             title: a.scope.map { "\(a.name)  ·  \($0)" } ?? a.name,
                             badge: SourceBadge(source: a.source)) {
                        if a.hasAllTools {
                            Pill(text: "All tools (*)", systemImage: "infinity", color: .orange)
                        } else {
                            FlowLayout(spacing: 6) { ForEach(a.tools, id: \.self) { Pill(text: $0, color: .blue) } }
                        }
                    }
                }
                Spacer()
            }
            .padding(20)
            .frame(width: 980, alignment: .top)
        }
        .background(DeckBackground())
    }
}

/// Product banner for the README — brand mark, name, tagline, AI attribution, and a few
/// live counts from the real scan to show it's a real tool.
private struct HeroBanner: View {
    let store: ElementsStore
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                BrandMark(size: 84)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Agents Elements")
                        .font(.system(size: 56, weight: .bold)).foregroundStyle(Palette.textPrimary)
                    Text("A control center for everything your AI coding agents install —\nacross Claude Code and Codex.")
                        .font(.title3).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                AIBuiltBadge().scaleEffect(1.25, anchor: .leading).padding(.vertical, 4)
                HStack(spacing: 10) {
                    heroStat("\(store.skills.count)", "skills")
                    heroStat("\(store.sessions.count)", "sessions")
                    heroStat("\(store.plugins.count)", "plugins")
                    heroStat(Pricing.money(store.totalCost), "tracked")
                }
                .padding(.top, 6)
            }
            .padding(.leading, 64)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeckBackground())
    }

    private func heroStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(Palette.accent)
            Text(label).microLabel().foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Palette.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.stroke, lineWidth: 0.7))
    }
}

private struct SnapshotPoster: View {
    let store: ElementsStore
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            FauxSidebar(store: store).frame(width: 236, height: 840)
            Divider()
            OverviewContent(store: store, selection: .constant(.overview))
                .frame(width: 980, alignment: .top)
        }
        .background(DeckBackground())
    }
}

/// Verifies the Markdown renderer against a real SKILL.md body (rendered directly,
/// not through the scrolling container, so ImageRenderer captures it).
private struct MarkdownPoster: View {
    let store: ElementsStore
    var body: some View {
        let skill = store.skills.max { $0.body.count < $1.body.count }
        return HStack(alignment: .top, spacing: 0) {
            FauxSidebar(store: store, selected: .skills).frame(width: 236, height: 860)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                if let skill {
                    DetailHeader(systemImage: "wand.and.stars", tint: .purple, title: skill.name) {
                        ProviderBadge(provider: skill.provider)
                    }
                    MarkdownView(markdown: String(skill.body.prefix(2600)))
                        .padding(14)
                        .background(Palette.canvasBottom.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.stroke, lineWidth: 0.7))
                } else {
                    Text("No skills to preview").foregroundStyle(Palette.textSecondary)
                }
                Spacer()
            }
            .padding(20)
            .frame(width: 980, alignment: .top)
        }
        .background(DeckBackground())
    }
}

private struct InsightsPoster: View {
    let store: ElementsStore
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            FauxSidebar(store: store, selected: .insights).frame(width: 236, height: 860)
            Divider()
            InsightsContent(store: store).frame(width: 980, alignment: .top)
        }
        .background(DeckBackground())
    }
}

private struct FauxSidebar: View {
    let store: ElementsStore
    var selected: Category = .overview
    private let active: [Category] = [.skills, .subagents, .commands, .plugins, .mcp, .hooks]
    private let workspace: [Category] = [.sessions, .projects, .plans, .tasks]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 11) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Palette.brand, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .shadow(color: Palette.accent.opacity(0.6), radius: 10, y: 1)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Agents Elements").font(.headline).foregroundStyle(Palette.textPrimary)
                        Text("all agents").font(.caption2.monospaced()).foregroundStyle(Palette.textTertiary)
                    }
                    Spacer()
                }
                HStack(spacing: 0) {
                    ForEach(["All", "Claude", "Codex"], id: \.self) { t in
                        Text(t).font(.caption2.weight(.medium))
                            .foregroundStyle(t == "All" ? Palette.textPrimary : Palette.textSecondary)
                            .padding(.vertical, 4).frame(maxWidth: .infinity)
                            .background(t == "All" ? Palette.accent.opacity(0.30) : Color.clear)
                    }
                }
                .background(Palette.surfaceHi, in: RoundedRectangle(cornerRadius: 7))
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.stroke).frame(height: 1) }

            row(.overview)
            row(.insights)
            row(.relationships)
            label("Elements")
            ForEach(active) { row($0) }
            label("Workspace")
            ForEach(workspace) { row($0) }
            Spacer()
            HStack(spacing: 8) {
                if store.liveSessions.isEmpty {
                    Circle().fill(Palette.textTertiary).frame(width: 7, height: 7)
                } else {
                    Circle().fill(Palette.live).frame(width: 7, height: 7)
                        .shadow(color: Palette.live.opacity(0.9), radius: 4)
                }
                Text(store.liveSessions.isEmpty ? "idle" : "\(store.liveSessions.count) live").microLabel()
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                if let f = store.activeFill { Text("\(f)% ctx").font(.caption2.monospaced()).foregroundStyle(Palette.textSecondary) }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .overlay(alignment: .top) { Rectangle().fill(Palette.stroke).frame(height: 1) }
        }
        .background(DeckBackground())
        .overlay(alignment: .trailing) { Rectangle().fill(Palette.stroke).frame(width: 1) }
    }

    private func label(_ text: String) -> some View {
        Text(text).microLabel().foregroundStyle(Palette.textTertiary)
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ c: Category) -> some View {
        HStack(spacing: 9) {
            Image(systemName: c.systemImage).foregroundStyle(c.tint).frame(width: 20)
            Text(c.title).font(.callout).foregroundStyle(Palette.textPrimary)
            Spacer()
            if c.showsCount {
                Text("\(store.count(for: c))").font(.caption.monospacedDigit()).foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(c == selected ? Palette.accent.opacity(0.20) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) {
            if c == selected { Capsule().fill(Palette.accent).frame(width: 2.5, height: 16).padding(.leading, 2) }
        }
        .padding(.horizontal, 8)
    }
}
