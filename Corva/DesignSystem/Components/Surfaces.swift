import SwiftUI

/// A full-width Liquid Glass container for a group of content.
///
/// Uses the system glass effect directly; nothing here imitates glass with blurs or materials.
/// A tint lets the glass carry the metric's colour faintly, the way Liquid Glass picks up
/// colour from what's behind it.
struct GlassCard<Content: View>: View {
    private let padding: CGFloat
    private let tint: Color?
    private let isInteractive: Bool
    private let content: Content

    init(
        padding: CGFloat = Spacing.m,
        tint: Color? = nil,
        isInteractive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.tint = tint
        self.isInteractive = isInteractive
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Glass isn't hit-testable on its own; make the whole card tappable.
            .contentShape(.rect(cornerRadius: Radius.l))
            .glassEffect(
                .regular.tint(tint.map { $0.opacity(0.12) }).interactive(isInteractive),
                in: .rect(cornerRadius: Radius.l)
            )
    }
}

/// Title row for a card: colour key, tracked label, trailing context, and a chevron when the
/// card navigates somewhere.
struct CardHeader: View {
    let title: String
    var tint: Color?
    var detail: String?
    var showsChevron = false

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let tint {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                    .shadow(color: tint.opacity(0.8), radius: 3)
            }
            Text(title).textStyle(.label)
            Spacer(minLength: Spacing.xs)
            if let detail {
                Text(detail)
                    .textStyle(.caption)
                    .lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CorvaColor.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Hairline between rows inside a card.
struct CardDivider: View {
    var body: some View {
        Rectangle()
            .fill(CorvaColor.separator)
            .frame(height: 1)
    }
}

extension View {
    /// The screen's canvas (near-black, or near-white in light mode), optionally lit from the
    /// top by a soft glow in the colour of the screen's headline metric.
    ///
    /// The glow is data, not decoration: it takes the colour of today's recovery zone (or the
    /// metric a detail screen is about), and it gives the glass above it something to refract.
    func screenBackground(glow: Color? = nil) -> some View {
        modifier(ScreenBackground(glow: glow))
    }
}

private struct ScreenBackground: ViewModifier {
    let glow: Color?
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        // Colour washes read much stronger on white, so light mode uses about two thirds.
        let strength = colorScheme == .dark ? 1.0 : 0.6
        content.background {
            ZStack(alignment: .top) {
                CorvaColor.background
                if let glow {
                    EllipticalGradient(
                        colors: [glow.opacity(0.34 * strength), glow.opacity(0.12 * strength), .clear],
                        center: .top,
                        startRadiusFraction: 0,
                        endRadiusFraction: 0.8
                    )
                    .frame(height: Size.ambientGlowHeight)
                }
            }
            .ignoresSafeArea()
        }
    }
}

#Preview("Glass card") {
    VStack(spacing: Spacing.m) {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                CardHeader(title: "Label", detail: "Context")
                Text("128").textStyle(.numeral)
            }
        }
        GlassCard(tint: CorvaColor.strain, isInteractive: true) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                CardHeader(title: "Strain", tint: CorvaColor.strain, detail: "Today", showsChevron: true)
                Text("Tinted, interactive glass").textStyle(.bodySecondary)
            }
        }
    }
    .padding(Spacing.screen)
    .frame(maxHeight: .infinity, alignment: .top)
    .screenBackground(glow: CorvaColor.recoveryHigh)
    .corvaPreview()
}
