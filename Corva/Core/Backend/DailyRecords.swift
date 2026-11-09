import Foundation

// Real data: the `daily_records` rows the google-health function writes, turned into the
// app's `DailySummary` with the same scoring the mock data uses.

/// One `daily_records` row, decoded with snake_case keys converted to camelCase.
nonisolated struct DailyRecordRow: Decodable, Sendable {
    let date: String
    let steps: Int?
    let activeKcal: Double?
    let hrAvg: Double?
    let hrMax: Double?
    let zoneSeconds: [String: Double]?
    let restingHr: Double?
    let hrv: Double?
    let respiratoryRate: Double?
    let spo2: Double?
    let skinTemp: Double?
    let vo2max: Double?
    let sleep: Sleep?
    let exercises: [Exercise]?

    struct Sleep: Decodable, Sendable {
        let start: String
        let end: String
        let stages: [Stage]?
        /// Google's own total, which accounts for gaps between stages.
        let minutesAsleep: Double?

        struct Stage: Decodable, Sendable {
            let type: String
            let start: String
            let end: String
        }
    }

    struct Exercise: Decodable, Sendable {
        let id: String?
        let type: String?
        let name: String?
        let start: String
        let end: String
        let seconds: Double?
        let kcal: Double?
        let distanceM: Double?
        let avgHr: Double?
    }
}

/// Builds summaries day by day, oldest first, carrying forward what the scoring needs: the
/// 30-day baseline, the previous day's strain and running sleep debt.
///
/// A day is summarised only if it has a night of sleep, HRV and resting heart rate. Without
/// those there's no recovery score, so the day is left out rather than half-filled.
nonisolated enum DailyRecordMapper {
    /// Corva's zones 2-5 from Google's four. Zone 1 (everyday movement) isn't reported.
    static let zoneMap: [String: HeartRateZone] = ["LIGHT": .two, "MODERATE": .three, "VIGOROUS": .four, "PEAK": .five]

    static func summaries(from rows: [DailyRecordRow], calendar: Calendar = .current) -> [DailySummary] {
        var summaries: [DailySummary] = []
        var previousStrain = 35
        var sleepDebt: TimeInterval = 0

        for row in rows.sorted(by: { $0.date < $1.date }) {
            guard let date = DayCoding.date(from: row.date, calendar: calendar) else { continue }
            let strain = strainMetrics(for: row, day: date)
            defer { previousStrain = strain.score }

            guard let hrv = row.hrv, let restingHeartRate = row.restingHr,
                  let night = row.sleep,
                  let bedtime = ISODate.parse(night.start), let wakeTime = ISODate.parse(night.end),
                  wakeTime > bedtime else { continue }

            // The baseline is the 30 calendar days before, so a gap doesn't stretch it.
            let baseline = Baseline(history: Baseline.window(before: date, in: summaries, calendar: calendar))
            let need = Scoring.sleepNeed(previousStrain: previousStrain, sleepDebt: sleepDebt)
            let stages = stagedSegments(for: night)
            // Classic sleep has no stages: one block, counted as asleep, and marked so the UI
            // doesn't present it as a night of light sleep.
            let segments = stages.isEmpty ? [SleepSegment(stage: .light, start: bedtime, end: wakeTime)] : stages
            let timeAsleep = night.minutesAsleep.map { $0 * 60 }
                ?? segments.filter(\.stage.isAsleep).reduce(0) { $0 + $1.duration }
            let sleep = SleepMetrics(
                score: Scoring.sleepScore(timeAsleep: timeAsleep, need: need),
                bedtime: bedtime,
                wakeTime: wakeTime,
                need: need,
                segments: segments,
                reportedTimeAsleep: night.minutesAsleep.map { $0 * 60 },
                hasStages: !stages.isEmpty,
                debtRepayment: Scoring.debtRepayment(sleepDebt: sleepDebt)
            )
            let vitals = Vitals(
                hrv: hrv,
                restingHeartRate: restingHeartRate,
                respiratoryRate: row.respiratoryRate,
                bloodOxygen: row.spo2,
                skinTemperature: row.skinTemp,
                vo2Max: row.vo2max
            )
            let recovery = Scoring.recovery(
                hrv: hrv,
                hrvBaseline: baseline[.hrv]?.mean ?? hrv,
                restingHeartRate: restingHeartRate,
                restingHeartRateBaseline: baseline[.restingHeartRate]?.mean ?? restingHeartRate,
                sleepScore: sleep.score
            )

            summaries.append(DailySummary(
                date: date,
                recovery: RecoveryMetrics(score: recovery),
                strain: strain,
                sleep: sleep,
                vitals: vitals,
                baseline: baseline
            ))

            let needBeforeDebt = Scoring.sleepNeed(previousStrain: previousStrain, sleepDebt: 0)
            sleepDebt = min(max(sleepDebt * 0.6 + needBeforeDebt - timeAsleep, 0), 4 * 3600)
        }
        return summaries
    }

    // MARK: - Pieces

    private static func strainMetrics(for row: DailyRecordRow, day: Date) -> StrainMetrics {
        let zones = HeartRateZone.allCases.map { zone in
            let seconds = row.zoneSeconds?.reduce(0.0) { total, entry in
                zoneMap[entry.key] == zone ? total + entry.value : total
            } ?? 0
            return ZoneDuration(zone: zone, duration: seconds)
        }
        return StrainMetrics(
            score: Scoring.strain(zones: zones),
            heartRateZones: zones,
            activities: (row.exercises ?? []).compactMap(activity(from:)).sorted { $0.start < $1.start },
            activeEnergy: row.activeKcal ?? 0,
            averageHeartRate: Int((row.hrAvg ?? 0).rounded()),
            maxHeartRate: Int((row.hrMax ?? 0).rounded()),
            steps: row.steps ?? 0
        )
    }

    /// The night's stages in order. Empty for classic sleep, which has none.
    private static func stagedSegments(for sleep: DailyRecordRow.Sleep) -> [SleepSegment] {
        (sleep.stages ?? []).compactMap { stage -> SleepSegment? in
            guard let from = ISODate.parse(stage.start), let to = ISODate.parse(stage.end), to > from else { return nil }
            return SleepSegment(stage: sleepStage(stage.type), start: from, end: to)
        }
        .sorted { $0.start < $1.start }
    }

    private static func sleepStage(_ type: String) -> SleepStage {
        switch type {
        case "DEEP": .deep
        case "REM": .rem
        case "AWAKE", "RESTLESS": .awake
        default: .light // LIGHT, and ASLEEP from classic sleep
        }
    }

    /// Google reports a workout's average heart rate, not its zones, so the whole session is
    /// placed in the zone its average falls in. Max heart rate is estimated at 190.
    private static func activity(from exercise: DailyRecordRow.Exercise) -> Activity? {
        guard let start = ISODate.parse(exercise.start), let end = ISODate.parse(exercise.end) else { return nil }
        let duration = exercise.seconds ?? end.timeIntervalSince(start)
        let averageHeartRate = exercise.avgHr ?? 0
        let fraction = averageHeartRate / 190
        let zone = HeartRateZone.allCases.last { fraction >= $0.bounds.lowerBound } ?? .one
        let zones = HeartRateZone.allCases.map { ZoneDuration(zone: $0, duration: $0 == zone && averageHeartRate > 0 ? duration : 0) }
        return Activity(
            id: exercise.id ?? exercise.start,
            kind: activityKind(exercise.type),
            start: start,
            duration: duration,
            strain: averageHeartRate > 0 ? Scoring.strain(zones: zones) : 0,
            averageHeartRate: Int(averageHeartRate.rounded()),
            maxHeartRate: 0,
            energy: exercise.kcal ?? 0,
            distance: exercise.distanceM,
            heartRateZones: zones,
            name: exercise.name.flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    private static func activityKind(_ type: String?) -> ActivityKind {
        let type = type ?? ""
        if type.contains("RUN") { return .run }
        if type.contains("BIK") || type.contains("CYCL") || type.contains("SPINNING") { return .ride }
        if type.contains("WEIGHT") || type.contains("STRENGTH") || type.contains("CIRCUIT") { return .strength }
        if type.contains("WALK") || type.contains("HIK") { return .walk }
        if type.contains("SWIM") { return .swim }
        if type.contains("YOGA") || type.contains("PILATES") { return .yoga }
        return .other
    }
}

/// RFC 3339 timestamps, with or without fractional seconds (Postgres sends microseconds).
nonisolated enum ISODate {
    static func parse(_ string: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) { return date }
        if let date = try? Date.ISO8601FormatStyle().parse(string) { return date }
        // Drop the fraction and try again: "2026-11-09T00:30:24.207578+00:00" → "…:24+00:00".
        let trimmed = string.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return try? Date.ISO8601FormatStyle().parse(trimmed)
    }
}

/// Holds the last pull of daily records and the summaries built from them, so every screen
/// doesn't refetch. Refreshed after five minutes or when the data changes (a sync, a source
/// connected or disconnected).
actor DailyRecordCache {
    /// Enough for 90-day screens plus a 30-day baseline warm-up.
    static let windowDays = 130

    /// Reads the records from `from` (a yyyy-MM-dd day) onwards, from every connected source.
    typealias Fetch = @MainActor @Sendable (_ from: String) async throws -> [DailyRecordRow]

    private var summaries: [DailySummary]?
    private var fetchedAt: Date?
    /// The load in progress, shared by every screen that asks meanwhile.
    private var loading: Task<[DailySummary], Error>?
    /// Bumped by `invalidate()`, so a load that started before it isn't kept.
    private var generation = 0

    func allSummaries(fetch: @escaping Fetch) async throws -> [DailySummary] {
        if let summaries, let fetchedAt, Date.now.timeIntervalSince(fetchedAt) < 300 {
            return summaries
        }
        if let loading { return try await loading.value }

        let calendar = Calendar.current
        let from = calendar.date(byAdding: .day, value: -Self.windowDays, to: calendar.startOfDay(for: .now)) ?? .now
        let task = Task {
            let rows = try await fetch(DayCoding.string(from: from, calendar: calendar))
            return DailyRecordMapper.summaries(from: rows, calendar: calendar)
        }
        let started = generation
        loading = task
        do {
            let built = try await task.value
            if generation == started {
                summaries = built
                fetchedAt = .now
                loading = nil
            }
            return built
        } catch {
            if generation == started { loading = nil }
            throw error
        }
    }

    /// When the summaries were last built, if they're still held.
    var lastFetched: Date? { fetchedAt }

    func invalidate() {
        generation += 1
        summaries = nil
        fetchedAt = nil
        loading = nil
    }
}

/// Health data from the user's own records: Google Health synced to their account, Apple
/// Health on this phone, or both.
nonisolated struct RemoteHealthDataProvider: HealthDataProvider {
    let cache: DailyRecordCache
    let fetch: DailyRecordCache.Fetch
    let status: @Sendable (DataSource) async -> ConnectionStatus

    func summaries(from start: Date, through end: Date) async throws -> [DailySummary] {
        try await cache.allSummaries(fetch: fetch).filter { $0.date >= start && $0.date <= end }
    }

    func connectionStatus(for source: DataSource) async -> ConnectionStatus {
        await status(source)
    }
}
