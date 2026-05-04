//
//  AppGradient.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

enum AppGradient {
    static var softPrimary: LinearGradient {
        LinearGradient(
            colors: [AppColors.primaryLight, AppColors.primary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func hero(for colorScheme: ColorScheme) -> LinearGradient {
        AppColors.heroGradient(for: colorScheme)
    }

    static func primarySoft(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [AppColors.surfaceSoft, AppColors.surface]
                : [AppColors.surface, AppColors.surfaceSoft],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
