// DaemonModel.swift — HTTP polling/pushing and the observable app model.

import AppKit
import Foundation
import SwiftUI

// MARK: - Wire types

struct Agent: Decodable, Identifiable, Equatable, Sendable {
    let key: String
    let source: String
    let sessionId: String?
    let label: String
    let cwd: String?
    let tool: String?
    let state: String

    var id: String { key }
}

struct RingConfig: Codable, Equatable, Sendable {
    var display = Display()
    var layout = Layout()
    var motion = Motion()
    var sources: [String: Source] = [:]
    var stateColors: [String: String] = [
        "thinking": "#4d6bfe",
        "tool": "#2e9bff",
        "editing": "#a855f7",
        "waiting": "#ffaa28",
        "done": "#28dc6e",
        "error": "#ff3030",
    ]

    struct Display: Codable, Equatable, Sendable {
        /// What a running session's arc is coloured by: a state/source
        /// identity palette, a curated ramp, or the rainbow wheel.
        var accent = "state"
        var rainbowSpeed = 0.35
        var brightness = 0.5
        var standby = "dot"
        var standbyPalette = "mono"
        var standbySpeed = 1.0
        var standbyColor = "#b4beff"
        var gamma = 1.0
        var currentLimitMa = 900.0
        var nightMode = NightMode()
    }

    struct NightMode: Codable, Equatable, Sendable {
        var enabled = false
        var startMinute = 23 * 60
        var endMinute = 7 * 60
        var brightness = 0.08
    }

    struct Layout: Codable, Equatable, Sendable {
        var mode = "split"
        var maxAgents = 4.0
        var gapLeds = 1.0
        var showIdle = false
        var rotateSeconds = 8.0
    }

    struct Motion: Codable, Equatable, Sendable {
        var speeds = Speeds()
        var effects = Effects()
        var doneHoldSeconds = 8.0
        var staleMinutes = 10.0

        struct Speeds: Codable, Equatable, Sendable {
            var thinking = 1.0
            var tool = 1.0
            var editing = 1.0
            var waiting = 1.0
            var done = 1.0
            var error = 1.0
        }

        struct Effects: Codable, Equatable, Sendable {
            var thinking = "breathe"
            var tool = "comet"
            var editing = "patches"
            var waiting = "breathe"
            var done = "flash"
            var error = "blink"
        }
    }

    struct Source: Codable, Equatable, Sendable {
        var enabled = true
        var color = "#10a37f"
    }

    static let fallback: RingConfig = {
        var config = RingConfig()
        config.sources = [
            "codex": Source(enabled: true, color: "#10a37f"),
            "dsh": Source(enabled: true, color: "#4d6bfe"),
            "claude": Source(enabled: true, color: "#d97757"),
            "trae": Source(enabled: true, color: "#ff4d4d"),
            "workbuddy": Source(enabled: true, color: "#ff9f0a"),
        ]
        return config
    }()

    func stateColor(_ state: String) -> Color {
        if let hex = stateColors[state], let color = Color(hex: hex) { return color }
        return Theme.stateColor(state)
    }

    func color(for source: String) -> Color {
        if let hex = sources[source]?.color, let color = Color(hex: hex) { return color }
        return Theme.source(source)
    }
}

struct Snapshot: Decodable, Sendable {
    let agents: [Agent]
    let active: Int
    let config: RingConfig?
}

struct DaemonHealth: Decodable, Sendable {
    let version: String?
    let lanFrames: Int?
    let lanLastFrameAt: Double?
    let lanLastFrameFrom: String?
    let streamClients: Int?
    let streamFrames: Int?
    let streamLastFrameAt: Double?
    let streamLastFrameFrom: String?
}

struct EffectOption: Decodable, Identifiable, Sendable, Equatable {
    let id: String
    let label: String
    /// One-line explanation shown in the effect preview card.
    var hint: String? = nil
    /// Palette kind (`state`, `source`, `ramp`, `hue`, `mono`). Effect options
    /// leave this nil; the daemon decides how a palette is drawn.
    var kind: String? = nil
    /// One-line palette description shown under the tile grid.
    var blurb: String? = nil
    /// Palette swatch stops; effect options leave this nil. The daemon keeps
    /// the colours so the app tiles and the rendered LEDs cannot drift.
    var colors: [String]? = nil
}

struct EffectGroup: Decodable, Sendable, Equatable {
    let defaultEffect: String
    let options: [EffectOption]

    enum CodingKeys: String, CodingKey {
        case defaultEffect = "default"
        case options
    }
}

/// Effect metadata comes from the daemon's `/capabilities` endpoint so the app
/// does not maintain a second option list. The fallback only matters while the
/// daemon is unreachable.
struct Capabilities: Decodable, Sendable, Equatable {
    let version: Int
    let standby: EffectGroup
    /// Optional so an app built against a newer daemon still decodes an older
    /// `/capabilities` payload; the fallback covers that case.
    let accents: EffectGroup?
    let standbyPalettes: EffectGroup?
    let effects: [String: EffectGroup]

    static let fallback: Capabilities = {
        func group(_ defaultEffect: String, _ pairs: [(String, String)]) -> EffectGroup {
            EffectGroup(
                defaultEffect: defaultEffect,
                options: pairs.map { EffectOption(id: $0.0, label: $0.1) }
            )
        }
        let ramps = [
            EffectOption(
                id: "neon", label: "霓虹", kind: "ramp", blurb: "青蓝到品红",
                colors: ["#00e5ff", "#7c4dff", "#ff2d95"]
            ),
            EffectOption(
                id: "sunset", label: "日落", kind: "ramp", blurb: "玫红到晚霞金",
                colors: ["#ff3d6e", "#ff7a45", "#ffd166"]
            ),
            EffectOption(
                id: "mint", label: "薄荷", kind: "ramp", blurb: "青绿到薄荷白",
                colors: ["#2ec4b6", "#4cc9f0", "#a8e6cf"]
            ),
            EffectOption(
                id: "aurora", label: "极光", kind: "ramp", blurb: "青绿、天蓝到紫色",
                colors: ["#2dd4bf", "#38bdf8", "#818cf8", "#a855f7"]
            ),
            EffectOption(
                id: "ember", label: "暖光", kind: "ramp", blurb: "暖金到珊瑚色",
                colors: ["#ffe2a8", "#ffb56b", "#ff7a59", "#ff5e7a"]
            ),
        ]
        return Capabilities(
            version: 2,
            standby: group("dot", [
                ("dot", "常亮单点"), ("orbit", "巡游"), ("breathe", "随机呼吸"),
            ]),
            accents: EffectGroup(defaultEffect: "state", options: [
                EffectOption(id: "state", label: "状态色", kind: "state", blurb: "按状态取色，一眼看出在做什么"),
                EffectOption(id: "source", label: "来源色", kind: "source", blurb: "按工具取色，一眼看出是谁"),
            ] + ramps + [
                EffectOption(id: "rainbow", label: "彩虹", kind: "hue", blurb: "色相沿环流动"),
            ]),
            standbyPalettes: EffectGroup(defaultEffect: "mono", options: [
                EffectOption(id: "mono", label: "单色", kind: "mono", blurb: "只用下面选的一种颜色"),
            ] + ramps + [
                EffectOption(id: "rainbow", label: "彩虹", kind: "hue", blurb: "色相沿环流动"),
            ]),
            effects: [
                "thinking": group("breathe", [("breathe", "呼吸"), ("comet", "巡游")]),
                "tool": group("comet", [("breathe", "呼吸"), ("comet", "巡游"), ("pulse", "脉冲")]),
                "editing": group("patches", [("patches", "雨滴"), ("pulse", "脉冲")]),
                "waiting": group("breathe", [("breathe", "呼吸"), ("blink", "闪烁")]),
                "done": group("flash", [("flash", "闪烁"), ("solid", "常亮")]),
                "error": group("blink", [("blink", "闪烁"), ("solid", "常亮")]),
            ]
        )
    }()
}

// MARK: - Source detection

/// Install and bridge status for one agent tool, as reported by `/sources`.
/// Detection is advisory: the daemon reads the tool's manifests and app bundle,
/// it never installs or edits anything.
struct SourceEntry: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let detected: Bool
    let install: Install?
    let bridge: Bridge?
    let error: String?

    struct Install: Decodable, Equatable, Sendable {
        let path: String?
        let version: String?
        let running: Bool?
        let profile: String?
    }

    struct Bridge: Decodable, Equatable, Sendable {
        let state: String
        let kind: String?
        let detail: String?
        /// The installer command shown for manual use.
        let command: String?
        /// True when the daemon can run an AgentRing-owned installer itself.
        let installable: Bool?
    }

    /// Before the first report (or while the daemon is offline) the page still
    /// lists the known agents, without claiming a status.
    static func unknown(_ id: String) -> SourceEntry {
        SourceEntry(id: id, detected: false, install: nil, bridge: nil, error: nil)
    }
}

struct SourceReport: Decodable, Equatable, Sendable {
    let checkedAt: Double
    let entries: [SourceEntry]
}

// MARK: - Model

@MainActor
final class DaemonModel: ObservableObject {
    @Published private(set) var agents: [Agent] = []
    @Published private(set) var connected = false
    @Published private(set) var config = RingConfig.fallback
    @Published private(set) var capabilities = Capabilities.fallback
    /// Whether the physical ring is actually receiving frames (stream preferred,
    /// `/frame` polling as a fallback for older firmware).
    @Published private(set) var ringConnected = false
    @Published private(set) var ringFPS = 0
    @Published private(set) var ringIP = ""
    @Published private(set) var sourceReport: SourceReport?
    @Published private(set) var daemonVersion = ""

    /// Dev-only: point the app at another daemon (e.g. a lab instance on
    /// 7803) so screenshots do not disturb the live ring.
    let base: URL = {
        if let raw = ProcessInfo.processInfo.environment["AGENTRING_BASE"],
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "http://127.0.0.1:7801")!
    }()

    private var pollTask: Task<Void, Never>?
    private var healthTask: Task<Void, Never>?
    private var sourcesTask: Task<Void, Never>?
    private var pushTask: Task<Void, Never>?
    private var lastLanFrames: Int?
    private var lastStreamFrames: Int?
    private var lastHealthAt: Double = 0
    private var lastHealthSource: Bool?
    /// While the user is editing a control, polling must not snap the value back
    /// to the daemon's older copy.
    private var editingConfig = false

    init() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
        healthTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshHealth()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
        // Install state changes outside the app (a plugin install, a hooks
        // edit), so re-detect on a slow poll. The filesystem probes are cheap.
        sourcesTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshSources()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    var activeCount: Int { agents.filter { $0.state != "idle" }.count }
    var waitingCount: Int { agents.filter { $0.state == "waiting" }.count }
    var errorCount: Int { agents.filter { $0.state == "error" }.count }

    func refresh() async {
        var request = URLRequest(url: base.appendingPathComponent("state"))
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, _) = try await AgentRingSession.shared.data(for: request)
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            // Publishing only real changes keeps the settings form from
            // re-evaluating every 1.5 s while nothing is happening.
            if agents != snapshot.agents { agents = snapshot.agents }
            if !connected {
                await loadConfig()
                await loadCapabilities()
                connected = true
            }
        } catch {
            if connected { connected = false }
        }
    }

    /// `/state` is polled often and no longer carries the config; fetch it when
    /// the daemon (re)connects or after an edit.
    /// `/health` tells us whether the ESP32 is actually fetching frames. The app
    /// preview itself also calls `/frame`, so only LAN frames count.
    func refreshHealth() async {
        var request = URLRequest(url: base.appendingPathComponent("health"))
        request.timeoutInterval = 1.5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, _) = try? await AgentRingSession.shared.data(for: request),
              let health = try? JSONDecoder().decode(DaemonHealth.self, from: data) else {
            if ringConnected { ringConnected = false }
            if ringFPS != 0 { ringFPS = 0 }
            if !ringIP.isEmpty { ringIP = "" }
            lastStreamFrames = nil
            lastLanFrames = nil
            lastHealthSource = nil
            return
        }

        if daemonVersion != (health.version ?? "") {
            daemonVersion = health.version ?? ""
        }

        let now = Date().timeIntervalSince1970 * 1000
        let streamFrames = health.streamFrames ?? 0
        let streamLastAt = health.streamLastFrameAt ?? 0
        let useStream = streamFrames > 0 || streamLastAt > 0 || (health.streamClients ?? 0) > 0
        let last = useStream ? streamLastAt : (health.lanLastFrameAt ?? 0)
        let online = last > 0 && now - last < 2500
        if ringConnected != online { ringConnected = online }

        let address = online
            ? ((useStream ? health.streamLastFrameFrom : health.lanLastFrameFrom) ?? "")
            : ""
        if ringIP != address { ringIP = address }

        let counter = useStream ? streamFrames : (health.lanFrames ?? 0)
        let previous = useStream ? lastStreamFrames : lastLanFrames
        if let previous, lastHealthAt > 0, lastHealthSource == useStream {
            let seconds = (now - lastHealthAt) / 1000
            let fps = seconds > 0 ? Double(max(0, counter - previous)) / seconds : 0
            let rounded = online ? Int(fps.rounded()) : 0
            if ringFPS != rounded { ringFPS = rounded }
        } else if online, ringFPS != 0 {
            ringFPS = 0
        }

        lastStreamFrames = streamFrames
        lastLanFrames = health.lanFrames
        lastHealthSource = useStream
        lastHealthAt = now
    }

    /// Fetch the daemon-owned effect catalogue after connecting. A failed fetch
    /// keeps the offline fallback, so the settings still render.
    func loadCapabilities() async {
        var request = URLRequest(url: base.appendingPathComponent("capabilities"))
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, _) = try? await AgentRingSession.shared.data(for: request),
              let remote = try? JSONDecoder().decode(Capabilities.self, from: data) else { return }
        if capabilities != remote { capabilities = remote }
    }

    func sourceEntry(_ id: String) -> SourceEntry? {
        sourceReport?.entries.first { $0.id == id }
    }

    func refreshSources() async {
        var request = URLRequest(url: base.appendingPathComponent("sources"))
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, _) = try? await AgentRingSession.shared.data(for: request),
              let report = try? JSONDecoder().decode(SourceReport.self, from: data) else { return }
        // checkedAt changes on every poll; republish only when the status did.
        if sourceReport?.entries != report.entries || sourceReport == nil {
            sourceReport = report
        }
    }

    /// Mirror a synthetic state/effect to the physical ring (and every `/frame`
    /// reader) for `ttlMs`. The lighting page refreshes this while previewing
    /// and clears it when the preview closes.
    func setPreview(state: String, effect: String, ttlMs: Int = 45_000) async -> Bool {
        var request = URLRequest(url: base.appendingPathComponent("preview"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["state": state, "effect": effect, "ttlMs": ttlMs]
        )
        guard let (_, response) = try? await AgentRingSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    func clearPreview() async {
        var request = URLRequest(url: base.appendingPathComponent("preview"))
        request.httpMethod = "DELETE"
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData
        _ = try? await AgentRingSession.shared.data(for: request)
    }

    /// Run AgentRing's bridge installer for one source. Returns an error
    /// message on failure; success updates the published source report.
    func installBridge(_ id: String) async -> String? {
        var request = URLRequest(
            url: base
                .appendingPathComponent("sources")
                .appendingPathComponent(id)
                .appendingPathComponent("install")
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 40
        request.cachePolicy = .reloadIgnoringLocalCacheData

        struct Reply: Decodable {
            let ok: Bool
            let error: String?
            let report: SourceReport?
        }

        guard let (data, _) = try? await AgentRingSession.shared.data(for: request),
              let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            return "无法连接守护进程"
        }
        if reply.ok {
            if let report = reply.report {
                sourceReport = report
            } else {
                await refreshSources()
            }
            return nil
        }
        return reply.error ?? "接入失败"
    }

    func effectOptions(for state: String) -> [EffectOption] {
        capabilities.effects[state]?.options ?? Capabilities.fallback.effects[state]?.options ?? []
    }

    func effectLabel(for state: String, id: String) -> String {
        effectOptions(for: state).first(where: { $0.id == id })?.label ?? id
    }

    func standbyOptions() -> [EffectOption] {
        let options = capabilities.standby.options
        return options.isEmpty ? Capabilities.fallback.standby.options : options
    }

    func standbyLabel(id: String) -> String {
        standbyOptions().first(where: { $0.id == id })?.label ?? id
    }

    func paletteOptions() -> [EffectOption] {
        capabilities.standbyPalettes?.options
            ?? Capabilities.fallback.standbyPalettes?.options
            ?? []
    }

    func paletteLabel(id: String) -> String {
        paletteOptions().first(where: { $0.id == id })?.label ?? id
    }

    func paletteBlurb(_ id: String) -> String? {
        paletteOptions().first(where: { $0.id == id })?.blurb
    }

    func paletteKind(_ id: String) -> String {
        if let kind = paletteOptions().first(where: { $0.id == id })?.kind { return kind }
        switch id {
        case "rainbow": return "hue"
        case "mono": return "mono"
        default: return "ramp"
        }
    }

    /// Display swatches for a palette. Mono has no fixed stops: its swatch is
    /// the colour picker's current value. Rainbow has no stops either, so the
    /// tile shows a representative hue run instead of falling back to grey.
    func paletteSwatches(_ id: String) -> [Color] {
        switch paletteKind(id) {
        case "mono":
            return [Color(hex: config.display.standbyColor) ?? Theme.standby]
        case "hue":
            return Self.rainbowSwatches
        default:
            let hexes = paletteOptions().first(where: { $0.id == id })?.colors ?? []
            return hexes.compactMap { Color(hex: $0) }
        }
    }

    // MARK: - Session accent

    func accentOptions() -> [EffectOption] {
        let options = capabilities.accents?.options ?? []
        return options.isEmpty ? (Capabilities.fallback.accents?.options ?? []) : options
    }

    func accentLabel(id: String) -> String {
        accentOptions().first(where: { $0.id == id })?.label ?? id
    }

    func accentBlurb(_ id: String) -> String? {
        accentOptions().first(where: { $0.id == id })?.blurb
    }

    func accentKind(_ id: String) -> String {
        if let kind = accentOptions().first(where: { $0.id == id })?.kind { return kind }
        switch id {
        case "state", "source": return id
        case "rainbow": return "hue"
        default: return "ramp"
        }
    }

    /// The tile swatch for an accent: the running state colours, a few tool
    /// colours, the curated ramp, or a hue run.
    func accentSwatches(_ id: String) -> [Color] {
        switch accentKind(id) {
        case "state":
            return ["thinking", "tool", "editing"].map { config.stateColor($0) }
        case "source":
            var keys = sourceKeysInUse
            // Pad with the brand palette so the tile never shows a lone dot.
            let preferred = ["codex", "dsh", "claude"] + config.sources.keys.sorted()
            for key in preferred
            where keys.count < 3 && !keys.contains(key) && config.sources[key] != nil {
                keys.append(key)
            }
            return keys.prefix(3).map { config.color(for: $0) }
        case "hue":
            return Self.rainbowSwatches
        default:
            let hexes = accentOptions().first(where: { $0.id == id })?.colors ?? []
            return hexes.compactMap { Color(hex: $0) }
        }
    }

    /// Sources with a live session, sorted; the source card lists these first.
    var sourceKeysInUse: [String] {
        let seen = Set(agents.map(\.source))
        return config.sources.keys.filter { seen.contains($0) }.sorted()
    }

    var otherSourceKeys: [String] {
        config.sources.keys.sorted().filter { !sourceKeysInUse.contains($0) }
    }

    private static let rainbowSwatches: [Color] = [
        "#ff5e5e", "#ffcf5c", "#5eead4", "#60a5fa", "#c084fc",
    ].compactMap { Color(hex: $0) }

    /// A single representative colour for icons and the preview aura.
    var standbyAccentColor: Color {
        let palette = config.display.standbyPalette
        if palette == "mono" {
            return Color(hex: config.display.standbyColor) ?? Theme.standby
        }
        let colors = paletteSwatches(palette)
        guard !colors.isEmpty else { return Theme.standby }
        return colors[colors.count / 2]
    }

    func loadConfig() async {
        var request = URLRequest(url: base.appendingPathComponent("config"))
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, _) = try? await AgentRingSession.shared.data(for: request),
              let remote = try? JSONDecoder().decode(RingConfig.self, from: data) else { return }
        if !editingConfig, config != remote { config = remote }
    }

    /// Apply a local edit immediately (the preview reacts at once) and push it
    /// to the daemon after the user stops dragging.
    func updateConfig(_ mutate: (inout RingConfig) -> Void) {
        var next = config
        mutate(&next)
        config = next

        editingConfig = true
        pushTask?.cancel()
        pushTask = Task { [next] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            if !Task.isCancelled {
                var request = URLRequest(url: base.appendingPathComponent("config"))
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "content-type")
                request.httpBody = try? JSONEncoder().encode(next)
                if let (data, _) = try? await AgentRingSession.shared.data(for: request),
                   let saved = try? JSONDecoder().decode(RingConfig.self, from: data),
                   saved != self.config {
                    self.config = saved
                }
            }
            self.editingConfig = false
        }
    }

    /// Drop a stale record (e.g. an agent that was killed before it could send
    /// its SessionEnd hook).
    func forget(_ agent: Agent) {
        agents.removeAll { $0.key == agent.key }
        postForget(["sessionId": agent.sessionId ?? ""])
    }

    func clearSessions() {
        agents.removeAll()
        postForget(["all": true])
    }

    private func postForget(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var request = URLRequest(url: base.appendingPathComponent("forget"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = data
        AgentRingSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    func resetConfig() {
        Task {
            var request = URLRequest(url: base.appendingPathComponent("config").appendingPathComponent("reset"))
            request.httpMethod = "POST"
            guard let (data, _) = try? await AgentRingSession.shared.data(for: request),
                  let remote = try? JSONDecoder().decode(RingConfig.self, from: data) else { return }
            config = remote
        }
    }

    func restartDaemon() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["kickstart", "-k", "gui/\(getuid())/com.agentring.daemon"]
        try? process.run()
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            await refresh()
        }
    }

    func openInBrowser() {
        NSWorkspace.shared.open(base)
    }
}
