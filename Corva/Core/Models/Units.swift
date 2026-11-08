import Foundation

nonisolated enum TemperatureUnit: String, CaseIterable, Identifiable, Hashable, Sendable {
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .celsius: "Celsius"
        case .fahrenheit: "Fahrenheit"
        }
    }

    var symbol: String {
        switch self {
        case .celsius: "°C"
        case .fahrenheit: "°F"
        }
    }
}

nonisolated enum DistanceUnit: String, CaseIterable, Identifiable, Hashable, Sendable {
    case kilometers
    case miles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kilometers: "Kilometres"
        case .miles: "Miles"
        }
    }

    var symbol: String {
        switch self {
        case .kilometers: "km"
        case .miles: "mi"
        }
    }
}
