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
