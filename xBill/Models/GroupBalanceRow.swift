//
//  GroupBalanceRow.swift
//  xBill
//
//  One row of `public.get_group_balances()` — a single member of a single group, with their
//  profile and their net balance there.
//
//  PERF-02: the home screen made four requests per group (expenses, members, splits, settlements),
//  so ten groups meant forty requests. This replaces three of the four with one request for every
//  group at once. Expenses are still fetched per group, because the Recent Expenses list needs the
//  rows themselves.
//

import Foundation

struct GroupBalanceRow: Decodable, Equatable, Sendable {
    let groupID: UUID
    let currency: String
    let userID: UUID
    let email: String
    let displayName: String
    let avatarURL: String?
    let venmoHandle: String?
    let paypalHandle: String?
    let isActive: Bool
    let createdAt: Date
    /// Decimal **string**, not a number.
    ///
    /// PostgREST renders `numeric` as a JSON number, and decoding a JSON number into `Decimal`
    /// goes through a binary floating-point representation on the way. This app's standing rule is
    /// that money crosses every JSON boundary as a decimal string, so the function casts to text
    /// at a fixed scale of 2 and this is parsed with `Decimal(string:)`.
    ///
    /// No claim is made here about a specific value that breaks — the rule exists because the
    /// class of error is real, not because a particular literal was observed failing.
    let balance: String

    enum CodingKeys: String, CodingKey {
        case groupID       = "group_id"
        case currency
        case userID        = "user_id"
        case email
        case displayName   = "display_name"
        case avatarURL     = "avatar_url"
        case venmoHandle   = "venmo_handle"
        case paypalHandle  = "paypal_handle"
        case isActive      = "is_active"
        case createdAt     = "created_at"
        case balance
    }

    /// `nil` rather than zero when the string is not a number.
    ///
    /// Zero would be indistinguishable from a settled member and would quietly understate a debt.
    /// The caller treats `nil` as a failed read and raises the stale-data warning instead.
    var decimalBalance: Decimal? {
        Decimal(string: balance)
    }

    /// Rebuilds the `User` the per-group `fetchMembers` call used to return.
    ///
    /// `isActive` is the **membership** flag, which is what `GroupService.fetchMembers` writes over
    /// the profile's own flag — the two mean different things and the group's is the one the UI
    /// wants.
    var user: User {
        User(
            id: userID,
            email: email,
            displayName: displayName,
            avatarURL: avatarURL.flatMap(URL.init(string:)),
            venmoHandle: venmoHandle,
            // The initialiser spells this `paypalEmail`; the stored property is `paypalHandle`.
            paypalEmail: paypalHandle,
            isActive: isActive,
            createdAt: createdAt
        )
    }
}
