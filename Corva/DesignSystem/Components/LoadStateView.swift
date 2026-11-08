import SwiftUI

/// The lifecycle of data a screen fetches from a `HealthDataProvider`.
enum LoadState<Value> {
    case loading
    case loaded(Value)
    /// The request worked but there is nothing to show (e.g. today hasn't synced yet).
    case empty
    case failed(String)
}

/// Renders loading, empty and error states consistently, and hands loaded values to `content`.
struct LoadStateView<Value, Content: View>: View {
    private let state: LoadState<Value>
    private let content: (Value) -> Content

    init(_ state: LoadState<Value>, @ViewBuilder content: @escaping (Value) -> Content) {
        self.state = state
        self.content = content
    }

    var body: some View {
        switch state {
        case .loading:
            ProgressView()
                .tint(CorvaColor.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView(
                "No data yet",
                systemImage: "waveform.path.ecg",
                description: Text("Data appears here once a source has synced.")
            )
        case .failed(let message):
            ContentUnavailableView(
                "Couldn’t load data",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .loaded(let value):
            content(value)
        }
    }
}

#Preview("Load states") {
    TabView {
        Tab("Loading", systemImage: "circle.dotted") {
            LoadStateView(LoadState<Int>.loading) { Text("\($0)") }
        }
        Tab("Empty", systemImage: "circle") {
            LoadStateView(LoadState<Int>.empty) { Text("\($0)") }
        }
        Tab("Failed", systemImage: "exclamationmark.triangle") {
            LoadStateView(LoadState<Int>.failed("The source didn’t respond.")) { Text("\($0)") }
        }
    }
    .corvaPreview()
}
