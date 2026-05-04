//
//  BalanceMessageHelper.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation

enum BalanceMessageHelper {
    static func message(for balance: Decimal) -> String {
        if balance > .zero { return "You're owed money" }
        if balance < .zero { return "You've got balances to settle" }
        return "All settled. Nice!"
    }
}
