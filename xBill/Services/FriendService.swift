//
//  FriendService.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import Supabase

final class FriendService: Sendable {
    static let shared = FriendService()
    private let supabase = SupabaseManager.shared
    private init() {}

    // MARK: - Friend Graph

    /// Returns profiles of all accepted friends for the given user.
    func fetchFriends(userID: UUID) async throws -> [User] {
        // Fetch all accepted rows where the user is either party, then resolve profiles.
        let rows: [Friend] = try await supabase.table("friends")
            .select()
            .eq("status", value: "accepted")
            .or("requester_id.eq.\(userID),addressee_id.eq.\(userID)")
            .execute()
            .value
        let friendIDs = rows.map { $0.requesterID == userID ? $0.addresseeID : $0.requesterID }
        return try await fetchProfiles(ids: friendIDs)
    }

    /// Inbound pending requests (caller is the addressee).
    func fetchPendingReceived(userID: UUID) async throws -> [User] {
        let rows: [Friend] = try await supabase.table("friends")
            .select()
            .eq("addressee_id", value: userID)
            .eq("status", value: "pending")
            .execute()
            .value
        return try await fetchProfiles(ids: rows.map(\.requesterID))
    }

    /// Outbound pending requests (caller is the requester).
    func fetchPendingSent(userID: UUID) async throws -> [User] {
        let rows: [Friend] = try await supabase.table("friends")
            .select()
            .eq("requester_id", value: userID)
            .eq("status", value: "pending")
            .execute()
            .value
        return try await fetchProfiles(ids: rows.map(\.addresseeID))
    }

    // MARK: - Actions

    /// Sends a friend request. Idempotent — safe to call if request already exists.
    /// Fires a push notification to the addressee as a fire-and-forget side effect.
    func sendFriendRequest(to addresseeID: UUID) async throws {
        struct Params: Encodable { let p_addressee_id: UUID }
        try await supabase.client
            .rpc("send_friend_request", params: Params(p_addressee_id: addresseeID))
            .execute()
        // M-18: fire-and-forget push notification. `final class: Sendable` cannot safely hold
        // mutable debounce state, so duplicate-notification guard belongs in the caller (ViewModel).
        // The ViewModel MUST disable its "Add Friend" button while this call is in flight.
        Task { await notifyFriendRequest(toUserID: addresseeID) }
    }

    private func notifyFriendRequest(toUserID: UUID) async {
        struct Payload: Encodable {
            let toUserID, fromUserID, fromName: String
            let isDevelopment: Bool
        }
        #if DEBUG
        let dev = true
        #else
        let dev = false
        #endif
        guard let sender = try? await AuthService.shared.currentUser() else { return }
        let payload = Payload(
            toUserID:      toUserID.uuidString,
            fromUserID:    sender.id.uuidString,
            fromName:      sender.displayName,
            isDevelopment: dev
        )
        _ = try? await supabase.client.functions
            .invoke("notify-friend-request", options: .init(body: payload))
    }

    /// Accepts an inbound friend request from requesterID.
    func acceptRequest(from requesterID: UUID) async throws {
        struct Params: Encodable { let p_requester_id: UUID; let p_accept: Bool }
        try await supabase.client
            .rpc("respond_to_friend_request", params: Params(p_requester_id: requesterID, p_accept: true))
            .execute()
    }

    /// Declines (deletes) an inbound friend request from requesterID.
    func declineRequest(from requesterID: UUID) async throws {
        struct Params: Encodable { let p_requester_id: UUID; let p_accept: Bool }
        try await supabase.client
            .rpc("respond_to_friend_request", params: Params(p_requester_id: requesterID, p_accept: false))
            .execute()
    }

    /// Removes an accepted friendship (either party may call this).
    func removeFriend(id friendUserID: UUID, currentUserID: UUID) async throws {
        let a = currentUserID.uuidString
        let b = friendUserID.uuidString
        try await supabase.table("friends")
            .delete()
            .or("and(requester_id.eq.\(a),addressee_id.eq.\(b)),and(requester_id.eq.\(b),addressee_id.eq.\(a))")
            .execute()
    }

    // MARK: - Discovery

    /// Partial match on email or display_name (case-insensitive, max 20 results).
    /// Uses the search_profiles SECURITY DEFINER RPC from migration 021.
    /// Email is NOT returned by the RPC (M1 fix) — results contain id/display_name/avatar_url only.
    func searchProfiles(query: String) async throws -> [User] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        struct Params: Encodable { let p_query: String }
        struct Row: Decodable {
            let id: UUID
            let displayName: String
            let avatarURL: String?
            enum CodingKeys: String, CodingKey {
                case id
                case displayName = "display_name"
                case avatarURL   = "avatar_url"
            }
        }
        let rows: [Row] = try await supabase.client
            .rpc("search_profiles", params: Params(p_query: trimmed))
            .execute()
            .value
        return rows.map {
            User(id: $0.id, email: "", displayName: $0.displayName,
                 avatarURL: $0.avatarURL.flatMap { URL(string: $0) }, createdAt: Date())
        }
    }

    /// Returns xBill profiles for a list of contact emails.
    /// Reuses the lookup_profiles_by_email RPC from migration 018.
    func lookupByContactEmails(_ emails: [String]) async throws -> [User] {
        guard !emails.isEmpty else { return [] }
        struct Params: Encodable { let p_emails: [String] }
        struct Row: Decodable {
            let id: UUID
            let email: String
            let displayName: String
            let avatarURL: String?
            enum CodingKeys: String, CodingKey {
                case id, email
                case displayName = "display_name"
                case avatarURL   = "avatar_url"
            }
        }
        let rows: [Row] = try await supabase.client
            .rpc("lookup_profiles_by_email", params: Params(p_emails: emails))
            .execute()
            .value
        return rows.map {
            User(id: $0.id, email: $0.email, displayName: $0.displayName,
                 avatarURL: $0.avatarURL.flatMap { URL(string: $0) }, createdAt: Date())
        }
    }

    /// Returns the current friendship status between two users, or nil if none.
    func friendshipStatus(currentUserID: UUID, otherUserID: UUID) async throws -> FriendStatus? {
        let a = currentUserID.uuidString
        let b = otherUserID.uuidString
        let rows: [Friend] = try await supabase.table("friends")
            .select()
            .or("and(requester_id.eq.\(a),addressee_id.eq.\(b)),and(requester_id.eq.\(b),addressee_id.eq.\(a))")
            .limit(1)
            .execute()
            .value
        return rows.first?.status
    }

    /// Returns group IDs that both users share as members.
    func fetchMutualGroupIDs(currentUserID: UUID, friendID: UUID) async throws -> [UUID] {
        struct Row: Decodable { let groupId: UUID; enum CodingKeys: String, CodingKey { case groupId = "group_id" } }
        async let myGroupRows: [Row] = supabase.table("group_members")
            .select("group_id")
            .eq("user_id", value: currentUserID)
            .execute()
            .value
        async let friendGroupRows: [Row] = supabase.table("group_members")
            .select("group_id")
            .eq("user_id", value: friendID)
            .execute()
            .value
        let (mine, theirs) = try await (myGroupRows, friendGroupRows)
        let mySet = Set(mine.map(\.groupId))
        return theirs.map(\.groupId).filter { mySet.contains($0) }
    }

    // MARK: - Helpers

    private func fetchProfiles(ids: [UUID]) async throws -> [User] {
        guard !ids.isEmpty else { return [] }
        return try await supabase.table("profiles")
            .select()
            .in("id", values: ids)
            .execute()
            .value
    }

    /// Fetches profiles for an arbitrary set of user IDs. Used by FriendsView
    /// to resolve IOU counterparties without querying Supabase directly from the View layer.
    func fetchProfiles(ids: Set<UUID>) async throws -> [User] {
        try await fetchProfiles(ids: Array(ids))
    }
}
