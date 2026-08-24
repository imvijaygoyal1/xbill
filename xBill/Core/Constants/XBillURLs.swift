//
//  XBillURLs.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation

enum XBillURLs {

    /// The link behind a user's add-friend QR code and share sheet.
    ///
    /// An **https universal link**, not `xbill://add/<uuid>`. A custom scheme has no handler on a
    /// device without xBill — which is exactly who you send an add-friend link to — and the native
    /// Camera app treats custom schemes inconsistently, which is how the link is usually opened.
    ///
    /// Built here rather than in each view: `MyQRCodeView` and `AddFriendView` each built their
    /// own, and that duplication is precisely how the *group* QR was left on the old scheme when
    /// the emailed invite was converted (INV-05).
    ///
    /// `DeepLinkParser` resolves this and the legacy `xbill://add/<uuid>` to the same intent, so
    /// codes already shared keep working.
    static func addFriend(userID: UUID) -> URL? {
        var c = URLComponents()
        c.scheme = "https"
        c.host   = DeepLinkParser.universalLinkHost
        c.path   = "/add"
        c.queryItems = [URLQueryItem(name: "user", value: userID.uuidString)]
        return c.url
    }

    static let privacyPolicy = URL(string: "https://xbill.vijaygoyal.org/privacy")!
    static let termsOfService = URL(string: "https://xbill.vijaygoyal.org/terms")!
    static let landingPage   = URL(string: "https://xbill.vijaygoyal.org")!
    static let appInvite     = URL(string: "https://xbill.vijaygoyal.org/invite")!

    /// App Store product page. `id` is the Apple-assigned adam ID, not the bundle identifier.
    static let appStore = URL(string: "https://apps.apple.com/app/id6780284715")!

    /// Opens the product page with the review composer already presented.
    ///
    /// Deliberately separate from the StoreKit `requestReview` prompt in `ReviewPromptService`:
    /// Apple rate-limits that to **three prompts per user per year** and may show nothing at all,
    /// whereas a link the user taps themselves has no such limit. At 0 ratings — which suppresses
    /// both App Store search ranking and conversion — this is the cheaper lever of the two.
    static let appStoreReview = URL(string: "https://apps.apple.com/app/id6780284715?action=write-review")!

    /// **Required attribution**, not decoration. ExchangeRate-API's Open Access terms permit
    /// commercial use *on condition* that the app links back with the words
    /// "Rates By Exchange Rate API". Shipping conversions without it is a licence breach — v1.0
    /// did. The terms allow the link to be discreet and styled to match the app.
    /// Do not remove without also removing every use of `open.er-api.com`.
    static let exchangeRateAttribution = URL(string: "https://www.exchangerate-api.com")!

    static let supportEmail = "imvijaygoyal1@icloud.com"

    static func supportMailURL(subject: String, body: String) -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url ?? URL(string: "mailto:\(supportEmail)")!
    }
}
