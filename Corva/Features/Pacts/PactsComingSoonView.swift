import SwiftUI

/// The Pacts tab while pacts are paused for launch: what's coming, nothing to tap.
///
/// The pact code (`PactsView` and friends) and the server's settlement stay in place; only
/// the tab shows this instead.
struct PactsComingSoonView: View {
    private let points: [(symbol: String, title: String, detail: String)] = [
        ("target", "Commit to a goal", "Steps, sleep, exercise, strain or bedtime, over days or weeks."),
        ("applewatch.radiowaves.left.and.right", "Your wearable is the referee", "Days are scored from your synced data. Nothing is self-reported."),
        ("cross.case", "Sick days don’t count", "When your vitals move the way illness moves them, the day is set aside."),
        ("person.2", "Solo or with a friend", "Hold yourself to it, or go head to head."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Image(systemName: "target")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(CorvaColor.pact)
                            .frame(width: 64, height: 64)
                            .glassEffect(.regular.tint(CorvaColor.pact.opacity(0.15)), in: .circle)
                            .accessibilityHidden(true)
                        Text("Coming soon")
                            .textStyle(.label)
                        Text("Pacts: goals your wearable holds you to")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(CorvaColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            ForEach(points, id: \.title) { point in
                                HStack(alignment: .top, spacing: Spacing.s) {
                                    Image(systemName: point.symbol)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(CorvaColor.pact)
                                        .frame(width: 28)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(point.title).textStyle(.body)
                                        Text(point.detail)
                                            .textStyle(.caption)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }

                    Text("Pacts are being finished before launch. Everything else in Corva works today.")
                        .textStyle(.caption)
                        .padding(.horizontal, Spacing.xxs)
                }
                .padding(.horizontal, Spacing.screen)
                .padding(.top, Spacing.s)
                .padding(.bottom, Spacing.xxl)
            }
            .screenBackground(glow: CorvaColor.pact.opacity(0.6))
            .navigationTitle("Pacts")
            .toolbarTitleDisplayMode(.inlineLarge)
        }
    }
}

#Preview {
    PactsComingSoonView()
        .corvaPreview()
}
