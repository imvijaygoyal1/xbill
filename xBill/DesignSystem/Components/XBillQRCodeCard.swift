//
//  XBillQRCodeCard.swift
//  xBill
//

import SwiftUI
import UIKit

struct XBillQRCodeCard: View {
    let image: UIImage
    let label: String

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            XBillQRPlaceholderFrame {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            }
            .frame(width: 260, height: 260)
            Text(label)
                .font(.appCaption)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .xbillCard()
    }
}
