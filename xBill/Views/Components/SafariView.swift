//
//  SafariView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI
import SafariServices

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredBarTintColor = UIColor(Color.brandPrimary)
        vc.preferredControlTintColor = .white
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

extension View {
    func safariSheet(isPresented: Binding<Bool>, url: URL) -> some View {
        self.sheet(isPresented: isPresented) {
            SafariView(url: url)
                .ignoresSafeArea()
        }
    }
}
