//
//  DeepLinkParser.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  One place that turns an incoming URL into an intent, for BOTH forms xBill accepts:
//
//    xbill://join/<token>                              custom scheme
//    https://xbill.vijaygoyal.org/invite?token=<token> universal link
//
//  They are deliberately parsed by the same function. The invite work (INV-01…04) was four
//  defects that each existed because two code paths meant to agree had drifted — a join screen
//  reading a table the joiner could not see, an email builder whose token the caller never sent.
//  Two URL handlers diverging is the same failure waiting to happen, so there is one.
//

import Foundation

enum XBillDeepLink: Equatable, Sendable {
    case joinGroup(token: String)
    case addFriend(userID: UUID)
    /// Supabase auth redirect (email confirmation, password recovery). Handled by the SDK, not us.
    case authCallback
}

enum DeepLinkParser {

    /// The domain declared in `applinks:` and in the AASA file. Kept here so the entitlement, the
    /// hosted file and the parser cannot disagree about which host is trusted.
    static let universalLinkHost = "xbill.vijaygoyal.org"

    static func parse(_ url: URL) -> XBillDeepLink? {
        switch url.scheme?.lowercased() {
        case "xbill":  return parseCustomScheme(url)
        case "https":  return parseUniversalLink(url)
        default:       return nil
        }
    }

    // MARK: - xbill://

    private static func parseCustomScheme(_ url: URL) -> XBillDeepLink? {
        switch url.host {
        case "join":
            // `lastPathComponent` returns "/" — not "" — for `xbill://join/`, so an emptiness
            // check alone let a malformed link through as a join with the token "/". The original
            // handler had this bug; it reached the server, which rejected it as an invalid token
            // and showed the user an error for a link that was simply empty.
            return sanitisedToken(url.lastPathComponent).map(XBillDeepLink.joinGroup)
        case "add":
            guard let uuid = UUID(uuidString: url.lastPathComponent) else { return nil }
            return .addFriend(userID: uuid)
        default:
            // Anything else on our scheme is an auth redirect; the Supabase SDK reads the fragment.
            return .authCallback
        }
    }

    // MARK: - https://

    /// Only our own host is honoured. A universal link is delivered by the system only for a
    /// declared domain, but this is also reachable from `openURL`, so the host is checked rather
    /// than assumed.
    private static func parseUniversalLink(_ url: URL) -> XBillDeepLink? {
        guard url.host?.lowercased() == universalLinkHost else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        // "/invite" and "/invite/" are the same page — Cloudflare Pages serves both.
        let path = components.path.hasSuffix("/") && components.path.count > 1
            ? String(components.path.dropLast())
            : components.path
        guard path == "/invite" else { return nil }

        let raw = components.queryItems?.first { $0.name == "token" }?.value
        return sanitisedToken(raw).map(XBillDeepLink.joinGroup)
    }

    /// A token is whatever survives trimming and is not a path separator. Shared so the two routes
    /// cannot disagree about what counts as present.
    private static func sanitisedToken(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty, trimmed != "/" else { return nil }
        return trimmed
    }
}
