import SwiftUI

/// A one-line note floating at the top of a screen: demo data, data still syncing.
struct ScreenNotice: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: symbol)
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(CorvaColor.textSecondary)
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.m))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: Spacing.m) {
        ScreenNotice(symbol: "sparkles", text: "Demo data. Connect Google Health in Settings to see yours.")
        ScreenNotice(symbol: "arrow.triangle.2.circlepath", text: "Last night hasn’t synced yet. Showing Sunday.")
    }
    .padding(Spacing.screen)
    .corvaPreview()
}
