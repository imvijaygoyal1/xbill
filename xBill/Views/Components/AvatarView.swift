//
//  AvatarView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI

struct AvatarView: View {
    let name: String
    var url: URL? = nil
    var size: CGFloat = XBillIcon.avatarMd

    private var initials: String {
        name.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
    }

    private var bgColor: Color {
        let colors: [Color] = [.brandPrimary, .brandAccent, .moneyPositive, .brandDeep, .catEntertain]
        let index = abs(name.hashValue) % colors.count
        return colors[index]
    }

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure, .empty:
                        initialsView
                    @unknown default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsView: some View {
        ZStack {
            bgColor
            Text(initials)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(Color.textInverse)
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        AvatarView(name: "Alice Wonderland", size: XBillIcon.avatarLg)
        AvatarView(name: "Bob Smith", size: XBillIcon.avatarMd)
        AvatarView(name: "C", size: XBillIcon.avatarSm)
    }
    .padding()
}
