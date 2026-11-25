// Theme.swift — colours, state labels, SF Symbols and the menu-bar icon.

import SwiftUI

enum Theme {
    static let amber = Color.orange
    static let red = Color.red
    static let green = Color.green
    static let standby = Color(red: 0.72, green: 0.76, blue: 0.95)

    /// Brand-ish source colours, kept close to each tool's own accent.
    static func source(_ name: String) -> Color {
        return switch name {
        case "codex": Color(red: 0.063, green: 0.639, blue: 0.498)
        case "dsh": Color(red: 0.302, green: 0.420, blue: 0.996)
        case "claude": Color(red: 0.851, green: 0.467, blue: 0.341)
        case "trae": Color(red: 0.867, green: 0.267, blue: 0.267)
        case "workbuddy": Color(red: 0.851, green: 0.529, blue: 0.031)
        default: Color.secondary
        }
    }

    static func sourceLabel(_ name: String) -> String {
        switch name {
        case "codex": "Codex"
        case "dsh": "DeepSeek Harness"
        case "claude": "Claude Code"
        case "trae": "Trae"
        case "workbuddy": "WorkBuddy"
        case "gemini": "Gemini CLI"
        case "cursor": "Cursor"
        case "opencode": "OpenCode"
        case "qwen": "Qwen Code"
        case "kimi": "Kimi CLI"
        case "grok": "Grok Build"
        case "pi": "Pi"
        case "omp": "Oh My Pi"
        case "qoder": "Qoder"
        case "factory": "Factory"
        case "codebuddy": "CodeBuddy"
        case "zcode": "ZCode"
        case "hermes": "Hermes"
        default: name.capitalized
        }
    }

    static func stateLabel(_ state: String) -> String {
        switch state {
        case "thinking": "等模型回复"
        case "tool": "执行工具"
        case "editing": "改文件"
        case "waiting": "等待审批"
        case "done": "完成"
        case "error": "报错"
        case "idle": "空闲"
        default: state
        }
    }

    /// SF Symbol used in menus and status rows for a state.
    static func stateSymbol(_ state: String) -> String {
        switch state {
        case "thinking": "brain.head.profile"
        case "tool": "wrench.and.screwdriver.fill"
        case "editing": "pencil.and.outline"
        case "waiting": "hand.raised.fill"
        case "done": "checkmark.circle.fill"
        case "error": "exclamationmark.triangle.fill"
        case "idle": "moon.zzz.fill"
        default: "circle"
        }
    }

    static func stateColor(_ state: String) -> Color {
        switch state {
        case "thinking": Color(red: 0.302, green: 0.420, blue: 0.996)
        case "tool": Color(red: 0.180, green: 0.608, blue: 1.0)
        case "editing": Color(red: 0.659, green: 0.333, blue: 0.969)
        case "waiting": amber
        case "error": red
        case "done": green
        default: .secondary
        }
    }

    /// The settings window uses a calm, slightly cool neutral stack instead of
    /// the default window chrome: a lighter page, white cards and a quiet
    /// sidebar. Dynamic colours keep the same hierarchy in dark mode.
    static let pageBackground = dynamic(
        light: NSColor(srgbRed: 0.961, green: 0.965, blue: 0.973, alpha: 1),
        dark: NSColor(srgbRed: 0.086, green: 0.090, blue: 0.102, alpha: 1)
    )

    static let sidebarBackground = dynamic(
        light: NSColor(srgbRed: 0.925, green: 0.933, blue: 0.949, alpha: 1),
        dark: NSColor(srgbRed: 0.059, green: 0.063, blue: 0.071, alpha: 1)
    )

    static let cardBackground = dynamic(
        light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        dark: NSColor(srgbRed: 0.125, green: 0.133, blue: 0.153, alpha: 1)
    )

    static let cardStroke = dynamic(
        light: NSColor.black.withAlphaComponent(0.06),
        dark: NSColor.white.withAlphaComponent(0.07)
    )

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

extension Color {
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }

    var hexString: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return String(
            format: "#%02x%02x%02x",
            Int((color.redComponent * 255).rounded()),
            Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded())
        )
    }
}


