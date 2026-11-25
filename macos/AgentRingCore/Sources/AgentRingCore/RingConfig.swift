import Foundation

/// The v3 display configuration, ported from `daemon/src/config.mjs`.
///
/// The App Store app will own this config in its sandbox container; the core
/// keeps the same defaults, ranges and fallbacks as the daemon so the renderer
/// can be ported without a second set of rules.
public struct RingConfig: Codable, Sendable, Equatable {
    public var version: Int
    public var display: Display
    public var layout: Layout
    public var motion: Motion
    public var sources: [String: Source]
    public var stateColors: [String: String]

    public static let currentVersion = 3
    public static let stateKeys = ["thinking", "tool", "editing", "waiting", "done", "error"]
    public static let accents = ["state", "source", "neon", "sunset", "mint", "aurora", "ember", "rainbow"]
    public static let standbyModes = ["dot", "orbit", "breathe"]
    public static let standbyPalettes = ["mono", "neon", "sunset", "mint", "aurora", "ember", "rainbow"]
    public static let layoutModes = ["split", "focus", "rotate"]
    public static let effectsByState: [String: [String]] = [
        "thinking": ["breathe", "comet"],
        "tool": ["breathe", "comet", "pulse"],
        "editing": ["patches", "pulse"],
        "waiting": ["breathe", "blink"],
        "done": ["flash", "solid"],
        "error": ["blink", "solid"],
    ]
    public static let defaultEffects: [String: String] = [
        "thinking": "breathe",
        "tool": "comet",
        "editing": "patches",
        "waiting": "breathe",
        "done": "flash",
        "error": "blink",
    ]

    public static let fallback = RingConfig(
        version: currentVersion,
        display: Display(),
        layout: Layout(),
        motion: Motion(),
        sources: Source.defaults,
        stateColors: [
            "thinking": "#4d6bfe",
            "tool": "#2e9bff",
            "editing": "#a855f7",
            "waiting": "#ffaa28",
            "done": "#28dc6e",
            "error": "#ff3030",
        ]
    )

    public struct Display: Codable, Sendable, Equatable {
        public var accent: String = "state"
        public var rainbowSpeed: Double = 0.35
        public var brightness: Double = 0.5
        public var standby: String = "dot"
        public var standbyPalette: String = "mono"
        public var standbySpeed: Double = 1
        public var standbyColor: String = "#b4beff"
        public var gamma: Double = 1
        public var currentLimitMa: Double = 900
        public var nightMode = NightMode()

        public init() {}
    }

    public struct NightMode: Codable, Sendable, Equatable {
        public var enabled: Bool = false
        public var startMinute: Int = 23 * 60
        public var endMinute: Int = 7 * 60
        public var brightness: Double = 0.08

        public init() {}
    }

    public struct Layout: Codable, Sendable, Equatable {
        public var mode: String = "split"
        public var maxAgents: Double = 4
        public var gapLeds: Double = 1
        public var showIdle: Bool = false
        public var rotateSeconds: Double = 8

        public init() {}
    }

    public struct Motion: Codable, Sendable, Equatable {
        public var speeds = Speeds()
        public var effects = Effects()
        public var doneHoldSeconds: Double = 8
        public var staleMinutes: Double = 10

        public init() {}

        public struct Speeds: Codable, Sendable, Equatable {
            public var thinking: Double = 1
            public var tool: Double = 1
            public var editing: Double = 1
            public var waiting: Double = 1
            public var done: Double = 1
            public var error: Double = 1

            public init() {}
        }

        public struct Effects: Codable, Sendable, Equatable {
            public var thinking: String = "breathe"
            public var tool: String = "comet"
            public var editing: String = "patches"
            public var waiting: String = "breathe"
            public var done: String = "flash"
            public var error: String = "blink"

            public init() {}
        }
    }

    public struct Source: Codable, Sendable, Equatable {
        public var enabled: Bool = true
        public var color: String = "#8c8ca0"

        public init(enabled: Bool = true, color: String = "#8c8ca0") {
            self.enabled = enabled
            self.color = color
        }

        public static let defaults: [String: Source] = [
            "codex": Source(color: "#10a37f"),
            "dsh": Source(color: "#4d6bfe"),
            "claude": Source(color: "#d97757"),
            "gemini": Source(color: "#4a8cff"),
            "cursor": Source(color: "#8b5cf6"),
            "opencode": Source(color: "#10b981"),
            "qwen": Source(color: "#6366f1"),
            "kimi": Source(color: "#22d3ee"),
            "grok": Source(color: "#e5e7eb"),
            "pi": Source(color: "#f472b6"),
            "omp": Source(color: "#fbbf24"),
            "qoder": Source(color: "#34d399"),
            "factory": Source(color: "#fb7185"),
            "codebuddy": Source(color: "#60a5fa"),
            "zcode": Source(color: "#f59e0b"),
            "hermes": Source(color: "#a78bfa"),
            "trae": Source(color: "#ff4d4d"),
            "workbuddy": Source(color: "#ff9f0a"),
        ]
    }

    public init(
        version: Int = currentVersion,
        display: Display = Display(),
        layout: Layout = Layout(),
        motion: Motion = Motion(),
        sources: [String: Source] = Source.defaults,
        stateColors: [String: String] = fallbackColors
    ) {
        self.version = version
        self.display = display
        self.layout = layout
        self.motion = motion
        self.sources = sources
        self.stateColors = stateColors
    }

    public init(from decoder: Decoder) throws {
        guard let raw = try? RawRingConfig(from: decoder) else {
            self = .fallback
            return
        }
        self = Self.sanitize(raw)
    }

    // Explicit encode keeps the config shape stable even though `init(from:)`
    // is custom.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(display, forKey: .display)
        try c.encode(layout, forKey: .layout)
        try c.encode(motion, forKey: .motion)
        try c.encode(sources, forKey: .sources)
        try c.encode(stateColors, forKey: .stateColors)
    }

    private enum CodingKeys: String, CodingKey {
        case version, display, layout, motion, sources, stateColors
    }

    /// Clamp/validate a raw config exactly where the daemon does.
    private static func sanitize(_ raw: RawRingConfig, base: RingConfig = .fallback) -> RingConfig {
        var config = base
        config.version = currentVersion

        let display = raw.display
        let legacyRainbow = display?.standby == "rainbow"
        config.display.accent = oneOf(display?.accent, Self.accents, base.display.accent)
        config.display.rainbowSpeed = clamp(display?.rainbowSpeed, 0, 2, base.display.rainbowSpeed)
        config.display.brightness = clamp(display?.brightness, 0.05, 1, base.display.brightness)
        config.display.standby = oneOf(
            legacyRainbow ? "orbit" : display?.standby,
            Self.standbyModes,
            base.display.standby
        )
        let palette = legacyRainbow && display?.standbyPalette == nil
            ? "rainbow"
            : display?.standbyPalette
        config.display.standbyPalette = oneOf(
            palette,
            Self.standbyPalettes,
            base.display.standbyPalette
        )
        config.display.standbySpeed = clamp(display?.standbySpeed, 0.2, 3, base.display.standbySpeed)
        config.display.standbyColor = normalizeHex(
            display?.standbyColor,
            base.display.standbyColor
        )
        config.display.gamma = clamp(display?.gamma, 0.8, 2.6, base.display.gamma)
        config.display.currentLimitMa = clamp(
            display?.currentLimitMa,
            300,
            2000,
            base.display.currentLimitMa
        )

        let night = display?.nightMode
        config.display.nightMode.enabled = night?.enabled ?? base.display.nightMode.enabled
        config.display.nightMode.startMinute = clampInt(
            night?.startMinute,
            0,
            1439,
            base.display.nightMode.startMinute
        )
        config.display.nightMode.endMinute = clampInt(
            night?.endMinute,
            0,
            1439,
            base.display.nightMode.endMinute
        )
        config.display.nightMode.brightness = clamp(
            night?.brightness,
            0.02,
            0.5,
            base.display.nightMode.brightness
        )

        let layout = raw.layout
        config.layout.mode = oneOf(layout?.mode, Self.layoutModes, base.layout.mode)
        config.layout.maxAgents = Double(clampInt(
            layout?.maxAgents.map { Int($0.rounded()) },
            1,
            8,
            Int(base.layout.maxAgents)
        ))
        config.layout.gapLeds = Double(clampInt(
            layout?.gapLeds.map { Int($0.rounded()) },
            0,
            3,
            Int(base.layout.gapLeds)
        ))
        config.layout.showIdle = layout?.showIdle ?? base.layout.showIdle
        config.layout.rotateSeconds = Double(clampInt(
            layout?.rotateSeconds.map { Int($0.rounded()) },
            3,
            60,
            Int(base.layout.rotateSeconds)
        ))

        let motion = raw.motion
        let rawSpeeds = motion?.speeds ?? [:]
        var speeds = Motion.Speeds()
        speeds.thinking = round1(clamp(rawSpeeds["thinking"], 0.2, 3, base.motion.speeds.thinking))
        speeds.tool = round1(clamp(rawSpeeds["tool"], 0.2, 3, base.motion.speeds.tool))
        speeds.editing = round1(clamp(rawSpeeds["editing"], 0.2, 3, base.motion.speeds.editing))
        speeds.waiting = round1(clamp(rawSpeeds["waiting"], 0.2, 3, base.motion.speeds.waiting))
        speeds.done = round1(clamp(rawSpeeds["done"], 0.2, 3, base.motion.speeds.done))
        speeds.error = round1(clamp(rawSpeeds["error"], 0.2, 3, base.motion.speeds.error))
        config.motion.speeds = speeds

        let rawEffects = motion?.effects ?? [:]
        var effects = Motion.Effects()
        effects.thinking = effect("thinking", rawEffects["thinking"], base.motion.effects.thinking)
        effects.tool = effect("tool", rawEffects["tool"], base.motion.effects.tool)
        effects.editing = effect("editing", rawEffects["editing"], base.motion.effects.editing)
        effects.waiting = effect("waiting", rawEffects["waiting"], base.motion.effects.waiting)
        effects.done = effect("done", rawEffects["done"], base.motion.effects.done)
        effects.error = effect("error", rawEffects["error"], base.motion.effects.error)
        config.motion.effects = effects

        config.motion.doneHoldSeconds = Double(clampInt(
            motion?.doneHoldSeconds.map { Int($0.rounded()) },
            2,
            30,
            Int(base.motion.doneHoldSeconds)
        ))
        config.motion.staleMinutes = Double(clampInt(
            motion?.staleMinutes.map { Int($0.rounded()) },
            2,
            60,
            Int(base.motion.staleMinutes)
        ))

        var sources = base.sources
        let incoming = raw.sources ?? [:]
        for key in Set(base.sources.keys).union(incoming.keys) {
            let prior = base.sources[key] ?? Source()
            let next = incoming[key]
            sources[key] = Source(
                enabled: next?.enabled ?? prior.enabled,
                color: normalizeHex(next?.color, prior.color)
            )
        }
        config.sources = sources

        var colors = base.stateColors
        let rawColors = raw.stateColors ?? [:]
        for key in Self.stateKeys {
            colors[key] = normalizeHex(rawColors[key], base.stateColors[key] ?? "#888888")
        }
        config.stateColors = colors
        return config
    }

    public static var fallbackColors: [String: String] {
        [
            "thinking": "#4d6bfe",
            "tool": "#2e9bff",
            "editing": "#a855f7",
            "waiting": "#ffaa28",
            "done": "#28dc6e",
            "error": "#ff3030",
        ]
    }

    private static func effect(_ state: String, _ value: String?, _ base: String) -> String {
        let allowed = effectsByState[state] ?? []
        if let value, allowed.contains(value) { return value }
        if allowed.contains(base) { return base }
        return defaultEffects[state] ?? base
    }

    private static func oneOf(_ value: String?, _ allowed: [String], _ fallback: String) -> String {
        guard let value, allowed.contains(value) else { return fallback }
        return value
    }

    private static func clamp(_ value: Double?, _ min: Double, _ max: Double, _ fallback: Double) -> Double {
        guard let value, value.isFinite else { return fallback }
        return Swift.min(max, Swift.max(min, value))
    }

    private static func clampInt(_ value: Int?, _ min: Int, _ max: Int, _ fallback: Int) -> Int {
        guard let value else { return fallback }
        return Swift.min(max, Swift.max(min, value))
    }

    private static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    static func normalizeHex(_ value: String?, _ fallback: String) -> String {
        guard let value else { return fallback }
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6,
              text.allSatisfy({ $0.isHexDigit }) else { return fallback }
        return "#" + text.lowercased()
    }
}

// MARK: - Tolerant decoding

private struct RawRingConfig: Decodable {
    var version: Int?
    var display: RawDisplay?
    var layout: RawLayout?
    var motion: RawMotion?
    var sources: [String: RawSource]?
    var stateColors: [String: String]?
}

private struct RawDisplay: Decodable {
    var accent: String?
    var rainbowSpeed: Double?
    var brightness: Double?
    var standby: String?
    var standbyPalette: String?
    var standbySpeed: Double?
    var standbyColor: String?
    var gamma: Double?
    var currentLimitMa: Double?
    var nightMode: RawNightMode?
}

private struct RawNightMode: Decodable {
    var enabled: Bool?
    var startMinute: Int?
    var endMinute: Int?
    var brightness: Double?
}

private struct RawLayout: Decodable {
    var mode: String?
    var maxAgents: Double?
    var gapLeds: Double?
    var showIdle: Bool?
    var rotateSeconds: Double?
}

private struct RawMotion: Decodable {
    var speeds: [String: Double]?
    var effects: [String: String]?
    var doneHoldSeconds: Double?
    var staleMinutes: Double?
}

private struct RawSource: Decodable {
    var enabled: Bool?
    var color: String?
}
