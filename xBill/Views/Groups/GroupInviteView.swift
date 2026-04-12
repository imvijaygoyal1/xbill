import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct GroupInviteView: View {
    let group: BillGroup
    let currentUserID: UUID

    @State private var invite: GroupInvite?
    @State private var isLoading = false
    @State private var error: AppError?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: XBillSpacing.xl) {
                Spacer()

                if isLoading {
                    ProgressView("Generating link…")
                } else if let invite {
                    groupHeader
                    qrCodeView(invite: invite)
                    shareControls(invite: invite)
                    expiryLabel(invite: invite)
                } else {
                    EmptyStateView(
                        icon: "link.badge.plus",
                        title: "Couldn't Generate Link",
                        message: error?.localizedDescription ?? "Try again.",
                        actionLabel: "Retry",
                        action: { Task { await generateInvite() } }
                    )
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Invite via Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if invite != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await generateInvite() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .task { await generateInvite() }
            .errorAlert(error: $error)
        }
    }

    // MARK: - Subviews

    private var groupHeader: some View {
        VStack(spacing: XBillSpacing.sm) {
            Text(group.emoji)
                .font(.system(size: 48))
            Text(group.name)
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)
            Text("Scan or share the link below to join this group")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func qrCodeView(invite: GroupInvite) -> some View {
        Group {
            if let url = invite.inviteURL,
               let qrImage = generateQRCode(from: url.absoluteString) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(XBillSpacing.base)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: XBillRadius.lg))
                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
            }
        }
    }

    private func shareControls(invite: GroupInvite) -> some View {
        Group {
            if let url = invite.inviteURL {
                ShareLink(
                    item: url,
                    message: Text("Join \(group.emoji) \(group.name) on xBill!")
                ) {
                    Label("Share Invite Link", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandPrimary)
            }
        }
    }

    private func expiryLabel(invite: GroupInvite) -> some View {
        Text("Link valid for 7 days · expires \(invite.expiresAt.formatted(date: .abbreviated, time: .omitted))")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }

    // MARK: - Helpers

    private func generateInvite() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            invite = try await GroupService.shared.createInvite(groupID: group.id, createdBy: currentUserID)
        } catch {
            self.error = AppError.from(error)
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
