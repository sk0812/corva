import Charts
import SwiftUI

/// Paired values as dots with their least-squares line: how one metric moves with another.
struct ScatterChart: View {
    struct Point: Identifiable {
        let id: Int
        let x: Double
        let y: Double
    }

    let points: [Point]
    var xTitle: String
    var yTitle: String
    var tint: Color = CorvaColor.neutralData
    /// Least-squares line, as `y = intercept + slope · x`.
    var fit: (slope: Double, intercept: Double)?
    var height: CGFloat = Size.chartHeight

    var body: some View {
        Chart {
            ForEach(points) { point in
                PointMark(
                    x: .value(xTitle, point.x),
                    y: .value(yTitle, point.y)
                )
                .foregroundStyle(tint.opacity(0.55))
                .symbolSize(22)
            }
            if let fit, let low = points.map(\.x).min(), let high = points.map(\.x).max() {
                LineMark(x: .value(xTitle, low), y: .value(yTitle, fit.intercept + fit.slope * low), series: .value("Fit", "fit"))
                    .foregroundStyle(CorvaColor.textPrimary)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                LineMark(x: .value(xTitle, high), y: .value(yTitle, fit.intercept + fit.slope * high), series: .value("Fit", "fit"))
                    .foregroundStyle(CorvaColor.textPrimary)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .chartXScale(domain: .automatic(includesZero: false))
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxisLabel(xTitle, alignment: .center)
        .chartYAxisLabel(yTitle, position: .leading)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(CorvaColor.chartGrid)
                AxisValueLabel(anchor: .top).foregroundStyle(CorvaColor.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(CorvaColor.chartGrid)
                AxisValueLabel().foregroundStyle(CorvaColor.textTertiary)
            }
        }
        .frame(height: height)
    }
}

#Preview("Scatter chart") {
    let relationship = Insights.relationships(in: MockHealthDataProvider.preview.days)[0]
    GlassCard {
        ScatterChart(
            points: relationship.pairs.map { ScatterChart.Point(id: $0.id, x: $0.x, y: $0.y) },
            xTitle: "Strain",
            yTitle: "Next-day recovery",
            tint: CorvaColor.strain,
            fit: relationship.fit.map { ($0.slope, $0.intercept) }
        )
    }
    .padding(Spacing.screen)
    .corvaPreview()
}
