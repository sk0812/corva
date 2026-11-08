import SwiftUI

/// A change against a reference (usually the 30-day baseline): arrow plus magnitude.
///
/// Deliberately neutral grey. Whether "up" is good depends on the metric, and colouring it
/// would add hues beyond the one-colour-per-metric rule.
struct DeltaLabel: View {
    enum Size {
        case regular
        case large
    }

    let delta: FormattedDelta
    /// Context such as "vs 30-day avg".
    var suffix: String?
    var size: Size = .regular

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size == .large ? Spacing.xxs : 3) {
            Image(systemName: symbolName)
                .font(symbolFont)
            Text(delta.text)
                .font(valueFont)
                .monospacedDigit()
                .foregroundStyle(size == .large ? CorvaColor.textPrimary : CorvaColor.textSecondary)
            if let suffix {
                Text(suffix)
                    .font(.footnote)
            }
        }
        .foregroundStyle(CorvaColor.textSecondary)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var symbolName: String {
        switch delta.direction {
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .flat: "equal"
        }
    }

    private var symbolFont: Font {
        switch size {
        case .regular: .caption2.weight(.bold)
        case .large: .subheadline.weight(.bold)
        }
    }

    private var valueFont: Font {
        switch size {
        case .regular: .system(.footnote, design: .rounded, weight: .semibold)
        case .large: .system(.title2, design: .rounded, weight: .semibold)
        }
    }

    private var accessibilityText: String {
        let context = suffix.map { " \($0)" } ?? ""
        switch delta.direction {
        case .up: return "Up \(delta.text)\(context)"
        case .down: return "Down \(delta.text)\(context)"
        case .flat: return "No change\(context)"
        }
    }
}

#Preview("Delta labels") {
    VStack(alignment: .leading, spacing: Spacing.m) {
        DeltaLabel(delta: FormattedDelta(text: "6", direction: .up), suffix: "vs 30-day avg")
        DeltaLabel(delta: FormattedDelta(text: "2", direction: .down))
        DeltaLabel(delta: FormattedDelta(text: "0", direction: .flat))
        DeltaLabel(delta: FormattedDelta(text: "4.2", direction: .up), size: .large)
    }
    .padding(Spacing.screen)
    .corvaPreview()
}
