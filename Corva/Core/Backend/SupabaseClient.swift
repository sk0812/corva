import CryptoKit
import Foundation

/// A signed-in user, as far as the app needs to know them.
nonisolated struct AuthUser: Codable, Hashable, Sendable {
    let id: UUID
    let email: String?
    let name: String?
}

/// Tokens for the signed-in user. Stored in the Keychain.
nonisolated struct AuthSession: Codable, Hashable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var user: AuthUser
}

nonisolated enum BackendError: LocalizedError, Equatable {
    case notSignedIn
    case server(status: Int, message: String)
    case invalidResponse
    case signInCancelled

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "You’re not signed in."
        case .server(_, let message): message
        case .invalidResponse: "The server sent something unexpected. Try again."
        case .signInCancelled: "Sign-in was cancelled."
        }
    }
}

/// A small client for the two Supabase services Corva uses: Auth (sign-in, tokens) and the
/// Data API (PostgREST tables and functions). Plain `URLSession`, no dependencies.
///
/// Requests carry the publishable key, plus the user's access token once signed in. The
/// database's row-level security does the rest, so this client never sees other people's
/// rows.
final class SupabaseClient {
    private let baseURL: URL
    private let publishableKey: String
    private let keychain: KeychainStore
    private let urlSession: URLSession

    /// The current session, if signed in. Restored from the Keychain at launch.
    private(set) var session: AuthSession?

    /// The PKCE verifier for a Google sign-in in progress.
    private var pendingVerifier: String?

    /// The token refresh in flight, shared by every caller that needs a fresh token. Supabase
    /// rotates refresh tokens, so two parallel refreshes with the same token would make one
    /// fail and sign the user out.
    private var refreshTask: Task<AuthSession, Error>?

    init(
        baseURL: URL = BackendConfig.projectURL,
        publishableKey: String = BackendConfig.publishableKey,
        keychain: KeychainStore = KeychainStore(service: "com.corva.auth", account: "session"),
        restoringSession: Bool = true,
        urlSession: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.publishableKey = publishableKey
        self.keychain = keychain
        self.urlSession = urlSession
        session = restoringSession ? keychain.load(AuthSession.self) : nil
    }

    // MARK: - Google sign-in (OAuth with PKCE)

    /// The page that starts Google sign-in. Open it in a web authentication session that
    /// listens for `BackendConfig.authCallbackURL`'s scheme, then pass the callback URL to
    /// `completeOAuthSignIn(callbackURL:)`.
    func googleSignInURL() -> URL {
        let verifier = Self.makeVerifier()
        pendingVerifier = verifier
        var components = URLComponents(url: baseURL.appending(path: "auth/v1/authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: BackendConfig.authCallbackURL.absoluteString),
            URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "s256"),
        ]
        return components.url!
    }

    func completeOAuthSignIn(callbackURL: URL) async throws -> AuthUser {
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let message = items.first(where: { $0.name == "error_description" })?.value {
            throw BackendError.server(status: 400, message: message)
        }
        guard let code = items.first(where: { $0.name == "code" })?.value,
              let verifier = pendingVerifier else { throw BackendError.invalidResponse }
        pendingVerifier = nil
        return try await requestSession(
            grantType: "pkce",
            body: ["auth_code": code, "code_verifier": verifier]
        )
    }

    // MARK: - Email sign-in (one-time code)

    /// Emails a one-time code, creating the account if it's new.
    func sendEmailCode(to email: String) async throws {
        _ = try await send(
            "POST",
            path: "auth/v1/otp",
            body: JSONSerialization.data(withJSONObject: ["email": email, "create_user": true]),
            authenticated: false
        )
    }

    func verifyEmailCode(_ code: String, email: String) async throws -> AuthUser {
        let data = try await send(
            "POST",
            path: "auth/v1/verify",
            body: JSONSerialization.data(withJSONObject: ["type": "email", "email": email, "token": code]),
            authenticated: false
        )
        return try store(tokenResponse: data)
    }

    // MARK: - Session

    /// Forgets the session on this phone straight away, then tells the server in the
    /// background. `scope=local` ends only this device's session, not every device's.
    func signOut() {
        guard let ending = session else { return }
        session = nil
        refreshTask = nil
        keychain.delete()
        var components = URLComponents(url: baseURL.appending(path: "auth/v1/logout"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "scope", value: "local")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(ending.accessToken)", forHTTPHeaderField: "Authorization")
        let urlSession = urlSession
        Task.detached { _ = try? await urlSession.data(for: request) }
    }

    /// An access token that's valid for at least another minute, refreshing if needed.
    func validAccessToken() async throws -> String {
        guard let session else { throw BackendError.notSignedIn }
        if session.expiresAt.timeIntervalSinceNow > 60 {
            return session.accessToken
        }
        if let refreshTask {
            return try await refreshTask.value.accessToken
        }
        let sentToken = session.refreshToken
        let task = Task { () throws -> AuthSession in
            do {
                _ = try await requestSession(grantType: "refresh_token", body: ["refresh_token": sentToken])
            } catch BackendError.server(let status, _) where status == 400 || status == 401 {
                // The refresh token was revoked or already used up: sign in again. Only clear
                // the session if nothing replaced it in the meantime.
                if self.session?.refreshToken == sentToken {
                    self.session = nil
                    keychain.delete()
                }
                throw BackendError.notSignedIn
            }
            // Anything else (offline, 429, 5xx) is temporary: keep the session and let the
            // caller retry later.
            guard let refreshed = self.session else { throw BackendError.notSignedIn }
            return refreshed
        }
        refreshTask = task
        defer { if refreshTask == task { refreshTask = nil } }
        return try await task.value.accessToken
    }

    private func requestSession(grantType: String, body: [String: String]) async throws -> AuthUser {
        let data = try await send(
            "POST",
            path: "auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: grantType)],
            body: JSONSerialization.data(withJSONObject: body),
            authenticated: false
        )
        return try store(tokenResponse: data)
    }

    private func store(tokenResponse data: Data) throws -> AuthUser {
        guard let response = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw BackendError.invalidResponse
        }
        let metadata = response.user.userMetadata
        let user = AuthUser(id: response.user.id, email: response.user.email, name: metadata?.fullName ?? metadata?.name)
        let newSession = AuthSession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: Date(timeIntervalSinceNow: response.expiresIn),
            user: user
        )
        session = newSession
        keychain.save(newSession)
        return user
    }

    // MARK: - Data API

    /// Rows from a table or view. `query` holds PostgREST parameters such as
    /// `select=…` and filters like `id=eq.…`.
    func select<Row: Decodable>(
        _ table: String,
        query: [URLQueryItem] = [],
        as type: Row.Type = Row.self,
        convertingSnakeCase: Bool = false
    ) async throws -> [Row] {
        let data = try await send("GET", path: "rest/v1/\(table)", query: query, body: nil)
        let decoder = JSONDecoder()
        if convertingSnakeCase { decoder.keyDecodingStrategy = .convertFromSnakeCase }
        do {
            return try decoder.decode([Row].self, from: data)
        } catch {
            throw BackendError.invalidResponse
        }
    }

    /// Calls an Edge Function as the signed-in user.
    func function<Body: Encodable, Result: Decodable>(_ path: String, _ body: Body, returning type: Result.Type) async throws -> Result {
        let data = try await send("POST", path: "functions/v1/\(path)", body: try JSONEncoder().encode(body))
        do {
            return try JSONDecoder().decode(Result.self, from: data)
        } catch {
            throw BackendError.invalidResponse
        }
    }

    /// Inserts rows and returns them as stored (with server defaults filled in).
    func insert<Body: Encodable, Row: Decodable>(_ table: String, _ body: Body, query: [URLQueryItem] = [], returning type: Row.Type) async throws -> [Row] {
        let data = try await send(
            "POST", path: "rest/v1/\(table)", query: query,
            body: try JSONEncoder().encode(body), prefer: "return=representation"
        )
        do {
            return try JSONDecoder().decode([Row].self, from: data)
        } catch {
            throw BackendError.invalidResponse
        }
    }

    /// Inserts or updates rows by primary key (or `onConflict` columns).
    func upsert<Body: Encodable>(_ table: String, _ body: Body, onConflict: String? = nil, ignoreDuplicates: Bool = false) async throws {
        var query: [URLQueryItem] = []
        if let onConflict { query.append(URLQueryItem(name: "on_conflict", value: onConflict)) }
        _ = try await send(
            "POST", path: "rest/v1/\(table)", query: query,
            body: try JSONEncoder().encode(body),
            prefer: "resolution=\(ignoreDuplicates ? "ignore" : "merge")-duplicates,return=minimal"
        )
    }

    func update<Body: Encodable>(_ table: String, _ body: Body, filters: [URLQueryItem]) async throws {
        _ = try await send(
            "PATCH", path: "rest/v1/\(table)", query: filters,
            body: try JSONEncoder().encode(body), prefer: "return=minimal"
        )
    }

    func delete(_ table: String, filters: [URLQueryItem]) async throws {
        _ = try await send("DELETE", path: "rest/v1/\(table)", query: filters, body: nil, prefer: "return=minimal")
    }

    /// Calls a database function, e.g. `accept_pact_invite`.
    func rpc<Body: Encodable, Result: Decodable>(_ function: String, _ body: Body, returning type: Result.Type) async throws -> Result {
        let data = try await send("POST", path: "rest/v1/rpc/\(function)", body: try JSONEncoder().encode(body))
        do {
            return try JSONDecoder().decode(Result.self, from: data)
        } catch {
            throw BackendError.invalidResponse
        }
    }

    // MARK: - Transport

    private func send(
        _ method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: Data?,
        prefer: String? = nil,
        authenticated: Bool = true,
        retryingUnauthorized: Bool = true
    ) async throws -> Data {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if authenticated {
            let token = try await validAccessToken()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        // An access token the server no longer accepts (expired early, clock skew): refresh
        // once and retry.
        if http.statusCode == 401, authenticated, retryingUnauthorized, session != nil {
            session?.expiresAt = .distantPast
            return try await send(
                method, path: path, query: query, body: body, prefer: prefer,
                authenticated: true, retryingUnauthorized: false
            )
        }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendError.server(status: http.statusCode, message: Self.errorMessage(from: data, status: http.statusCode))
        }
        return data
    }

    /// Auth and PostgREST name their error fields differently; take whichever is there.
    private static func errorMessage(from data: Data, status: Int) -> String {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        for key in ["error", "msg", "error_description", "message"] {
            if let message = object?[key] as? String, !message.isEmpty { return message }
        }
        return "The server returned an error (\(status))."
    }

    // MARK: - PKCE

    private static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// The parts of Supabase Auth's token response the app uses.
private nonisolated struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Double
    let user: User

    struct User: Decodable {
        let id: UUID
        let email: String?
        let userMetadata: Metadata?

        enum CodingKeys: String, CodingKey {
            case id, email
            case userMetadata = "user_metadata"
        }
    }

    struct Metadata: Decodable {
        let fullName: String?
        let name: String?

        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
            case name
        }
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}
