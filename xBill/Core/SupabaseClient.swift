//
//  SupabaseClient.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import Supabase

// MARK: - SupabaseManager

@MainActor
final class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    private init() {
        let urlString = (Bundle.main.infoDictionary?["SUPABASE_URL"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let key = (Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        #if DEBUG
        // Keep previews and local UI-only tests from crashing before credentials
        // are configured. Authenticated app flows still require real Supabase values.
        let resolvedURL = URL(string: urlString) ?? URL(string: "https://placeholder.supabase.co")!
        let resolvedKey = key.isEmpty ? "placeholder-key" : key
        #else
        guard
            let resolvedURL = URL(string: urlString),
            resolvedURL.scheme == "https",
            resolvedURL.host?.contains("placeholder") == false,
            !urlString.contains("$("),
            !key.isEmpty,
            key != "placeholder-key",
            !key.contains("$(")
        else {
            preconditionFailure("Missing or invalid Supabase configuration in app Info.plist")
        }
        let resolvedKey = key
        #endif

        client = SupabaseClient(
            supabaseURL: resolvedURL,
            supabaseKey: resolvedKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    storage: KeychainSessionStorage(),
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }
}

// MARK: - Convenience

extension SupabaseManager {
    var auth: AuthClient { client.auth }

    /// The encoder PostgREST requests are actually built with. Exposed so payload tests
    /// pin the real wire format — a plain `JSONEncoder` would emit `Date` as a number,
    /// which Postgres cannot cast to `timestamptz`.
    nonisolated static var postgrestEncoder: JSONEncoder { PostgrestClient.Configuration.jsonEncoder }
    /// The decoder PostgREST responses are actually parsed with. Exposed so tests can pin real
    /// wire payloads rather than a decoder they configured themselves — a model that decodes under
    /// a hand-rolled `JSONDecoder` and fails under this one looks fine in tests and degrades
    /// silently in the app.
    nonisolated static var postgrestDecoder: JSONDecoder { PostgrestClient.Configuration.jsonDecoder }

    func table(_ name: String) -> PostgrestQueryBuilder {
        client.from(name)
    }
}
