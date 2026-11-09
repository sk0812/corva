import Charts
import SwiftUI

struct ExperimentDetailView: View {
    let id: Experiment.ID
    @Environment(\.healthDataProvider) private var provider
    @Environment(\.dataVersion) private var dataVersion
    @Environment(\.dismiss) private var dismiss
    @Environment(ExperimentStore.self) private var store
    @State private var model = LabViewModel()
    @State private var isConfirmingDelete = false

    var body: some View {
        Group {
            if let experiment = store.experiment(id: id) {
                LoadStateView(model.state) { days in
                    ScrollView {
                        ExperimentContent(
                            experiment: experiment,
                            result: model.analysis(of: experiment, in: days),
                            days: days,
                            model: model
                        )
                    }
                }
                .navigationTitle(experiment.title)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("Options", systemImage: "ellipsis") {
                            if !experiment.isComplete(today: model.today, calendar: model.calendar) {
                                Button("End now", systemImage: "stop.circle") {
                                    store.end(id, today: model.today, calendar: model.calendar)
                                }
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                isConfirmingDelete = true
                            }
                        }
                    }
                }
                .confirmationDialog("Delete this experiment?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                    Button("Delete experiment", role: .destructive) {
                        dismiss()
                        store.delete(id)
                    }
                } message: {
                    Text("Its tags and results are removed. Your health data isn’t affected.")
                }
            } else {
                ContentUnavailableView("Experiment deleted", systemImage: "flask")
            }
        }
        .screenBackground(glow: glow)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: dataVersion) { await model.load(using: provider) }
    }

    private var glow: Color? {
        guard let experiment = store.experiment(id: id), case .loaded(let days) = model.state else { return nil }
        let verdict = model.analysis(of: experiment, in: days).headline?.verdict
        return verdict.map { $0.color.opacity(0.7) }
    }
}

private struct ExperimentContent: View {
    let experiment: Experiment
    let result: ExperimentAnalysis.Result
    let days: [DailySummary]
    let model: LabViewModel
    @Environment(\.metricFormatter) private var format

    var body: some View {
        VStack(spacing: Spacing.m) {
            header
            TonightPlan(experiment: experiment, today: model.today, calendar: model.calendar)
            if let headline = result.headline {
                HeadlineCard(outcome: headline)
            }
            outcomes
            if let headline = result.headline {
                chart(for: headline.metric)
            }
            if experiment.usesTags {
                TagCalendar(experiment: experiment, today: model.today, calendar: model.calendar)
            }
            sensitivity
            Text(method)
                .textStyle(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.xxs)
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.xxl)
    }

    private var header: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                CardHeader(title: experiment.design.title, detail: ExperimentText.status(experiment, result: result))
                ProgressBar(fraction: Double(result.daysElapsed) / Double(max(experiment.length, 1)), tint: CorvaColor.neutralData, height: 6)
                Text(experiment.design.explanation)
                    .textStyle(.caption)
                Text(ExperimentText.dates(experiment, calendar: model.calendar))
                    .textStyle(.caption)
            }
        }
    }

    private var outcomes: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                CardHeader(title: "All measures", detail: "With vs without")
                VStack(spacing: 0) {
                    ForEach(Array(result.outcomes.enumerated()), id: \.element.id) { index, outcome in
                        if index > 0 { CardDivider() }
                        OutcomeRow(outcome: outcome)
                    }
                }
            }
        }
    }

    private func chart(for metric: Metric) -> some View {
        let shown = days.filter { result.controlDates.contains($0.date) || result.trialDates.contains($0.date) }
        let trial = Set(result.trialDates)
        return GlassCard {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardHeader(title: metric.title, detail: "Each dot is a morning")
                ExperimentChart(
                    points: shown.compactMap { day in
                        metric.value(in: day).map {
                            ExperimentChart.Point(date: day.date, value: format.convert($0, for: metric), isTrial: trial.contains(day.date))
                        }
                    },
                    formatValue: { $0.formatted(.number.precision(.fractionLength(format.fractionDigits(for: metric)))) }
                )
                ChartLegend(items: [
                    .init(label: experiment.usesTags ? "After ON evenings" : "During", color: CorvaColor.bioAge),
                    .init(label: experiment.usesTags ? "Other mornings" : "Four weeks before", color: CorvaColor.neutralData.opacity(0.5)),
                ])
            }
        }
    }

    private var sensitivity: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                CardHeader(title: "Sensitivity", detail: "Smallest change it can catch")
                if let headline = result.headline, let now = headline.detectableNow {
                    StatGrid(columns: 2) {
                        StatTile(label: "Now", value: "±" + format.value(now, for: headline.metric), unit: format.unit(for: headline.metric))
                        if let end = headline.detectableAtEnd, !result.isComplete {
                            StatTile(label: "By day \(experiment.length)", value: "±" + format.value(end, for: headline.metric), unit: format.unit(for: headline.metric))
                        }
                    }
                    Text("A real effect smaller than this could still be hiding in the noise. More days shrink it.")
                        .textStyle(.caption)
                } else {
                    Text("Needs at least \(ExperimentAnalysis.minimumDays) mornings with and without the change before Corva can say anything.")
                        .textStyle(.caption)
                }
            }
        }
    }

    private var method: String {
        var text = "Comparing \(result.trialDates.count) mornings with the change against \(result.controlDates.count) without, using a 95% interval."
        if !result.excludedDates.isEmpty {
            let count = result.excludedDates.count
            text += " \(count) \(count == 1 ? "day" : "days") when your vitals suggested you were unwell \(count == 1 ? "is" : "are") left out."
        }
        return text
    }
}

/// The headline measure as one big number with its interval.
private struct HeadlineCard: View {
    let outcome: ExperimentAnalysis.Outcome
    @Environment(\.metricFormatter) private var format

    var body: some View {
        GlassCard(tint: outcome.verdict == .collecting ? nil : outcome.verdict.color) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack {
                    Text(outcome.metric.title).textStyle(.label)
                    Spacer()
                    VerdictBadge(verdict: outcome.verdict)
                }
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                    Text(format.signed(format.convertDelta(outcome.difference, for: outcome.metric), fractionDigits: format.fractionDigits(for: outcome.metric)))
                        .textStyle(.largeNumeral)
                    Text(format.unit(for: outcome.metric)).textStyle(.unit)
                }
                IntervalBar(
                    estimate: outcome.difference,
                    interval: outcome.interval,
                    limit: ExperimentText.scale(for: outcome),
                    tint: outcome.verdict.color
                )
                Text(ExperimentText.explanation(outcome, format: format))
                    .textStyle(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct OutcomeRow: View {
    let outcome: ExperimentAnalysis.Outcome
    @Environment(\.metricFormatter) private var format

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(outcome.metric.title).textStyle(.body)
                    Text("\(format.valueWithUnit(outcome.control.mean, for: outcome.metric)) → \(format.valueWithUnit(outcome.trial.mean, for: outcome.metric))")
                        .textStyle(.caption)
                        .monospacedDigit()
                }
                Spacer(minLength: Spacing.xs)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(format.signedChange(outcome.difference, for: outcome.metric))
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(CorvaColor.textPrimary)
                    Text(outcome.verdict.title)
                        .font(.caption)
                        .foregroundStyle(outcome.verdict == .noClearChange || outcome.verdict == .collecting ? CorvaColor.textTertiary : outcome.verdict.color)
                }
            }
            IntervalBar(
                estimate: outcome.difference,
                interval: outcome.interval,
                limit: ExperimentText.scale(for: outcome),
                tint: outcome.verdict.color
            )
        }
        .padding(.vertical, Spacing.s)
        .accessibilityElement(children: .combine)
    }
}

/// Daily values, with-change mornings in colour, and the two group means.
private struct ExperimentChart: View {
    struct Point: Identifiable {
        let date: Date
        let value: Double
        let isTrial: Bool
        var id: Date { date }
    }

    let points: [Point]
    let formatValue: (Double) -> String

    var body: some View {
        let trialMean = Statistics.mean(points.filter(\.isTrial).map(\.value))
        let controlMean = Statistics.mean(points.filter { !$0.isTrial }.map(\.value))
        Chart {
            ForEach(points) { point in
                PointMark(x: .value("Day", point.date, unit: .day), y: .value("Value", point.value))
                    .foregroundStyle(point.isTrial ? CorvaColor.bioAge : CorvaColor.neutralData.opacity(0.45))
                    .symbolSize(point.isTrial ? 46 : 26)
            }
            if points.contains(where: { !$0.isTrial }) {
                RuleMark(y: .value("Without", controlMean))
                    .foregroundStyle(CorvaColor.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
            if points.contains(where: \.isTrial) {
                RuleMark(y: .value("With", trialMean))
                    .foregroundStyle(CorvaColor.bioAge)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .foregroundStyle(CorvaColor.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(CorvaColor.chartGrid)
                AxisValueLabel {
                    if let number = value.as(Double.self) { Text(formatValue(number)) }
                }
                .foregroundStyle(CorvaColor.textTertiary)
            }
        }
        .frame(height: Size.chartHeight)
    }
}

/// Every evening of an on & off experiment. Tap the evenings the behaviour happened.
private struct TagCalendar: View {
    let experiment: Experiment
    let today: Date
    let calendar: Calendar
    @Environment(ExperimentStore.self) private var store

    /// Randomised experiments show the whole plan; others only evenings so far.
    private var evenings: [Date] {
        let all = experiment.evenings(calendar: calendar)
        return experiment.design == .randomised ? all : all.filter { $0 <= today }
    }

    private var isPlan: Bool { experiment.design == .randomised }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardHeader(
                    title: isPlan ? "Your plan" : "Tag evenings",
                    detail: isPlan ? "\(experiment.taggedEvenings.count) ON nights" : "\(experiment.taggedEvenings.count) tagged"
                )
                Text(isPlan
                     ? "Filled nights are ON. If a night didn’t go to plan, tap it so the results reflect what you actually did."
                     : "Tap each evening you did it. Results update as you go.")
                    .textStyle(.caption)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.xs), count: 7), spacing: Spacing.xs) {
                    ForEach(evenings, id: \.self) { evening in
                        let isTagged = experiment.taggedEvenings.contains(evening)
                        Button {
                            store.toggleTag(evening: evening, in: experiment.id)
                        } label: {
                            VStack(spacing: 0) {
                                Text(evening, format: .dateTime.weekday(.narrow))
                                    .font(.caption2)
                                    .foregroundStyle(isTagged ? CorvaColor.background : CorvaColor.textTertiary)
                                Text(evening, format: .dateTime.day())
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(isTagged ? CorvaColor.background : CorvaColor.textPrimary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(isTagged ? CorvaColor.bioAge : CorvaColor.ringTrack, in: .rect(cornerRadius: Radius.s))
                        }
                        .buttonStyle(.plain)
                        .disabled(evening > today)
                        .opacity(evening > today ? 0.55 : 1)
                        .accessibilityLabel(evening.formatted(date: .complete, time: .omitted))
                        .accessibilityAddTraits(isTagged ? .isSelected : [])
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: experiment.taggedEvenings)
    }
}

/// For a running randomised experiment: whether tonight is an ON or OFF night.
struct TonightPlan: View {
    let experiment: Experiment
    let today: Date
    let calendar: Calendar

    var body: some View {
        if experiment.design == .randomised,
           !experiment.isComplete(today: today, calendar: calendar),
           experiment.evenings(calendar: calendar).contains(today) {
            let isOn = experiment.isOnNight(today, calendar: calendar)
            HStack(spacing: Spacing.s) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "moon.zzz.fill")
                    .font(.title3)
                    .foregroundStyle(isOn ? CorvaColor.bioAge : CorvaColor.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isOn ? "Tonight is an ON night" : "Tonight is an OFF night")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CorvaColor.textPrimary)
                    Text(isOn ? "\(experiment.title): do it tonight." : "\(experiment.title): skip it tonight.")
                        .textStyle(.caption)
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(isOn ? CorvaColor.bioAge.opacity(0.15) : nil), in: .rect(cornerRadius: Radius.m))
            .accessibilityElement(children: .combine)
        }
    }
}

/// A verdict as a small tinted glass capsule.
struct VerdictBadge: View {
    let verdict: ExperimentAnalysis.Verdict

    var body: some View {
        Text(verdict.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(verdict == .collecting || verdict == .noClearChange ? CorvaColor.textSecondary : verdict.color)
            .lineLimit(1)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xxs)
            .glassEffect(.regular.tint(verdict == .collecting || verdict == .noClearChange ? nil : verdict.color.opacity(0.2)), in: .capsule)
    }
}

extension ExperimentAnalysis.Verdict {
    var title: String {
        switch self {
        case .collecting: "Collecting"
        case .better: "Better"
        case .worse: "Worse"
        case .changed(.up): "Higher"
        case .changed(.down): "Lower"
        case .changed(.flat), .noClearChange: "No clear change"
        }
    }

    var color: Color {
        switch self {
        case .better: CorvaColor.better
        case .worse: CorvaColor.worse
        case .changed: CorvaColor.strain
        case .collecting, .noClearChange: CorvaColor.neutralData
        }
    }
}

/// Wording shared by the Lab card and the detail screen.
enum ExperimentText {
    static func status(_ experiment: Experiment, result: ExperimentAnalysis.Result) -> String {
        result.isComplete ? "Finished · \(experiment.length) days" : "Day \(result.daysElapsed) of \(experiment.length)"
    }

    static func dates(_ experiment: Experiment, calendar: Calendar) -> String {
        let end = experiment.evenings(calendar: calendar).last ?? experiment.start
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated)
        return "Evenings \(experiment.start.formatted(style)) to \(end.formatted(style))"
    }

    /// Half-width for an interval bar: room for the interval and the detectable effect.
    static func scale(for outcome: ExperimentAnalysis.Outcome) -> Double {
        let interval = outcome.interval.map { max(abs($0.lowerBound), abs($0.upperBound)) } ?? 0
        return max(interval, outcome.detectableNow ?? 0, abs(outcome.difference) * 1.5, 0.5) * 1.15
    }

    static func explanation(_ outcome: ExperimentAnalysis.Outcome, format: MetricFormatter) -> String {
        guard let interval = outcome.interval else {
            return "Needs at least \(ExperimentAnalysis.minimumDays) mornings with and without the change. So far: \(outcome.trial.count) with, \(outcome.control.count) without."
        }
        let low = format.signedChange(interval.lowerBound, for: outcome.metric, keepingNonZero: true)
        let high = format.signedChange(interval.upperBound, for: outcome.metric, keepingNonZero: true)
        let range = "The true effect is likely between \(low) and \(high)."
        switch outcome.verdict {
        case .noClearChange: return range + " That includes no change, so it’s too close to call."
        default: return range
        }
    }
}

#Preview {
    NavigationStack {
        ExperimentDetailView(id: ExperimentStore.preview.experiments[0].id)
    }
    .corvaPreview()
}
