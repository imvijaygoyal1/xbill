//
//  SupabaseClient.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import Supabase

// MARK: - SupabaseManager

final class SupabaseManager: Sendable {
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

    func table(_ name: String) -> PostgrestQueryBuilder {
        client.from(name)
    }
}
