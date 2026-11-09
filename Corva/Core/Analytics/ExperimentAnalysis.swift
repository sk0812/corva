import Foundation

/// The statistics behind experiments: a difference in means with an honest 95% interval, and
/// how small an effect the data can currently detect.
///
/// Uses Welch's two-sample comparison, which doesn't assume both periods vary equally. Days
/// your vitals say you were unwell are left out of both groups, because a cold would swamp
/// almost any lifestyle effect. Daily values are treated as independent; real day-to-day
/// carry-over makes the interval somewhat optimistic.
nonisolated enum ExperimentAnalysis {
    /// Mornings before the first evening used as the comparison for before & after designs.
    static let baselineDays = 28
    /// Fewest days each group needs before an interval is shown.
    static let minimumDays = 5
    /// z for 80% power, added to the critical t for the minimum detectable effect.
    private static let powerZ = 0.84

    nonisolated struct Sample: Hashable, Sendable {
        let mean: Double
        let standardDeviation: Double
        let count: Int

        init(_ values: [Double]) {
            mean = Statistics.mean(values)
            standardDeviation = Statistics.standardDeviation(values)
            count = values.count
        }
    }

    nonisolated enum Verdict: Hashable, Sendable {
        /// Not enough days in one of the groups yet.
        case collecting
        case better
        case worse
        /// A clear change in a metric with no better or worse direction.
        case changed(TrendDirection)
        case noClearChange
    }

    nonisolated struct Outcome: Identifiable, Hashable, Sendable {
        let metric: Metric
        /// Days without the change.
        let control: Sample
        /// Days with it.
        let trial: Sample
        /// Trial minus control.
        let difference: Double
        /// 95% interval for the true difference. Nil until both groups have enough days.
        let interval: ClosedRange<Double>?
        /// Smallest true difference the current data would reliably catch.
        let detectableNow: Double?
        /// The same, projected to the planned end of the experiment.
        let detectableAtEnd: Double?
        let verdict: Verdict

        var id: Metric { metric }
    }

    nonisolated struct Result: Hashable, Sendable {
        let controlDates: [Date]
        let trialDates: [Date]
        /// Unwell days left out of both groups.
        let excludedDates: [Date]
        let daysElapsed: Int
        let isComplete: Bool
        let outcomes: [Outcome]

        var headline: Outcome? { outcomes.first }
    }

    static func analyze(
        _ experiment: Experiment,
        days: [DailySummary],
        today: Date,
        calendar: Calendar = .current
    ) -> Result {
        let firstMorning = calendar.date(byAdding: .day, value: 1, to: experiment.start) ?? experiment.start
        let lastMorning = calendar.date(byAdding: .day, value: experiment.length, to: experiment.start) ?? experiment.start
        let measuredThrough = min(lastMorning, calendar.startOfDay(for: today))

        let measured = days.filter { $0.date >= firstMorning && $0.date <= measuredThrough }
        var control: [DailySummary]
        var trial: [DailySummary]
        switch experiment.design {
        case .beforeAfter:
            let baselineStart = calendar.date(byAdding: .day, value: -(baselineDays - 1), to: experiment.start) ?? experiment.start
            control = days.filter { $0.date >= baselineStart && $0.date <= experiment.start }
            trial = measured
        case .onOff:
            trial = measured.filter { experiment.isTagged(morning: $0.date, calendar: calendar) }
            control = measured.filter { !experiment.isTagged(morning: $0.date, calendar: calendar) }
        }

        let excluded = (control + trial).filter(\.isLikelyUnwell).map(\.date).sorted()
        control.removeAll(where: \.isLikelyUnwell)
        trial.removeAll(where: \.isLikelyUnwell)

        // Expected group sizes at the planned end, for projecting what will be detectable.
        let elapsed = experiment.daysElapsed(today: today, calendar: calendar)
        let projected: (control: Double, trial: Double) = switch experiment.design {
        case .beforeAfter:
            (Double(control.count), Double(experiment.length))
        case .onOff:
            {
                let share = measured.isEmpty ? 0.3 : Double(trial.count) / Double(measured.count)
                return (Double(experiment.length) * (1 - share), Double(experiment.length) * share)
            }()
        }

        let outcomes = experiment.outcomes.map { metric in
            outcome(
                metric: metric,
                control: control.compactMap(metric.value(in:)),
                trial: trial.compactMap(metric.value(in:)),
                projected: projected
            )
        }

        return Result(
            controlDates: control.map(\.date),
            trialDates: trial.map(\.date),
            excludedDates: excluded,
            daysElapsed: elapsed,
            isComplete: elapsed >= experiment.length,
            outcomes: outcomes
        )
    }

    static func outcome(
        metric: Metric,
        control controlValues: [Double],
        trial trialValues: [Double],
        projected: (control: Double, trial: Double)
    ) -> Outcome {
        let control = Sample(controlValues)
        let trial = Sample(trialValues)
        let difference = trial.mean - control.mean

        guard control.count >= minimumDays, trial.count >= minimumDays else {
            return Outcome(
                metric: metric, control: control, trial: trial, difference: difference,
                interval: nil, detectableNow: nil, detectableAtEnd: nil, verdict: .collecting
            )
        }

        let (standardError, degreesOfFreedom) = welch(control, trial)
        let t = tCritical(degreesOfFreedom: degreesOfFreedom)
        let interval = (difference - t * standardError)...(difference + t * standardError)

        let endError = welch(
            control,
            trial,
            counts: (max(projected.control, Double(control.count)), max(projected.trial, Double(trial.count)))
        ).standardError

        let verdict: Verdict
        if interval.contains(0) {
            verdict = .noClearChange
        } else {
            let direction: TrendDirection = difference > 0 ? .up : .down
            switch metric.preferredDirection {
            case .some(let preferred) where preferred == direction: verdict = .better
            case .some: verdict = .worse
            case .none: verdict = .changed(direction)
            }
        }

        return Outcome(
            metric: metric,
            control: control,
            trial: trial,
            difference: difference,
            interval: interval,
            detectableNow: (t + powerZ) * standardError,
            detectableAtEnd: (tCritical(degreesOfFreedom: projected.control + projected.trial - 2) + powerZ) * endError,
            verdict: verdict
        )
    }

    /// Standard error of the difference and Welch–Satterthwaite degrees of freedom.
    private static func welch(
        _ a: Sample,
        _ b: Sample,
        counts: (Double, Double)? = nil
    ) -> (standardError: Double, degreesOfFreedom: Double) {
        let nA = counts?.0 ?? Double(a.count)
        let nB = counts?.1 ?? Double(b.count)
        let varianceA = pow(a.standardDeviation, 2) / nA
        let varianceB = pow(b.standardDeviation, 2) / nB
        let standardError = (varianceA + varianceB).squareRoot()
        let denominator = pow(varianceA, 2) / max(nA - 1, 1) + pow(varianceB, 2) / max(nB - 1, 1)
        let degreesOfFreedom = denominator > 0 ? pow(varianceA + varianceB, 2) / denominator : nA + nB - 2
        return (standardError, degreesOfFreedom)
    }

    /// Two-sided 95% critical value of Student's t.
    static func tCritical(degreesOfFreedom df: Double) -> Double {
        let table: [Double] = [
            12.71, 4.30, 3.18, 2.78, 2.57, 2.45, 2.36, 2.31, 2.26, 2.23,
            2.20, 2.18, 2.16, 2.14, 2.13, 2.12, 2.11, 2.10, 2.09, 2.09,
            2.08, 2.07, 2.07, 2.06, 2.06, 2.06, 2.05, 2.05, 2.05, 2.04,
        ]
        let whole = Int(df.rounded(.down))
        if whole < 1 { return table[0] }
        if whole <= table.count { return table[whole - 1] }
        return 1.96 + 0.08 * 30 / df
    }
}
