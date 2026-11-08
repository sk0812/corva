import Charts
import SwiftUI

/// Daily values over time, as bars (scores) or a line (vitals), with optional baseline
/// reference and typical-range band.
///
/// Drag across the chart to scrub: the nearest day is highlighted and its value appears in a
/// glass bubble.
struct TrendChart: View {
    enum Mark {
        case bars
        case line
    }

    let points: [DatedValue]
    var mark: Mark = .line
    var tint: Color = CorvaColor.neutralData
    /// Per-value bar colour (e.g. recovery zones). Falls back to `tint`.
    var barColor: ((Double) -> Color)?
    /// Dashed horizontal reference, e.g. the baseline or period average.
    var reference: Double?
    /// Shaded typical range behind the data.
    var band: ClosedRange<Double>?
    /// Fixed y domain, e.g. 0...100 for scores. Fitted to the data when nil.
    var yDomain: ClosedRange<Double>?
    /// Formats y-axis labels and the scrub bubble.
    var formatValue: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0))) }
    var height: CGFloat = Size.chartHeight

    @State private var selectedDate: Date?

    var body: some View {
        Chart {
            if let band, let first = points.first, let last = points.last {
                RectangleMark(
                    xStart: .value("Start", first.date),
                    xEnd: .value("End", last.date),
                    yStart: .value("Typical low", band.lowerBound),
                    yEnd: .value("Typical high", band.upperBound)
                )
                .foregroundStyle(CorvaColor.chartBand)
            }

            ForEach(points) { point in
                if mark == .bars {
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(barColor?(point.value) ?? tint)
                    .opacity(isDimmed(point) ? 0.35 : 1)
                    .cornerRadius(3)
                } else {
                    AreaMark(
                        x: .value("Day", point.date),
                        yStart: .value("Floor", resolvedDomain.lowerBound),
                        yEnd: .value("Value", point.value)
                    )
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(band == nil ? 0.26 : 0.14), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Day", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(tint)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    if isShortRange || point.id == points.last?.id {
                        PointMark(
                            x: .value("Day", point.date),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(tint)
                        .symbolSize(28)
                    }
                }
            }

            if let reference {
                RuleMark(y: .value("Reference", reference))
                    .foregroundStyle(CorvaColor.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            if let selected = selectedPoint {
                RuleMark(x: .value("Selected", selected.date, unit: .day))
                    .foregroundStyle(CorvaColor.textSecondary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(
                        position: .top,
                        spacing: 0,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        ScrubBubble(value: formatValue(selected.value), date: selected.date)
                    }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: isShortRange ? points.count : 4)) { _ in
                AxisValueLabel(
                    format: isShortRange ? .dateTime.weekday(.abbreviated) : .dateTime.month(.abbreviated).day(),
                    centered: mark == .bars
                )
                .foregroundStyle(CorvaColor.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                    .foregroundStyle(CorvaColor.chartGrid)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(formatValue(number))
                    }
                }
                .foregroundStyle(CorvaColor.textTertiary)
            }
        }
        .chartYScale(domain: resolvedDomain)
        .chartLegend(.hidden)
        .frame(height: height)
    }

    private var isShortRange: Bool { points.count <= 7 }

    private var selectedPoint: DatedValue? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    private func isDimmed(_ point: DatedValue) -> Bool {
        guard let selectedPoint else { return false }
        return selectedPoint.id != point.id
    }

    private var resolvedDomain: ClosedRange<Double> {
        if let yDomain { return yDomain }
        var values = points.map(\.value)
        if let band { values += [band.lowerBound, band.upperBound] }
        if let reference { values.append(reference) }
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let span = high - low
        let padding = span > 0 ? span * 0.15 : max(abs(high) * 0.05, 1)
        return (low - padding)...(high + padding)
    }
}

/// The value-and-date readout that floats over a chart while scrubbing.
struct ScrubBubble: View {
    let value: String
    let date: Date

    var body: some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(CorvaColor.textPrimary)
            Text(date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                .font(.caption2)
                .foregroundStyle(CorvaColor.textSecondary)
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xxs + 2)
        .glassEffect(.regular, in: .capsule)
    }
}

#Preview("Trend charts") {
    let days = Array(MockHealthDataProvider.preview.days.suffix(30))
    let today = DailySummary.preview
    ScrollView {
        VStack(spacing: Spacing.m) {
            GlassCard {
                TrendChart(
                    points: Metric.recovery.series(in: days),
                    mark: .bars,
                    barColor: { Metric.recovery.tint(for: $0) },
                    reference: today.baseline[.recovery]?.mean,
                    yDomain: 0...100
                )
            }
            GlassCard {
                TrendChart(
                    points: Metric.hrv.series(in: days),
                    reference: today.baseline[.hrv]?.mean,
                    band: today.baseline[.hrv]?.typicalRange
                )
            }
            GlassCard {
                TrendChart(
                    points: Metric.strain.series(in: Array(days.suffix(7))),
                    mark: .bars,
                    tint: CorvaColor.strain,
                    yDomain: 0...100
                )
            }
        }
        .padding(Spacing.screen)
    }
    .corvaPreview()
}
