import SwiftUI

/// An estimate with its 95% interval against a zero line: one row of a forest plot.
///
/// The whisker is the range the true effect plausibly lies in. If it crosses the zero line,
/// the data can't yet tell the change apart from no change.
struct IntervalBar: View {
    let estimate: Double
    let interval: ClosedRange<Double>?
    /// Symmetric around zero. Values beyond it are pinned to the ends.
    let limit: Double
    var tint: Color = CorvaColor.neutralData

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let mid = proxy.size.height / 2
            let zero = x(0, width: width)
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(CorvaColor.ringTrack)
                    .frame(width: width, height: 4)
                    .offset(y: mid - 2)
                Rectangle()
                    .fill(CorvaColor.textTertiary)
                    .frame(width: 1, height: proxy.size.height)
                    .offset(x: zero)
                if let interval {
                    let low = x(interval.lowerBound, width: width)
                    let high = x(interval.upperBound, width: width)
                    Capsule()
                        .fill(tint.opacity(0.45))
                        .frame(width: max(high - low, 4), height: 4)
                        .offset(x: low, y: mid - 2)
                }
                Circle()
                    .fill(tint)
                    .frame(width: 12, height: 12)
                    .shadow(color: tint.opacity(0.6), radius: 4)
                    .offset(x: x(estimate, width: width) - 6, y: mid - 6)
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }

    private func x(_ value: Double, width: CGFloat) -> CGFloat {
        let limit = max(self.limit, 0.0001)
        let fraction = (min(max(value, -limit), limit) + limit) / (2 * limit)
        return CGFloat(fraction) * width
    }
}

/// Two means on one scale, joined: best days in green, worst days in red.
struct DumbbellBar: View {
    let best: Double
    let worst: Double
    let domain: ClosedRange<Double>

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width - 12
            let bestX = x(best, width: width)
            let worstX = x(worst, width: width)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(CorvaColor.ringTrack)
                    .frame(height: 4)
                Capsule()
                    .fill(CorvaColor.textTertiary)
                    .frame(width: abs(bestX - worstX) + 12, height: 4)
                    .offset(x: min(bestX, worstX))
                dot(CorvaColor.worse).offset(x: worstX)
                dot(CorvaColor.better).offset(x: bestX)
            }
            .frame(height: proxy.size.height)
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }

    private func dot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .shadow(color: color.opacity(0.6), radius: 4)
    }

    private func x(_ value: Double, width: CGFloat) -> CGFloat {
        let span = max(domain.upperBound - domain.lowerBound, 0.0001)
        let fraction = (value - domain.lowerBound) / span
        return CGFloat(min(max(fraction, 0), 1)) * width
    }
}

/// A value growing left (negative, green) or right (positive, red) from a centre line, e.g.
/// years a marker takes off or adds to bio age.
struct DivergingBar: View {
    let value: Double
    /// The value that fills one half.
    let limit: Double
    var negativeColor: Color = CorvaColor.better
    var positiveColor: Color = CorvaColor.worse

    var body: some View {
        GeometryReader { proxy in
            let half = proxy.size.width / 2
            let length = half * CGFloat(min(abs(value) / max(limit, 0.0001), 1))
            let color = value < 0 ? negativeColor : positiveColor
            ZStack(alignment: .leading) {
                Capsule().fill(CorvaColor.ringTrack)
                Capsule()
                    .fill(color)
                    .frame(width: max(length, value == 0 ? 0 : 3))
                    .shadow(color: color.opacity(0.5), radius: 4)
                    .offset(x: value < 0 ? half - length : half)
                Rectangle()
                    .fill(CorvaColor.textTertiary)
                    .frame(width: 1)
                    .offset(x: half)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

#Preview("Analytics bars") {
    GlassCard {
        VStack(alignment: .leading, spacing: Spacing.l) {
            IntervalBar(estimate: -7.7, interval: -15.2 ... -0.3, limit: 16, tint: CorvaColor.worse)
            IntervalBar(estimate: 0.3, interval: -4.2...4.8, limit: 16)
            DumbbellBar(best: 301, worst: 331, domain: 270...360)
            DivergingBar(value: -2.0, limit: 4)
            DivergingBar(value: 0.6, limit: 4)
        }
    }
    .padding(Spacing.screen)
    .corvaPreview()
}
