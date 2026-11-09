import SwiftUI

struct RecoveryDetailView: View {
    @Environment(\.healthDataProvider) private var provider
    @Environment(\.dataVersion) private var dataVersion
    @Environment(\.metricFormatter) private var format
    @State private var model: RecoveryDetailViewModel

    init(date: Date) {
        _model = State(initialValue: RecoveryDetailViewModel(date: date))
    }

    var body: some View {
        LoadStateView(model.state) { content in
            ScrollView {
                RecoveryDetailContent(content: content)
            }
        }
        .screenBackground(glow: glow)
        .navigationTitle(Metric.recovery.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationSubtitle(format.dayTitle(model.date))
        .task(id: dataVersion) { await model.load(using: provider) }
    }

    private var glow: Color? {
        guard case .loaded(let content) = model.state else { return nil }
        return content.day.recovery.zone.color
    }
}

private struct RecoveryDetailContent: View {
    let content: RecoveryDetailViewModel.Content
    @Environment(\.metricFormatter) private var format

    var body: some View {
        VStack(spacing: Spacing.m) {
            VStack(spacing: Spacing.m) {
                ScoreRing(
                    score: content.day.recovery.score,
                    label: content.day.recovery.zone.title,
                    unit: format.unit(for: .recovery),
                    tint: content.day.recovery.zone.color
                )
                if let delta = content.day.baseline.delta(for: .recovery, in: content.day) {
                    DeltaLabel(delta: format.delta(delta, for: .recovery), suffix: "vs 30-day avg")
                }
            }
            .padding(.vertical, Spacing.m)

            contributors
            lastThirtyDays
            vitalCard(.hrv)
            vitalCard(.restingHeartRate)
            relationship
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.xxl)
    }

    private var contributors: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                CardHeader(title: "Contributors", detail: "vs 30-day baseline")
                VStack(spacing: 0) {
                    ForEach(Array(content.contributors.enumerated()), id: \.element.id) { index, contributor in
                        if index > 0 { CardDivider() }
                        ContributorRow(contributor: contributor, sleep: content.day.sleep)
                    }
                }
            }
        }
    }

    private var lastThirtyDays: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardHeader(title: "Last 30 days", detail: "Drag to inspect")
                StatGrid {
                    StatTile(label: "Average", value: format.value(content.average, for: .recovery), unit: "%")
                    StatTile(label: "Best", value: "\(content.best)", unit: "%")
                    StatTile(label: "Lowest", value: "\(content.lowest)", unit: "%")
                }
                TrendChart(
                    points: Metric.recovery.series(in: content.history),
                    mark: .bars,
                    barColor: { Metric.recovery.tint(for: $0) },
                    reference: content.baselineScore,
                    yDomain: 0...100,
                    formatValue: { format.valueWithUnit($0, for: .recovery) }
                )
                ZoneDistribution(distribution: content.distribution)
            }
        }
    }

    private func vitalCard(_ metric: Metric) -> some View {
        let baseline = content.day.baseline[metric]
        return GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                CardHeader(
                    title: metric.title,
                    detail: baseline.map { stat in
                        "Typical \(format.value(stat.typicalRange.lowerBound, for: metric))–\(format.valueWithUnit(stat.typicalRange.upperBound, for: metric))"
                    }
                )
                TrendChart(
                    points: metric.series(in: content.history),
                    reference: baseline?.mean,
                    band: baseline?.typicalRange,
                    formatValue: { format.value($0, for: metric) },
                    height: Size.compactChartHeight
                )
            }
        }
    }

    private var relationship: some View {
        let relationship = content.strainRelationship
        return GlassCard {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardHeader(title: relationship.title, detail: "\(relationship.pairs.count) days")
                RelationshipSummary(relationship: relationship)
                ScatterChart(
                    points: relationship.pairs.map { .init(id: $0.id, x: $0.x, y: $0.y) },
                    xTitle: "Strain",
                    yTitle: "Next-day recovery",
                    tint: CorvaColor.strain,
                    fit: relationship.fit.map { ($0.slope, $0.intercept) }
                )
            }
        }
    }
}

private struct ContributorRow: View {
    let contributor: RecoveryDetailViewModel.Contributor
    let sleep: SleepMetrics
    @Environment(\.metricFormatter) private var format

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            StatRow(
                title: contributor.metric == .sleep ? "Sleep performance" : contributor.metric.title,
                value: format.value(contributor.value, for: contributor.metric),
                unit: format.unit(for: contributor.metric),
                detail: detail,
                delta: contributor.delta.map { format.delta($0, for: contributor.metric) }
            )
            HStack(spacing: Spacing.s) {
                ProgressBar(
                    fraction: contributor.subScore / 100,
                    tint: RecoveryZone(score: Int(contributor.subScore.rounded())).color,
                    height: 6
                )
                Text("\(Int(contributor.subScore.rounded())) × \(format.percent(contributor.weight))")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(CorvaColor.textTertiary)
                    .frame(width: 64, alignment: .trailing)
            }
            .padding(.bottom, Spacing.xs)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sub-score \(Int(contributor.subScore.rounded())), weighted \(format.percent(contributor.weight))")
        }
    }

    private var detail: String {
        if contributor.metric == .sleep {
            return "\(format.duration(sleep.timeAsleep)) of \(format.duration(sleep.need)) needed"
        }
        guard let baseline = contributor.baseline else { return "" }
        return "Baseline \(format.valueWithUnit(baseline, for: contributor.metric))"
    }
}

/// Days per recovery zone as one bar with counts.
struct ZoneDistribution: View {
    let distribution: [RecoveryZone: Int]

    private var total: Int { distribution.values.reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SegmentedBar(segments: [RecoveryZone.high, .moderate, .low].map {
                .init(id: $0.rawValue, value: Double(distribution[$0] ?? 0), color: $0.color)
            })
            HStack(spacing: Spacing.m) {
                ForEach([RecoveryZone.high, .moderate, .low], id: \.self) { zone in
                    HStack(spacing: Spacing.xxs) {
                        Circle().fill(zone.color).frame(width: 7, height: 7)
                        Text("\(distribution[zone] ?? 0) \(zone.title.lowercased())")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(CorvaColor.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                Text("\(total) days")
                    .font(.caption)
                    .foregroundStyle(CorvaColor.textTertiary)
            }
        }
    }
}

/// Correlation, strength and the fitted slope in plain numbers.
struct RelationshipSummary: View {
    let relationship: Insights.Relationship
    @Environment(\.metricFormatter) private var format

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Correlation").textStyle(.label)
                Text(relationship.strength == .notEnoughData ? "—" : signedR(relationship.r))
                    .textStyle(.numeral)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(relationship.strength.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CorvaColor.textPrimary)
                if relationship.strength == .notEnoughData {
                    Text("\(relationship.pairs.count) days so far")
                        .font(.caption)
                        .foregroundStyle(CorvaColor.textSecondary)
                } else if let slope = relationship.fit?.slope {
                    Text(slopeText(slope))
                        .font(.caption)
                        .foregroundStyle(CorvaColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func signedR(_ r: Double) -> String {
        let magnitude = abs(r).formatted(.number.precision(.fractionLength(2)))
        return r < 0 ? "−\(magnitude)" : "+\(magnitude)"
    }

    private func slopeText(_ slope: Double) -> String {
        let step = relationship.x.isScore ? 10.0 : 5.0
        let change = format.delta(slope * step, for: relationship.y)
        let sign = change.direction == .down ? "−" : (change.direction == .up ? "+" : "±")
        let xStep = format.valueWithUnit(step, for: relationship.x)
        return "Each +\(xStep) \(relationship.x.title.lowercased()) ≈ \(sign)\(change.text) \(relationship.y.title.lowercased())"
    }
}

#Preview {
    NavigationStack {
        RecoveryDetailView(date: DailySummary.preview.date)
    }
    .corvaPreview()
}
