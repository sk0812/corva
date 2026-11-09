import SwiftUI

struct BestDaysView: View {
    @Environment(\.healthDataProvider) private var provider
    @Environment(\.dataVersion) private var dataVersion
    @Environment(ExperimentStore.self) private var experiments
    @State private var model = LabViewModel()
    @State private var ranking: DayContrast.Ranking = .recovery
    @State private var idea: ExperimentIdea?

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
                        BestDaysContent(result: result, test: { idea = $0 })
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
        .sheet(item: $idea) { idea in
            NewExperimentView(title: idea.title, design: idea.design)
        }
        .task(id: dataVersion) { await model.load(using: provider) }
    }
}

private struct BestDaysContent: View {
    let result: DayContrast.Result
    let test: (ExperimentIdea) -> Void
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
                            FactorRow(factor: factor, onTest: factor.strength == .none ? nil : factor.kind.experimentIdea.map { idea in { test(idea) } })
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
    /// Opens a pre-filled experiment, for factors you can actually change.
    var onTest: (() -> Void)?
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
            if let onTest {
                Button(action: onTest) {
                    Label("Test this", systemImage: "flask")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.glass)
                .accessibilityHint("Starts a randomised experiment to see whether this really makes a difference")
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

/// A ready-made experiment for a factor that stood out.
struct ExperimentIdea: Identifiable {
    let title: String
    let design: Experiment.Design
    var id: String { title }
}

extension DayContrast.FactorKind {
    /// What you could test about this factor. Nil for things you can't choose (weekends,
    /// being unwell) or that are outcomes rather than behaviours.
    var experimentIdea: ExperimentIdea? {
        switch self {
        case .bedtime, .timeInBed, .timeAsleep:
            ExperimentIdea(title: "In bed 30 minutes earlier", design: .randomised)
        case .priorStrain, .priorHardMinutes:
            ExperimentIdea(title: "Easier training day", design: .randomised)
        case .restorativeSleep, .awakenings:
            ExperimentIdea(title: "No screens in the hour before bed", design: .randomised)
        case .tag(let name):
            ExperimentIdea(title: name, design: .randomised)
        case .priorSteps, .wakeTime, .weekend, .unwell:
            nil
        }
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
