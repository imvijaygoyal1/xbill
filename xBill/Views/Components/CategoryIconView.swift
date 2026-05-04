//
//  CategoryIconView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

// Extends the existing Expense.Category model with visual properties
extension Expense.Category {

    var emoji: String {
        switch self {
        case .food:          return "🍕"
        case .transport:     return "✈️"
        case .accommodation: return "🏠"
        case .entertainment: return "🎬"
        case .utilities:     return "⚡️"
        case .shopping:      return "🛍️"
        case .health:        return "💊"
        case .other:         return "💸"
        }
    }

    var categoryBackground: Color {
        switch self {
        case .food:          return .catFood
        case .transport:     return .catTravel
        case .accommodation: return .catHome
        case .entertainment: return .catEntertain
        case .utilities:     return .catHome
        case .shopping:      return .catShopping
        case .health:        return .catHealth
        case .other:         return .catOther
        }
    }
}

struct CategoryIconView: View {
    let category: Expense.Category
    var size: CGFloat = XBillIcon.categorySize

    var body: some View {
        XBillCategoryIcon(category: category, size: size)
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 48))], spacing: 8) {
        ForEach(Expense.Category.allCases, id: \.self) { cat in
            CategoryIconView(category: cat)
        }
    }
    .padding()
}
