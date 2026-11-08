import Charts
import SwiftUI

struct SleepDetailView: View {
    @Environment(\.healthDataProvider) private var provider
    @Environment(\.metricFormatter) private var format
    @State private var model: SleepDetailViewModel

    init(date: Date) {
        _model = State(initialValue: SleepDetailViewModel(date: date))
    }

    var body: some View {
        LoadStateView(model.state) { content in
            ScrollView {
                SleepDetailContent(content: content)
            }
        }
        .screenBackground(glow: CorvaColor.sleep)
        .navigationTitle(Metric.sleep.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationSubtitle(format.dayTitle(model.date))
        .task { await model.load(using: provider) }
    }
}

private struct SleepDetailContent: View {
    let content: SleepDetailViewModel.Content
    @Environment(\.metricFormatter) private var format

    private var sleep: SleepMetrics { content.sleep }

    var body: some View {
        VStack(spacing: Spacing.m) {
            VStack(spacing: Spacing.m) {
                ScoreRing(score: sleep.score, label: "Of need", unit: format.unit(for: .sleep), tint: CorvaColor.sleep)
                if let delta = content.delta {
                    DeltaLabel(delta: format.delta(delta, for: .sleep), suffix: "vs 30-day avg")
                }
            }
            .padding(.vertical, Spacing.m)

            durationCard
            qualityCard
            stagesCard
            fortnightCard
            consistencyCard
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.xxl)
    }

    // MARK: Duration vs need

    private var durationCard: some View {
        GlassCard(tint: CorvaColor.sleep) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardHeader(
                    title: "Duration",
                    tint: CorvaColor.sleep,
                    detail: "\(format.clockTime(sleep.bedtime)) – \(format.clockTime(sleep.wakeTime))"
                )
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text(format.duration(sleep.timeAsleep)).textStyle(.numeral)
                    Text("of \(format.duration(sleep.need))").textStyle(.caption)
                    Spacer(minLength: 0)
                    Text("\(format.duration(max(sleep.need - sleep.timeAsleep, 0))) short")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(CorvaColor.textSecondary)
                }
                ProgressBar(fraction: sleep.need > 0 ? sleep.timeAsleep / sleep.need : 0, tint: CorvaColor.sleep)
            }
        }
    }

    // MARK: Quality

    private var qualityCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardHeader(title: "Quality")
                StatGrid {
                    StatTile(label: "Efficiency", value: format.percent(sleep.efficiency), detail: "asleep in bed")
                    StatTile(label: "Latency", value: format.duration(sleep.latency), detail: "to fall asleep")
                    StatTile(label: "Wakes", value: "\(sleep.awakenings)", detail: "during the night")
                    StatTile(label: "Deep + REM", value: format.percent(sleep.restorativeShare), detail: "of time asleep")
                    StatTile(label: "Debt · 7d", value: format.duration(content.weeklyDebt), detail: "missed vs need")
                    StatTile(label: "In bed", value: format.duration(sleep.timeInBed))
                }
            }
        }
    }

    // MARK: Stages

    private var stagesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                CardHeader(title: "Stages", detail: "vs 30-day avg")
                Hypnogram(segments: sleep.segments)
                    .padding(.bottom, Spacing.xs)
                VStack(spacing: 0) {
                    ForEach(Array(SleepStage.displayOrder.enumerated()), id: \.element) { index, stage in
                        if index > 0 { CardDivider() }
                        StatRow(
                            title: stage.title,
                            value: format.duration(sleep.duration(of: stage)),
                            detail: format.percent(share(of: stage)),
                            delta: content.stageAverages[stage].map { format.durationDelta(sleep.duration(of: stage) - $0) },
                            swatch: stage.color
                        )
                    }
                }
            }
        }
    }

    private func share(of stage: SleepStage) -> Double {
        sleep.timeInBed > 0 ? sleep.duration(of: stage) / sleep.timeInBed : 0
    }

    // MARK: Last 14 nights

    private var fortnightCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardHeader(title: "Asleep vs need", detail: "14 nights")
                ComboChart(
                    bars: content.fortnight.map { DatedValue(date: $0.date, value: $0.sleep.timeAsleep / 3600) },
                    line: content.fortnight.map { DatedValue(date: $0.date, value: $0.sleep.need / 3600) },
                    barColor: { _ in CorvaColor.sleep.opacity(0.75) },
                    lineColor: CorvaColor.textPrimary,
                    yDomain: 0...11,
                    formatValue: { "\(Int($0))h" }
                )
                ChartLegend(items: [
                    .init(label: "Asleep", color: CorvaColor.sleep),
                    .init(label: "Need", color: CorvaColor.textPrimary),
                ])
            }
        }
    }

    // MARK: Consistency

    private var consistencyCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardHeader(title: "Consistency", detail: "Last \(content.nights.count) nights")
                if let consistency = content.consistency {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(consistency, format: .number).textStyle(.numeral)
                        Text("%").textStyle(.unit)
                    }
                    .accessibilityLabel("Consistency \(consistency) percent")
                }
                ScheduleChart(nights: content.nights, anchor: content.eveningAnchor)
                StatGrid(columns: 2) {
                    if let bedtime = content.averageBedtime {
                        StatTile(label: "Avg bedtime", value: format.clockTime(bedtime))
                    }
                    if let wakeTime = content.averageWakeTime {
                        StatTile(label: "Avg wake", value: format.clockTime(wakeTime))
                    }
                }
            }
        }
    }
}

/// Stages across the night, deepest at the bottom.
///
/// Stages are placed at numeric levels rather than on a categorical axis so each label sits
/// exactly beside its row.
private struct Hypnogram: View {
    let segments: [SleepSegment]

    var body: some View {
        Chart(segments) { segment in
            let level = Double(segment.stage.hypnogramLevel)
            RectangleMark(
                xStart: .value("Start", segment.start),
                xEnd: .value("End", segment.end),
                yStart: .value("Stage", level + 0.12),
                yEnd: .value("Stage", level + 0.88)
            )
            .foregroundStyle(segment.stage.color)
            .cornerRadius(2)
        }
        .chartYScale(domain: 0...Double(SleepStage.allCases.count))
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                AxisGridLine()
                    .foregroundStyle(CorvaColor.chartGrid)
                AxisValueLabel(format: .dateTime.hour(), anchor: .top)
                    .foregroundStyle(CorvaColor.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: SleepStage.allCases.map { Double($0.hypnogramLevel) + 0.5 }) { value in
                AxisValueLabel {
                    if let position = value.as(Double.self) {
                        Text(SleepStage(hypnogramLevel: Int(position))?.title ?? "")
                    }
                }
                .font(.caption)
                .foregroundStyle(CorvaColor.textSecondary)
            }
        }
        .frame(height: 168)
    }
}

private extension SleepStage {
    /// Row in the hypnogram, counted from the bottom.
    var hypnogramLevel: Int {
        switch self {
        case .deep: 0
        case .light: 1
        case .rem: 2
        case .awake: 3
        }
    }

    init?(hypnogramLevel: Int) {
        guard let stage = SleepStage.allCases.first(where: { $0.hypnogramLevel == hypnogramLevel }) else { return nil }
        self = stage
    }
}

/// Bed-to-wake span for each recent night on a shared clock, so drift is easy to see.
/// Oldest night at the top.
private struct ScheduleChart: View {
    let nights: [SleepDetailViewModel.Night]
    /// 6 PM on the selected evening; hour offsets are labelled relative to it.
    let anchor: Date

    var body: some View {
        Chart(Array(nights.enumerated()), id: \.element.id) { index, night in
            let row = Double(row(for: index))
            RectangleMark(
                xStart: .value("Bedtime", night.bedtimeHour),
                xEnd: .value("Wake", night.wakeHour),
                yStart: .value("Night", row - 0.22),
                yEnd: .value("Night", row + 0.22)
            )
            .foregroundStyle(night.isSelected ? CorvaColor.sleep : CorvaColor.sleep.opacity(0.4))
            .clipShape(Capsule())
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: -0.5...(Double(nights.count) - 0.5))
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                AxisGridLine()
                    .foregroundStyle(CorvaColor.chartGrid)
                AxisValueLabel(anchor: .top) {
                    if let hour = value.as(Double.self) {
                        Text(anchor.addingTimeInterval(hour * 3600), format: .dateTime.hour())
                    }
                }
                .foregroundStyle(CorvaColor.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: Array(nights.indices).map { Double(row(for: $0)) }) { value in
                AxisValueLabel {
                    if let row = value.as(Double.self) {
                        Text(label(forRow: Int(row.rounded())))
                    }
                }
                .font(.caption)
                .foregroundStyle(CorvaColor.textSecondary)
            }
        }
        .frame(height: CGFloat(nights.count) * 28 + 20)
    }

    /// Charts count up from the bottom; nights read top to bottom.
    private func row(for index: Int) -> Int {
        nights.count - 1 - index
    }

    private func label(forRow row: Int) -> String {
        let index = nights.count - 1 - row
        guard nights.indices.contains(index) else { return "" }
        return nights[index].date.formatted(.dateTime.weekday(.abbreviated))
    }

    private var domain: ClosedRange<Double> {
        let earliest = nights.map(\.bedtimeHour).min() ?? 4
        let latest = nights.map(\.wakeHour).max() ?? 14
        return floor(earliest - 0.5)...ceil(latest + 0.5)
    }

    /// Every two hours, on even clock hours.
    private var ticks: [Double] {
        let start = (domain.lowerBound / 2).rounded(.up) * 2
        return Array(stride(from: start, through: domain.upperBound, by: 2))
    }
}

#Preview {
    NavigationStack {
        SleepDetailView(date: DailySummary.preview.date)
    }
    .corvaPreview()
}
