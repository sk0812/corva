import Foundation

// Rows as the database stores them, and the mapping to and from the app's models. Column
// names are snake_case; text values match the Swift raw values.

/// `date` columns travel as "2026-11-09", in the user's own calendar and time zone, because a
/// pact day or an experiment evening is a local day, not an instant.
nonisolated enum DayCoding {
    static func string(from date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 1, parts.day ?? 1)
    }

    static func date(from string: String, calendar: Calendar = .current) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

// MARK: - Profile

nonisolated struct ProfileRecord: Codable, Sendable {
    var displayName: String?
    var birthYear: Int?
    var sex: String
    var currency: String
    var appearance: String
    var temperatureUnit: String
    var distanceUnit: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case birthYear = "birth_year"
        case sex, currency, appearance
        case temperatureUnit = "temperature_unit"
        case distanceUnit = "distance_unit"
    }
}

// MARK: - Experiments

nonisolated struct ExperimentRecord: Codable, Sendable {
    let id: UUID
    let title: String
    let design: String
    let startDate: String
    let lengthDays: Int
    let outcomes: [String]

    enum CodingKeys: String, CodingKey {
        case id, title, design, outcomes
        case startDate = "start_date"
        case lengthDays = "length_days"
    }

    init(_ experiment: Experiment) {
        id = experiment.id
        title = experiment.title
        design = experiment.design.rawValue
        startDate = DayCoding.string(from: experiment.start)
        lengthDays = experiment.length
        outcomes = experiment.outcomes.map(\.rawValue)
    }
}

/// An experiment with its tags, as read back.
nonisolated struct ExperimentRow: Decodable, Sendable {
    let id: UUID
    let title: String
    let design: String
    let startDate: String
    let lengthDays: Int
    let outcomes: [String]
    let tags: [Tag]

    struct Tag: Decodable, Sendable {
        let evening: String
    }

    enum CodingKeys: String, CodingKey {
        case id, title, design, outcomes
        case startDate = "start_date"
        case lengthDays = "length_days"
        case tags = "experiment_tags"
    }

    /// The select clause that produces this shape.
    static let select = "id,title,design,start_date,length_days,outcomes,experiment_tags(evening)"

    var experiment: Experiment? {
        guard let design = Experiment.Design(rawValue: design),
              let start = DayCoding.date(from: startDate) else { return nil }
        return Experiment(
            id: id,
            title: title,
            design: design,
            start: start,
            length: lengthDays,
            outcomes: outcomes.compactMap(Metric.init(rawValue:)),
            taggedEvenings: Set(tags.compactMap { DayCoding.date(from: $0.evening) })
        )
    }
}

nonisolated struct ExperimentTagRecord: Codable, Sendable {
    let experimentID: UUID
    let evening: String

    enum CodingKeys: String, CodingKey {
        case experimentID = "experiment_id"
        case evening
    }
}

nonisolated struct SoftDeleteRecord: Encodable, Sendable {
    let deletedAt: String

    enum CodingKeys: String, CodingKey {
        case deletedAt = "deleted_at"
    }

    init(now: Date = .now) {
        deletedAt = now.ISO8601Format()
    }
}

// MARK: - Pacts

/// A new pact as sent to the server. Status is set by the database.
nonisolated struct NewPactRecord: Encodable, Sendable {
    let id: UUID
    let goal: String
    let target: Double
    let startDate: String
    let lengthDays: Int
    let requiredDays: Int
    let stake: Int
    let currency: String
    let mode: String
    let recipientKind: String?
    let recipientName: String?
    let opponentName: String?
    let sickDayPass: Bool

    enum CodingKeys: String, CodingKey {
        case id, goal, target, stake, currency, mode
        case startDate = "start_date"
        case lengthDays = "length_days"
        case requiredDays = "required_days"
        case recipientKind = "recipient_kind"
        case recipientName = "recipient_name"
        case opponentName = "opponent_name"
        case sickDayPass = "sick_day_pass"
    }

    init(_ pact: Pact) {
        id = pact.id
        goal = pact.goal.rawValue
        target = pact.target
        startDate = DayCoding.string(from: pact.start)
        lengthDays = pact.length
        requiredDays = pact.requiredDays
        stake = pact.stake
        currency = pact.currencyCode
        switch pact.mode {
        case .solo(let recipient):
            mode = "solo"
            switch recipient {
            case .friend(let name): (recipientKind, recipientName) = ("friend", name)
            case .charity(let name): (recipientKind, recipientName) = ("charity", name)
            }
            opponentName = nil
        case .headToHead(let friend):
            mode = "headToHead"
            recipientKind = nil
            recipientName = nil
            opponentName = friend
        }
        sickDayPass = pact.sickDayPass
    }
}

nonisolated struct PactRow: Decodable, Sendable {
    let id: UUID
    let creatorID: UUID
    let creatorName: String?
    let goal: String
    let target: Double
    let startDate: String
    let lengthDays: Int
    let requiredDays: Int
    let stake: Int
    let currency: String
    let mode: String
    let recipientKind: String?
    let recipientName: String?
    let opponentName: String?
    let sickDayPass: Bool
    let status: String

    enum CodingKeys: String, CodingKey {
        case id, goal, target, stake, currency, mode, status
        case creatorID = "creator_id"
        case creatorName = "creator_name"
        case startDate = "start_date"
        case lengthDays = "length_days"
        case requiredDays = "required_days"
        case recipientKind = "recipient_kind"
        case recipientName = "recipient_name"
        case opponentName = "opponent_name"
        case sickDayPass = "sick_day_pass"
    }

    /// The app's pact, seen from `me`'s side: for the friend who joined, the "friend" is the
    /// creator.
    func pact(for me: UUID, inviteCode: String?, participantCount: Int) -> Pact? {
        guard let goal = Pact.Goal(rawValue: goal), let start = DayCoding.date(from: startDate) else { return nil }
        let isCreator = creatorID == me
        let mode: Pact.Mode
        if self.mode == "headToHead" {
            mode = .headToHead(friend: isCreator ? (opponentName ?? "Your friend") : (creatorName ?? "Your friend"))
        } else if recipientKind == "charity" {
            mode = .solo(.charity(recipientName ?? "Charity"))
        } else {
            mode = .solo(.friend(recipientName ?? "Your friend"))
        }
        return Pact(
            id: id,
            goal: goal,
            target: target,
            start: start,
            length: lengthDays,
            requiredDays: requiredDays,
            stake: stake,
            currencyCode: currency,
            mode: mode,
            sickDayPass: sickDayPass,
            sync: Pact.Sync(
                status: Pact.Sync.Status(rawValue: status) ?? .active,
                inviteCode: inviteCode,
                isCreator: isCreator,
                friendJoined: participantCount > 1
            )
        )
    }
}

nonisolated struct PactInviteRow: Decodable, Sendable {
    let pactID: UUID
    let code: String

    enum CodingKeys: String, CodingKey {
        case pactID = "pact_id"
        case code
    }
}

nonisolated struct PactParticipantRow: Decodable, Sendable {
    let pactID: UUID

    enum CodingKeys: String, CodingKey {
        case pactID = "pact_id"
    }
}

nonisolated struct NewInviteRecord: Encodable, Sendable {
    let pactID: UUID

    enum CodingKeys: String, CodingKey {
        case pactID = "pact_id"
    }
}

nonisolated struct InviteCodeArgument: Encodable, Sendable {
    let inviteCode: String

    enum CodingKeys: String, CodingKey {
        case inviteCode = "invite_code"
    }
}

/// What an invite shows before it's accepted.
nonisolated struct PactInvitePreview: Decodable, Hashable, Sendable {
    let pactID: UUID
    let goal: String
    let target: Double
    let startDate: String
    let lengthDays: Int
    let requiredDays: Int
    let stake: Int
    let currency: String
    let sickDayPass: Bool
    let inviterName: String?

    enum CodingKeys: String, CodingKey {
        case goal, target, stake, currency
        case pactID = "pact_id"
        case startDate = "start_date"
        case lengthDays = "length_days"
        case requiredDays = "required_days"
        case sickDayPass = "sick_day_pass"
        case inviterName = "inviter_name"
    }
}
