import SwiftUI

enum Brand {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Span"
    static let tagline = "See who you know. Find who to meet."
    static let creatorName = Bundle.main.object(forInfoDictionaryKey: "CreatorName") as? String ?? ""
    static var creatorURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "CreatorLinkedInURL") as? String,
              let url = URL(string: value), url.scheme == "https",
              url.host == "www.linkedin.com", url.path.hasPrefix("/in/") else { return nil }
        return url
    }
    static let ink = Color(red: 0.08, green: 0.19, blue: 0.16)
    static let accent = Color(red: 0.77, green: 0.25, blue: 0.14)
    static let paper = Color(red: 0.98, green: 0.97, blue: 0.93)
}

struct BrandMark: View {
    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let icon = NSImage(contentsOf: url) {
                Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up").resizable().scaledToFit()
                    .foregroundStyle(Brand.ink)
            }
        }
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
    }
}
