import SwiftUI

/// Type styles. Numbers are the hero: SF Pro Rounded with monospaced digits so values
/// don't jitter as they change. Labels are small, secondary and tracked uppercase.
enum TypeStyle {
    /// The score inside the Today recovery ring.
    case heroNumeral
    /// Scores inside detail-screen rings and headline values.
    case largeNumeral
    /// Scores inside the featured dial on Today.
    case mediumNumeral
    /// Scores inside small dials.
    case dialNumeral
    /// Values in metric cards.
    case numeral
    /// Values in compact cards and stat rows.
    case smallNumeral
    /// Units next to numerals ("ms", "%").
    case unit
    /// Small, tracked, uppercase, secondary.
    case label
    case body
    case bodySecondary
    case caption
}

extension View {
    func textStyle(_ style: TypeStyle) -> some View {
        modifier(TextStyleModifier(style: style))
    }
}

private struct TextStyleModifier: ViewModifier {
    let style: TypeStyle

    func body(content: Content) -> some View {
        switch style {
        case .heroNumeral:
            content.modifier(NumeralModifier(size: 76, relativeTo: .largeTitle))
        case .largeNumeral:
            content.modifier(NumeralModifier(size: 52, relativeTo: .largeTitle))
        case .mediumNumeral:
            content.modifier(NumeralModifier(size: 40, relativeTo: .largeTitle))
        case .dialNumeral:
            content.modifier(NumeralModifier(size: 28, relativeTo: .title))
        case .numeral:
            content.modifier(NumeralModifier(size: 34, relativeTo: .title))
        case .smallNumeral:
            content.modifier(NumeralModifier(size: 20, relativeTo: .title3))
        case .unit:
            content
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(CorvaColor.textSecondary)
        case .label:
            content
                .font(.caption.weight(.semibold))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(CorvaColor.textSecondary)
        case .body:
            content
                .font(.body)
                .foregroundStyle(CorvaColor.textPrimary)
        case .bodySecondary:
            content
                .font(.body)
                .foregroundStyle(CorvaColor.textSecondary)
        case .caption:
            content
                .font(.footnote)
                .foregroundStyle(CorvaColor.textSecondary)
        }
    }
}

/// Rounded, monospaced-digit numerals that still scale with Dynamic Type.
private struct NumeralModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat

    init(size: CGFloat, relativeTo textStyle: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(CorvaColor.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

#Preview("Typography") {
    VStack(alignment: .leading, spacing: Spacing.m) {
        Text("72").textStyle(.heroNumeral)
        Text("54").textStyle(.largeNumeral)
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
            Text("64").textStyle(.numeral)
            Text("ms").textStyle(.unit)
        }
        Text("14.6").textStyle(.smallNumeral)
        Text("Recovery").textStyle(.label)
        Text("Body copy").textStyle(.body)
        Text("Secondary body copy").textStyle(.bodySecondary)
        Text("Caption").textStyle(.caption)
    }
    .padding(Spacing.screen)
    .frame(maxWidth: .infinity, alignment: .leading)
    .corvaPreview()
}
