import AuthenticationServices
import Foundation
import Observation

/// The signed-in account: signing in and out, and keeping experiments, pacts and settings in
/// step with the backend.
///
/// - **Signed out:** Lab and Pacts show demo data.
/// - **Signing in:** the account's own experiments and pacts replace the demo data. Health data
///   stays mock until Apple Health is connected.
/// - **Local changes:** pushed as they happen, one at a time and in order, so a tag never
///   arrives before its experiment.
/// - **Full pull:** at sign-in, at launch, and from Settings › Sync now.
@Observable
final class AccountService {
    private(set) var user: AuthUser?
    /// A sign-in or a full sync is in progress.
    private(set) var isWorking = false
    private(set) var lastSynced: Date?
    private(set) var lastError: String?
    /// The Google Health connection as the server reports it. Nil until checked.
    private(set) var googleHealth: GoogleHealthStatus?
    /// Why the last attempt to connect Google Health failed, shown beside the Connect button.
    private(set) var googleHealthConnectError: String?
    /// Bumped when real data changes underneath the screens (connect, sync, disconnect), so
    /// they reload.
    private(set) var dataVersion = 0

    var isSignedIn: Bool { user != nil }

    /// Real data needs an account with Google Health connected; otherwise screens show demo data.
    var usesRealData: Bool { isSignedIn && googleHealth?.connected == true }

    /// Where every screen's health data comes from right now.
    var healthDataProvider: any HealthDataProvider {
        guard usesRealData else { return demoProvider }
        let status = googleHealth
        return RemoteHealthDataProvider(cache: recordCache) { source in
            source == .googleHealth ? .connected(lastSync: status?.lastSynced ?? .now) : .notConnected
        }
    }

    @ObservationIgnored private let client: SupabaseClient
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let experiments: ExperimentStore
    @ObservationIgnored private let pacts: PactStore
    @ObservationIgnored private let demoExperiments: [Experiment]
    @ObservationIgnored private let demoPacts: [Pact]
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private var profilePush: Task<Void, Never>?
    @ObservationIgnored private let demoProvider: any HealthDataProvider
    @ObservationIgnored private let recordCache: DailyRecordCache

    init(
        client: SupabaseClient,
        settings: AppSettings,
        experiments: ExperimentStore,
        pacts: PactStore,
        demoProvider: any HealthDataProvider
    ) {
        self.client = client
        self.demoProvider = demoProvider
        let fetchRecords: @MainActor @Sendable (String) async throws -> [DailyRecordRow] = { [client] from in
            try await client.select("daily_records", query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "source", value: "eq.google_health"),
                URLQueryItem(name: "date", value: "gte.\(from)"),
                URLQueryItem(name: "order", value: "date.asc"),
            ], as: DailyRecordRow.self, convertingSnakeCase: true)
        }
        recordCache = DailyRecordCache(fetch: fetchRecords)
        self.settings = settings
        self.experiments = experiments
        self.pacts = pacts
        demoExperiments = experiments.experiments
        demoPacts = pacts.pacts
        user = client.session?.user
        experiments.remote = self
        pacts.remote = self
        if user != nil {
            experiments.replace(with: [])
            pacts.replace(with: [])
        }
    }

    /// At launch: pull everything if a session was restored.
    func start() async {
        guard isSignedIn else { return }
        await refresh()
    }

    // MARK: - Signing in and out

    /// `authenticate` opens the sign-in page in a web authentication session and returns the
    /// callback URL.
    func signInWithGoogle(authenticate: (URL) async throws -> URL) async {
        await signIn {
            let callback = try await authenticate(client.googleSignInURL())
            return try await client.completeOAuthSignIn(callbackURL: callback)
        }
    }

    /// Emails a one-time code. Returns whether it was sent.
    func sendEmailCode(to email: String) async -> Bool {
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            try await client.sendEmailCode(to: email)
            return true
        } catch {
            record(error)
            return false
        }
    }

    /// Returns whether the code was right and the user is now signed in.
    func verifyEmailCode(_ code: String, email: String) async -> Bool {
        await signIn { try await client.verifyEmailCode(code, email: email) }
    }

    func signOut() async {
        queue?.cancel()
        profilePush?.cancel()
        await client.signOut()
        user = nil
        lastSynced = nil
        lastError = nil
        googleHealth = nil
        experiments.replace(with: demoExperiments)
        pacts.replace(with: demoPacts)
        await dataChanged()
    }

    @discardableResult
    private func signIn(_ operation: () async throws -> AuthUser) async -> Bool {
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            user = try await operation()
        } catch {
            record(error)
            return false
        }
        experiments.replace(with: [])
        pacts.replace(with: [])
        await refresh(isFirstSignIn: true)
        return true
    }

    // MARK: - Pulling

    /// Pulls the profile, experiments and pacts. Pending pushes finish first.
    func refresh(isFirstSignIn: Bool = false) async {
        guard let user else { return }
        isWorking = true
        defer { isWorking = false }
        await queue?.value
        do {
            try await loadGoogleHealthStatus()
            try await pullProfile(pushLocalIfNew: isFirstSignIn)
            let rows = try await client.select("experiments", query: [
                URLQueryItem(name: "select", value: ExperimentRow.select),
                URLQueryItem(name: "deleted_at", value: "is.null"),
                URLQueryItem(name: "order", value: "created_at.desc"),
            ], as: ExperimentRow.self)
            experiments.replace(with: rows.compactMap(\.experiment))
            try await pullPacts(for: user.id)
            lastSynced = .now
            lastError = nil
        } catch {
            record(error)
        }
    }

    private func pullProfile(pushLocalIfNew: Bool) async throws {
        let rows = try await client.select("profiles", query: [URLQueryItem(name: "select", value: "*")], as: ProfileRecord.self)
        guard let remote = rows.first else { return }
        // A brand-new account has no birth year yet: keep this phone's settings and send them up.
        if remote.birthYear == nil && pushLocalIfNew {
            pushProfile()
            return
        }
        settings.sex = BiologicalSex(rawValue: remote.sex) ?? settings.sex
        settings.currencyCode = remote.currency
        settings.appearance = AppSettings.Appearance(rawValue: remote.appearance) ?? settings.appearance
        settings.temperatureUnit = TemperatureUnit(rawValue: remote.temperatureUnit) ?? settings.temperatureUnit
        settings.distanceUnit = DistanceUnit(rawValue: remote.distanceUnit) ?? settings.distanceUnit
        if let birthYear = remote.birthYear {
            settings.age = min(max(currentYear - birthYear, 18), 90)
        }
    }

    private func pullPacts(for me: UUID) async throws {
        let rows = try await client.select("pacts", query: [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "status", value: "neq.cancelled"),
            URLQueryItem(name: "order", value: "created_at.desc"),
        ], as: PactRow.self)
        let invites = try await client.select("pact_invites", query: [URLQueryItem(name: "select", value: "pact_id,code")], as: PactInviteRow.self)
        let participants = try await client.select("pact_participants", query: [URLQueryItem(name: "select", value: "pact_id")], as: PactParticipantRow.self)
        let codes = Dictionary(invites.map { ($0.pactID, $0.code) }, uniquingKeysWith: { first, _ in first })
        let counts = Dictionary(grouping: participants, by: \.pactID).mapValues(\.count)
        var loaded = rows.compactMap { row in
            row.pact(for: me, inviteCode: codes[row.id], participantCount: counts[row.id] ?? 1)
        }
        // Everyone's values for each running or finished pact, scored from server data.
        for index in loaded.indices where loaded[index].sync?.status != .pending {
            let progress = try await client.rpc(
                "pact_progress",
                PactArgument(targetPact: loaded[index].id),
                returning: [PactProgressRow].self
            )
            var own: [Date: Double] = [:]
            var friend: [Date: Double] = [:]
            for row in progress {
                guard let day = DayCoding.date(from: row.day), let value = row.value else { continue }
                if row.userID == me { own[day] = value } else { friend[day] = value }
            }
            loaded[index].ownValues = own
            loaded[index].friendValues = friend
        }
        pacts.replace(with: loaded)
    }

    // MARK: - Google Health

    /// Connects Google Health: the server makes the consent link, `authenticate` shows it,
    /// and the server stores the tokens and starts pulling history.
    func connectGoogleHealth(authenticate: (URL) async throws -> URL) async {
        isWorking = true
        googleHealthConnectError = nil
        defer { isWorking = false }
        do {
            let response = try await client.function("google-health/connect", EmptyRequest(), returning: ConnectResponse.self)
            let callback = try await authenticate(response.url)
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard items.first(where: { $0.name == "status" })?.value == "connected" else {
                googleHealthConnectError = items.first(where: { $0.name == "message" })?.value ?? "Google Health didn’t connect. Try again."
                // A refused connection is removed on the server; reflect that here.
                try? await loadGoogleHealthStatus()
                return
            }
            try await loadGoogleHealthStatus()
            // The first pull of history runs on the server; wait for it (up to a minute and a half).
            for _ in 0..<30 where googleHealth?.lastSynced == nil && googleHealth?.lastError == nil {
                try await Task.sleep(for: .seconds(3))
                try await loadGoogleHealthStatus()
            }
            await dataChanged()
            await refresh()
        } catch {
            if let authError = error as? ASWebAuthenticationSessionError, authError.code == .canceledLogin { return }
            googleHealthConnectError = error.localizedDescription
        }
    }

    /// Pulls the last `days` days from Google now.
    func syncGoogleHealth(days: Int = 7) async {
        guard usesRealData else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await client.function("google-health/sync", SyncRequest(days: days), returning: SyncResponse.self)
            try await loadGoogleHealthStatus()
            await dataChanged()
        } catch {
            record(error)
            try? await loadGoogleHealthStatus()
        }
    }

    /// When the app comes to the foreground: sync if the last one was over 30 minutes ago.
    func syncIfStale() async {
        guard usesRealData, !isWorking else { return }
        if let last = googleHealth?.lastSynced, Date.now.timeIntervalSince(last) < 30 * 60 { return }
        await syncGoogleHealth(days: 3)
    }

    /// Revokes Google's access and deletes the synced data from the server.
    func disconnectGoogleHealth() async {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await client.function("google-health/disconnect", EmptyRequest(), returning: DisconnectResponse.self)
            googleHealth = GoogleHealthStatus(connected: false)
            await dataChanged()
        } catch {
            record(error)
        }
    }

    private func loadGoogleHealthStatus() async throws {
        let rows = try await client.rpc("google_health_status", EmptyRequest(), returning: [GoogleHealthStatusRow].self)
        googleHealth = rows.first.map(GoogleHealthStatus.init) ?? GoogleHealthStatus(connected: false)
    }

    private func dataChanged() async {
        await recordCache.invalidate()
        dataVersion += 1
    }

    // MARK: - Settings

    /// Call when a synced setting changes. Pushes a second later, so a run of taps on the
    /// age stepper sends one update.
    func settingsChanged() {
        guard isSignedIn else { return }
        profilePush?.cancel()
        profilePush = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            pushProfile()
        }
    }

    private func pushProfile() {
        guard let user else { return }
        let record = ProfileRecord(
            displayName: nil,
            birthYear: currentYear - settings.age,
            sex: settings.sex.rawValue,
            currency: settings.currencyCode,
            appearance: settings.appearance.rawValue,
            temperatureUnit: settings.temperatureUnit.rawValue,
            distanceUnit: settings.distanceUnit.rawValue
        )
        enqueue { [client] in
            try await client.update("profiles", record, filters: [URLQueryItem(name: "id", value: "eq.\(user.id.uuidString)")])
        }
    }

    private var currentYear: Int { Calendar.current.component(.year, from: .now) }

    // MARK: - Joining a friend's pact

    func previewInvite(code: String) async throws -> PactInvitePreview? {
        let rows = try await client.rpc(
            "preview_pact_invite",
            InviteCodeArgument(inviteCode: Self.normalized(code)),
            returning: [PactInvitePreview].self
        )
        return rows.first
    }

    func acceptInvite(code: String) async throws {
        _ = try await client.rpc("accept_pact_invite", InviteCodeArgument(inviteCode: Self.normalized(code)), returning: UUID.self)
        await refresh()
    }

    private static func normalized(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Pushing

    /// Runs `operation` after every earlier push has finished.
    private func enqueue(_ operation: @escaping @MainActor () async throws -> Void) {
        guard isSignedIn else { return }
        let previous = queue
        queue = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            do {
                try await operation()
                lastSynced = .now
            } catch {
                record(error)
            }
        }
    }

    private func record(_ error: Error) {
        if let authError = error as? ASWebAuthenticationSessionError, authError.code == .canceledLogin {
            return
        }
        if error is CancellationError { return }
        if let backendError = error as? BackendError, backendError == .notSignedIn, user != nil {
            // The session expired or was revoked elsewhere.
            user = nil
            experiments.replace(with: demoExperiments)
            pacts.replace(with: demoPacts)
            lastError = "You were signed out. Sign in again to sync."
            return
        }
        lastError = error.localizedDescription
    }
}

extension AccountService: ExperimentSyncing {
    func experimentSaved(_ experiment: Experiment) {
        let record = ExperimentRecord(experiment)
        enqueue { [client] in
            try await client.upsert("experiments", [record], onConflict: "id")
        }
    }

    func experimentDeleted(_ id: Experiment.ID) {
        enqueue { [client] in
            try await client.update("experiments", SoftDeleteRecord(), filters: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")])
        }
    }

    func experimentTag(evening: Date, isOn: Bool, in id: Experiment.ID) {
        let record = ExperimentTagRecord(experimentID: id, evening: DayCoding.string(from: evening))
        enqueue { [client] in
            if isOn {
                try await client.upsert("experiment_tags", [record], onConflict: "experiment_id,evening", ignoreDuplicates: true)
            } else {
                try await client.delete("experiment_tags", filters: [
                    URLQueryItem(name: "experiment_id", value: "eq.\(id.uuidString)"),
                    URLQueryItem(name: "evening", value: "eq.\(record.evening)"),
                ])
            }
        }
    }
}

extension AccountService: PactSyncing {
    var isConnected: Bool { isSignedIn }

    func pactCreated(_ pact: Pact) {
        guard let me = user?.id else { return }
        let record = NewPactRecord(pact)
        let isHeadToHead = record.mode == "headToHead"
        enqueue { [client, pacts] in
            let saved = try await client.insert("pacts", [record], returning: PactRow.self)
            guard let row = saved.first else { return }
            var code: String?
            if isHeadToHead {
                let invites = try await client.insert("pact_invites", [NewInviteRecord(pactID: row.id)], returning: PactInviteRow.self)
                code = invites.first?.code
            }
            if let updated = row.pact(for: me, inviteCode: code, participantCount: 1) {
                pacts.update(updated)
            }
        }
    }
}

// MARK: - Google Health status and requests

nonisolated struct GoogleHealthStatus: Hashable, Sendable {
    var connected: Bool
    var connectedAt: Date?
    var lastSynced: Date?
    var lastError: String?
    /// While the Google project is in Testing, access lapses after 7 days.
    var expiresAt: Date?

    init(connected: Bool, connectedAt: Date? = nil, lastSynced: Date? = nil, lastError: String? = nil, expiresAt: Date? = nil) {
        self.connected = connected
        self.connectedAt = connectedAt
        self.lastSynced = lastSynced
        self.lastError = lastError
        self.expiresAt = expiresAt
    }

    init(_ row: GoogleHealthStatusRow) {
        self.init(
            connected: row.connected ?? false,
            connectedAt: row.connectedAt.flatMap(ISODate.parse),
            lastSynced: row.lastSyncedAt.flatMap(ISODate.parse),
            lastError: row.lastError,
            expiresAt: row.refreshTokenExpiresAt.flatMap(ISODate.parse)
        )
    }
}

nonisolated struct GoogleHealthStatusRow: Decodable, Sendable {
    let connected: Bool?
    let connectedAt: String?
    let lastSyncedAt: String?
    let lastError: String?
    let refreshTokenExpiresAt: String?

    enum CodingKeys: String, CodingKey {
        case connected
        case connectedAt = "connected_at"
        case lastSyncedAt = "last_synced_at"
        case lastError = "last_error"
        case refreshTokenExpiresAt = "refresh_token_expires_at"
    }
}

private nonisolated struct EmptyRequest: Encodable, Sendable {}

private nonisolated struct ConnectResponse: Decodable, Sendable {
    let url: URL
}

private nonisolated struct SyncRequest: Encodable, Sendable {
    let days: Int
}

private nonisolated struct SyncResponse: Decodable, Sendable {
    let days: Int
}

private nonisolated struct DisconnectResponse: Decodable, Sendable {
    let disconnected: Bool
}

private nonisolated struct PactArgument: Encodable, Sendable {
    let targetPact: UUID

    enum CodingKeys: String, CodingKey {
        case targetPact = "target_pact"
    }
}

private nonisolated struct PactProgressRow: Decodable, Sendable {
    let userID: UUID
    let day: String
    let value: Double?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case day, value
    }
}

// MARK: - Previews

extension AccountService {
    /// Signed out, with no network and no Keychain session.
    static let preview = AccountService(
        client: SupabaseClient(restoringSession: false),
        settings: AppSettings(),
        experiments: ExperimentStore(),
        pacts: PactStore(),
        demoProvider: MockHealthDataProvider.preview
    )
}
