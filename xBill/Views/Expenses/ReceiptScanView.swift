//
//  ReceiptScanView.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import SwiftUI
import UIKit
import VisionKit
import PhotosUI

// MARK: - DocumentCameraView
// Wraps VNDocumentCameraViewController — automatically detects receipt boundary,
// applies perspective correction, and captures ALL pages (Gap 6: multi-page support).

private struct DocumentCameraView: UIViewControllerRepresentable {
    @Binding var scannedPages: [UIImage]
    @Binding var isPresented:  Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentCameraView
        init(_ parent: DocumentCameraView) { self.parent = parent }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            // Capture every page so multi-page receipts are fully processed
            parent.scannedPages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.isPresented  = false
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.isPresented = false
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            parent.isPresented = false
        }
    }
}

// MARK: - ReceiptScanView

struct ReceiptScanView: View {
    @Bindable var vm: ReceiptViewModel
    var members: [User] = []
    var onConfirmed: (([SplitInput]) -> Void)? = nil

    @State private var showCamera      = false
    @State private var selectedPhoto:  PhotosPickerItem? = nil
    @State private var showReview      = false
    @State private var photoTask:      Task<Void, Never>? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let image = vm.capturedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)

                    // Multi-page badge
                    if vm.capturedPages.count > 1 {
                        Text("\(vm.capturedPages.count) pages captured")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if vm.isScanning {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Scanning receipt…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else if vm.scannedReceipt != nil {
                        VStack(spacing: 10) {
                            Button {
                                showReview = true
                            } label: {
                                Label("Review Receipt", systemImage: "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(.tint)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }

                            Button {
                                vm.capturedPages  = []
                                vm.scannedReceipt = nil
                                vm.items          = []
                            } label: {
                                Text("Scan Again")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(.systemGray5))
                                    .foregroundStyle(.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemGray6))
                            .frame(height: 260)
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text.viewfinder")
                                .font(.system(size: 56))
                                .foregroundStyle(.secondary)
                            Text("Scan or upload a receipt")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)

                    VStack(spacing: 12) {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Scan Receipt", systemImage: "camera.fill")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.tint)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(!VNDocumentCameraViewController.isSupported)

                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("Choose from Library", systemImage: "photo.fill")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.systemGray5))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }

                        Button {
                            vm.startManually(members: members)
                            showReview = true
                        } label: {
                            Label("Enter Manually", systemImage: "pencil")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.systemGray6))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(.horizontal, 24)
                }

                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Scan Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showReview) {
                ReceiptReviewView(vm: vm) { splits in
                    onConfirmed?(splits)
                    dismiss()
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                DocumentCameraView(scannedPages: $vm.capturedPages, isPresented: $showCamera)
                    .ignoresSafeArea()
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                photoTask?.cancel()
                photoTask = Task {
                    if let data  = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        vm.capturedPages = [image]
                    }
                    selectedPhoto = nil
                }
            }
            .onChange(of: vm.capturedPages) { _, pages in
                guard !pages.isEmpty else { return }
                Task { await vm.scan(pages: pages) }
            }
        }
        .onAppear { vm.members = members }
        .errorAlert(item: $vm.errorAlert)
    }
}

#Preview {
    ReceiptScanView(vm: ReceiptViewModel())
}
