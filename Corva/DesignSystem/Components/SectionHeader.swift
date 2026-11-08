import SwiftUI

/// Small tracked label above a group of content, with optional trailing context.
struct SectionHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Text(title).textStyle(.label)
            Spacer(minLength: 0)
            if let detail {
                Text(detail)
                    .textStyle(.caption)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Spacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview("Section headers") {
    VStack(spacing: Spacing.l) {
        SectionHeader(title: "Vitals", detail: "vs 30-day baseline")
        SectionHeader(title: "Contributors")
    }
    .padding(Spacing.screen)
    .corvaPreview()
}
