import SwiftUI

struct BestDaysView: View {
    @Environment(\.healthDataProvider) private var provider
    @Environment(ExperimentStore.self) private var experiments
    @State private var model = LabViewModel()
    @State private var ranking: DayContrast.Ranking = .recovery

    var body: some View {
        LoadStateView(model.state) { days in
            ScrollView {
                VStack(spacing: Spacing.m) {
                    Picker("Rank days by", selection: $ranking) {
                        ForEach(DayContrast.Ranking.allCases) { ranking in
                            Text(ranking.metric.title).tag(ranking)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, Spacing.xs)

                    if let result = model.contrast(in: days, rankingBy: ranking, experiments: experiments.experiments) {
                        BestDaysContent(result: result)
                    }
                }
                .padding(.horizontal, Spacing.screen)
                .padding(.top, Spacing.s)
                .padding(.bottom, Spacing.xxl)
            }
        }
        .screenBackground(glow: CorvaColor.better.opacity(0.7))
        .navigationTitle("Best vs worst days")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: ranking)
        .task { await model.load(using: provider) }
    }
}

private struct BestDaysContent: View {
    let result: DayContrast.Result
    @Environment(\.metricFormatter) private var format

    private var metric: Metric { result.ranking.metric }

    /// The ranking metric in running text.
    private var metricName: String {
        switch result.ranking {
        case .recovery: "recovery"
        case .hrv: "HRV"
        case .sleep: "sleep performance"
        }
    }

    var body: some View {
        VStack(spacing: Spacing.m) {
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    CardHeader(title: "Top and bottom quarter", detail: "\(result.dates.count) days")
                    StatGrid(columns: 2) {
                        StatTile(
                            label: "Best \(result.groupSize) days",
                            value: format.value(result.bestMean, for: metric),
                            unit: format.unit(for: metric),
                            detail: "average \(metricName)"
                        )
                        StatTile(
                            label: "Worst \(result.groupSize) days",
                            value: format.value(result.worstMean, for: metric),
                            unit: format.unit(for: metric),
                            detail: "average \(metricName)"
                        )
                    }
                    DayStrip(dates: result.dates, best: result.bestDates, worst: result.worstDates)
                    HStack {
                        ChartLegend(items: [
                            .init(label: "Best", color: CorvaColor.better),
                            .init(label: "Worst", color: CorvaColor.worse),
                        ])
                        Spacer()
                        Text("Oldest to newest").textStyle(.caption)
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    CardHeader(title: "What was different", detail: "Biggest first")
                    VStack(spacing: 0) {
                        ForEach(Array(result.factors.enumerated()), id: \.element.id) { index, factor in
                            if index > 0 { CardDivider() }
                            FactorRow(factor: factor)
                                .padding(.vertical, Spacing.s)
                        }
                    }
                }
            }

            Text("Days ranked by \(metricName); best and worst are the top and bottom quarter. Factors describe the night before and the day before each morning. They show what went together, not what caused what.")
                .textStyle(.caption)
                .padding(.horizontal, Spacing.xxs)
        }
    }
}

/// One factor: best-day and worst-day averages on a shared scale, and how big the gap is.
struct FactorRow: View {
    let factor: DayContrast.Factor
    @Environment(\.metricFormatter) private var format

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(factor.kind.title)
                    .font(.subheadline)
                    .foregroundStyle(CorvaColor.textPrimary)
                Spacer(minLength: Spacing.xs)
                Text(factor.strength.rawValue)
                    .font(.caption)
                    .foregroundStyle(factor.strength == .none ? CorvaColor.textTertiary : CorvaColor.textSecondary)
            }
            DumbbellBar(best: factor.best, worst: factor.worst, domain: factor.spread)
            HStack {
                label("Best", value: factor.best, color: CorvaColor.better)
                Spacer()
                label("Worst", value: factor.worst, color: CorvaColor.worse)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(factor.kind.title): best days \(format.factor(factor.best, kind: factor.kind)), worst days \(format.factor(factor.worst, kind: factor.kind)). \(factor.strength.rawValue).")
    }

    private func label(_ title: String, value: Double, color: Color) -> some View {
        HStack(spacing: Spacing.xxs) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).foregroundStyle(CorvaColor.textTertiary)
            Text(format.factor(value, kind: factor.kind))
                .monospacedDigit()
                .foregroundStyle(CorvaColor.textSecondary)
        }
        .font(.caption)
    }
}

/// Every day as a thin mark, coloured if it's among the best or worst.
private struct DayStrip: View {
    let dates: [Date]
    let best: Set<Date>
    let worst: Set<Date>

    var body: some View {
        HStack(spacing: 1) {
            ForEach(dates, id: \.self) { date in
                Capsule()
                    .fill(color(for: date))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 22)
        .accessibilityHidden(true)
    }

    private func color(for date: Date) -> Color {
        if best.contains(date) { return CorvaColor.better }
        if worst.contains(date) { return CorvaColor.worse }
        return CorvaColor.ringTrack
    }
}

#Preview {
    NavigationStack {
        BestDaysView()
    }
    .corvaPreview()
}
