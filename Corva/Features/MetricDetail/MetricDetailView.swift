import SwiftUI

struct MetricDetailView: View {
    @Environment(\.healthDataProvider) private var provider
    @Environment(\.dataVersion) private var dataVersion
    @Environment(\.metricFormatter) private var format
    @State private var model: MetricDetailViewModel

    init(metric: Metric, date: Date) {
        _model = State(initialValue: MetricDetailViewModel(metric: metric, date: date))
    }

    var body: some View {
        LoadStateView(model.state) { content in
            ScrollView {
                MetricDetailContent(content: content)
            }
        }
        .screenBackground(glow: glow)
        .navigationTitle(model.metric.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationSubtitle(format.dayTitle(model.date))
        .task(id: dataVersion) { await model.load(using: provider) }
    }

    /// Neutral for a normal reading, the alert colour when today is outside the typical range.
    private var glow: Color? {
        guard case .loaded(let content) = model.state else { return nil }
        return content.isInTypicalRange ? CorvaColor.neutralData.opacity(0.6) : CorvaColor.alert
    }
}

private struct MetricDetailContent: View {
    let content: MetricDetailViewModel.Content
    @Environment(\.metricFormatter) private var format

    private var metric: Metric { content.metric }
    private var unit: String { format.unit(for: metric) }

    var body: some View {
        VStack(spacing: Spacing.m) {
            VStack(spacing: Spacing.s) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                    Text(format.value(content.value, for: metric)).textStyle(.largeNumeral)
                    Text(unit).textStyle(.unit)
                }
                if let delta = content.delta {
                    DeltaLabel(delta: format.delta(delta, for: metric), suffix: "vs 30-day baseline")
                }
                Text(content.isInTypicalRange ? "Within typical range" : "Outside typical range")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(content.isInTypicalRange ? CorvaColor.textSecondary : CorvaColor.alert)
                    .padding(.horizontal, Spacing.s)
                    .padding(.vertical, Spacing.xxs + 2)
                    .glassEffect(.regular.tint(content.isInTypicalRange ? nil : CorvaColor.alert.opacity(0.2)), in: .capsule)
                    .padding(.top, Spacing.xxs)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.l)
            .accessibilityElement(children: .combine)

            if let baseline = content.baseline {
                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        CardHeader(title: "Today vs typical range")
                        RangeBar(value: content.value, typicalRange: baseline.typicalRange)
                        HStack {
                            Text(format.valueWithUnit(baseline.typicalRange.lowerBound, for: metric))
                            Spacer()
                            Text("Baseline \(format.valueWithUnit(baseline.mean, for: metric))")
                            Spacer()
                            Text(format.valueWithUnit(baseline.typicalRange.upperBound, for: metric))
                        }
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(CorvaColor.textTertiary)
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    CardHeader(title: "Last 30 days", detail: "Drag to inspect")
                    TrendChart(
                        points: content.points.map { DatedValue(date: $0.date, value: format.convert($0.value, for: metric)) },
                        tint: metric.tint,
                        reference: content.baseline.map { format.convert($0.mean, for: metric) },
                        band: content.baseline.map { stat in
                            format.convert(stat.typicalRange.lowerBound, for: metric)...format.convert(stat.typicalRange.upperBound, for: metric)
                        },
                        formatValue: { $0.formatted(.number.precision(.fractionLength(format.fractionDigits(for: metric)))) },
                        height: Size.chartHeight + 30
                    )
                    Text("The band is your typical range: mean ± 1.5 standard deviations of the previous 30 days. About seven days in eight fall inside it.")
                        .font(.caption)
                        .foregroundStyle(CorvaColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            GlassCard {
                StatGrid {
                    StatTile(label: "30-day avg", value: format.value(content.average, for: metric), unit: unit)
                    StatTile(label: "Lowest", value: format.value(content.lowest ?? 0, for: metric), unit: unit)
                    StatTile(label: "Highest", value: format.value(content.highest ?? 0, for: metric), unit: unit)
                    StatTile(
                        label: "7d vs 30d",
                        value: format.value(abs(content.weekVersusMonth), for: metric),
                        unit: unit,
                        delta: format.delta(content.weekVersusMonth, for: metric)
                    )
                    StatTile(label: "Outside range", value: "\(content.daysOutsideRange)", detail: "of \(content.history.count) days")
                    if let baseline = content.baseline {
                        StatTile(label: "Spread", value: format.value(baseline.standardDeviation, for: metric), unit: unit, detail: "1 SD")
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.xxl)
    }
}

#Preview {
    NavigationStack {
        MetricDetailView(metric: .hrv, date: DailySummary.preview.date)
    }
    .corvaPreview()
}
