//
//  GroupService.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import Supabase

// MARK: - GroupService

final class GroupService: Sendable {
    static let shared = GroupService()
    private let supabase = SupabaseManager.shared
    private init() {}

    // MARK: - Fetch

    func fetchGroups(for userID: UUID) async throws -> [BillGroup] {
        let groupIDs = try await memberGroupIDs(userID: userID)
        guard !groupIDs.isEmpty else { return [] }
        return try await supabase.table("groups")
            .select()
            .in("id", values: groupIDs)
            .eq("is_archived", value: false)
            .execute()
            .value
    }

    func fetchArchivedGroups(for userID: UUID) async throws -> [BillGroup] {
        let groupIDs = try await memberGroupIDs(userID: userID)
        guard !groupIDs.isEmpty else { return [] }
        return try await supabase.table("groups")
            .select()
            .in("id", values: groupIDs)
            .eq("is_archived", value: true)
            .execute()
            .value
    }

    private func memberGroupIDs(userID: UUID) async throws -> [UUID] {
        struct Row: Decodable {
            let groupId: UUID
            enum CodingKeys: String, CodingKey { case groupId = "group_id" }
        }
        let rows: [Row] = try await supabase.table("group_members")
            .select("group_id")
            .eq("user_id", value: userID)
            .execute()
            .value
        return rows.map(\.groupId)
    }

    func fetchGroup(id: UUID) async throws -> BillGroup {
        try await supabase.table("groups")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    func fetchMembers(groupID: UUID) async throws -> [User] {
        // Two-step: get user_ids from group_members, then fetch their profiles
        struct Row: Decodable {
            let userId: UUID
            enum CodingKeys: String, CodingKey { case userId = "user_id" }
        }
        let rows: [Row] = try await supabase.table("group_members")
            .select("user_id")
            .eq("group_id", value: groupID)
            .execute()
            .value
        let ids = rows.map(\.userId)
        guard !ids.isEmpty else { return [] }
        return try await supabase.table("profiles")
            .select()
            .in("id", values: ids)
            .execute()
            .value
    }

    // MARK: - Create

    func createGroup(name: String, emoji: String, currency: String, createdBy: UUID) async throws -> BillGroup {
        struct Params: Encodable {
            let p_name: String
            let p_emoji: String
            let p_currency: String
        }
        // H-07: atomic RPC — group INSERT + member INSERT in one transaction.
        // Eliminates the window where the group exists but the creator is not a member.
        let groups: [BillGroup] = try await supabase.client
            .rpc("create_group_with_member", params: Params(p_name: name, p_emoji: emoji, p_currency: currency))
            .execute()
            .value
        guard let group = groups.first else {
            throw AppError.serverError("create_group_with_member returned no rows")
        }
        return group
    }

    // MARK: - Update

    func updateGroup(_ group: BillGroup) async throws -> BillGroup {
        struct Payload: Encodable {
            let name: String
            let emoji: String
            let currency: String
            let isArchived: Bool
            enum CodingKeys: String, CodingKey {
                case name, emoji, currency
                case isArchived = "is_archived"
            }
        }
        return try await supabase.table("groups")
            .update(Payload(name: group.name, emoji: group.emoji, currency: group.currency, isArchived: group.isArchived))
            .eq("id", value: group.id)
            .select()
            .single()
            .execute()
            .value
    }

    // MARK: - Members

    func addMember(groupId: UUID, userId: UUID) async throws {
        struct Payload: Encodable {
            let groupId: UUID
            let userId: UUID
            enum CodingKeys: String, CodingKey {
                case groupId = "group_id"
                case userId  = "user_id"
            }
        }
        try await supabase.table("group_members")
            .insert(Payload(groupId: groupId, userId: userId))
            .execute()
    }

    func removeMember(groupId: UUID, userId: UUID) async throws {
        struct Deleted: Decodable {
            let userId: UUID
            enum CodingKeys: String, CodingKey { case userId = "user_id" }
        }
        let rows: [Deleted] = try await supabase.table("group_members")
            .delete()
            .eq("group_id", value: groupId)
            .eq("user_id", value: userId)
            .select("user_id")
            .execute()
            .value
        guard !rows.isEmpty else {
            throw AppError.unknown("Only the group creator can remove other members.")
        }
    }

    // MARK: - Delete

    func deleteGroup(groupId: UUID) async throws {
        try await supabase.table("groups")
            .delete()
            .eq("id", value: groupId)
            .execute()
    }

    // MARK: - Invites

    func inviteMembers(
        emails: [String],
        groupName: String,
        groupEmoji: String,
        inviterName: String
    ) async throws {
        struct InvitePayload: Encodable {
            let groupName: String
            let groupEmoji: String
            let inviterName: String
            let emails: [String]
            enum CodingKeys: String, CodingKey {
                case groupName   = "groupName"
                case groupEmoji  = "groupEmoji"
                case inviterName = "inviterName"
                case emails
            }
        }
        struct InviteResponse: Decodable {
            let sent: Int
            let failed: [String]
        }
        let payload = InvitePayload(
            groupName: groupName,
            groupEmoji: groupEmoji,
            inviterName: inviterName,
            emails: emails
        )
        let _: InviteResponse = try await supabase.client.functions
            .invoke("invite-member", options: .init(body: payload))
    }

    // MARK: - Invite Links

    func createInvite(groupID: UUID, createdBy: UUID) async throws -> GroupInvite {
        struct Payload: Encodable {
            let groupID: UUID
            let createdBy: UUID
            enum CodingKeys: String, CodingKey {
                case groupID   = "group_id"
                case createdBy = "created_by"
            }
        }
        return try await supabase.table("group_invites")
            .insert(Payload(groupID: groupID, createdBy: createdBy))
            .select()
            .single()
            .execute()
            .value
    }

    func fetchInvite(token: String) async throws -> GroupInvite {
        try await supabase.table("group_invites")
            .select()
            .eq("token", value: token)
            .single()
            .execute()
            .value
    }

    /// Validates the token and adds the current user to the group atomically (SECURITY DEFINER RPC).
    /// Returns the joined group_id on success.
    func joinGroupViaInvite(token: String) async throws -> UUID {
        struct Params: Encodable { let p_token: String }
        return try await supabase.client.rpc("join_group_via_invite", params: Params(p_token: token))
            .execute()
            .value
    }

    // MARK: - Profile Lookup

    /// Returns xBill profiles matching any of the provided email addresses.
    /// Uses a SECURITY DEFINER RPC so callers cannot enumerate the profiles table directly.
    func lookupProfilesByEmail(_ emails: [String]) async throws -> [User] {
        struct Params: Encodable { let p_emails: [String] }
        struct Row: Decodable {
            let id: UUID
            let email: String?
            let displayName: String
            let avatarURL: String?
            enum CodingKeys: String, CodingKey {
                case id
                case email
                case displayName = "display_name"
                case avatarURL   = "avatar_url"
            }
        }
        let rows: [Row] = try await supabase.client
            .rpc("lookup_profiles_by_email", params: Params(p_emails: emails))
            .execute()
            .value
        return rows.map { User(id: $0.id, email: $0.email ?? "", displayName: $0.displayName,
                               avatarURL: $0.avatarURL.flatMap { URL(string: $0) },
                               // createdAt synthesised — not the actual registration date; do not sort by this field.
                               createdAt: Date()) }
    }

    // MARK: - Realtime

    /// Returns an AsyncStream that yields whenever the current user's group memberships or group metadata change.
    func groupChanges(userID: UUID) async throws -> AsyncStream<Void> {
        let topic = "groups-\(userID.uuidString)"
        // The SDK caches channels by topic; remove any existing subscribed channel
        // before registering new callbacks to avoid "callbacks after subscribe" error.
        let stale = supabase.client.channel(topic)
        await supabase.client.removeChannel(stale)

        let channel = supabase.client.channel(topic)
        let membersStream = channel.postgresChange(AnyAction.self, schema: "public", table: "group_members")
        let groupsStream  = channel.postgresChange(AnyAction.self, schema: "public", table: "groups")
        try await channel.subscribeWithError()
        let client = supabase.client
        return AsyncStream { continuation in
            // M-17: retain task handles so they can be cancelled when the stream terminates.
            // Without retention the tasks are fire-and-forget and keep running even after
            // the consumer (HomeViewModel) cancels the enclosing Task.
            let t1 = Task { for await _ in membersStream { continuation.yield() } }
            let t2 = Task { for await _ in groupsStream  { continuation.yield() } }
            continuation.onTermination = { _ in
                t1.cancel()
                t2.cancel()
                Task { await client.removeChannel(channel) }
            }
        }
    }
}
