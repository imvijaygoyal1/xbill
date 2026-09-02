//
//  CategoryIconView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

// Extends the existing Expense.Category model with visual properties.
//
// ICON-01: `var emoji` was declared here and is **deleted** — it was the third symbol vocabulary
// on this enum and had zero call sites. The symbol vocabulary is `Expense.Category.systemImage`
// (`Models/Expense.swift`); the group-level emoji this was confused with is `BillGroup.emoji`,
// which is user-chosen data, not a design token.
extension Expense.Category {

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
