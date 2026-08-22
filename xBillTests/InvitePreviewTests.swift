//
//  InvitePreviewTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  INV-01. `JoinGroupView` treats a failed preview as "cannot show the group's name" and falls
//  back to a generic card — which is correct for a network failure, and is also what a DECODING
//  failure would look like. That makes decoding drift silent: the invite still works, it just
//  stops naming the group, and nobody finds out.
//
//  These pin the payload `get_invite_preview` actually returns, captured verbatim from production
//  on 2026-08-22, and decode it with the decoder PostgREST really uses.
//

import Testing
import Foundation
@testable import xBill

@Suite("Invite preview decoding")
struct InvitePreviewTests {

    /// Captured from `POST /rest/v1/rpc/get_invite_preview` against production. Do not tidy it:
    /// the six-digit fractional seconds and the `+00:00` offset are the parts most likely to break.
    private static let productionPayload = """
    [{"group_id":"9dc07b00-892f-49ac-9377-565a3f729db1","name":"Smoky Mountains Trip",\
    "emoji":"🎯","currency":"USD","member_count":1,\
    "expires_at":"2026-08-29T16:16:59.603754+00:00"}]
    """

    @Test("The real production payload decodes")
    func productionPayloadDecodes() throws {
        let rows = try SupabaseManager.postgrestDecoder.decode(
            [InvitePreview].self, from: Data(Self.productionPayload.utf8))
        let preview = try #require(rows.first)
        #expect(preview.name == "Smoky Mountains Trip")
        #expect(preview.currency == "USD")
        #expect(preview.memberCount == 1)
        #expect(preview.displayEmoji == "🎯")
        #expect(preview.groupID == UUID(uuidString: "9dc07b00-892f-49ac-9377-565a3f729db1"))
        #expect(preview.expiresAt != nil,
                "Six-digit fractional seconds must survive — a nil here means the whole row failed")
    }

    /// `emoji` is nullable on `groups`, and a group created without one must still render.
    @Test("A null emoji falls back rather than failing the decode")
    func nullEmojiTolerated() throws {
        let json = """
        [{"group_id":"9dc07b00-892f-49ac-9377-565a3f729db1","name":"Trip","emoji":null,\
        "currency":"USD","member_count":3,"expires_at":null}]
        """
        let rows = try SupabaseManager.postgrestDecoder.decode(
            [InvitePreview].self, from: Data(json.utf8))
        #expect(rows.first?.displayEmoji == "👥")
        #expect(rows.first?.memberSummary == "3 members")
    }

    @Test("Member count is pluralised")
    func pluralisation() {
        func preview(_ n: Int) -> InvitePreview {
            let json = """
            [{"group_id":"9dc07b00-892f-49ac-9377-565a3f729db1","name":"T","emoji":"🎯",\
            "currency":"USD","member_count":\(n),"expires_at":null}]
            """
            return try! SupabaseManager.postgrestDecoder
                .decode([InvitePreview].self, from: Data(json.utf8))[0]
        }
        #expect(preview(1).memberSummary == "1 member")
        #expect(preview(2).memberSummary == "2 members")
    }
}
