import Charts
import SwiftUI

/// Bars and a line sharing one day axis and one scale: e.g. recovery bars with the strain that
/// followed, or hours asleep against hours needed.
struct ComboChart: View {
    let bars: [DatedValue]
    let line: [DatedValue]
    var barColor: (Double) -> Color
    var lineColor: Color
    var yDomain: ClosedRange<Double> = 0...100
    var formatValue: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0))) }
    var height: CGFloat = Size.chartHeight

    var body: some View {
        Chart {
            ForEach(bars) { point in
                BarMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Bar", point.value),
                    width: .ratio(0.55)
                )
                .foregroundStyle(barColor(point.value))
                .cornerRadius(3)
            }
            ForEach(line) { point in
                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Line", point.value)
                )
                .foregroundStyle(lineColor)
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                PointMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Line", point.value)
                )
                .foregroundStyle(lineColor)
                .symbolSize(26)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: bars.count > 7 ? 3 : 1)) { _ in
                AxisValueLabel(
                    format: bars.count > 7 ? .dateTime.day() : .dateTime.weekday(.abbreviated),
                    centered: true
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
        .chartYScale(domain: yDomain)
        .chartLegend(.hidden)
        .frame(height: height)
    }
}

#Preview("Combo chart") {
    let week = DailySummary.previewWeek
    GlassCard {
        VStack(alignment: .leading, spacing: Spacing.s) {
            ComboChart(
                bars: Metric.recovery.series(in: week),
                line: Metric.strain.series(in: week),
                barColor: { Metric.recovery.tint(for: $0).opacity(0.85) },
                lineColor: CorvaColor.strain
            )
            ChartLegend(items: [
                .init(label: "Recovery", color: CorvaColor.recoveryHigh),
                .init(label: "Strain", color: CorvaColor.strain),
            ])
        }
    }
    .padding(Spacing.screen)
    .corvaPreview()
}
