//
//  DeepLinkParserTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  xBill accepts an invite by two routes — the custom scheme and a universal link — and they must
//  resolve identically. Four invite defects (INV-01…04) each came from two paths that were meant
//  to agree and had drifted, so the equivalence is asserted directly rather than assumed.
//

import Testing
import Foundation
@testable import xBill

@Suite("Deep link parsing")
struct DeepLinkParserTests {

    private func url(_ s: String) -> URL { URL(string: s)! }

    // MARK: - The equivalence that matters

    /// The headline property: both forms of an invite produce the same intent.
    @Test("A custom-scheme and a universal-link invite parse identically")
    func bothInviteFormsAgree() {
        let scheme    = DeepLinkParser.parse(url("xbill://join/abc123"))
        let universal = DeepLinkParser.parse(url("https://xbill.vijaygoyal.org/invite?token=abc123"))
        #expect(scheme == .joinGroup(token: "abc123"))
        #expect(scheme == universal, "The two routes must not drift: \(String(describing: scheme)) vs \(String(describing: universal))")
    }

    // MARK: - Universal links

    @Test("Trailing slash and extra query parameters are tolerated")
    func universalLinkVariants() {
        #expect(DeepLinkParser.parse(url("https://xbill.vijaygoyal.org/invite/?token=t1"))
                == .joinGroup(token: "t1"))
        #expect(DeepLinkParser.parse(url("https://xbill.vijaygoyal.org/invite?utm=email&token=t2"))
                == .joinGroup(token: "t2"))
    }

    /// A universal link is only delivered for a declared domain, but `openURL` can hand us
    /// anything, so the host is checked rather than trusted.
    @Test("Another host is not honoured")
    func foreignHostRejected() {
        #expect(DeepLinkParser.parse(url("https://evil.example.com/invite?token=abc")) == nil)
        #expect(DeepLinkParser.parse(url("https://xbill.pages.dev/invite?token=abc")) == nil)
    }

    @Test("An invite without a token is not a join")
    func missingTokenRejected() {
        #expect(DeepLinkParser.parse(url("https://xbill.vijaygoyal.org/invite")) == nil)
        #expect(DeepLinkParser.parse(url("https://xbill.vijaygoyal.org/invite?token=")) == nil)
    }

    /// Only `/invite` is claimed. The AASA file lists the same paths; if either side gains a path
    /// the other must too, and a link to a page we do not claim must not be swallowed.
    @Test("Unclaimed paths are ignored")
    func unclaimedPathsIgnored() {
        #expect(DeepLinkParser.parse(url("https://xbill.vijaygoyal.org/privacy")) == nil)
        #expect(DeepLinkParser.parse(url("https://xbill.vijaygoyal.org/")) == nil)
    }

    // MARK: - Custom scheme, unchanged behaviour

    @Test("Add-friend links still resolve")
    func addFriend() {
        let id = UUID()
        #expect(DeepLinkParser.parse(url("xbill://add/\(id.uuidString)")) == .addFriend(userID: id))
        #expect(DeepLinkParser.parse(url("xbill://add/not-a-uuid")) == nil)
    }

    @Test("An auth redirect is routed to the SDK, not treated as an invite")
    func authCallback() {
        #expect(DeepLinkParser.parse(url("xbill://auth/callback#access_token=x")) == .authCallback)
    }

    @Test("An empty join token is rejected")
    func emptySchemeToken() {
        #expect(DeepLinkParser.parse(url("xbill://join/")) == nil)
    }

    /// The parser and the hosted AASA file must name the same host.
    @Test("The declared host matches the entitlement domain")
    func hostConstantMatchesEntitlement() {
        #expect(DeepLinkParser.universalLinkHost == "xbill.vijaygoyal.org")
    }
}

// MARK: - The QR code's own URL
//
// INV-06 follow-up. `INV-05` converted the emailed invite link to an https universal link and left
// the QR encoding `xbill://join/<token>` — the custom scheme the native Camera handles worst, and
// the very path a QR is scanned by. These pin the QR's URL to the form the parser accepts.

@Suite("Invite QR URL")
struct InviteQRURLTests {

    private func invite(_ token: String) -> GroupInvite {
        GroupInvite(token: token, groupID: UUID(), createdBy: UUID(),
                    expiresAt: Date().addingTimeInterval(604_800))
    }

    @Test("The QR encodes an https universal link, not a custom scheme")
    func qrUsesUniversalLink() throws {
        let url = try #require(invite("abc123").inviteURL)
        #expect(url.scheme == "https")
        #expect(url.host == DeepLinkParser.universalLinkHost)
        #expect(url.absoluteString == "https://xbill.vijaygoyal.org/invite?token=abc123")
    }

    /// The round trip that matters: whatever the QR encodes, the app must resolve it to a join.
    @Test("The app parses its own QR link back to the same token")
    func qrRoundTrips() throws {
        let url = try #require(invite("tok-987").inviteURL)
        #expect(DeepLinkParser.parse(url) == .joinGroup(token: "tok-987"))
    }

    /// QR codes printed or shared before this change still exist in the world.
    @Test("Legacy custom-scheme QR codes still resolve")
    func legacySchemeStillWorks() {
        #expect(DeepLinkParser.parse(URL(string: "xbill://join/tok-987")!) == .joinGroup(token: "tok-987"))
    }

    /// A token with URL-significant characters must survive encoding.
    @Test("Tokens are percent-encoded into the query")
    func tokensAreEncoded() throws {
        let url = try #require(invite("a b&c=d").inviteURL)
        #expect(DeepLinkParser.parse(url) == .joinGroup(token: "a b&c=d"))
    }
}

// MARK: - Add-friend links
//
// The add-friend QR carried the same defect the group QR did: `xbill://add/<uuid>`, a custom
// scheme with no handler on a device without xBill — which is precisely who you send an add-friend
// link to — and one the native Camera app treats inconsistently.
//
// Both forms must resolve identically, because QR codes and links already shared in the world
// still carry the old scheme.

@Suite("Add-friend links")
struct AddFriendLinkTests {

    private func url(_ s: String) -> URL { URL(string: s)! }

    @Test("The two forms of an add-friend link agree")
    func bothFormsAgree() {
        let id = UUID()
        let scheme    = DeepLinkParser.parse(url("xbill://add/\(id.uuidString)"))
        let universal = DeepLinkParser.parse(url("https://xbill.vijaygoyal.org/add?user=\(id.uuidString)"))
        #expect(scheme == .addFriend(userID: id))
        #expect(scheme == universal, "The routes must not drift: \(String(describing: scheme)) vs \(String(describing: universal))")
    }

    @Test("Trailing slash and extra query parameters are tolerated")
    func variants() {
        let id = UUID()
        #expect(DeepLinkParser.parse(url("https://xbill.vijaygoyal.org/add/?user=\(id.uuidString)"))
                == .addFriend(userID: id))
        #expect(DeepLinkParser.parse(url("https://xbill.vijaygoyal.org/add?utm=qr&user=\(id.uuidString)"))
                == .addFriend(userID: id))
    }

    @Test("A malformed or missing user id is not an add-friend")
    func malformedRejected() {
        #expect(DeepLinkParser.parse(url("https://xbill.vijaygoyal.org/add")) == nil)
        #expect(DeepLinkParser.parse(url("https://xbill.vijaygoyal.org/add?user=")) == nil)
        #expect(DeepLinkParser.parse(url("https://xbill.vijaygoyal.org/add?user=not-a-uuid")) == nil)
    }

    /// Only our own host is honoured — `openURL` can hand the app anything.
    @Test("Another host is not honoured")
    func foreignHostRejected() {
        let id = UUID()
        #expect(DeepLinkParser.parse(url("https://evil.example.com/add?user=\(id.uuidString)")) == nil)
    }

    /// The invite path must not start swallowing add links, or vice versa.
    @Test("The two paths stay distinct")
    func pathsStayDistinct() {
        let id = UUID()
        #expect(DeepLinkParser.parse(url("https://xbill.vijaygoyal.org/invite?user=\(id.uuidString)")) == nil)
        #expect(DeepLinkParser.parse(url("https://xbill.vijaygoyal.org/add?token=abc")) == nil)
    }
}
