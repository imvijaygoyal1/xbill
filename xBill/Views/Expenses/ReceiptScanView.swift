import SwiftUI
import UIKit

// MARK: - ImagePickerController

private struct ImagePickerController: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    @Binding var selectedImage: UIImage?
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate   = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePickerController
        init(_ parent: ImagePickerController) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.selectedImage = info[.originalImage] as? UIImage
            parent.isPresented   = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
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
    @State private var showPhotoPicker = false
    @State private var showReview      = false
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

                    if vm.isScanning {
                        ProgressView("Scanning receipt…")
                    } else if vm.scannedReceipt != nil {
                        // Scan complete — show review CTA
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
                                vm.capturedImage  = nil
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
                    // Placeholder
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

                    // Capture buttons
                    VStack(spacing: 12) {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Take Photo", systemImage: "camera.fill")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.tint)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                        Button {
                            showPhotoPicker = true
                        } label: {
                            Label("Choose from Library", systemImage: "photo.fill")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.systemGray5))
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
            .sheet(isPresented: $showCamera) {
                ImagePickerController(
                    sourceType: .camera,
                    selectedImage: $vm.capturedImage,
                    isPresented: $showCamera
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showPhotoPicker) {
                ImagePickerController(
                    sourceType: .photoLibrary,
                    selectedImage: $vm.capturedImage,
                    isPresented: $showPhotoPicker
                )
                .ignoresSafeArea()
            }
            .onChange(of: vm.capturedImage) { _, image in
                guard let image else { return }
                Task { await vm.scan(image: image) }
            }
        }
        .onAppear { vm.members = members }
        .errorAlert(error: $vm.error)
    }
}

#Preview {
    ReceiptScanView(vm: ReceiptViewModel())
}
