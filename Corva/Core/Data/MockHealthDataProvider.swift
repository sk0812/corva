import Foundation

/// Deterministic, realistic data for development and previews.
///
/// Generates 90 days for one simulated person, plus 30 hidden warm-up days so every visible
/// day has a full 30-day baseline. The days are causally linked rather than independently
/// random:
///
/// - Yesterday's strain raises tonight's sleep need, adds restlessness, and suppresses
///   tomorrow's HRV and raises resting heart rate.
/// - Short or broken sleep lowers the next morning's HRV and raises resting heart rate, and
///   feeds directly into recovery.
/// - Low recovery makes a planned hard session more likely to be cut short; high recovery
///   lets it run a little harder.
/// - Two colds (about three weeks and about ten weeks ago) raise skin temperature,
///   respiratory rate and resting heart rate, crush HRV and replace training with rest.
/// - Evenings with alcohol (mostly Fridays and Saturdays) lower that night's HRV, raise
///   resting heart rate and fragment sleep.
/// - A two-week stretch about two months ago of going to bed by ~10:20 PM every night
///   lengthens sleep and lifts recovery.
///
/// `lifestyle` records those behaviours so the mock experiments and pacts can be seeded from
/// the same events the data reflects.
///
/// Every day, today included, is treated as complete, as if viewed in the evening.
nonisolated struct MockHealthDataProvider: HealthDataProvider {
    /// Shared instance for previews and the environment default, so data is generated once.
    static let preview = MockHealthDataProvider()

    /// Every generated day, oldest first. Exposed so previews can use a summary directly.
    let days: [DailySummary]
    /// What the simulated person did, as reflected in `days`.
    let lifestyle: MockLifestyle
    private let statuses: [DataSource: ConnectionStatus]

    init(
        endingOn endDate: Date = .now,
        dayCount: Int = 90,
        seed: UInt64 = 0xC0_12_7A,
        calendar: Calendar = .current
    ) {
        var generator = MockDataGenerator(seed: seed, calendar: calendar)
        (days, lifestyle) = generator.make(endingOn: calendar.startOfDay(for: endDate), count: dayCount)
        statuses = [
            .googleHealth: .connected(lastSync: endDate.addingTimeInterval(-12 * 60)),
            .appleHealth: .notConnected,
        ]
    }

    func summaries(from start: Date, through end: Date) async throws -> [DailySummary] {
        days.filter { $0.date >= start && $0.date <= end }
    }

    func connectionStatus(for source: DataSource) async -> ConnectionStatus {
        statuses[source] ?? .notConnected
    }
}

/// Behaviour the simulated person logged. Every entry has a real effect in the generated
/// days (except magnesium, which deliberately has none), so experiments find real results.
nonisolated struct MockLifestyle: Hashable, Sendable {
    /// Evenings with alcohol, each the start of that calendar day.
    let alcoholEvenings: Set<Date>
    /// First evening of the early-bedtime fortnight.
    let earlyBedtimeStart: Date
    let earlyBedtimeNights: Int
    /// First evening of taking magnesium before bed.
    let magnesiumStart: Date
    /// The last generated day.
    let today: Date
}

// MARK: - Generator

private nonisolated struct MockDataGenerator {
    private var random: SeededRandomNumberGenerator
    /// Separate stream for behaviours and VO2 max, so adding them left the original
    /// physiology sequence (and every number already tuned against it) unchanged.
    private var lifestyleRandom: SeededRandomNumberGenerator
    private let calendar: Calendar
    private let maxHeartRate = 188.0

    init(seed: UInt64, calendar: Calendar) {
        random = SeededRandomNumberGenerator(seed: seed)
        lifestyleRandom = SeededRandomNumberGenerator(seed: seed ^ 0x5EED_1A1F)
        self.calendar = calendar
    }

    mutating func make(endingOn lastDay: Date, count: Int) -> ([DailySummary], MockLifestyle) {
        let total = count + Baseline.windowDays
        let lifestyle = makeLifestyle(endingOn: lastDay, total: total)
        let earlyBedtimeEvenings = Set((0..<lifestyle.earlyBedtimeNights).compactMap {
            calendar.date(byAdding: .day, value: $0, to: lifestyle.earlyBedtimeStart)
        })
        var summaries: [DailySummary] = []
        summaries.reserveCapacity(total)
        var previousStrain = 45
        var sleepDebt: TimeInterval = 0

        for index in 0..<total {
            let daysAgo = total - 1 - index
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: lastDay) else { continue }
            // Slow fitness improvement across the window: HRV drifts up, resting HR down.
            let fitness = Double(index) / Double(max(total - 1, 1))
            let illness = illness(daysAgo: daysAgo)
            let baseline = Baseline(history: Array(summaries.suffix(Baseline.windowDays)))
            let evening = calendar.date(byAdding: .day, value: -1, to: date) ?? date
            let drankLastNight = lifestyle.alcoholEvenings.contains(evening)

            let sleep = makeSleep(
                morning: date,
                previousStrain: previousStrain,
                sleepDebt: sleepDebt,
                illness: illness,
                alcohol: drankLastNight,
                earlyBedtime: earlyBedtimeEvenings.contains(evening)
            )
            let vitals = makeVitals(
                fitness: fitness,
                sleepScore: sleep.score,
                previousStrain: previousStrain,
                illness: illness,
                alcohol: drankLastNight
            )
            let recovery = Scoring.recovery(
                hrv: vitals.hrv,
                hrvBaseline: baseline[.hrv]?.mean ?? typicalHRV(fitness: fitness),
                restingHeartRate: vitals.restingHeartRate,
                restingHeartRateBaseline: baseline[.restingHeartRate]?.mean ?? typicalRestingHeartRate(fitness: fitness),
                sleepScore: sleep.score
            )
            let strain = makeStrain(day: date, recovery: recovery, restingHeartRate: vitals.restingHeartRate, illness: illness)

            summaries.append(DailySummary(
                date: date,
                recovery: RecoveryMetrics(score: recovery),
                strain: strain,
                sleep: sleep,
                vitals: vitals,
                baseline: baseline
            ))

            // Debt is measured against need excluding debt repayment, and half-life decays.
            let needBeforeDebt = Scoring.sleepNeed(previousStrain: previousStrain, sleepDebt: 0)
            sleepDebt = clamp(sleepDebt * 0.6 + needBeforeDebt - sleep.timeAsleep, 0...(4 * 3600))
            previousStrain = strain.score
        }
        return (Array(summaries.suffix(count)), lifestyle)
    }

    // MARK: Lifestyle

    private mutating func makeLifestyle(endingOn lastDay: Date, total: Int) -> MockLifestyle {
        var alcohol: Set<Date> = []
        for daysAgo in 1..<total {
            guard let evening = calendar.date(byAdding: .day, value: -daysAgo, to: lastDay) else { continue }
            // Nobody drinks with a cold.
            guard max(illness(daysAgo: daysAgo), illness(daysAgo: daysAgo - 1)) < 0.15 else { continue }
            let weekday = calendar.component(.weekday, from: evening) // 5 = Thursday … 7 = Saturday
            let likelihood = switch weekday {
            case 6, 7: 0.6
            case 5: 0.25
            default: 0.08
            }
            if lifestyleRandom.chance(likelihood) {
                alcohol.insert(evening)
            }
        }
        let calendar = calendar
        let day = { (daysAgo: Int) in calendar.date(byAdding: .day, value: -daysAgo, to: lastDay) ?? lastDay }
        return MockLifestyle(
            alcoholEvenings: alcohol,
            earlyBedtimeStart: day(58),
            earlyBedtimeNights: 14,
            magnesiumStart: day(12),
            today: lastDay
        )
    }

    // MARK: Illness

    /// 0 (healthy) to 1 (properly ill). Triangular episodes around a peak day.
    private func illness(daysAgo: Int) -> Double {
        let episodes: [(peakDaysAgo: Int, severity: Double, halfWidth: Double)] = [
            (24, 1.0, 3),
            (68, 0.5, 2.5),
        ]
        return episodes
            .map { max(0, $0.severity * (1 - abs(Double(daysAgo - $0.peakDaysAgo)) / $0.halfWidth)) }
            .max() ?? 0
    }

    // MARK: Sleep

    private mutating func makeSleep(
        morning: Date,
        previousStrain: Int,
        sleepDebt: TimeInterval,
        illness: Double,
        alcohol: Bool,
        earlyBedtime: Bool
    ) -> SleepMetrics {
        let weekday = calendar.component(.weekday, from: morning) // 1 = Sunday
        let isWeekendMorning = weekday == 1 || weekday == 7
        let isLateNight = illness < 0.2 && random.chance(0.11)
        // 6 PM the evening before; clock times below are minutes after it.
        let anchor = calendar.startOfDay(for: morning).addingTimeInterval(-6 * 3600)

        var bedMinutes = random.normal(mean: 295, standardDeviation: 18) // ~10:55 PM
        var lateExtra = 0.0
        if isLateNight { lateExtra = random.normal(mean: 85, standardDeviation: 20) }
        if earlyBedtime {
            bedMinutes -= 33 // ~10:20 PM, weekends and all
        } else {
            if isWeekendMorning { bedMinutes += 45 } // Friday and Saturday nights
            bedMinutes += lateExtra
        }
        if alcohol { bedMinutes += 20 }
        bedMinutes -= 35 * illness

        var wakeMinutes = isWeekendMorning
            ? random.normal(mean: 835, standardDeviation: 25) // ~7:55 AM
            : random.normal(mean: 780, standardDeviation: 10) // ~7:00 AM alarm
        wakeMinutes += 45 * illness
        wakeMinutes = max(wakeMinutes, bedMinutes + 240)

        let bedtime = anchor.addingTimeInterval(bedMinutes * 60)
        let wakeTime = anchor.addingTimeInterval(wakeMinutes * 60)

        // Illness lengthens time in bed but fragments the sleep within it.
        var restlessness = 0.035 + abs(random.normal(mean: 0, standardDeviation: 0.015)) + 0.16 * illness
        if previousStrain > 75 { restlessness += 0.02 }
        if isLateNight && !earlyBedtime { restlessness += 0.025 }
        if alcohol { restlessness += 0.035 }

        let segments = makeHypnogram(bedtime: bedtime, wakeTime: wakeTime, restlessness: restlessness)
        let need = Scoring.sleepNeed(previousStrain: previousStrain, sleepDebt: sleepDebt) + illness * 60 * 60
        let timeAsleep = segments.filter(\.stage.isAsleep).reduce(0) { $0 + $1.duration }

        return SleepMetrics(
            score: Scoring.sleepScore(timeAsleep: timeAsleep, need: need),
            bedtime: bedtime,
            wakeTime: wakeTime,
            need: need,
            segments: segments
        )
    }

    /// ~90-minute cycles of light → deep → light → REM. Deep sleep front-loads, REM
    /// back-loads, and restlessness lengthens sleep onset and adds awakenings.
    private mutating func makeHypnogram(bedtime: Date, wakeTime: Date, restlessness: Double) -> [SleepSegment] {
        let totalMinutes = wakeTime.timeIntervalSince(bedtime) / 60
        let finalWake = clamp(random.normal(mean: 4, standardDeviation: 1.5), 1...10)
        let sleepWindow = totalMinutes - finalWake

        let latency = clamp(random.normal(mean: 10, standardDeviation: 4) + restlessness * 80, 3...45)
        var plan: [(stage: SleepStage, minutes: Double)] = [(.awake, latency)]
        var planned = latency
        var cycle = 0.0

        while planned < sleepWindow - 5 {
            let length = clamp(random.normal(mean: 92, standardDeviation: 9), 70...115)
            let deepShare = max(0.04, 0.36 - 0.075 * cycle) * max(0.4, 1 - restlessness * 3)
            let remShare = min(0.40, 0.13 + 0.07 * cycle)
            let lightShare = 1 - deepShare - remShare
            plan += [
                (.light, length * lightShare * 0.55),
                (.deep, length * deepShare),
                (.light, length * lightShare * 0.45),
                (.rem, length * remShare),
            ]
            planned += length
            if random.chance(0.3 + restlessness * 4) {
                let awake = clamp(random.normal(mean: 3, standardDeviation: 1.5) * (1 + restlessness * 10), 1...35)
                plan.append((.awake, awake))
                planned += awake
            }
            cycle += 1
        }

        // Lay the plan onto the clock, trim at the end of the sleep window, then wake up.
        var raw: [SleepSegment] = []
        var cursor = 0.0
        for step in plan where cursor < sleepWindow {
            let length = min(step.minutes, sleepWindow - cursor)
            raw.append(segment(step.stage, from: cursor, to: cursor + length, after: bedtime))
            cursor += length
        }
        raw.append(segment(.awake, from: cursor, to: totalMinutes, after: bedtime))

        // Drop empty blocks and merge neighbours of the same stage.
        var merged: [SleepSegment] = []
        for next in raw where next.end > next.start {
            if let last = merged.last, last.stage == next.stage {
                merged[merged.count - 1] = SleepSegment(stage: last.stage, start: last.start, end: next.end)
            } else {
                merged.append(next)
            }
        }
        return merged
    }

    private func segment(_ stage: SleepStage, from start: Double, to end: Double, after origin: Date) -> SleepSegment {
        SleepSegment(
            stage: stage,
            start: origin.addingTimeInterval(start * 60),
            end: origin.addingTimeInterval(end * 60)
        )
    }

    // MARK: Vitals

    private func typicalHRV(fitness: Double) -> Double { 58 + 6 * fitness }
    private func typicalRestingHeartRate(fitness: Double) -> Double { 54 - 2 * fitness }

    private mutating func makeVitals(
        fitness: Double,
        sleepScore: Int,
        previousStrain: Int,
        illness: Double,
        alcohol: Bool
    ) -> Vitals {
        let sleepPerformance = Double(sleepScore) / 100
        let strainEffect = Double(previousStrain - 45)

        let hrvFactor = 1 + 0.25 * (sleepPerformance - 0.9) - 0.0035 * strainEffect - 0.35 * illness
        let hrv = typicalHRV(fitness: fitness) * hrvFactor
            * exp(random.normal(mean: 0, standardDeviation: 0.07))
            * (alcohol ? 0.86 : 1)
        let restingHeartRate = typicalRestingHeartRate(fitness: fitness)
            - 5 * (sleepPerformance - 0.9)
            + 0.045 * strainEffect
            + 6.5 * illness
            + random.normal(mean: 0, standardDeviation: 0.9)
            + (alcohol ? 3.2 : 0)
        let respiratoryRate = 14.3 + 1.5 * illness + random.normal(mean: 0, standardDeviation: 0.22)
        let skinTemperature = 33.7 + 0.8 * illness + random.normal(mean: 0, standardDeviation: 0.14)
        let bloodOxygen = min(99.5, 96.6 - 1.6 * illness + random.normal(mean: 0, standardDeviation: 0.45))
        // Wearable VO2 max estimates move slowly; this one climbs with fitness.
        let vo2Max = 43.8 + 2.4 * fitness + lifestyleRandom.normal(mean: 0, standardDeviation: 0.2)

        // Rounded to the precision wearables actually report.
        return Vitals(
            hrv: hrv.rounded(),
            restingHeartRate: restingHeartRate.rounded(),
            respiratoryRate: (respiratoryRate * 10).rounded() / 10,
            bloodOxygen: (bloodOxygen * 10).rounded() / 10,
            skinTemperature: (skinTemperature * 100).rounded() / 100,
            vo2Max: (vo2Max * 10).rounded() / 10
        )
    }

    // MARK: Strain

    private struct PlannedActivity {
        let kind: ActivityKind
        let startHour: Double
        var minutes: Double
        let zoneTemplate: [Double]
    }

    /// Share of time in zones 1-5 for each kind of session.
    private enum ZoneTemplate {
        static let tempoRun = [0.08, 0.27, 0.40, 0.20, 0.05]
        static let longRun = [0.06, 0.38, 0.42, 0.12, 0.02]
        static let intervalRide = [0.10, 0.28, 0.25, 0.25, 0.12]
        static let longRide = [0.10, 0.45, 0.35, 0.09, 0.01]
        static let strength = [0.30, 0.40, 0.22, 0.08, 0.0]
        static let walk = [0.75, 0.22, 0.03, 0.0, 0.0]
        static let yoga = [0.85, 0.15, 0.0, 0.0, 0.0]
        static let swim = [0.15, 0.40, 0.35, 0.10, 0.0]
    }

    private mutating func makeStrain(day: Date, recovery: Int, restingHeartRate: Double, illness: Double) -> StrainMetrics {
        var plan = weeklyPlan(for: day)

        if illness > 0.3 {
            plan = plan.filter { $0.kind == .walk }.map { var walk = $0; walk.minutes *= 0.6; return walk }
        } else if random.chance(0.07) {
            plan = [] // Life gets in the way.
        }

        var intensity = exp(random.normal(mean: 0, standardDeviation: 0.05))
        switch RecoveryZone(score: recovery) {
        case .low:
            intensity *= 0.75
            plan = plan.map { var session = $0; session.minutes *= 0.75; return session }
        case .moderate:
            break
        case .high:
            intensity *= 1.08
        }

        var activities: [Activity] = []
        for (index, session) in plan.enumerated() {
            activities.append(makeActivity(session, day: day, index: index, intensity: intensity))
        }

        // Everyday movement outside of recorded activities.
        let healthy = 1 - illness
        let everyday: [HeartRateZone: Double] = [
            .one: clamp(random.normal(mean: 55, standardDeviation: 15), 20...100) * (1 - 0.4 * illness),
            .two: clamp(random.normal(mean: 10, standardDeviation: 4), 2...25) * (1 - 0.5 * illness),
            .three: clamp(random.normal(mean: 2, standardDeviation: 1.5), 0...6) * healthy,
        ]

        let zones = HeartRateZone.allCases.map { zone in
            let activityTime = activities.reduce(0) { total, activity in
                total + (activity.heartRateZones.first { $0.zone == zone }?.duration ?? 0)
            }
            return ZoneDuration(zone: zone, duration: (everyday[zone] ?? 0) * 60 + activityTime)
        }

        let everydayEnergy = 180 + (everyday[.one] ?? 0) * 4 + (everyday[.two] ?? 0) * 6 + (everyday[.three] ?? 0) * 9
        let activeEnergy = everydayEnergy + activities.reduce(0) { $0 + $1.energy }

        // Steps: everyday walking plus cadence-based steps for on-foot sessions.
        let stepsPerMinute: [ActivityKind: Double] = [.walk: 112, .run: 166, .strength: 18]
        let everydaySteps = clamp(random.normal(mean: 5800, standardDeviation: 1400), 2500...10000) * (1 - 0.55 * illness)
        let activitySteps = activities.reduce(0.0) { $0 + (stepsPerMinute[$1.kind] ?? 0) * $1.duration / 60 }

        let load = Scoring.cardiovascularLoad(zones)
        let averageHeartRate = restingHeartRate + 12 + 0.035 * load + random.normal(mean: 0, standardDeviation: 1.5)
        let everydayPeak = ((everyday[.three] ?? 0) > 0.5 ? 0.76 : 0.68) * maxHeartRate * random.uniform(0.97...1.03)
        let peakHeartRate = max(Double(activities.map(\.maxHeartRate).max() ?? 0), everydayPeak)

        return StrainMetrics(
            score: Scoring.strain(zones: zones),
            heartRateZones: zones,
            activities: activities,
            activeEnergy: activeEnergy.rounded(),
            averageHeartRate: Int(averageHeartRate.rounded()),
            maxHeartRate: Int(peakHeartRate.rounded()),
            steps: Int(everydaySteps + activitySteps)
        )
    }

    /// A consistent week: strength Monday, tempo run Tuesday, walk Wednesday, intervals on
    /// the bike Thursday, optional yoga Friday, a long run or ride Saturday, an easy Sunday.
    private mutating func weeklyPlan(for day: Date) -> [PlannedActivity] {
        let weekday = calendar.component(.weekday, from: day) // 1 = Sunday
        switch weekday {
        case 2:
            return [PlannedActivity(kind: .strength, startHour: 18, minutes: random.uniform(48...62), zoneTemplate: ZoneTemplate.strength)]
        case 3:
            return [PlannedActivity(kind: .run, startHour: 7, minutes: random.uniform(38...55), zoneTemplate: ZoneTemplate.tempoRun)]
        case 4:
            return [PlannedActivity(kind: .walk, startHour: 12.5, minutes: random.uniform(30...50), zoneTemplate: ZoneTemplate.walk)]
        case 5:
            return [PlannedActivity(kind: .ride, startHour: 18.25, minutes: random.uniform(58...78), zoneTemplate: ZoneTemplate.intervalRide)]
        case 6:
            guard random.chance(0.7) else { return [] }
            return [PlannedActivity(kind: .yoga, startHour: 7.25, minutes: random.uniform(28...40), zoneTemplate: ZoneTemplate.yoga)]
        case 7:
            let week = calendar.component(.weekOfYear, from: day)
            return week.isMultiple(of: 2)
                ? [PlannedActivity(kind: .run, startHour: 8.5, minutes: random.uniform(75...100), zoneTemplate: ZoneTemplate.longRun)]
                : [PlannedActivity(kind: .ride, startHour: 8.5, minutes: random.uniform(100...140), zoneTemplate: ZoneTemplate.longRide)]
        default:
            var sunday = [PlannedActivity(kind: .walk, startHour: 10, minutes: random.uniform(45...70), zoneTemplate: ZoneTemplate.walk)]
            if random.chance(0.3) {
                sunday.append(PlannedActivity(kind: .swim, startHour: 16.5, minutes: random.uniform(35...45), zoneTemplate: ZoneTemplate.swim))
            }
            return sunday
        }
    }

    private mutating func makeActivity(_ session: PlannedActivity, day: Date, index: Int, intensity: Double) -> Activity {
        // Shift time towards higher zones when intensity > 1, lower when < 1, with jitter.
        let weights = session.zoneTemplate.enumerated().map { zoneIndex, share in
            share * pow(intensity, Double(zoneIndex) - 1.5)
                * exp(random.normal(mean: 0, standardDeviation: 0.12))
        }
        let totalWeight = weights.reduce(0, +)
        let fractions = weights.map { totalWeight > 0 ? $0 / totalWeight : 0 }

        let duration = session.minutes * 60
        let zones = HeartRateZone.allCases.map { zone in
            ZoneDuration(zone: zone, duration: duration * fractions[zone.rawValue - 1])
        }

        let kilocaloriesPerMinute: [HeartRateZone: Double] = [.one: 5, .two: 8, .three: 11, .four: 14, .five: 16]
        let energy = zones.reduce(0) { $0 + $1.duration / 60 * (kilocaloriesPerMinute[$1.zone] ?? 0) }

        let averageFraction = zones.reduce(0) { total, zone in
            let bounds = zone.zone.bounds
            return total + fractions[zone.zone.rawValue - 1] * (bounds.lowerBound + bounds.upperBound) / 2
        }
        let topZone = HeartRateZone.allCases.last { fractions[$0.rawValue - 1] > 0.02 } ?? .one
        let peakHeartRate = topZone.bounds.upperBound * maxHeartRate * random.uniform(0.95...0.99)

        let metresPerMinute: [ActivityKind: Double] = [.run: 175, .ride: 450, .walk: 90, .swim: 40]
        var distance: Double?
        if let speed = metresPerMinute[session.kind] {
            let metres = speed * session.minutes * random.uniform(0.92...1.08) * intensity.squareRoot()
            distance = (metres / 10).rounded() * 10
        }

        let start = day.addingTimeInterval(session.startHour * 3600 + random.normal(mean: 0, standardDeviation: 600))

        return Activity(
            id: "\(Int(day.timeIntervalSince1970))-\(index)",
            kind: session.kind,
            start: start,
            duration: duration,
            strain: Scoring.strain(zones: zones),
            averageHeartRate: Int((averageFraction * maxHeartRate).rounded()),
            maxHeartRate: Int(peakHeartRate.rounded()),
            energy: energy.rounded(),
            distance: distance,
            heartRateZones: zones
        )
    }

    private func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
