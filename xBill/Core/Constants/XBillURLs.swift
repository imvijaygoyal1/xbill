//
//  XBillURLs.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation

enum XBillURLs {
    static let privacyPolicy = URL(string: "https://xbill.vijaygoyal.org/privacy")!
    static let termsOfService = URL(string: "https://xbill.vijaygoyal.org/terms")!
    static let landingPage   = URL(string: "https://xbill.vijaygoyal.org")!
    static let appInvite     = URL(string: "https://xbill.vijaygoyal.org/invite")!

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
