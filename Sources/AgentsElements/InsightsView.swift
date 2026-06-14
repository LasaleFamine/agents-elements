import SwiftUI

struct InsightsView: View {
    @Bindable var store: ElementsStore

    var body: some View {
        if store.totalTokens == 0 {
            EmptyStateView(systemImage: "chart.bar.xaxis",
                           title: "No token usage yet",
                           message: "Once your sessions accrue token usage, spend by project and model — plus an activity heatmap — will appear here.",
                           tint: Color(hex: 0x6EE7B7))
        } else {
            ScrollView { InsightsContent(store: store) }
        }
    }
}

/// Scrollable body of Insights, factored out so it can be rendered offscreen.
struct InsightsContent: View {
    @Bindable var store: ElementsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            totals
            DeckSectionHeader(title: "Activity", systemImage: "calendar", tint: Color(hex: 0x6EE7B7))
            Card { ActivityHeatmap(byDay: store.tokensByDay) }
            HStack(alignment: .top, spacing: 14) {
                breakdown("Spend by project", store.costByProject, .brown)
                breakdown("Spend by model", store.costByModel, .blue)
            }
            footnote
        }
        .padding(20)
    }

    private var totals: some View {
        HStack(spacing: 14) {
            bigTile("Estimated cost", Pricing.money(store.totalCost), "All-time across \(store.sessions.count) sessions", Color(hex: 0x6EE7B7))
            bigTile("Last 7 days", Pricing.money(store.cost(since: 7)), "recent spend", Palette.accent2)
            bigTile("Total tokens", Format.compact(store.totalTokens), "processed", Palette.accent)
        }
    }

    private func bigTile(_ label: String, _ value: String, _ sub: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).microLabel().foregroundStyle(Palette.textSecondary)
            Text(value).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(Palette.textPrimary)
            Text(sub).font(.caption).foregroundStyle(Palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .deckSurface(glow: tint, glowStrength: 0.25)
    }

    private func breakdown(_ title: String, _ rows: [ElementsStore.CostRow], _ tint: Color) -> some View {
        let maxCost = rows.map(\.cost).max() ?? 1
        return VStack(alignment: .leading, spacing: 10) {
            DeckSectionHeader(title: title, tint: tint)
            Card {
                VStack(spacing: 9) {
                    ForEach(rows.prefix(8)) { row in
                        CostBar(row: row, maxCost: maxCost, tint: tint)
                    }
                    if rows.isEmpty {
                        Text("No usage").font(.caption).foregroundStyle(Palette.textTertiary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footnote: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle").font(.caption2)
            Text("Estimates from list pricing (Opus $5/$25, Sonnet $3/$15, Haiku $1/$5, Fable $10/$50 per 1M in/out). Cache reads ≈0.1×, writes ≈1.25× input. Excludes batch discounts and free server-tool usage.")
        }
        .font(.caption2).foregroundStyle(Palette.textTertiary)
        .padding(.top, 4)
    }
}

struct CostBar: View {
    let row: ElementsStore.CostRow
    let maxCost: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(row.label)
                .font(.callout).foregroundStyle(Palette.textPrimary)
                .frame(width: 140, alignment: .leading).lineLimit(1).truncationMode(.middle)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.surfaceHi).frame(height: 8)
                    Capsule().fill(tint)
                        .frame(width: max(4, geo.size.width * (maxCost > 0 ? row.cost / maxCost : 0)), height: 8)
                        .shadow(color: tint.opacity(0.5), radius: 4)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 14)
            Text(Pricing.money(row.cost))
                .font(.callout.weight(.semibold).monospacedDigit()).foregroundStyle(Palette.textPrimary)
                .frame(width: 64, alignment: .trailing)
            Text(Format.compact(row.tokens))
                .font(.caption.monospacedDigit()).foregroundStyle(Palette.textTertiary)
                .frame(width: 50, alignment: .trailing)
        }
    }
}

/// GitHub-style calendar heatmap of tokens per day.
struct ActivityHeatmap: View {
    let byDay: [Date: Int]
    var weeks = 17

    private let cal = Calendar.current

    var body: some View {
        let maxTokens = max(1, byDay.values.max() ?? 1)
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let startOfThisWeek = cal.date(byAdding: .day, value: -(weekday - 1), to: today) ?? today
        let start = cal.date(byAdding: .day, value: -7 * (weeks - 1), to: startOfThisWeek) ?? today

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 3) {
                ForEach(0..<weeks, id: \.self) { col in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { row in
                            cell(start: start, col: col, row: row, today: today, maxTokens: maxTokens)
                        }
                    }
                }
            }
            HStack(spacing: 5) {
                Text("less").font(.caption2).foregroundStyle(Palette.textTertiary)
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2).fill(color(level: Double(i) / 4)).frame(width: 11, height: 11)
                }
                Text("more").font(.caption2).foregroundStyle(Palette.textTertiary)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func cell(start: Date, col: Int, row: Int, today: Date, maxTokens: Int) -> some View {
        let date = cal.date(byAdding: .day, value: col * 7 + row, to: start) ?? start
        let tokens = byDay[cal.startOfDay(for: date)] ?? 0
        let future = date > today
        RoundedRectangle(cornerRadius: 2.5)
            .fill(future ? Color.clear : color(level: tokens == 0 ? 0 : 0.2 + 0.8 * min(1, Double(tokens) / Double(maxTokens))))
            .frame(width: 12, height: 12)
            .help(future ? "" : "\(Format.compact(tokens)) tokens · \(date.formatted(date: .abbreviated, time: .omitted))")
    }

    private func color(level: Double) -> Color {
        if level <= 0 { return Palette.surfaceHi }
        return Color(hex: 0x34D399).opacity(0.2 + 0.8 * level)
    }
}
