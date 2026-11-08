import Charts
import SwiftUI

struct TrendsView: View {
    @Environment(\.healthDataProvider) private var provider
    @State private var model = TrendsViewModel()

    var body: some View {
        NavigationStack {
            LoadStateView(model.state) { content in
                ScrollView {
                    TrendsContent(content: content, model: model)
                }
                .refreshable { await model.load(using: provider) }
            }
            .screenBackground(glow: CorvaColor.strain.opacity(0.7))
            .navigationTitle("Trends")
        }
        .task { await model.load(using: provider) }
    }
}

private struct TrendsContent: View {
    let content: TrendsViewModel.Content
    @Bindable var model: TrendsViewModel

    var body: some View {
        VStack(spacing: Spacing.m) {
            Picker("Period", selection: $model.period) {
                ForEach(TrendPeriod.allCases) { period in
                    Text(period.title)
                        .accessibilityLabel(period.accessibilityTitle)
                        .tag(period)
                }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, Spacing.xs)

            SummaryRow(series: Metric.scores.map { model.series(for: $0, in: content) })

            SectionHeader(title: "Scores", detail: "Drag a chart to inspect")
                .padding(.top, Spacing.s)
            GlassEffectContainer(spacing: Spacing.m) {
                VStack(spacing: Spacing.m) {
                    ForEach(Metric.scores) { metric in
                        TrendCard(series: model.series(for: metric, in: content))
                    }
                }
            }
            ZoneMixCard(distribution: model.distribution(in: content), period: model.period)

            SectionHeader(title: "Patterns", detail: "Last \(content.days.count) days")
                .padding(.top, Spacing.s)
            WeekdayCard(recovery: content.recoveryByWeekday, strain: content.strainByWeekday)
            RelationshipsCard(relationships: content.relationships, selectedID: $model.selectedRelationshipID)

            SectionHeader(title: "Vitals")
                .padding(.top, Spacing.s)
            GlassEffectContainer(spacing: Spacing.m) {
                VStack(spacing: Spacing.m) {
                    ForEach(Metric.vitals) { metric in
                        TrendCard(series: model.series(for: metric, in: content))
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.xxl)
    }
}

// MARK: - Summary

/// The three scores for the period at a glance.
private struct SummaryRow: View {
    let series: [TrendsViewModel.Series]
    @Environment(\.metricFormatter) private var format

    var body: some View {
        GlassEffectContainer(spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                ForEach(series) { item in
                    MetricCard(
                        label: item.metric.title,
                        value: format.value(item.average, for: item.metric),
                        unit: format.unit(for: item.metric),
                        delta: format.delta(item.change, for: item.metric),
                        detail: "average",
                        trend: item.points.map(\.value),
                        tint: item.metric.tint(for: item.average)
                    )
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Per-metric chart

private struct TrendCard: View {
    let series: TrendsViewModel.Series
    @Environment(\.metricFormatter) private var format

    private var metric: Metric { series.metric }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardHeader(title: metric.title, tint: metric.isScore ? metric.tint(for: series.average) : nil)
                StatGrid(columns: 4) {
                    StatTile(label: "Avg", value: format.value(series.average, for: metric), unit: format.unit(for: metric))
                    StatTile(label: "Low", value: format.value(series.lowest, for: metric))
                    StatTile(label: "High", value: format.value(series.highest, for: metric))
                    StatTile(label: "Change", value: signed(format.delta(series.change, for: metric)))
                }
                TrendChart(
                    points: series.points.map { DatedValue(date: $0.date, value: format.convert($0.value, for: metric)) },
                    mark: metric.isScore ? .bars : .line,
                    tint: metric.tint,
                    barColor: metric == .recovery ? { Metric.recovery.tint(for: $0) } : nil,
                    reference: format.convert(series.average, for: metric),
                    yDomain: metric.isScore ? 0...100 : nil,
                    formatValue: { $0.formatted(.number.precision(.fractionLength(format.fractionDigits(for: metric)))) },
                    height: Size.compactChartHeight + 20
                )
            }
        }
    }

    private func signed(_ delta: FormattedDelta) -> String {
        switch delta.direction {
        case .up: "+\(delta.text)"
        case .down: "−\(delta.text)"
        case .flat: delta.text
        }
    }
}

// MARK: - Zone mix

private struct ZoneMixCard: View {
    let distribution: [RecoveryZone: Int]
    let period: TrendPeriod
    @Environment(\.metricFormatter) private var format

    private var total: Int { max(distribution.values.reduce(0, +), 1) }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardHeader(title: "Recovery zones", detail: "Last \(period.days) days")
                StatGrid {
                    ForEach([RecoveryZone.high, .moderate, .low], id: \.self) { zone in
                        StatTile(
                            label: zone.title,
                            value: format.percent(Double(distribution[zone] ?? 0) / Double(total)),
                            detail: "\(distribution[zone] ?? 0) days"
                        )
                    }
                }
                ZoneDistribution(distribution: distribution)
            }
        }
    }
}

// MARK: - Weekday patterns

private struct WeekdayCard: View {
    let recovery: [Insights.WeekdayAverage]
    let strain: [Insights.WeekdayAverage]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardHeader(title: "By weekday", detail: "Average")
                Text("Recovery").textStyle(.caption)
                WeekdayChart(averages: recovery, color: { Metric.recovery.tint(for: $0) })
                Text("Strain").textStyle(.caption)
                WeekdayChart(averages: strain, color: { _ in CorvaColor.strain })
            }
        }
    }
}

/// Seven bars, one per weekday, with the mean above and the day name below each. Labels are
/// annotations on the bars themselves so they always sit centred under them.
private struct WeekdayChart: View {
    let averages: [Insights.WeekdayAverage]
    let color: (Double) -> Color

    var body: some View {
        Chart(averages) { average in
            BarMark(
                x: .value("Weekday", Double(average.position)),
                y: .value("Average", average.mean),
                width: .fixed(26)
            )
            .foregroundStyle(color(average.mean))
            .cornerRadius(4)
            .annotation(position: .top, spacing: 3) {
                Text(average.mean, format: .number.precision(.fractionLength(0)))
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(CorvaColor.textSecondary)
            }
            .annotation(position: .bottom, spacing: 4) {
                Text(average.shortName)
                    .font(.caption2)
                    .foregroundStyle(CorvaColor.textTertiary)
            }
        }
        .chartXScale(domain: -0.5...6.5)
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 110)
        .padding(.bottom, Spacing.s)
    }
}

// MARK: - Relationships

private struct RelationshipsCard: View {
    let relationships: [Insights.Relationship]
    @Binding var selectedID: String

    private var selected: Insights.Relationship? {
        relationships.first { $0.id == selectedID } ?? relationships.first
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardHeader(title: "Relationships", detail: "Tap to plot")
                if let selected {
                    Text(selected.title)
                        .font(.headline)
                        .foregroundStyle(CorvaColor.textPrimary)
                    RelationshipSummary(relationship: selected)
                    ScatterChart(
                        points: selected.pairs.map { .init(id: $0.id, x: $0.x, y: $0.y) },
                        xTitle: selected.x.title,
                        yTitle: selected.y.title,
                        tint: selected.x.isScore ? selected.x.tint : CorvaColor.neutralData,
                        fit: selected.fit.map { ($0.slope, $0.intercept) }
                    )
                }
                VStack(spacing: 0) {
                    ForEach(Array(relationships.enumerated()), id: \.element.id) { index, relationship in
                        if index > 0 { CardDivider() }
                        Button {
                            selectedID = relationship.id
                        } label: {
                            RelationshipRow(relationship: relationship, isSelected: relationship.id == selected?.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedID)
    }
}

private struct RelationshipRow: View {
    let relationship: Insights.Relationship
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(relationship.title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? CorvaColor.textPrimary : CorvaColor.textSecondary)
                Text(relationship.strength.rawValue)
                    .font(.caption)
                    .foregroundStyle(CorvaColor.textTertiary)
            }
            Spacer(minLength: Spacing.s)
            CorrelationBar(r: relationship.r)
                .frame(width: 64)
            Text((relationship.r < 0 ? "−" : "+") + abs(relationship.r).formatted(.number.precision(.fractionLength(2))))
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(CorvaColor.textPrimary)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, Spacing.s)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// r from −1 to 1 as a bar growing left or right from a centre line.
private struct CorrelationBar: View {
    let r: Double

    var body: some View {
        GeometryReader { proxy in
            let half = proxy.size.width / 2
            let length = half * CGFloat(min(abs(r), 1))
            ZStack(alignment: .leading) {
                Capsule().fill(CorvaColor.ringTrack)
                Capsule()
                    .fill(CorvaColor.neutralData)
                    .frame(width: length)
                    .offset(x: r >= 0 ? half : half - length)
                Rectangle()
                    .fill(CorvaColor.textTertiary)
                    .frame(width: 1)
                    .offset(x: half)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

#Preview {
    TrendsView()
        .corvaPreview()
}
