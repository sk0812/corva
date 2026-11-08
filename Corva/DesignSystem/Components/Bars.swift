import SwiftUI

/// Where a value sits relative to its typical range: track, shaded range, and a dot that
/// turns to the alert colour when the value falls outside the range.
struct RangeBar: View {
    let value: Double
    let typicalRange: ClosedRange<Double>

    private var isOutside: Bool { !typicalRange.contains(value) }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let low = position(of: typicalRange.lowerBound, width: width)
            let high = position(of: typicalRange.upperBound, width: width)
            let dot = position(of: value, width: width)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(CorvaColor.ringTrack)
                    .frame(height: 6)
                Capsule()
                    .fill(CorvaColor.neutralData.opacity(0.3))
                    .frame(width: max(high - low, 6), height: 6)
                    .offset(x: low)
                Circle()
                    .fill(isOutside ? CorvaColor.alert : CorvaColor.textPrimary)
                    .frame(width: 12, height: 12)
                    .shadow(color: (isOutside ? CorvaColor.alert : CorvaColor.textPrimary).opacity(0.6), radius: 4)
                    .offset(x: min(max(dot - 6, 0), width - 12))
            }
            .frame(height: proxy.size.height)
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }

    /// The range sits in the middle 50% of the track, extended if the value falls far outside.
    private var domain: ClosedRange<Double> {
        let span = max(typicalRange.upperBound - typicalRange.lowerBound, 0.0001)
        let low = min(typicalRange.lowerBound - span / 2, value - span * 0.1)
        let high = max(typicalRange.upperBound + span / 2, value + span * 0.1)
        return low...high
    }

    private func position(of value: Double, width: CGFloat) -> CGFloat {
        let domain = self.domain
        let fraction = (value - domain.lowerBound) / (domain.upperBound - domain.lowerBound)
        return CGFloat(min(max(fraction, 0), 1)) * width
    }
}

/// Progress towards a target range on a 0-100 scale: the filled bar is the current value and
/// the outlined capsule is the target.
struct TargetBar: View {
    let value: Double
    let target: ClosedRange<Double>
    let tint: Color
    var domain: ClosedRange<Double> = 0...100

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fill = position(of: value, width: width)
            let start = position(of: target.lowerBound, width: width)
            let end = position(of: target.upperBound, width: width)
            ZStack(alignment: .leading) {
                Capsule().fill(CorvaColor.ringTrack)
                Capsule()
                    .fill(tint.opacity(0.16))
                    .frame(width: end - start)
                    .offset(x: start)
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.5), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(fill, 12))
                    .shadow(color: tint.opacity(0.5), radius: 6)
                Capsule()
                    .strokeBorder(tint, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .frame(width: end - start)
                    .offset(x: start)
            }
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }

    private func position(of value: Double, width: CGFloat) -> CGFloat {
        let fraction = (value - domain.lowerBound) / (domain.upperBound - domain.lowerBound)
        return CGFloat(min(max(fraction, 0), 1)) * width
    }
}

/// A simple share-of-whole bar, e.g. time asleep against need.
struct ProgressBar: View {
    let fraction: Double
    let tint: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(CorvaColor.ringTrack)
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.55), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                    .shadow(color: tint.opacity(0.5), radius: 5)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Proportions of a whole as one horizontal bar, e.g. sleep stages or time in zones.
struct SegmentedBar: View {
    struct Segment: Identifiable {
        let id: String
        let value: Double
        let color: Color
    }

    let segments: [Segment]
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            let visible = segments.filter { $0.value > 0 }
            let total = visible.reduce(0) { $0 + $1.value }
            let gaps = CGFloat(max(visible.count - 1, 0)) * 2
            HStack(spacing: 2) {
                ForEach(visible) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: total > 0 ? max((proxy.size.width - gaps) * segment.value / total, 0) : 0)
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

/// A row of small colour keys explaining a chart.
struct ChartLegend: View {
    struct Item: Identifiable {
        let label: String
        let color: Color
        var id: String { label }
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: Spacing.m) {
            ForEach(items) { item in
                HStack(spacing: Spacing.xxs + 2) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(item.color)
                        .frame(width: 10, height: 10)
                    Text(item.label)
                        .font(.caption)
                        .foregroundStyle(CorvaColor.textSecondary)
                }
            }
        }
    }
}

#Preview("Bars") {
    VStack(alignment: .leading, spacing: Spacing.l) {
        RangeBar(value: 54, typicalRange: 52...66)
        RangeBar(value: 71, typicalRange: 52...66)
        TargetBar(value: 41, target: 48...62, tint: CorvaColor.strain)
        ProgressBar(fraction: 0.84, tint: CorvaColor.sleep)
        SegmentedBar(segments: [
            .init(id: "deep", value: 78, color: SleepStage.deep.color),
            .init(id: "rem", value: 101, color: SleepStage.rem.color),
            .init(id: "light", value: 267, color: SleepStage.light.color),
            .init(id: "awake", value: 26, color: SleepStage.awake.color),
        ])
        ChartLegend(items: [
            .init(label: "Recovery", color: CorvaColor.recoveryHigh),
            .init(label: "Strain", color: CorvaColor.strain),
        ])
    }
    .padding(Spacing.screen)
    .corvaPreview()
}
