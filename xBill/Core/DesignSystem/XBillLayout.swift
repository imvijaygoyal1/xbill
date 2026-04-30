//
//  XBillLayout.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

enum XBillSpacing {
    static let xs:   CGFloat = 4
    static let sm:   CGFloat = 8
    static let md:   CGFloat = 12
    static let base: CGFloat = 16
    static let lg:   CGFloat = 20
    static let xl:   CGFloat = 24
    static let xxl:  CGFloat = 32
    static let xxxl: CGFloat = 48
}

// Clay border radius scale
// Sharp (4): inputs, ghost buttons
// Standard (8): small cards, images
// Badge (12): tag badges, pill buttons
// Card (24): feature cards, panels
// Section (40): large sections, footer containers

enum XBillRadius {
    static let sharp:   CGFloat = 4    // inputs, ghost buttons
    static let sm:      CGFloat = 8    // small cards, image insets
    static let md:      CGFloat = 12   // badges, standard buttons
    static let lg:      CGFloat = 16   // intermediate (kept for compat)
    static let card:    CGFloat = 24   // feature cards — clay standard
    static let section: CGFloat = 40   // large containers, footer
    static let full:    CGFloat = 999  // pill / fully-rounded
}

enum XBillIcon {
    static let categorySize: CGFloat = 36
    static let avatarSm:     CGFloat = 32
    static let avatarMd:     CGFloat = 40
    static let avatarLg:     CGFloat = 56
    static let tabBarHeight: CGFloat = 49
    static let fabSize:      CGFloat = 56
}
