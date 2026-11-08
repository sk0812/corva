import SwiftUI

struct StrainDetailView: View {
    @Environment(\.healthDataProvider) private var provider
    @Environment(\.metricFormatter) private var format
    @State private var model: StrainDetailViewModel

    init(date: Date) {
        _model = State(initialValue: StrainDetailViewModel(date: date))
    }

    var body: some View {
        LoadStateView(model.state) { content in
            ScrollView {
                StrainDetailContent(content: content)
            }
        }
        .screenBackground(glow: CorvaColor.strain)
        .navigationTitle(Metric.strain.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationSubtitle(format.dayTitle(model.date))
        .task { await model.load(using: provider) }
    }
}

private struct StrainDetailContent: View {
    let content: StrainDetailViewModel.Content
    @Environment(\.metricFormatter) private var format

    private var strain: StrainMetrics { content.strain }

    var body: some View {
        VStack(spacing: Spacing.m) {
            VStack(spacing: Spacing.m) {
                ScoreRing(score: strain.score, label: "Day strain", tint: CorvaColor.strain)
                if let delta = content.delta {
                    DeltaLabel(delta: format.delta(delta, for: .strain), suffix: "vs 30-day avg")
                }
            }
            .padding(.vertical, Spacing.m)

            target
            stats
            zones
            trainingLoad
            fortnight
            activities
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.xxl)
    }

    private var target: some View {
        GlassCard(tint: CorvaColor.strain) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardHeader(title: "Target", tint: CorvaColor.strain, detail: "From \(content.day.recovery.score)% recovery")
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text("\(content.target.lowerBound)–\(content.target.upperBound)").textStyle(.numeral)
                    Text("recommended range").textStyle(.caption)
                }
                TargetBar(
                    value: Double(strain.score),
                    target: Double(content.target.lowerBound)...Double(content.target.upperBound),
                    tint: CorvaColor.strain
                )
                HStack {
                    Text("0")
                    Spacer()
                    Text("50")
                    Spacer()
                    Text("100")
                }
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(CorvaColor.textTertiary)
            }
        }
    }

    private var stats: some View {
        GlassCard {
            StatGrid {
                StatTile(label: "Active", value: format.value(strain.activeEnergy, for: .strain), unit: "kcal")
                StatTile(label: "Steps", value: format.steps(strain.steps))
                StatTile(label: "Activities", value: "\(strain.activities.count)")
                StatTile(label: "Avg HR", value: "\(strain.averageHeartRate)", unit: "bpm")
                StatTile(label: "Max HR", value: "\(strain.maxHeartRate)", unit: "bpm")
                StatTile(label: "Zone 3+", value: format.duration(content.hardZoneTime))
            }
        }
    }

    private var zones: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardHeader(title: "Heart rate zones", detail: "\(format.duration(content.totalZoneTime)) total")
                HeartRateZoneBars(zones: strain.heartRateZones)
            }
        }
    }

    @ViewBuilder
    private var trainingLoad: some View {
        if let load = content.trainingLoad {
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    CardHeader(title: "Training load", detail: "7 vs 28 days")
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                        Text(format.ratio(load.ratio)).textStyle(.numeral)
                        Text(load.status.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(load.status == .balanced ? CorvaColor.textPrimary : CorvaColor.alert)
                        Spacer(minLength: 0)
                    }
                    RangeBar(value: load.ratio, typicalRange: Insights.TrainingLoad.balancedRange)
                    StatGrid {
                        StatTile(label: "Load · 7d", value: format.value(load.acute, for: .strain), detail: "per day")
                        StatTile(label: "Load · 28d", value: format.value(load.chronic, for: .strain), detail: "per day")
                        StatTile(label: "Balanced", value: "0.8–1.3", detail: "ratio")
                    }
                    TrendChart(
                        points: Metric.strain.series(in: content.history),
                        mark: .bars,
                        tint: CorvaColor.strain,
                        reference: content.averageStrain,
                        yDomain: 0...100,
                        height: Size.compactChartHeight
                    )
                }
            }
        }
    }

    private var fortnight: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardHeader(title: "Strain vs recovery", detail: "14 days")
                ComboChart(
                    bars: Metric.recovery.series(in: content.fortnight),
                    line: Metric.strain.series(in: content.fortnight),
                    barColor: { Metric.recovery.tint(for: $0).opacity(0.8) },
                    lineColor: CorvaColor.strain
                )
                ChartLegend(items: [
                    .init(label: "Recovery", color: CorvaColor.recoveryHigh),
                    .init(label: "Strain", color: CorvaColor.strain),
                ])
            }
        }
    }

    private var activities: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                CardHeader(title: "Activities", detail: "\(format.energy(strain.activeEnergy)) active")
                if strain.activities.isEmpty {
                    Text("No activities recorded")
                        .textStyle(.bodySecondary)
                        .padding(.vertical, Spacing.xs)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(strain.activities.enumerated()), id: \.element.id) { index, activity in
                            if index > 0 { CardDivider() }
                            ActivityRow(activity: activity)
                        }
                    }
                }
            }
        }
    }
}

/// Time in each zone as horizontal bars, hardest zone on top, scaled to the longest zone.
private struct HeartRateZoneBars: View {
    let zones: [ZoneDuration]
    @Environment(\.metricFormatter) private var format

    var body: some View {
        VStack(spacing: Spacing.s) {
            ForEach(zones.sorted { $0.zone > $1.zone }) { zone in
                HStack(spacing: Spacing.s) {
                    Text(zone.zone.title)
                        .font(.caption)
                        .foregroundStyle(CorvaColor.textSecondary)
                        .frame(width: 52, alignment: .leading)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(CorvaColor.ringTrack)
                            Capsule()
                                .fill(zone.zone.color)
                                .frame(width: proxy.size.width * share(of: zone))
                                .shadow(color: zone.zone.color.opacity(0.5), radius: 4)
                        }
                    }
                    .frame(height: 10)
                    Text(format.duration(zone.duration))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(CorvaColor.textSecondary)
                        .frame(width: 52, alignment: .trailing)
                    Text(format.percent(fraction(of: zone)))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(CorvaColor.textTertiary)
                        .frame(width: 36, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(zone.zone.title), \(format.duration(zone.duration))")
            }
        }
        .padding(.vertical, Spacing.xxs)
    }

    private func share(of zone: ZoneDuration) -> Double {
        let longest = zones.map(\.duration).max() ?? 0
        return longest > 0 ? zone.duration / longest : 0
    }

    private func fraction(of zone: ZoneDuration) -> Double {
        let total = zones.reduce(0) { $0 + $1.duration }
        return total > 0 ? zone.duration / total : 0
    }
}

#Preview {
    NavigationStack {
        StrainDetailView(date: DailySummary.preview.date)
    }
    .corvaPreview()
}
