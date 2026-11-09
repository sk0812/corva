import Foundation
import HealthKit

/// Reads Apple Health on this phone and builds the same daily records the Google Health sync
/// writes, so everything downstream (scoring, baselines, analytics) is shared.
///
/// Apple Health needs no account and its data never leaves the phone. Heart-rate zones aren't
/// stored in Health, so they're worked out from 5-minute heart-rate averages against the
/// user's maximum heart rate, into the same four zones Google reports.
nonisolated final class AppleHealthSource: @unchecked Sendable {
    private let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private static let quantityTypes: [HKQuantityTypeIdentifier] = [
        .stepCount, .activeEnergyBurned, .heartRate, .restingHeartRate, .heartRateVariabilitySDNN,
        .respiratoryRate, .oxygenSaturation, .appleSleepingWristTemperature, .vo2Max,
        .distanceWalkingRunning, .distanceCycling, .distanceSwimming,
    ]

    private static let bpm = HKUnit.count().unitDivided(by: .minute())

    /// Shows Apple's permission sheet (only the first time). Apple doesn't reveal what the
    /// user allowed, so a declined type simply has no data.
    func requestAccess() async throws {
        var read: Set<HKObjectType> = Set(Self.quantityTypes.map { HKQuantityType($0) })
        read.insert(HKCategoryType(.sleepAnalysis))
        read.insert(HKWorkoutType.workoutType())
        try await store.requestAuthorization(toShare: [], read: read)
    }

    /// One record per day from `start` to now, oldest first. Runs off the main thread.
    @concurrent
    func records(from start: Date, maxHeartRate: Double, calendar: Calendar = .current) async throws -> [DailyRecordRow] {
        let end = Date.now
        var days: [String: Builder] = [:]
        func day(_ date: Date) -> Builder {
            let key = DayCoding.string(from: date, calendar: calendar)
            if let existing = days[key] { return existing }
            let builder = Builder(date: key)
            days[key] = builder
            return builder
        }

        // Daily totals and averages.
        for (date, value) in try await daily(.stepCount, sum: true, unit: .count(), from: start, to: end, calendar: calendar) {
            day(date).steps = Int(value.rounded())
        }
        for (date, value) in try await daily(.activeEnergyBurned, sum: true, unit: .kilocalorie(), from: start, to: end, calendar: calendar) {
            day(date).activeKcal = value
        }
        for (date, stats) in try await statistics(.heartRate, [.discreteAverage, .discreteMax], from: start, to: end, every: DateComponents(day: 1), calendar: calendar) {
            day(date).hrAvg = stats.averageQuantity()?.doubleValue(for: Self.bpm)
            day(date).hrMax = stats.maximumQuantity()?.doubleValue(for: Self.bpm)
        }
        for (date, value) in try await daily(.restingHeartRate, sum: false, unit: Self.bpm, from: start, to: end, calendar: calendar) {
            day(date).restingHr = value
        }
        for (date, value) in try await daily(.vo2Max, sum: false, unit: HKUnit(from: "ml/kg*min"), from: start, to: end, calendar: calendar) {
            day(date).vo2max = value
        }
        for (date, zones) in try await zoneSeconds(from: start, to: end, maxHeartRate: maxHeartRate, calendar: calendar) {
            day(date).zoneSeconds = zones
        }
        for (date, exercise) in try await workouts(from: start, calendar: calendar) {
            day(date).exercises.append(exercise)
        }

        // Sleep, dated by the morning you woke up.
        let nights = try await nights(from: start, calendar: calendar)
        for (date, night) in nights {
            day(date).sleep = night.sleep
        }

        // Overnight readings, averaged over the night's sleep (or midnight to 10 AM when no
        // sleep was recorded), so daytime readings don't skew them.
        let windows = nights.mapValues(\.interval)
        let overnightReadings: [(HKQuantityTypeIdentifier, HKUnit, (Builder, Double) -> Void)] = [
            (.heartRateVariabilitySDNN, .secondUnit(with: .milli), { $0.hrv = $1 }),
            (.respiratoryRate, Self.bpm, { $0.respiratoryRate = $1 }),
            (.oxygenSaturation, .percent(), { $0.spo2 = $1 * 100 }),
            (.appleSleepingWristTemperature, .degreeCelsius(), { $0.skinTemp = $1 }),
        ]
        for (identifier, unit, apply) in overnightReadings {
            for (date, value) in try await overnight(identifier, unit: unit, from: start, windows: windows, calendar: calendar) {
                apply(day(date), value)
            }
        }

        return days.values.map(\.row).sorted { $0.date < $1.date }
    }

    // MARK: - Queries

    private func daily(
        _ identifier: HKQuantityTypeIdentifier,
        sum: Bool,
        unit: HKUnit,
        from start: Date,
        to end: Date,
        calendar: Calendar
    ) async throws -> [(Date, Double)] {
        try await statistics(identifier, sum ? .cumulativeSum : .discreteAverage, from: start, to: end, every: DateComponents(day: 1), calendar: calendar)
            .compactMap { date, stats in
                (sum ? stats.sumQuantity() : stats.averageQuantity()).map { (date, $0.doubleValue(for: unit)) }
            }
    }

    /// Statistics in fixed buckets from the start of `start`'s day. Empty buckets are left out.
    private func statistics(
        _ identifier: HKQuantityTypeIdentifier,
        _ options: HKStatisticsOptions,
        from start: Date,
        to end: Date,
        every interval: DateComponents,
        calendar: Calendar
    ) async throws -> [(Date, HKStatistics)] {
        let anchor = calendar.startOfDay(for: start)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(
                type: HKQuantityType(identifier),
                predicate: HKQuery.predicateForSamples(withStart: anchor, end: end)
            ),
            options: options,
            anchorDate: anchor,
            intervalComponents: interval
        )
        return try await descriptor.result(for: store).statistics().map { ($0.startDate, $0) }
    }

    /// The average of each night's samples, keyed by morning.
    private func overnight(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from start: Date,
        windows: [Date: DateInterval],
        calendar: Calendar
    ) async throws -> [(Date, Double)] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier), predicate: HKQuery.predicateForSamples(withStart: start, end: .now))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        var sums: [Date: (total: Double, count: Int)] = [:]
        for sample in try await descriptor.result(for: store) {
            guard let morning = Self.morning(for: sample.startDate, calendar: calendar) else { continue }
            if let window = windows[morning] {
                guard window.contains(sample.startDate) else { continue }
            } else {
                guard calendar.component(.hour, from: sample.startDate) < 10, sample.startDate >= morning else { continue }
            }
            let current = sums[morning] ?? (0, 0)
            sums[morning] = (current.total + sample.quantity.doubleValue(for: unit), current.count + 1)
        }
        return sums.map { ($0.key, $0.value.total / Double($0.value.count)) }
    }

    /// The morning an overnight moment belongs to: 6 PM to midnight → the next morning;
    /// midnight to 3 PM → that morning; late afternoons belong to no night (naps).
    private static func morning(for date: Date, calendar: Calendar) -> Date? {
        let hour = calendar.component(.hour, from: date)
        let day = calendar.startOfDay(for: date)
        if hour >= 18 { return calendar.date(byAdding: .day, value: 1, to: day) }
        if hour < 15 { return day }
        return nil
    }

    private func zoneSeconds(from start: Date, to end: Date, maxHeartRate: Double, calendar: Calendar) async throws -> [(Date, [String: Double])] {
        guard maxHeartRate > 0 else { return [] }
        let buckets = try await statistics(.heartRate, .discreteAverage, from: start, to: end, every: DateComponents(minute: 5), calendar: calendar)
        var zones: [Date: [String: Double]] = [:]
        for (bucketStart, stats) in buckets {
            guard let average = stats.averageQuantity()?.doubleValue(for: Self.bpm) else { continue }
            let zone: String? = switch average / maxHeartRate {
            case 0.9...: "PEAK"
            case 0.8..<0.9: "VIGOROUS"
            case 0.7..<0.8: "MODERATE"
            case 0.6..<0.7: "LIGHT"
            default: nil
            }
            guard let zone else { continue }
            zones[calendar.startOfDay(for: bucketStart), default: [:]][zone, default: 0] += 300
        }
        return zones.map { ($0.key, $0.value) }
    }

    private nonisolated struct Night {
        let sleep: DailyRecordRow.Sleep
        let interval: DateInterval
    }

    /// One night per morning, from whichever app or device recorded the most sleep that night,
    /// so a watch and a phone app aren't added together.
    private func nights(from start: Date, calendar: Calendar) async throws -> [Date: Night] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: HKQuery.predicateForSamples(withStart: start, end: .now))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await descriptor.result(for: store)
        let iso = Date.ISO8601FormatStyle()
        var result: [Date: Night] = [:]
        for (morning, nightSamples) in Dictionary(grouping: samples, by: { Self.morning(for: $0.endDate, calendar: calendar) }) {
            guard let morning else { continue }
            let bySource = Dictionary(grouping: nightSamples) { $0.sourceRevision.source.bundleIdentifier }
            guard let chosen = bySource.values.max(by: { Self.asleepSeconds($0) < Self.asleepSeconds($1) }) else { continue }
            let asleep = chosen.filter { Self.isAsleep($0) || Self.stageName($0) == "AWAKE" }
            let asleepSeconds = Self.asleepSeconds(chosen)
            guard asleepSeconds > 0, let first = asleep.map(\.startDate).min(), let last = asleep.map(\.endDate).max() else { continue }
            let stages = chosen.compactMap { sample in
                Self.stageName(sample).map { DailyRecordRow.Sleep.Stage(type: $0, start: sample.startDate.formatted(iso), end: sample.endDate.formatted(iso)) }
            }
            // Only "asleep" with no stages (older watches, phone apps) is classic sleep.
            let hasStages = stages.contains { $0.type != "AWAKE" }
            result[morning] = Night(
                sleep: DailyRecordRow.Sleep(
                    start: first.formatted(iso),
                    end: last.formatted(iso),
                    stages: hasStages ? stages : [],
                    minutesAsleep: asleepSeconds / 60
                ),
                interval: DateInterval(start: first, end: last)
            )
        }
        return result
    }

    private static func stageName(_ sample: HKCategorySample) -> String? {
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .asleepCore: "LIGHT"
        case .asleepDeep: "DEEP"
        case .asleepREM: "REM"
        case .awake: "AWAKE"
        default: nil // In bed, or asleep with no stage
        }
    }

    private static func isAsleep(_ sample: HKCategorySample) -> Bool {
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM: true
        default: false
        }
    }

    private static func asleepSeconds(_ samples: [HKCategorySample]) -> Double {
        samples.filter(isAsleep).reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
    }

    private func workouts(from start: Date, calendar: Calendar) async throws -> [(Date, DailyRecordRow.Exercise)] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: .now))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let iso = Date.ISO8601FormatStyle()
        return try await descriptor.result(for: store).map { workout in
            let (type, name) = Self.describe(workout.workoutActivityType)
            let distance = [HKQuantityTypeIdentifier.distanceWalkingRunning, .distanceCycling, .distanceSwimming]
                .compactMap { workout.statistics(for: HKQuantityType($0))?.sumQuantity()?.doubleValue(for: .meter()) }
                .first
            return (calendar.startOfDay(for: workout.startDate), DailyRecordRow.Exercise(
                id: workout.uuid.uuidString,
                type: type,
                name: name,
                start: workout.startDate.formatted(iso),
                end: workout.endDate.formatted(iso),
                seconds: workout.duration,
                kcal: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()),
                distanceM: distance,
                avgHr: workout.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: Self.bpm)
            ))
        }
    }

    /// A type the shared mapper understands, and a display name.
    private static func describe(_ type: HKWorkoutActivityType) -> (String, String) {
        switch type {
        case .running: ("RUNNING", "Run")
        case .cycling: ("BIKING", "Ride")
        case .walking: ("WALKING", "Walk")
        case .hiking: ("HIKING", "Hike")
        case .swimming: ("SWIMMING", "Swim")
        case .traditionalStrengthTraining, .functionalStrengthTraining: ("STRENGTH_TRAINING", "Strength")
        case .yoga: ("YOGA", "Yoga")
        case .pilates: ("PILATES", "Pilates")
        case .highIntensityIntervalTraining: ("WORKOUT", "HIIT")
        case .rowing: ("WORKOUT", "Rowing")
        case .badminton: ("SPORT", "Badminton")
        case .tennis: ("SPORT", "Tennis")
        case .squash: ("SPORT", "Squash")
        case .hockey: ("SPORT", "Hockey")
        case .soccer: ("SPORT", "Football")
        case .basketball: ("SPORT", "Basketball")
        case .cricket: ("SPORT", "Cricket")
        case .rugby: ("SPORT", "Rugby")
        case .boxing: ("WORKOUT", "Boxing")
        case .climbing: ("WORKOUT", "Climbing")
        case .golf: ("SPORT", "Golf")
        case .socialDance, .cardioDance: ("WORKOUT", "Dance")
        default: ("WORKOUT", "Workout")
        }
    }

    /// Collects one day's values before they become a row.
    private nonisolated final class Builder {
        let date: String
        var steps: Int?
        var activeKcal: Double?
        var hrAvg: Double?
        var hrMax: Double?
        var zoneSeconds: [String: Double]?
        var restingHr: Double?
        var hrv: Double?
        var respiratoryRate: Double?
        var spo2: Double?
        var skinTemp: Double?
        var vo2max: Double?
        var sleep: DailyRecordRow.Sleep?
        var exercises: [DailyRecordRow.Exercise] = []

        init(date: String) { self.date = date }

        var row: DailyRecordRow {
            DailyRecordRow(
                date: date, steps: steps, activeKcal: activeKcal, hrAvg: hrAvg, hrMax: hrMax,
                zoneSeconds: zoneSeconds, restingHr: restingHr, hrv: hrv, respiratoryRate: respiratoryRate,
                spo2: spo2, skinTemp: skinTemp, vo2max: vo2max, sleep: sleep,
                exercises: exercises.isEmpty ? nil : exercises
            )
        }
    }
}

/// Combines Google Health and Apple Health records.
///
/// Each kind of reading comes from one source for the whole history, never mixed day by day:
/// mixing would blend HRV measured two different ways (Google reports RMSSD, Apple SDNN) into
/// one baseline, and could count the same steps twice. Google is preferred, since it's the
/// wearable Corva was set up with; Apple Health is used for a reading when Google has less
/// than half as many days of it.
nonisolated enum DailyRecordMerger {
    static func merge(google: [DailyRecordRow], apple: [DailyRecordRow]) -> [DailyRecordRow] {
        if apple.isEmpty { return google }
        if google.isEmpty { return apple }

        func useApple<T>(_ field: (DailyRecordRow) -> T?) -> Bool {
            let googleDays = google.count { field($0) != nil }
            let appleDays = apple.count { field($0) != nil }
            return googleDays * 2 < appleDays
        }
        let steps = useApple(\.steps)
        let energy = useApple(\.activeKcal)
        let heart = useApple(\.hrAvg)
        let zones = useApple(\.zoneSeconds)
        let resting = useApple(\.restingHr)
        let hrv = useApple(\.hrv)
        let breathing = useApple(\.respiratoryRate)
        let oxygen = useApple(\.spo2)
        let temperature = useApple(\.skinTemp)
        let vo2 = useApple(\.vo2max)
        let sleep = useApple(\.sleep)
        let workouts = useApple(\.exercises)

        let googleByDate = Dictionary(google.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        let appleByDate = Dictionary(apple.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        return Set(googleByDate.keys).union(appleByDate.keys).sorted().map { date in
            let g = googleByDate[date]
            let a = appleByDate[date]
            func pick<T>(_ fromApple: Bool, _ field: (DailyRecordRow) -> T?) -> T? {
                fromApple ? a.flatMap(field) : g.flatMap(field)
            }
            return DailyRecordRow(
                date: date,
                steps: pick(steps, \.steps),
                activeKcal: pick(energy, \.activeKcal),
                hrAvg: pick(heart, \.hrAvg),
                hrMax: pick(heart, \.hrMax),
                zoneSeconds: pick(zones, \.zoneSeconds),
                restingHr: pick(resting, \.restingHr),
                hrv: pick(hrv, \.hrv),
                respiratoryRate: pick(breathing, \.respiratoryRate),
                spo2: pick(oxygen, \.spo2),
                skinTemp: pick(temperature, \.skinTemp),
                vo2max: pick(vo2, \.vo2max),
                sleep: pick(sleep, \.sleep),
                exercises: pick(workouts, \.exercises)
            )
        }
    }
}
