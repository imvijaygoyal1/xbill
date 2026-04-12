import SwiftUI

// MARK: - App Icon Reference
//
// The AppIcon asset is defined in xBill/Assets.xcassets/AppIcon.appiconset/
// and is automatically used as the app's home-screen icon by Xcode.
//
// To reference the icon image at runtime (e.g. in an About screen):

extension Image {
    /// The app's icon as a SwiftUI Image, loaded from the asset catalog.
    static var appIcon: Image {
        Image("AppIcon-1024") // reference the 1024pt image added to Assets.xcassets
    }
}

// MARK: - Usage example

struct AppIconView: View {
    var body: some View {
        Image.appIcon
            .resizable()
            .scaledToFit()
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .shadow(radius: 4)
    }
}

// MARK: - UIKit equivalent (for UIImageView)
//
//   let iconImageView = UIImageView(image: UIImage(named: "AppIcon"))
//
// Note: UIImage(named: "AppIcon") works on device/simulator to load the
// current app icon. On simulator it may return nil — prefer the asset
// catalog image name ("AppIcon-1024") added explicitly as an Image Set.
