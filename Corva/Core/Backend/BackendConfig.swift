import Foundation

/// Where Corva's backend lives.
///
/// The publishable key is meant to ship inside the app: it only identifies the project, and
/// row-level security in the database decides what each signed-in user can read or write.
/// The secret key must never appear in the app or the repository.
nonisolated enum BackendConfig {
    static let projectURL = URL(string: "https://buzvrepbqfvungvcqwjl.supabase.co")!
    static let publishableKey = "sb_publishable_X2OFdGaqgZx9Cev5RNxPDA_t-NJJA20"

    /// Where sign-in returns to the app. Must also be listed under Authentication > URL
    /// Configuration > Redirect URLs in the Supabase dashboard.
    static let authCallbackURL = URL(string: "corva://auth-callback")!
}
