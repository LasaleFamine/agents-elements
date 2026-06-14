import SwiftUI

// MARK: - Palette ("Command Deck")

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

enum Palette {
    static let canvasTop = Color(hex: 0x0D0C14)
    static let canvasBottom = Color(hex: 0x08070B)
    static let surface = Color(hex: 0x16151F)
    static let surfaceHi = Color(hex: 0x1E1C29)
    static let stroke = Color.white.opacity(0.07)
    static let strokeHi = Color.white.opacity(0.14)

    static let accent = Color(hex: 0x7C5CFF)   // violet
    static let accent2 = Color(hex: 0x5B8DEF)  // indigo/blue
    static let live = Color(hex: 0x34D399)     // emerald

    static let brand = LinearGradient(colors: [accent, accent2],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)

    static let textPrimary = Color.white.opacity(0.93)
    static let textSecondary = Color.white.opacity(0.56)
    static let textTertiary = Color.white.opacity(0.34)
}

// MARK: - Category accent colors (tuned for the dark canvas)

extension Category {
    var tint: Color {
        switch self {
        case .overview: return Palette.accent
        case .insights: return Color(hex: 0x6EE7B7)      // emerald
        case .skills: return Color(hex: 0xB58BFF)        // violet
        case .subagents: return Color(hex: 0x6AA6FF)     // blue
        case .commands: return Color(hex: 0x49E0A6)      // green
        case .plugins: return Color(hex: 0xFFB454)       // amber
        case .mcp: return Color(hex: 0x4FD6D2)           // teal
        case .hooks: return Color(hex: 0xFFD166)         // yellow
        case .sessions: return Color(hex: 0xFF7AB6)      // pink
        case .plans: return Color(hex: 0x8E97FF)         // indigo
        case .tasks: return Color(hex: 0x55E0C0)         // mint
        case .projects: return Color(hex: 0xD7A56B)      // sand
        case .relationships: return Color(hex: 0x5FD0E6) // cyan
        }
    }
}

/// Near-black canvas with two soft accent blooms — the signature backdrop.
struct DeckBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.canvasTop, Palette.canvasBottom],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Palette.accent.opacity(0.16), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 620)
            RadialGradient(colors: [Palette.accent2.opacity(0.10), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 720)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Surface treatment

extension View {
    /// Elevated dark card with hairline border, a thin glowing top edge, and depth shadow.
    func deckSurface(cornerRadius: CGFloat = 14, glow: Color? = nil, glowStrength: Double = 0) -> some View {
        self
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Palette.stroke, lineWidth: 0.7)
            )
            .overlay(alignment: .top) {
                if let glow {
                    LinearGradient(colors: [.clear, glow.opacity(0.85), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(height: 1.5)
                        .padding(.horizontal, cornerRadius)
                        .blur(radius: 0.4)
                }
            }
            .shadow(color: (glow ?? .clear).opacity(glowStrength), radius: 16, y: 0)
            .shadow(color: .black.opacity(0.38), radius: 12, y: 7)
    }

    /// Hide the default List/Form background so the canvas shows through.
    func deckList() -> some View {
        self.scrollContentBackground(.hidden).background(Color.clear)
    }
}

// MARK: - Typography

extension View {
    /// Uppercase tracked monospace micro-label — the Command Deck signature.
    func microLabel() -> some View {
        self.font(.system(.caption2, design: .monospaced).weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.9)
    }
}

/// Section header: accent tick + mono uppercase title.
struct DeckSectionHeader: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = Palette.accent
    var body: some View {
        HStack(spacing: 8) {
            Capsule().fill(tint).frame(width: 3, height: 13)
            if let systemImage {
                Image(systemName: systemImage).font(.caption).foregroundStyle(tint)
            }
            Text(title).microLabel().foregroundStyle(Palette.textSecondary)
        }
    }
}

// MARK: - Formatting

enum Format {
    static func bytes(_ n: Int) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file
        return f.string(fromByteCount: Int64(n))
    }
    static func relative(_ date: Date) -> String {
        guard date > .distantPast else { return "—" }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
    static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - State / source styling

extension Provider {
    var tint: Color {
        switch self {
        case .claude: return Color(hex: 0xD97757)   // Claude coral
        case .codex: return Color(hex: 0x10A37F)    // OpenAI green
        }
    }
}

/// Small provider chip (glyph + label).
struct ProviderBadge: View {
    let provider: Provider
    var compact = false
    var body: some View {
        Group {
            if compact {
                Image(systemName: provider.glyph)
            } else {
                Label(provider.label, systemImage: provider.glyph)
            }
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, compact ? 4 : 6).padding(.vertical, 2)
        .background(provider.tint.opacity(0.16), in: Capsule())
        .overlay(Capsule().strokeBorder(provider.tint.opacity(0.35), lineWidth: 0.6))
        .foregroundStyle(provider.tint)
        .help(provider.label)
    }
}

extension SessionState {
    var color: Color {
        switch self {
        case .live: return Palette.live
        case .resumable: return Palette.accent2
        case .stale: return Palette.textTertiary
        }
    }
    var label: String {
        switch self { case .live: return "Live"; case .resumable: return "Resumable"; case .stale: return "Stale" }
    }
    var systemImage: String {
        switch self {
        case .live: return "circle.fill"
        case .resumable: return "moon.zzz.fill"
        case .stale: return "clock.badge.xmark.fill"
        }
    }
}

extension Source {
    var color: Color {
        switch self {
        case .personal: return Palette.accent2
        case .plugin: return .orange
        case .builtin: return Palette.accent
        }
    }
    var systemImage: String {
        switch self {
        case .personal: return "person.crop.circle"
        case .plugin: return "puzzlepiece.extension.fill"
        case .builtin: return "shippingbox.fill"
        }
    }
}

// MARK: - Reusable components

/// Pulsing dot used for live indicators.
struct PulseDot: View {
    var color: Color = Palette.live
    var size: CGFloat = 8
    @State private var on = false
    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
            .overlay(
                Circle().stroke(color, lineWidth: 1.5)
                    .scaleEffect(on ? 2.2 : 1).opacity(on ? 0 : 0.7)
            )
            .shadow(color: color.opacity(0.9), radius: on ? 6 : 3)
            .onAppear { withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { on = true } }
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    var glow: Color? = nil
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding).deckSurface(glow: glow)
    }
}

/// Big stat card with category-tinted glowing top edge. Tappable.
struct StatCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    var subtitle: String? = nil
    var action: () -> Void = {}

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 32, height: 32)
                        .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(tint.opacity(0.35), lineWidth: 0.6))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.bold)).foregroundStyle(tint)
                        .opacity(hover ? 0.9 : 0)
                }
                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
                    .contentTransition(.numericText())
                Text(title).microLabel().foregroundStyle(Palette.textSecondary)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(Palette.textTertiary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .deckSurface(glow: tint, glowStrength: hover ? 0.5 : 0.22)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(hover ? tint.opacity(0.55) : .clear, lineWidth: 1)
            )
            .scaleEffect(hover ? 1.012 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.18)) { hover = h } }
    }
}

struct SourceBadge: View {
    let source: Source
    var body: some View {
        Label(source.label, systemImage: source.systemImage)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(source.color.opacity(0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(source.color.opacity(0.3), lineWidth: 0.6))
            .foregroundStyle(source.color)
    }
}

struct Pill: View {
    let text: String
    var systemImage: String? = nil
    var color: Color = Palette.textSecondary
    var body: some View {
        Group {
            if let systemImage { Label(text, systemImage: systemImage) } else { Text(text) }
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(color.opacity(0.15), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.28), lineWidth: 0.6))
        .foregroundStyle(color == Palette.textSecondary ? Palette.textSecondary : color)
    }
}

struct StateBadge: View {
    let state: SessionState
    var status: String? = nil
    var body: some View {
        HStack(spacing: 5) {
            if state == .live {
                PulseDot(color: state.color, size: 7)
            } else {
                Circle().fill(state.color).frame(width: 7, height: 7)
            }
            Text(status.map { "\(state.label) · \($0)" } ?? state.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(state == .stale ? Palette.textTertiary : Palette.textPrimary)
        }
    }
}

/// Circular context-fill indicator with a soft glow.
struct ContextRing: View {
    let percent: Int
    var size: CGFloat = 38
    private var fraction: Double { min(1, max(0, Double(percent) / 100)) }
    private var color: Color { percent >= 80 ? .red : percent >= 50 ? .orange : Palette.live }
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 4)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.7), radius: 4)
            Text("\(percent)%")
                .font(.system(size: size * 0.26, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.textPrimary)
        }
        .frame(width: size, height: size)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var mono: Bool = false
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).microLabel().foregroundStyle(Palette.textTertiary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(mono ? .caption.monospaced() : .callout)
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var message: String? = nil
    var tint: Color = Palette.accent
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(tint)
                .frame(width: 84, height: 84)
                .background(tint.opacity(0.12), in: Circle())
                .overlay(Circle().strokeBorder(tint.opacity(0.25), lineWidth: 1))
                .shadow(color: tint.opacity(0.3), radius: 18)
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(Palette.textPrimary)
            if let message {
                Text(message).font(.callout).foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }
}

struct DetailHeader<Trailing: View>: View {
    let systemImage: String
    let tint: Color
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 52, height: 52)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(tint.opacity(0.35), lineWidth: 0.7))
                .shadow(color: tint.opacity(0.35), radius: 12)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title2.weight(.bold)).foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled).lineLimit(2)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer()
            trailing
        }
    }
}

extension DetailHeader where Trailing == EmptyView {
    init(systemImage: String, tint: Color, title: String, subtitle: String? = nil) {
        self.init(systemImage: systemImage, tint: tint, title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct BodyPreview: View {
    let text: String
    var body: some View {
        ScrollView {
            Text(text.isEmpty ? "No content." : text)
                .font(.callout).foregroundStyle(Palette.textPrimary.opacity(0.85))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
        .background(Palette.canvasBottom.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.stroke, lineWidth: 0.7))
    }
}
