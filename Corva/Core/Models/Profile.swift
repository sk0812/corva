import Foundation

/// The few personal facts population comparisons need. Everything else in Corva compares you
/// with your own history.
nonisolated struct Profile: Hashable, Sendable {
    var age: Int
    var sex: BiologicalSex
}

/// Used only to choose reference values (VO2 max and resting heart rate differ by sex).
/// "Not set" uses values midway between the two.
nonisolated enum BiologicalSex: String, CaseIterable, Identifiable, Hashable, Sendable {
    case notSet
    case female
    case male

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notSet: "Not set"
        case .female: "Female"
        case .male: "Male"
        }
    }
}
