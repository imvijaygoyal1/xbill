//
//  AuthService.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import UIKit
import Supabase

// MARK: - AuthService

final class AuthService: Sendable {
    static let shared = AuthService()
    private let supabase = SupabaseManager.shared

    private init() {}

    // MARK: - Current Session

    // Reads from the Supabase SDK's in-memory session cache — no network call.
    // Callers that need the ID for multiple operations should capture it once into a local let.
    var currentUserID: UUID? {
        supabase.auth.currentUser?.id
    }

    func currentUser() async throws -> User {
        let session = try await supabase.auth.session
        return try await fetchProfile(userID: session.user.id)
    }

    // MARK: - Sign In

    func signInWithEmail(email: String, password: String) async throws -> User {
        let session = try await supabase.auth.signIn(email: email, password: password)
        return try await fetchProfile(userID: session.user.id)
    }

    func signInWithApple(idToken: String, nonce: String, displayName: String?) async throws -> User {
        let session = try await supabase.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )
        // Apple only provides fullName on the very first authorization.
        // Upsert it immediately so the trigger's fallback ("User") is overwritten.
        if let name = displayName, !name.isEmpty {
            try? await supabase.table("profiles")
                .update(DisplayNamePayload(displayName: name))
                .eq("id", value: session.user.id)
                .execute()
        }
        return try await fetchProfile(userID: session.user.id)
    }

    // MARK: - Sign Up

    func signUpWithEmail(
        email: String,
        password: String,
        displayName: String
    ) async throws -> User {
        // Pass display_name in metadata so the DB trigger can use it
        let response = try await supabase.auth.signUp(
            email: email,
            password: password,
            data: ["display_name": .string(displayName)]
        )
        // If session is nil, Supabase requires email confirmation
        guard response.session != nil else {
            throw AppError.confirmationRequired
        }
        // Session exists (email confirmation disabled) — profile was created by trigger
        return try await fetchProfile(userID: response.user.id)
    }

    // MARK: - Password Reset

    func sendPasswordReset(email: String) async throws {
        try await supabase.auth.resetPasswordForEmail(
            email,
            redirectTo: URL(string: "xbill://reset")!
        )
    }

    // MARK: - Sign Out

    func signOut() async throws {
        try await supabase.auth.signOut()
    }

    // MARK: - Delete Account

    func deleteAccount() async throws {
        guard (try? await supabase.auth.session) != nil else {
            throw AppError.unauthenticated
        }
        // The Edge Function verifies identity via adminClient.auth.getUser(jwt),
        // which supports both HS256 (email/password) and ES256 (Apple Sign-In) tokens.
        // verify_jwt = false in config.toml bypasses the gateway's HS256-only check.
        try await supabase.client.functions.invoke("delete-account")
        try await supabase.auth.signOut()
    }

    // MARK: - Profile

    func updateProfile(displayName: String, avatarURL: URL?) async throws -> User {
        guard let userID = currentUserID else { throw AppError.unauthenticated }
        let update = UserUpdatePayload(displayName: displayName, avatarURL: avatarURL)
        return try await supabase.table("profiles")
            .update(update)
            .eq("id", value: userID)
            .select()
            .single()
            .execute()
            .value
    }

    // MARK: - Device Token

    func updateDeviceToken(_ token: String) async throws {
        guard let userID = currentUserID else { return }
        struct TokenRow: Encodable {
            let userID: UUID
            let token: String
            let platform: String
            enum CodingKeys: String, CodingKey {
                case userID   = "user_id"
                case token
                case platform
            }
        }
        // Insert new token first (upsert on unique(user_id,token)) to guarantee
        // the user always has at least one valid token even if the cleanup step fails.
        // Then delete all other (stale) tokens for this user.
        try await supabase.table("device_tokens")
            .upsert(TokenRow(userID: userID, token: token, platform: "apns"),
                    onConflict: "user_id,token")
            .execute()
        try await supabase.table("device_tokens")
            .delete()
            .eq("user_id", value: userID)
            .neq("token", value: token)
            .execute()
    }

    // MARK: - Avatar Upload

    func uploadAvatar(_ image: UIImage, userID: UUID) async throws -> URL {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw AppError.validationFailed("Could not process avatar image.")
        }
        let path = "\(userID.uuidString).jpg"
        try await supabase.client.storage
            .from("avatars")
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
        let baseURLString = try supabase.client.storage
            .from("avatars")
            .getPublicURL(path: path)
            .absoluteString
        // Append a timestamp cache-buster so CDN serves the fresh image immediately
        // after an avatar update, rather than the previous version.
        let urlString = "\(baseURLString)?t=\(Int(Date().timeIntervalSince1970))"
        guard let url = URL(string: urlString) else {
            throw AppError.serverError("Invalid avatar URL returned from storage.")
        }
        return url
    }

    // MARK: - Helpers

    private func fetchProfile(userID: UUID) async throws -> User {
        do {
            return try await supabase.table("profiles")
                .select()
                .eq("id", value: userID)
                .single()
                .execute()
                .value
        } catch {
            // M-20: only create a profile when the row genuinely does not exist.
            // Network timeouts, RLS denials, and schema mismatches should be rethrown
            // so callers can handle them — not silently converted into spurious profile upserts.
            guard isNotFoundError(error) else { throw error }

            // Profile missing (account pre-dates trigger) — create it on the fly.
            let authUser = try await supabase.auth.session.user
            let payload = ProfileUpsertPayload(
                id: authUser.id,
                email: authUser.email ?? "",
                displayName: authUser.email?.components(separatedBy: "@").first ?? "User"
            )
            return try await supabase.table("profiles")
                .upsert(payload)
                .single()
                .execute()
                .value
        }
    }

    /// Returns true when `error` indicates that a requested row was not found.
    /// Matches Postgrest HTTP 406 / "PGRST116" (`.single()` found zero rows).
    private func isNotFoundError(_ error: Error) -> Bool {
        // AppError.notFound was already mapped upstream.
        if case AppError.notFound = error { return true }
        // PostgREST returns code "PGRST116" when .single() finds 0 rows.
        let desc = error.localizedDescription
        if desc.contains("PGRST116") { return true }
        // HTTP 406 is the transport-level signal for "not acceptable" / no rows.
        if desc.contains("406") { return true }
        // The SDK may surface "Row not found" or "The result contains 0 rows" text.
        let lower = desc.lowercased()
        if lower.contains("row not found") || lower.contains("0 rows") { return true }
        return false
    }

}

// MARK: - Payload types (write-only, not full User model)

private struct ProfileUpsertPayload: Encodable {
    let id: UUID
    let email: String
    let displayName: String
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
    }
}

private struct DisplayNamePayload: Encodable {
    let displayName: String
    enum CodingKeys: String, CodingKey { case displayName = "display_name" }
}

private struct UserUpdatePayload: Encodable {
    let displayName: String
    let avatarURL: URL?
    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case avatarURL   = "avatar_url"
    }
}
