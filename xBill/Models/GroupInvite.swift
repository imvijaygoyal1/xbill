//
//  GroupInvite.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation

// MARK: - InviteJoinRequest
// L-29: Moved here from AuthViewModel.swift — logically belongs alongside GroupInvite
// since both types represent the group-invite flow.

struct InviteJoinRequest: Identifiable, Sendable {
    let id = UUID()
    let token: String
}

// MARK: - GroupInvite

struct GroupInvite: Codable, Identifiable, Sendable {
    let token: String
    let groupID: UUID
    let createdBy: UUID
    let expiresAt: Date

    var id: String { token }

    /// The link that goes into the QR code and the share sheet.
    ///
    /// An **https universal link**, not `xbill://join/<token>` (INV-06 follow-up). A custom scheme
    /// has no handler on a device without xBill, and the native Camera app — which is how a QR
    /// actually gets scanned — treats custom schemes inconsistently and often will not offer to
    /// open them at all. `INV-05` converted the emailed link and left this one behind, so scanning
    /// stayed on the worst path.
    ///
    /// This works on every version:
    /// - **with the app and the `applinks` entitlement (1.3+)** — iOS opens xBill directly;
    /// - **with the app but without it (1.0–1.2)** — the web page opens and hands off via
    ///   `xbill://join/<token>`, which is exactly what those builds already understand;
    /// - **without the app** — the web page offers the App Store and shows the invite code.
    ///
    /// `DeepLinkParser` parses this and the legacy scheme to the same intent, and a test asserts
    /// the two agree, so old QR codes already in circulation keep working.
    var inviteURL: URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host   = DeepLinkParser.universalLinkHost
        components.path   = "/invite"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url
    }

    enum CodingKeys: String, CodingKey {
        case token
        case groupID   = "group_id"
        case createdBy = "created_by"
        case expiresAt = "expires_at"
    }
}
