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
///
/// With `retry`, the empty and failed states can be pulled down to refresh and have a Try
/// again button, so a screen is never a dead end.
struct LoadStateView<Value, Content: View>: View {
    private let state: LoadState<Value>
    private let emptyMessage: String
    private let retry: (() async -> Void)?
    private let content: (Value) -> Content

    init(
        _ state: LoadState<Value>,
        emptyMessage: String = "Data appears here once a source has synced.",
        retry: (() async -> Void)? = nil,
        @ViewBuilder content: @escaping (Value) -> Content
    ) {
        self.state = state
        self.emptyMessage = emptyMessage
        self.retry = retry
        self.content = content
    }

    var body: some View {
        switch state {
        case .loading:
            ProgressView()
                .tint(CorvaColor.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            unavailable(title: "No data yet", symbol: "waveform.path.ecg", message: emptyMessage)
        case .failed(let message):
            unavailable(title: "Couldn’t load data", symbol: "exclamationmark.triangle", message: message)
        case .loaded(let value):
            content(value)
        }
    }

    @ViewBuilder
    private func unavailable(title: String, symbol: String, message: String) -> some View {
        if let retry {
            ScrollView {
                ContentUnavailableView {
                    Label(title, systemImage: symbol)
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await retry() } }
                        .buttonStyle(.glass)
                }
                .containerRelativeFrame(.vertical)
            }
            .refreshable { await retry() }
        } else {
            ContentUnavailableView(title, systemImage: symbol, description: Text(message))
        }
    }
}

#Preview("Load states") {
    TabView {
        Tab("Loading", systemImage: "circle.dotted") {
            LoadStateView(LoadState<Int>.loading) { Text("\($0)") }
        }
        Tab("Empty", systemImage: "circle") {
            LoadStateView(LoadState<Int>.empty, retry: {}) { Text("\($0)") }
        }
        Tab("Failed", systemImage: "exclamationmark.triangle") {
            LoadStateView(LoadState<Int>.failed("The source didn’t respond.")) { Text("\($0)") }
        }
    }
    .corvaPreview()
}
