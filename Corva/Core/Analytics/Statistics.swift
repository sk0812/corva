import Foundation

/// Small, dependency-free statistics used by baselines, scoring and trends.
nonisolated enum Statistics {
    static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Sample standard deviation (n − 1). Zero when there are fewer than two values.
    static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = mean(values)
        let squaredDeviations = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return (squaredDeviations / Double(values.count - 1)).squareRoot()
    }

    /// Change across a series of equally spaced values, measured along its least-squares line.
    ///
    /// Using the fitted line instead of `last − first` keeps one unusual day at either end of
    /// the period from dominating the result.
    static func trendChange(_ values: [Double]) -> Double {
        let count = values.count
        guard count > 1 else { return 0 }
        let xs = (0..<count).map(Double.init)
        let meanX = mean(xs)
        let meanY = mean(values)
        var numerator = 0.0
        var denominator = 0.0
        for (x, y) in zip(xs, values) {
            numerator += (x - meanX) * (y - meanY)
            denominator += (x - meanX) * (x - meanX)
        }
        guard denominator > 0 else { return 0 }
        let slope = numerator / denominator
        return slope * Double(count - 1)
    }
}

nonisolated extension Statistics {
    struct LinearFit: Hashable, Sendable {
        let slope: Double
        let intercept: Double
        /// Pearson's r, -1 to 1.
        let correlation: Double

        func y(at x: Double) -> Double { intercept + slope * x }
    }

    /// Least-squares line and Pearson correlation for paired values. Nil if fewer than three
    /// pairs or either series is constant.
    static func linearFit(x: [Double], y: [Double]) -> LinearFit? {
        let count = min(x.count, y.count)
        guard count >= 3 else { return nil }
        let xs = Array(x.prefix(count))
        let ys = Array(y.prefix(count))
        let meanX = mean(xs)
        let meanY = mean(ys)
        var covariance = 0.0
        var varianceX = 0.0
        var varianceY = 0.0
        for (a, b) in zip(xs, ys) {
            covariance += (a - meanX) * (b - meanY)
            varianceX += (a - meanX) * (a - meanX)
            varianceY += (b - meanY) * (b - meanY)
        }
        guard varianceX > 0, varianceY > 0 else { return nil }
        let slope = covariance / varianceX
        return LinearFit(
            slope: slope,
            intercept: meanY - slope * meanX,
            correlation: covariance / (varianceX * varianceY).squareRoot()
        )
    }
}
