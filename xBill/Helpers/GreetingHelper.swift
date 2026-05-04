//
//  GreetingHelper.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation

enum GreetingHelper {
    static func greeting(for date: Date = .now, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5...11:  return "Good morning"
        case 12...16: return "Good afternoon"
        case 17...21: return "Good evening"
        default:      return "Welcome back"
        }
    }
}
