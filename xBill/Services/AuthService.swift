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

    var currentUserID: UUID? {
        get async {
            try? await supabase.auth.session.user.id
        }
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
        guard let userID = await currentUserID else { throw AppError.unauthenticated }
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
        guard let userID = await currentUserID else { return }
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
        // Replace all existing tokens for this user with the fresh token.
        // Uses delete+insert instead of upsert because device_tokens has no
        // single-column unique constraint on user_id alone (one user can have
        // multiple devices, but we treat one active token per user for now).
        try await supabase.table("device_tokens")
            .delete()
            .eq("user_id", value: userID)
            .execute()
        try await supabase.table("device_tokens")
            .insert(TokenRow(userID: userID, token: token, platform: "apns"))
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
        let urlString = try supabase.client.storage
            .from("avatars")
            .getPublicURL(path: path)
            .absoluteString
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
            // Profile missing (account pre-dates trigger) — create it on the fly
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
