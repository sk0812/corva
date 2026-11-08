import SwiftUI

/// Animated circular gauge for a 0-100 score, with the score as a numeral at its centre.
///
/// The arc carries a gradient along its length and a soft glow in the metric's colour. It
/// sweeps from zero to the score on first appearance (instantly with Reduce Motion on) and
/// animates between values when the score changes.
struct ScoreRing: View {
    enum Style {
        /// Side dials on Today.
        case small
        /// The featured dial on Today.
        case medium
        /// Top of a detail screen; shows the label inside the ring.
        case large

        var diameter: CGFloat {
            switch self {
            case .small: 100
            case .medium: 132
            case .large: 184
            }
        }

        var lineWidth: CGFloat {
            switch self {
            case .small: 9
            case .medium: 11
            case .large: 13
            }
        }

        var numeral: TypeStyle {
            switch self {
            case .small: .dialNumeral
            case .medium: .mediumNumeral
            case .large: .largeNumeral
            }
        }
    }

    let score: Int
    var label: String?
    var unit: String?
    let tint: Color
    var style: Style = .large

    @State private var progress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(CorvaColor.ringTrack, lineWidth: style.lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.45), tint],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * max(progress, 0.01))
                    ),
                    style: StrokeStyle(lineWidth: style.lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.55), radius: style.lineWidth * 0.9)
            VStack(spacing: Spacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(score, format: .number)
                        .textStyle(style.numeral)
                    if let unit {
                        Text(unit)
                            .font(.system(style == .small ? .caption : .subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(CorvaColor.textSecondary)
                    }
                }
                if style == .large, let label {
                    Text(label).textStyle(.label)
                }
            }
            .padding(style.lineWidth * 1.4)
        }
        .padding(style.lineWidth / 2)
        .frame(width: style.diameter, height: style.diameter)
        .onAppear(perform: animateToScore)
        .onChange(of: score, animateToScore)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "Score")
        .accessibilityValue("\(score)\(unit ?? "") out of 100")
    }

    private var fraction: Double {
        min(max(Double(score) / 100, 0), 1)
    }

    private func animateToScore() {
        guard !reduceMotion else {
            progress = fraction
            return
        }
        withAnimation(.easeOut(duration: 1.1).delay(0.1)) {
            progress = fraction
        }
    }
}

#Preview("Score rings") {
    VStack(spacing: Spacing.xl) {
        HStack(alignment: .center, spacing: Spacing.m) {
            ScoreRing(score: 88, label: "Sleep", unit: "%", tint: CorvaColor.sleep, style: .small)
            ScoreRing(score: 72, label: "Recovery", unit: "%", tint: CorvaColor.recoveryHigh, style: .medium)
            ScoreRing(score: 54, label: "Strain", tint: CorvaColor.strain, style: .small)
        }
        ScoreRing(score: 28, label: "Low", unit: "%", tint: CorvaColor.recoveryLow)
    }
    .padding(Spacing.screen)
    .corvaPreview()
}
