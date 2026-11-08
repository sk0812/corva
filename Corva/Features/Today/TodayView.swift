import SwiftUI

/// Where the Today tab can navigate.
enum TodayDestination: Hashable {
    case recovery(Date)
    case strain(Date)
    case sleep(Date)
    case metric(Metric, Date)
}

struct TodayView: View {
    @Environment(\.healthDataProvider) private var provider
    @Environment(\.metricFormatter) private var format
    @State private var model = TodayViewModel()

    var body: some View {
        NavigationStack {
            LoadStateView(model.state) { content in
                ScrollView {
                    TodayContent(content: content)
                }
                .refreshable { await model.load(using: provider) }
            }
            .screenBackground(glow: glow)
            .navigationTitle(title)
            .navigationSubtitle(format.dayTitle(model.date))
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Previous day", systemImage: "chevron.left") {
                        Task { await model.step(by: -1, using: provider) }
                    }
                    Button("Next day", systemImage: "chevron.right") {
                        Task { await model.step(by: 1, using: provider) }
                    }
                    .disabled(model.isToday)
                }
            }
            .navigationDestination(for: TodayDestination.self, destination: destinationView)
        }
        .sensoryFeedback(.selection, trigger: model.date)
        .task { await model.load(using: provider) }
    }

    private var title: String {
        if model.isToday { return "Today" }
        if model.isYesterday { return "Yesterday" }
        return model.date.formatted(.dateTime.weekday(.wide))
    }

    /// Today's recovery colour lights the top of the screen.
    private var glow: Color? {
        guard case .loaded(let content) = model.state else { return nil }
        return content.day.recovery.zone.color
    }

    @ViewBuilder
    private func destinationView(_ destination: TodayDestination) -> some View {
        switch destination {
        case .recovery(let date): RecoveryDetailView(date: date)
        case .strain(let date): StrainDetailView(date: date)
        case .sleep(let date): SleepDetailView(date: date)
        case .metric(let metric, let date): MetricDetailView(metric: metric, date: date)
        }
    }
}

private struct TodayContent: View {
    let content: TodayViewModel.Content

    var body: some View {
        VStack(spacing: Spacing.m) {
            ScoreDials(content: content)
                .padding(.bottom, Spacing.s)
            StrainTargetCard(content: content)
            HealthMonitorCard(content: content)
            SleepSummaryCard(content: content)
            ActivitySummaryCard(content: content)
            WeekCard(content: content)
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.xxl)
    }
}

// MARK: - Dials

/// Sleep, recovery and strain side by side: the day at a glance.
private struct ScoreDials: View {
    let content: TodayViewModel.Content
    @Environment(\.metricFormatter) private var format

    private var day: DailySummary { content.day }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            dial(.sleep, score: day.sleep.score, tint: CorvaColor.sleep, style: .small, destination: .sleep(day.date))
            Spacer(minLength: 0)
            dial(.recovery, score: day.recovery.score, tint: day.recovery.zone.color, style: .medium, destination: .recovery(day.date))
            Spacer(minLength: 0)
            dial(.strain, score: day.strain.score, tint: CorvaColor.strain, style: .small, destination: .strain(day.date))
        }
    }

    private func dial(_ metric: Metric, score: Int, tint: Color, style: ScoreRing.Style, destination: TodayDestination) -> some View {
        NavigationLink(value: destination) {
            VStack(spacing: Spacing.s) {
                ScoreRing(score: score, label: metric.title, unit: format.unit(for: metric).nilIfEmpty, tint: tint, style: style)
                    .padding(.top, style == .small ? (ScoreRing.Style.medium.diameter - style.diameter) / 2 : 0)
                VStack(spacing: 2) {
                    Text(metric.title)
                        .textStyle(.label)
                    if metric == .recovery {
                        Text(day.recovery.zone.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(day.recovery.zone.color)
                    }
                    if let delta = content.delta(metric) {
                        DeltaLabel(delta: format.delta(delta, for: metric), suffix: "vs avg")
                    }
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Strain target

private struct StrainTargetCard: View {
    let content: TodayViewModel.Content

    private var strain: Int { content.day.strain.score }
    private var target: ClosedRange<Int> { content.strainTarget }

    var body: some View {
        NavigationLink(value: TodayDestination.strain(content.day.date)) {
            GlassCard(tint: CorvaColor.strain, isInteractive: true) {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    CardHeader(
                        title: "Strain target",
                        tint: CorvaColor.strain,
                        detail: "From \(content.day.recovery.score)% recovery",
                        showsChevron: true
                    )
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                        Text(strain, format: .number).textStyle(.numeral)
                        Text("of \(target.lowerBound)–\(target.upperBound)").textStyle(.caption)
                        Spacer(minLength: Spacing.xs)
                        Text(status)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(CorvaColor.textSecondary)
                    }
                    TargetBar(
                        value: Double(strain),
                        target: Double(target.lowerBound)...Double(target.upperBound),
                        tint: CorvaColor.strain
                    )
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var status: String {
        if strain < target.lowerBound { return "\(target.lowerBound - strain) below target" }
        if strain > target.upperBound { return "\(strain - target.upperBound) above target" }
        return "Within target"
    }
}

// MARK: - Health monitor

/// Every overnight vital against its own typical range, flagged when outside it.
private struct HealthMonitorCard: View {
    let content: TodayViewModel.Content
    @Environment(\.metricFormatter) private var format

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                CardHeader(
                    title: "Health monitor",
                    tint: content.vitalsInRange == Metric.vitals.count ? nil : CorvaColor.alert,
                    detail: "\(content.vitalsInRange) of \(Metric.vitals.count) in typical range"
                )
                VStack(spacing: 0) {
                    ForEach(Array(Metric.vitals.enumerated()), id: \.element) { index, metric in
                        if index > 0 { CardDivider() }
                        NavigationLink(value: TodayDestination.metric(metric, content.day.date)) {
                            VitalRow(metric: metric, day: content.day)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct VitalRow: View {
    let metric: Metric
    let day: DailySummary
    @Environment(\.metricFormatter) private var format

    var body: some View {
        HStack(spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.title)
                    .font(.subheadline)
                    .foregroundStyle(CorvaColor.textPrimary)
                    .lineLimit(1)
                if let baseline = day.baseline[metric] {
                    Text("Baseline \(format.valueWithUnit(baseline.mean, for: metric))")
                        .font(.caption)
                        .foregroundStyle(CorvaColor.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let range = day.baseline[metric]?.typicalRange {
                RangeBar(value: metric.value(in: day), typicalRange: range)
                    .frame(width: 76)
            }
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(format.value(metric.value(in: day), for: metric))
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(CorvaColor.textPrimary)
                    Text(format.unit(for: metric))
                        .font(.caption2)
                        .foregroundStyle(CorvaColor.textSecondary)
                }
                if let delta = day.baseline.delta(for: metric, in: day) {
                    DeltaLabel(delta: format.delta(delta, for: metric))
                }
            }
            .frame(minWidth: 78, alignment: .trailing)
        }
        .padding(.vertical, Spacing.s)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Sleep

private struct SleepSummaryCard: View {
    let content: TodayViewModel.Content
    @Environment(\.metricFormatter) private var format

    private var sleep: SleepMetrics { content.day.sleep }

    var body: some View {
        NavigationLink(value: TodayDestination.sleep(content.day.date)) {
            GlassCard(tint: CorvaColor.sleep, isInteractive: true) {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    CardHeader(
                        title: "Sleep",
                        tint: CorvaColor.sleep,
                        detail: "\(format.clockTime(sleep.bedtime)) – \(format.clockTime(sleep.wakeTime))",
                        showsChevron: true
                    )
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                        Text(format.duration(sleep.timeAsleep)).textStyle(.numeral)
                        Text("of \(format.duration(sleep.need)) need").textStyle(.caption)
                    }
                    ProgressBar(fraction: sleep.need > 0 ? sleep.timeAsleep / sleep.need : 0, tint: CorvaColor.sleep)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        SegmentedBar(segments: SleepStage.displayOrder.map {
                            .init(id: $0.rawValue, value: sleep.duration(of: $0), color: $0.color)
                        })
                        HStack(spacing: Spacing.s) {
                            ForEach(SleepStage.displayOrder) { stage in
                                HStack(spacing: Spacing.xxs) {
                                    Circle().fill(stage.color).frame(width: 7, height: 7)
                                    Text("\(stage.title) \(format.percent(share(of: stage)))")
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(CorvaColor.textSecondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                            }
                        }
                    }
                    CardDivider()
                    StatGrid {
                        StatTile(label: "Efficiency", value: format.percent(sleep.efficiency))
                        StatTile(label: "Deep + REM", value: format.percent(sleep.restorativeShare))
                        StatTile(label: "Debt · 7d", value: format.duration(content.weeklySleepDebt))
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func share(of stage: SleepStage) -> Double {
        sleep.timeInBed > 0 ? sleep.duration(of: stage) / sleep.timeInBed : 0
    }
}

extension SleepStage {
    /// Deepest first, for breakdowns and legends.
    static let displayOrder: [SleepStage] = [.deep, .rem, .light, .awake]
}

// MARK: - Activity

private struct ActivitySummaryCard: View {
    let content: TodayViewModel.Content
    @Environment(\.metricFormatter) private var format

    private var strain: StrainMetrics { content.day.strain }

    var body: some View {
        NavigationLink(value: TodayDestination.strain(content.day.date)) {
            GlassCard(tint: CorvaColor.strain, isInteractive: true) {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    CardHeader(title: "Activity", tint: CorvaColor.strain, detail: activityCount, showsChevron: true)
                    StatGrid(columns: 4) {
                        StatTile(label: "Active", value: format.value(strain.activeEnergy, for: .strain), unit: "kcal")
                        StatTile(label: "Steps", value: format.steps(strain.steps))
                        StatTile(label: "Avg HR", value: "\(strain.averageHeartRate)", unit: "bpm")
                        StatTile(label: "Max HR", value: "\(strain.maxHeartRate)", unit: "bpm")
                    }
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack {
                            Text("Heart rate zones").textStyle(.caption)
                            Spacer()
                            Text(format.duration(strain.heartRateZones.reduce(0) { $0 + $1.duration }))
                                .textStyle(.caption)
                                .monospacedDigit()
                        }
                        SegmentedBar(segments: strain.heartRateZones.map {
                            .init(id: $0.zone.title, value: $0.duration, color: $0.zone.color)
                        })
                    }
                    if !strain.activities.isEmpty {
                        CardDivider()
                        VStack(spacing: 0) {
                            ForEach(strain.activities) { activity in
                                ActivityRow(activity: activity, style: .compact)
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var activityCount: String {
        switch strain.activities.count {
        case 0: "No activities"
        case 1: "1 activity"
        case let count: "\(count) activities"
        }
    }
}

// MARK: - Week

/// The last seven days of recovery with the strain taken on each day.
private struct WeekCard: View {
    let content: TodayViewModel.Content
    @Environment(\.metricFormatter) private var format

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardHeader(title: "Last 7 days")
                StatGrid {
                    StatTile(label: "Recovery", value: format.value(content.weekAverage(.recovery), for: .recovery), unit: "%", detail: "average")
                    StatTile(label: "Strain", value: format.value(content.weekAverage(.strain), for: .strain), detail: "average")
                    StatTile(label: "Sleep", value: format.value(content.weekAverage(.sleep), for: .sleep), unit: "%", detail: "average")
                }
                ComboChart(
                    bars: Metric.recovery.series(in: content.week),
                    line: Metric.strain.series(in: content.week),
                    barColor: { Metric.recovery.tint(for: $0).opacity(0.85) },
                    lineColor: CorvaColor.strain,
                    height: 150
                )
                ChartLegend(items: [
                    .init(label: "Recovery", color: CorvaColor.recoveryHigh),
                    .init(label: "Strain", color: CorvaColor.strain),
                ])
            }
        }
    }
}

extension String {
    /// Nil for an empty string, for optional UI text like units.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

#Preview {
    TodayView()
        .corvaPreview()
}
