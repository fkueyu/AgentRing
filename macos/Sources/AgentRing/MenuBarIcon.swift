// MenuBarIcon.swift — the brand ring as a template image for the menu bar.
//
// The PNGs are generated from macos/Resources/Logo.png by build.sh. A template
// image lets AppKit invert the artwork automatically for light/dark menu bars.

import AppKit
import SwiftUI

enum MenuBarIcon {
    static let image: NSImage? = {
        let bundle = Bundle.main
        // Prefer the 2x asset for Retina, but always expose an 18 pt image.
        let path = bundle.path(forResource: "MenuBarIcon@2x", ofType: "png")
            ?? bundle.path(forResource: "MenuBarIcon", ofType: "png")
        guard let path, let image = NSImage(contentsOfFile: path) else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()
}

struct MenuBarGlyph: View {
    var body: some View {
        if let image = MenuBarIcon.image {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)
                .accessibilityLabel("AgentRing")
        } else {
            Image(systemName: "circle.dotted")
                .font(.system(size: 15, weight: .regular))
                .accessibilityLabel("AgentRing")
        }
    }
}
