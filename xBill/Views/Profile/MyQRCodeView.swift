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

    private var deepLinkURL: URL {
        URL(string: "xbill://add/\(userID.uuidString)")!
    }

    private var qrImage: UIImage? { generateQRCode(from: deepLinkURL.absoluteString) }

    var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.xl) {
                Text("Share your code to let friends add you on xBill.")
                    .font(.appBody)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)

                if let image = qrImage {
                    XBillQRCodeCard(image: image, label: "Scan to add \(displayName)")
                        .accessibilityLabel("QR code for \(displayName)")
                } else {
                    ProgressView()
                        .frame(width: 220, height: 220)
                }

                ShareLink(item: deepLinkURL, subject: Text("Add me on xBill"),
                          message: Text("Tap to add \(displayName) as a friend on xBill.")) {
                    Label("Share Link", systemImage: "square.and.arrow.up")
                        .font(.appTitle)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.top, AppSpacing.xl)
            .padding(.horizontal, AppSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("My QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter  = CIFilter.qrCodeGenerator()
        filter.message         = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let ciImage = filter.outputImage else { return nil }
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
