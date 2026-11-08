import Foundation

/// SplitMix64: tiny, fast and deterministic, so mock data (and previews) are identical on
/// every launch.
nonisolated struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func uniform(_ range: ClosedRange<Double>) -> Double {
        Double.random(in: range, using: &self)
    }

    /// Normally distributed sample (Box–Muller).
    mutating func normal(mean: Double, standardDeviation: Double) -> Double {
        let u1 = max(Double.random(in: 0..<1, using: &self), .leastNonzeroMagnitude)
        let u2 = Double.random(in: 0..<1, using: &self)
        let z = (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        return mean + z * standardDeviation
    }

    mutating func chance(_ probability: Double) -> Bool {
        Double.random(in: 0..<1, using: &self) < probability
    }
}
