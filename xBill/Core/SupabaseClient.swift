import Foundation
import Supabase

// MARK: - SupabaseManager

final class SupabaseManager: Sendable {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    private init() {
        let urlString = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String ?? ""
        let key = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String ?? ""

        // Fall back to a stub URL in debug builds so the app doesn't crash before
        // real credentials are configured. All Supabase calls will fail gracefully.
        let resolvedURL = URL(string: urlString) ?? URL(string: "https://placeholder.supabase.co")!
        let resolvedKey = key.isEmpty ? "placeholder-key" : key

        client = SupabaseClient(supabaseURL: resolvedURL, supabaseKey: resolvedKey)
    }
}

// MARK: - Convenience

extension SupabaseManager {
    var auth: AuthClient { client.auth }

    func table(_ name: String) -> PostgrestQueryBuilder {
        client.from(name)
    }
}
