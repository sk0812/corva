import Foundation

/// Where health data comes from. Each source will get its own `HealthDataProvider`.
nonisolated enum DataSource: String, CaseIterable, Identifiable, Hashable, Sendable {
    case googleHealth
    case appleHealth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .googleHealth: "Google Health"
        case .appleHealth: "Apple Health"
        }
    }

    /// What the source provides, in a few words.
    var subtitle: String {
        switch self {
        case .googleHealth: "Fitbit Air"
        case .appleHealth: "Health app on this iPhone"
        }
    }
}

nonisolated enum ConnectionStatus: Hashable, Sendable {
    case connected(lastSync: Date)
    case notConnected
}
