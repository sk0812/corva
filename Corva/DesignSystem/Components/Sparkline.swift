import Charts
import SwiftUI

/// A tiny axis-free line showing the shape of recent values, with the latest one marked.
struct Sparkline: View {
    let values: [Double]
    var tint: Color = CorvaColor.neutralData

    var body: some View {
        if values.count > 1 {
            Chart {
                ForEach(Array(values.enumerated()), id: \.offset) { item in
                    LineMark(
                        x: .value("Day", item.offset),
                        y: .value("Value", item.element)
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                if let last = values.last {
                    PointMark(
                        x: .value("Day", values.count - 1),
                        y: .value("Value", last)
                    )
                    .symbolSize(30)
                }
            }
            .foregroundStyle(tint)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartXScale(domain: 0...(values.count - 1))
            .chartYScale(domain: domain)
            .padding(.horizontal, 3)
            .accessibilityHidden(true)
        }
    }

    private var domain: ClosedRange<Double> {
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let padding = max((high - low) * 0.15, 0.5)
        return (low - padding)...(high + padding)
    }
}

#Preview("Sparkline") {
    VStack(spacing: Spacing.l) {
        Sparkline(values: [52, 61, 48, 70, 66, 74, 59], tint: CorvaColor.strain)
            .frame(height: Size.sparklineHeight)
        Sparkline(values: DailySummary.previewWeek.map { Double($0.sleep.score) }, tint: CorvaColor.sleep)
            .frame(height: Size.sparklineHeight)
    }
    .padding(Spacing.screen)
    .corvaPreview()
}
