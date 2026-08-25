//
//  AuthService.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import OSLog
import UIKit
import Supabase

// MARK: - AuthService

@MainActor
final class AuthService {
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
            // Best-effort by design: a brand-new Apple account can race the `handle_new_user`
            // trigger, so zero affected rows is expected and must not fail sign-in. But the
            // previous `try?` also discarded genuine failures, leaving accounts stuck on the
            // trigger's "User" fallback with no trace (REV-06). Log the outcome instead.
            do {
                let rows: [AffectedRowID] = try await supabase.table("profiles")
                    .update(DisplayNamePayload(displayName: name))
                    .eq("id", value: session.user.id)
                    .select("id")
                    .execute()
                    .value
                if rows.isEmpty {
                    Logger(subsystem: "com.vijaygoyal.xbill", category: "Auth")
                        .warning("Apple display name not applied: no profile row yet for \(session.user.id, privacy: .public)")
                }
            } catch {
                Logger(subsystem: "com.vijaygoyal.xbill", category: "Auth")
                    .error("Apple display name update failed: \(error.localizedDescription, privacy: .public)")
            }
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
        try? await supabase.auth.signOut()
    }

    // MARK: - Profile

    func updateProfile(displayName: String, avatarURL: URL?, venmoHandle: String? = nil, paypalHandle: String? = nil) async throws -> User {
        guard let userID = currentUserID else { throw AppError.unauthenticated }
        let update = UserUpdatePayload(displayName: displayName, avatarURL: avatarURL, venmoHandle: venmoHandle, paypalHandle: paypalHandle)
        return try await supabase.table("profiles")
            .update(update)
            .eq("id", value: userID)
            .select()
            .single()
            .execute()
            .value
    }

    // MARK: - Device Token

    /// APNs environment this build's tokens are valid in.
    ///
    /// PUSH-02. This is the **only** place in the app where `#if DEBUG` legitimately answers the
    /// sandbox-vs-production question, because here it describes the local binary: `project.yml`
    /// signs Debug with `xBill.Debug.entitlements` (`aps-environment: development`) and Release
    /// with `xBill.entitlements` (`aps-environment: production`).
    ///
    /// The four notify functions used to ask the same question from the **sender's** build, where
    /// it describes the wrong device entirely. Never reintroduce it there — the answer belongs to
    /// the recipient's token, and that is what this writes.
    /// `nonisolated` because it is a compile-time constant: it reads no state and touches nothing
    /// on the main actor, so requiring isolation would only make the tests reach for a hop.
    nonisolated static var apnsEnvironment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    /// A row of `public.device_tokens`, as this app writes it.
    ///
    /// Lifted out of `updateDeviceToken` so its **encoded form** can be asserted. A missing or
    /// misnamed `environment` key does not fail — PostgREST simply applies the column's
    /// `DEFAULT 'production'`, and a sandbox device silently stops receiving anything. That is the
    /// same shape as `SPLIT-04`, where a key the client omitted changed the server's behaviour
    /// with no error anywhere.
    struct DeviceTokenRow: Encodable {
        let userID: UUID
        let token: String
        let platform: String
        let environment: String
        enum CodingKeys: String, CodingKey {
            case userID   = "user_id"
            case token
            case platform
            case environment
        }
    }

    func updateDeviceToken(_ token: String) async throws {
        guard let userID = currentUserID else { return }
        // Insert new token first (upsert on unique(user_id,token)) to guarantee
        // the user always has at least one valid token even if the cleanup step fails.
        // Then delete all other (stale) tokens for this user.
        try await supabase.table("device_tokens")
            .upsert(DeviceTokenRow(userID: userID, token: token, platform: "apns",
                                   environment: Self.apnsEnvironment),
                    onConflict: "user_id,token")
            .execute()
        try await supabase.table("device_tokens")
            .delete()
            .eq("user_id", value: userID)
            .neq("token", value: token)
            .execute()
    }

    /// Fire-and-forget token cleanup that **reports** failure instead of swallowing it.
    ///
    /// Every caller is a cleanup path with no user action to offer — sign-out, or discovering
    /// that notification permission has been revoked — so the previous `try?` looked harmless.
    /// It is not: if the delete fails, the server keeps an APNs token for someone who has
    /// explicitly denied notifications, and they keep receiving pushes. Silent by construction,
    /// and privacy-adjacent. Log it so it is at least observable.
    func deleteDeviceTokensReportingFailure() async {
        do {
            try await deleteDeviceTokens()
        } catch {
            Logger(subsystem: "com.vijaygoyal.xbill", category: "Auth")
                .error("deleteDeviceTokens failed; a revoked device may still receive pushes: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deleteDeviceTokens() async throws {
        guard let userID = currentUserID else { return }
        try await supabase.table("device_tokens")
            .delete()
            .eq("user_id", value: userID)
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
                .select()
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
        // PostgREST returns code "PGRST116" when .single() finds 0 rows;
        // also match the HTTP 406 transport signal with a precise substring.
        let desc = error.localizedDescription
        if desc.contains("PGRST116") || desc.range(of: "HTTP 406", options: .caseInsensitive) != nil { return true }
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

struct UserUpdatePayload: Encodable {
    let displayName: String
    let avatarURL: URL?
    let venmoHandle: String?
    let paypalHandle: String?
    enum CodingKeys: String, CodingKey {
        case displayName  = "display_name"
        case avatarURL    = "avatar_url"
        case venmoHandle  = "venmo_handle"
        case paypalHandle = "paypal_handle"
        case paypalEmail  = "paypal_email"
    }

    /// Payment handles are encoded explicitly, including when nil, so that clearing one
    /// actually writes NULL.
    ///
    /// Swift's synthesized `Encodable` uses `encodeIfPresent` for optionals, which omits a
    /// nil key entirely. A PATCH that omits `venmo_handle` leaves the existing column value
    /// untouched, so "delete the handle and Save" silently did nothing — the handle stayed
    /// on the profile and kept rendering a payment button. `ProfileViewModel.saveProfile`
    /// treats an empty field as a deliberate clear, and that intent only reaches the
    /// database because of this.
    ///
    /// `paypal_handle` is mirrored onto the legacy `paypal_email` column on every write —
    /// encoded when present, `encodeNil`'d when absent, in lockstep with `paypal_handle`
    /// itself, never independently. `User.init(from:)` falls back to `paypal_email` when
    /// `paypal_handle` is absent from a decode (`try?` flattening collapses an explicit
    /// JSON `null` the same as a missing key, per SE-0230), and pre-036 accounts still have
    /// both columns populated with the same value. Writing only `paypal_handle` here let a
    /// user clear their handle, null the new column, and have the decoder's fallback
    /// resurrect the stale value straight out of `paypal_email` — the Save button would
    /// reappear and settle-up kept a live deep link to a handle the user had just deleted.
    /// Keeping both columns identical on every save is what makes that fallback safe: it can
    /// never read a value that disagrees with what was just written.
    ///
    /// `avatarURL` deliberately keeps omit-on-nil semantics: callers pass the *current*
    /// avatar when no new image was picked, so encoding an explicit null there would erase
    /// an existing avatar on every profile save. If a "remove photo" affordance is ever
    /// added, this omit-on-nil behavior will silently no-op it — a nil `avatarURL` sent to
    /// "clear the avatar" will leave the existing column untouched, the same failure mode
    /// this fix closed for payment handles. `encode(to:)` will need an explicit clear
    /// signal (e.g. a separate `clearAvatar: Bool` flag) before that affordance can ship.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(avatarURL, forKey: .avatarURL)

        if let venmoHandle {
            try container.encode(venmoHandle, forKey: .venmoHandle)
        } else {
            try container.encodeNil(forKey: .venmoHandle)
        }
        if let paypalHandle {
            try container.encode(paypalHandle, forKey: .paypalHandle)
            try container.encode(paypalHandle, forKey: .paypalEmail)
        } else {
            try container.encodeNil(forKey: .paypalHandle)
            try container.encodeNil(forKey: .paypalEmail)
        }
    }
}
