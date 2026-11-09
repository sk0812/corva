import SwiftUI

/// Where the Lab tab can navigate.
enum LabDestination: Hashable {
    case bioAge
    case bestDays
    case experiment(Experiment.ID)
}

/// Longer-range analysis: bio age, what your best days have in common, and experiments.
struct LabView: View {
    @Environment(\.healthDataProvider) private var provider
    @Environment(\.dataVersion) private var dataVersion
    @State private var model = LabViewModel()
    @State private var isAddingExperiment = false

    var body: some View {
        NavigationStack {
            LoadStateView(model.state, retry: { await model.load(using: provider) }) { days in
                ScrollView {
                    LabContent(days: days, model: model, addExperiment: { isAddingExperiment = true })
                }
                .refreshable { await model.load(using: provider) }
            }
            .screenBackground(glow: CorvaColor.bioAge.opacity(0.8))
            .navigationTitle("Lab")
            // The title sits in the top bar row, not on its own row below it.
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New experiment", systemImage: "plus") { isAddingExperiment = true }
                }
            }
            .navigationDestination(for: LabDestination.self) { destination in
                switch destination {
                case .bioAge: BioAgeView()
                case .bestDays: BestDaysView()
                case .experiment(let id): ExperimentDetailView(id: id)
                }
            }
            .sheet(isPresented: $isAddingExperiment) {
                NewExperimentView()
            }
        }
        .task(id: dataVersion) { await model.load(using: provider) }
    }
}

private struct LabContent: View {
    let days: [DailySummary]
    let model: LabViewModel
    let addExperiment: () -> Void
    @Environment(AppSettings.self) private var settings
    @Environment(ExperimentStore.self) private var experiments

    var body: some View {
        VStack(spacing: Spacing.m) {
            DemoDataNotice()
            NavigationLink(value: LabDestination.bioAge) {
                BioAgeSummaryCard(
                    estimate: settings.profile.flatMap { model.bioAge(in: days, profile: $0) },
                    history: settings.profile.map { model.bioAgeHistory(in: days, profile: $0) } ?? [],
                    needsAge: settings.profile == nil
                )
            }
            .buttonStyle(.plain)

            NavigationLink(value: LabDestination.bestDays) {
                BestDaysSummaryCard(result: model.contrast(in: days, rankingBy: .recovery, experiments: experiments.experiments))
            }
            .buttonStyle(.plain)

            SectionHeader(title: "Experiments", detail: runningDetail)
                .padding(.top, Spacing.s)
            if experiments.experiments.isEmpty {
                EmptyExperimentsCard(action: addExperiment)
            } else {
                GlassEffectContainer(spacing: Spacing.m) {
                    VStack(spacing: Spacing.m) {
                        ForEach(experiments.experiments) { experiment in
                            NavigationLink(value: LabDestination.experiment(experiment.id)) {
                                ExperimentCard(experiment: experiment, result: model.analysis(of: experiment, in: days))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.xxl)
    }

    private var runningDetail: String {
        let running = experiments.experiments.filter { !$0.isComplete(today: model.today, calendar: model.calendar) }.count
        return running == 1 ? "1 running" : "\(running) running"
    }
}

// MARK: - Bio age

private struct BioAgeSummaryCard: View {
    let estimate: BioAge.Estimate?
    let history: [DatedValue]
    let needsAge: Bool
    @Environment(\.metricFormatter) private var format

    var body: some View {
        GlassCard(tint: CorvaColor.bioAge, isInteractive: true) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardHeader(title: "Bio age", tint: CorvaColor.bioAge, detail: "Last 30 days", showsChevron: true)
                if let estimate {
                    HStack(alignment: .bottom, spacing: Spacing.m) {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                                Text(format.age(estimate.biologicalAge)).textStyle(.largeNumeral)
                                Text("years").textStyle(.unit)
                            }
                            Text(BioAgeText.comparison(estimate, format: format))
                                .textStyle(.caption)
                        }
                        Spacer(minLength: 0)
                        Sparkline(values: history.map(\.value), tint: CorvaColor.bioAge)
                            .frame(width: 92, height: Size.sparklineHeight)
                    }
                    AgeScale(chronological: estimate.chronologicalAge, biological: estimate.biologicalAge)
                    // Side by side when they fit, stacked when the names are long.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Spacing.s) { markerChips }
                        VStack(alignment: .leading, spacing: Spacing.xs) { markerChips }
                    }
                } else {
                    Text(needsAge ? "Add your age in Settings › Profile to see your bio age." : "Bio age needs at least two weeks of data.")
                        .textStyle(.bodySecondary)
                }
            }
        }
    }
}

/// One marker's effect as a small glass capsule: "VO2 max −2.0 y".
struct MarkerChip: View {
    let marker: BioAge.Marker
    @Environment(\.metricFormatter) private var format

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Circle()
                .fill(marker.years < 0 ? CorvaColor.better : CorvaColor.worse)
                .frame(width: 6, height: 6)
            Text(marker.kind.title)
                .foregroundStyle(CorvaColor.textSecondary)
                .fixedSize()
            Text("\(format.signed(marker.years)) y")
                .monospacedDigit()
                .foregroundStyle(CorvaColor.textPrimary)
        }
        .font(.caption.weight(.medium))
        .lineLimit(1)
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xxs + 2)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Best vs worst

extension BioAgeSummaryCard {
    @ViewBuilder
    fileprivate var markerChips: some View {
        if let estimate {
            if let best = estimate.markers.min(by: { $0.years < $1.years }), best.years < 0 {
                MarkerChip(marker: best)
            }
            if let worst = estimate.markers.max(by: { $0.years < $1.years }), worst.years > 0 {
                MarkerChip(marker: worst)
            }
        }
    }
}

private struct BestDaysSummaryCard: View {
    let result: DayContrast.Result?
    @Environment(\.metricFormatter) private var format

    var body: some View {
        GlassCard(isInteractive: true) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardHeader(title: "Best vs worst days", detail: "Recovery · \(LabViewModel.historyDays) days", showsChevron: true)
                if let result {
                    StatGrid(columns: 2) {
                        StatTile(
                            label: "Best \(result.groupSize) days",
                            value: format.value(result.bestMean, for: .recovery),
                            unit: "%",
                            detail: "average recovery"
                        )
                        StatTile(
                            label: "Worst \(result.groupSize) days",
                            value: format.value(result.worstMean, for: .recovery),
                            unit: "%",
                            detail: "average recovery"
                        )
                    }
                    Text("What set them apart").textStyle(.label)
                    VStack(spacing: Spacing.m) {
                        ForEach(result.factors.prefix(3)) { factor in
                            FactorRow(factor: factor)
                        }
                    }
                } else {
                    Text("Needs at least two weeks of data.")
                        .textStyle(.bodySecondary)
                }
            }
        }
    }
}

// MARK: - Experiments

private struct ExperimentCard: View {
    let experiment: Experiment
    let result: ExperimentAnalysis.Result
    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: .now) }
    @Environment(\.metricFormatter) private var format

    var body: some View {
        GlassCard(isInteractive: true) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                CardHeader(title: experiment.design.title, detail: ExperimentText.status(experiment, result: result), showsChevron: true)
                Text(experiment.title)
                    .font(.headline)
                    .foregroundStyle(CorvaColor.textPrimary)
                if let headline = result.headline {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                        Text(headline.metric.title)
                            .font(.subheadline)
                            .foregroundStyle(CorvaColor.textSecondary)
                        Spacer(minLength: Spacing.xs)
                        if headline.verdict != .collecting {
                            Text(format.signedChange(headline.difference, for: headline.metric))
                                .font(.system(.title3, design: .rounded, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(CorvaColor.textPrimary)
                        }
                        VerdictBadge(verdict: headline.verdict)
                    }
                    IntervalBar(
                        estimate: headline.difference,
                        interval: headline.interval,
                        limit: ExperimentText.scale(for: headline),
                        tint: headline.verdict.color
                    )
                }
                ProgressBar(fraction: Double(result.daysElapsed) / Double(max(experiment.length, 1)), tint: CorvaColor.neutralData, height: 4)
                    .padding(.top, Spacing.xxs)
                if experiment.design == .randomised,
                   !experiment.isComplete(today: today, calendar: calendar),
                   experiment.evenings(calendar: calendar).contains(today) {
                    Label(
                        experiment.isOnNight(today, calendar: calendar) ? "Tonight: ON night" : "Tonight: OFF night",
                        systemImage: experiment.isOnNight(today, calendar: calendar) ? "checkmark.circle.fill" : "moon.zzz.fill"
                    )
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(experiment.isOnNight(today, calendar: calendar) ? CorvaColor.bioAge : CorvaColor.textSecondary)
                }
            }
        }
    }
}

private struct EmptyExperimentsCard: View {
    let action: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Test what actually works for you")
                    .font(.headline)
                    .foregroundStyle(CorvaColor.textPrimary)
                Text("Change one thing, like caffeine, alcohol or bedtime, and Corva measures the effect on your own numbers.")
                    .textStyle(.bodySecondary)
                Button("New experiment", action: action)
                    .buttonStyle(.glass)
                    .padding(.top, Spacing.xxs)
            }
        }
    }
}

#Preview {
    LabView()
        .corvaPreview()
}
