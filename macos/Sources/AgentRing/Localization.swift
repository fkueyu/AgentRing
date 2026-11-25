// Localization.swift — the in-app language switch and small bilingual helpers.
//
// Static interface copy lives in Resources/<language>.lproj/Localizable.strings
// and is selected with SwiftUI's locale environment. Strings that are assembled
// at runtime (counts, statuses and daemon-provided labels) go through L10n so
// they can be translated without maintaining a second view hierarchy.

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, zh, en

    var id: String { rawValue }

    /// An environment override is useful for screenshots and UI review; normal
    /// runs read the saved preference and fall back to the system language.
    static var current: AppLanguage {
        if let raw = ProcessInfo.processInfo.environment["AGENTRING_LANGUAGE"],
           let language = AppLanguage(rawValue: raw) {
            return language
        }
        let stored = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        return AppLanguage(rawValue: stored) ?? .system
    }

    var locale: Locale {
        switch self {
        case .system: Locale.autoupdatingCurrent
        case .zh: Locale(identifier: "zh-Hans")
        case .en: Locale(identifier: "en")
        }
    }

    var isEnglish: Bool {
        switch self {
        case .en: true
        case .zh: false
        case .system: !(Locale.preferredLanguages.first?.hasPrefix("zh") ?? false)
        }
    }
}

enum L10n {
    static var isEnglish: Bool { AppLanguage.current.isEnglish }
    static var locale: Locale { AppLanguage.current.locale }

    private static let englishBundle: Bundle? = {
        guard let path = Bundle.main.path(forResource: "en", ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }()

    /// Translate a complete key (a daemon label, a status phrase, …). Missing
    /// English entries fall back to the Chinese key rather than an empty string.
    static func text(_ key: String) -> String {
        guard isEnglish, let englishBundle else { return key }
        return englishBundle.localizedString(forKey: key, value: key, table: nil)
    }

    private static func plural(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
        count == 1 ? singular : (plural ?? singular + "s")
    }

    // MARK: Counts

    static func sessions(_ total: Int, active: Int) -> String {
        if isEnglish {
            return "\(total) \(plural(total, "session")) · \(active) active"
        }
        return "\(total) 个会话 · \(active) 个活跃"
    }

    static func sessions(_ total: Int) -> String {
        isEnglish ? "\(total) \(plural(total, "session"))" : "\(total) 个会话"
    }

    static func sessionsParenthetical(_ total: Int, active: Int) -> String {
        if isEnglish {
            return "\(total) \(plural(total, "session")) (\(active) active)"
        }
        return "\(total) 个会话（\(active) 活跃）"
    }

    static func activeSessions(_ active: Int) -> String {
        isEnglish ? "\(active) \(plural(active, "session")) running" : "\(active) 个会话进行中"
    }

    static func waitingApprovals(_ count: Int, long: Bool = false) -> String {
        if isEnglish {
            return long
                ? "\(count) \(plural(count, "session")) waiting for approval"
                : "\(count) waiting for approval"
        }
        return long ? "\(count) 个会话等待审批" : "\(count) 个等待审批"
    }

    static func errors(_ count: Int, long: Bool = false) -> String {
        if isEnglish {
            return long
                ? "\(count) \(plural(count, "session")) failed"
                : "\(count) \(plural(count, "error"))"
        }
        return long ? "\(count) 个会话报错" : "\(count) 个报错"
    }

    static func wired(_ count: Int) -> String {
        isEnglish ? "\(count) wired" : "\(count) 个已接入"
    }

    static func waitingSources(_ count: Int) -> String {
        isEnglish ? "\(count) waiting" : "\(count) 个待接入"
    }

    static func sources(_ count: Int) -> String {
        isEnglish ? "\(count) \(plural(count, "source"))" : "\(count) 个"
    }

    static func restSources(_ count: Int) -> String {
        if isEnglish {
            return "\(count) more \(plural(count, "source")) (colour and switch)"
        }
        return "其余 \(count) 个来源（颜色与开关）"
    }

    static func profile(_ name: String) -> String {
        isEnglish ? "\(name) profile" : "\(name) 配置"
    }

    // MARK: Ring and status

    static func ringStatus(_ fps: Int, synced: Bool = false, connected: Bool = false) -> String {
        if synced {
            if isEnglish { return fps > 0 ? "Ring synced · \(fps) fps" : "Ring synced" }
            return fps > 0 ? "灯环已同步 · \(fps) fps" : "灯环已同步"
        }
        if connected {
            if isEnglish { return fps > 0 ? "Connected · \(fps) fps" : "Connected" }
            return fps > 0 ? "已连接 · \(fps) fps" : "已连接"
        }
        if isEnglish { return fps > 0 ? "Ring online · \(fps) fps" : "Ring online" }
        return fps > 0 ? "灯环在线 · \(fps) fps" : "灯环在线"
    }

    static func previewFoot(synced: Bool) -> String {
        if isEnglish {
            return synced ? "Effect preview · synced to ring" : "Effect preview · ring offline"
        }
        return synced ? "效果预览 · 已同步灯环" : "效果预览 · 灯环未连接"
    }

    static func standbyLine(_ label: String) -> String {
        isEnglish ? "Standby · \(label)" : "待机 · \(label)"
    }

    static func effectLine(_ state: String, _ effect: String) -> String {
        "\(state) · \(effect)"
    }

    static func effectSpeedHelp(_ state: String) -> String {
        isEnglish ? "\(state) effect speed" : "\(state)的动效速度"
    }

    // MARK: Layout and timing

    static func segments(_ count: Int) -> String {
        isEnglish ? "\(count) \(plural(count, "segment"))" : "\(count) 段"
    }

    static func leds(_ count: Int) -> String {
        isEnglish ? "\(count) \(count == 1 ? "LED" : "LEDs")" : "\(count) 颗"
    }

    static func seconds(_ count: Int) -> String {
        isEnglish ? "\(count) s" : "\(count) 秒"
    }

    static func minutes(_ count: Int) -> String {
        isEnglish ? "\(count) min" : "\(count) 分"
    }

    static func segmentSummary(max: Int, gap: Int) -> String {
        if isEnglish {
            return "Up to \(max) \(plural(max, "segment")) · \(gap) \(gap == 1 ? "LED" : "LEDs") between"
        }
        return "最多 \(max) 段 · 段间空 \(gap) 颗灯"
    }

    static func actualBrightness(_ percent: Int) -> String {
        isEnglish ? "Output \(percent)%" : "实际输出 \(percent)%"
    }

    static func silentMinutes(_ minutes: Int) -> String {
        if isEnglish { return "Back to idle after \(minutes) min without events" }
        return "静默 \(minutes) 分钟后回到空闲"
    }

    static func colourFor(_ label: String) -> String {
        isEnglish ? "\(label) colours" : "\(label)配色"
    }

    static func layoutBlurb(_ id: String, seconds: Int) -> String {
        if isEnglish {
            switch id {
            case "focus":
                return "Keep only the segment that needs attention most; other sessions wait."
            case "rotate":
                return "Switch to the next group every \(seconds) s; useful when there are many sessions."
            default:
                return "Divide the ring between sessions in order; see all progress at a glance."
            }
        }
        switch id {
        case "focus":
            return "只保留最需要关注的那一段，其余会话暂时让位。"
        case "rotate":
            return "每隔 \(seconds) 秒轮换到下一组会话，适合会话很多时。"
        default:
            return "把环按顺序切分给每个会话，一眼看到全部进展。"
        }
    }

    // MARK: Daemon-provided source details

    /// The daemon describes a bridge in Chinese because it is also used by the
    /// browser preview. Translate the handful of shapes the sources probe emits
    /// while leaving paths, profile names and bundle names intact.
    static func sourceDetail(_ raw: String) -> String {
        guard isEnglish, raw != "—" else { return raw }

        if let range = raw.range(of: " 个 hook · ") {
            let count = raw[raw.startIndex..<range.lowerBound]
            let path = raw[range.upperBound...]
            return "\(count) hooks · \(path)"
        }

        if raw.hasPrefix("插件装在 "), let range = raw.range(of: "，当前运行 "), raw.hasSuffix(" 配置") {
            let installed = raw[raw.index(raw.startIndex, offsetBy: "插件装在 ".count)..<range.lowerBound]
            let profile = raw[range.upperBound..<raw.index(raw.endIndex, offsetBy: -" 配置".count)]
            return "Plugin installed in \(installed); running the \(profile) profile"
        }

        if raw.hasPrefix("已安装到 "), raw.hasSuffix("，但未在插件列表启用") {
            let profile = raw
                .replacingOccurrences(of: "已安装到 ", with: "")
                .replacingOccurrences(of: "，但未在插件列表启用", with: "")
            return "Installed in \(profile), but not enabled in the plugin list"
        }

        if raw.hasSuffix(" 中没有 AgentRing hook") {
            let path = raw.replacingOccurrences(of: " 中没有 AgentRing hook", with: "")
            return "No AgentRing hook in \(path)"
        }

        if raw.contains(" 配置 · ") {
            return raw.replacingOccurrences(of: " 配置 · ", with: " profile · ")
        }

        return text(raw)
    }
}
