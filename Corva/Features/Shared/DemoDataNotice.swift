import SwiftUI

/// Says plainly that these aren't the user's numbers yet. Shown at the top of every screen
/// that displays health data while demo data is in use.
struct DemoDataNotice: View {
    @Environment(AccountService.self) private var account
    @Environment(\.isShowingDemoData) private var isShowingDemoData

    var body: some View {
        if isShowingDemoData {
            ScreenNotice(
                symbol: "sparkles",
                text: account.isSignedIn
                    ? "Demo data. Connect Google Health in Settings to see yours."
                    : "Demo data. Sign in and connect Google Health in Settings to see yours."
            )
        }
    }
}

#Preview {
    DemoDataNotice()
        .padding(Spacing.screen)
        .corvaPreview()
}
