import SwiftUI
import AppKit

/// The app icon artwork — the Command Deck grid mark on the violet→indigo brand squircle.
/// Rendered offscreen at 1024² via `--render-icon`, then sliced into an .icns by
/// `Tools/make-icon.sh`. Kept in code so the icon and the in-app brand never drift apart.
struct IconView: View {
    var body: some View {
        ZStack {
            let squircle = RoundedRectangle(cornerRadius: 224, style: .continuous)
            squircle
                .fill(
                    LinearGradient(colors: [Color(hex: 0x8B6BFF), Color(hex: 0x5B8DEF)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    // top sheen
                    LinearGradient(colors: [.white.opacity(0.28), .clear],
                                   startPoint: .top, endPoint: .center)
                    .clipShape(squircle)
                )
                .overlay(
                    RadialGradient(colors: [Color(hex: 0x9C7BFF).opacity(0.55), .clear],
                                   center: .topLeading, startRadius: 40, endRadius: 720)
                    .clipShape(squircle)
                )
                .overlay(squircle.strokeBorder(.white.opacity(0.14), lineWidth: 3))
                .frame(width: 824, height: 824)
                .shadow(color: Color(hex: 0x4B2DCB).opacity(0.55), radius: 60, y: 26)

            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 392, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: Color(hex: 0x3A1E9E).opacity(0.45), radius: 26, y: 10)
        }
        .frame(width: 1024, height: 1024)
    }
}

enum IconRenderer {
    @MainActor
    static func renderAndExit(to path: String) -> Never {
        let renderer = ImageRenderer(content: IconView().frame(width: 1024, height: 1024))
        renderer.scale = 1
        if let img = renderer.nsImage,
           let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            FileHandle.standardError.write(Data("rendered icon \(path)\n".utf8))
        } else {
            FileHandle.standardError.write(Data("icon render failed\n".utf8))
        }
        exit(0)
    }
}
