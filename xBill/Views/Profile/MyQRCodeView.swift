//
//  MyQRCodeView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - MyQRCodeView

struct MyQRCodeView: View {
    let userID:      UUID
    let displayName: String

    @Environment(\.dismiss) private var dismiss
    @State private var qrImage: UIImage? = nil

    private var deepLinkURL: URL? {
        URL(string: "xbill://add/\(userID.uuidString)")
    }

    var body: some View {
        NavigationStack {
            XBillScreenContainer(
                horizontalPadding: AppSpacing.lg,
                bottomPadding: AppSpacing.xxl
            ) {
                XBillPageHeader(
                    title: "My QR Code",
                    subtitle: "Share your code to let friends add you on xBill.",
                    showsBackButton: true,
                    backAction: { dismiss() }
                )
                .padding(.horizontal, -AppSpacing.lg)

                XBillQRCodeIllustration(size: 210)
                    .frame(maxWidth: .infinity)

                Text("Share your code to let friends add you on xBill.")
                    .font(.appBody)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)

                if let image = qrImage {
                    XBillQRCodeCard(image: image, label: "Scan to add \(displayName)")
                        .accessibilityLabel("QR code for \(displayName)")
                } else {
                    ProgressView()
                        .frame(width: 220, height: 220)
                }

                if let url = deepLinkURL {
                    ShareLink(item: url, subject: Text("Add me on xBill"),
                              message: Text("Tap to add \(displayName) as a friend on xBill.")) {
                        Label("Share Link", systemImage: "square.and.arrow.up")
                            .font(.appTitle)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .navigationBarBackButtonHidden()
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(AppColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task {
                if let url = deepLinkURL {
                    qrImage = generateQRCode(from: url.absoluteString)
                }
            }
        }
    }

    private static let ciContext = CIContext()

    private func generateQRCode(from string: String) -> UIImage? {
        let filter  = CIFilter.qrCodeGenerator()
        filter.message         = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let ciImage = filter.outputImage else { return nil }
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = Self.ciContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
