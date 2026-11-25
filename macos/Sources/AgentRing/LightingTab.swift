// LightingTab.swift — the lighting studio: a live ring rail on the left and
// one focused control group on the right.
//
// Four sections, one per question: how bright the ring is (显示), what it does
// when nothing runs (待机), how sessions share it (布局), and what a session
// looks like (状态). Colour and motion live together in 状态 — one accent
// palette, then one row per state with its effect and speed — so the two never
// have to be cross-referenced across pages. Every edit goes through
// DaemonModel, so the preview and the hardware stay in sync.

import AppKit
import SwiftUI

struct LightingTab: View {
    @EnvironmentObject var model: DaemonModel
    @State var section: LightingSection
    /// A synthetic state/effect shown in the rail while an effect is being
    /// auditioned; nil means the rail follows the live ring.
    @State var preview: RingPreview?
    @State private var confirmingReset = false
    /// Re-evaluated every 30 s so the night-mode summary crosses its own
    /// boundaries even when no agent or config event arrives.
    @State private var now = Date()

    enum LightingSection: String, CaseIterable, Identifiable {
        case display, standby, layout, states

        var id: String { rawValue }

        var title: String {
            switch self {
            case .display: "显示"
            case .standby: "待机"
            case .layout: "布局"
            case .states: "状态"
            }
        }

        var symbol: String {
            switch self {
            case .display: "sun.max"
            case .standby: "moon.stars"
            case .layout: "circle.grid.3x3"
            case .states: "waveform.path.ecg"
            }
        }
    }

    init() {
        let requested = ProcessInfo.processInfo.environment["AGENTRING_LIGHTING_SECTION"] ?? ""
        _section = State(initialValue: LightingSection(rawValue: requested) ?? .display)
        // Dev-only screenshot/diagnostic entry: "thinking:breathe".
        let previewRequest = ProcessInfo.processInfo.environment["AGENTRING_MOTION_PREVIEW"] ?? ""
        let parts = previewRequest.split(separator: ":", maxSplits: 1).map(String.init)
        _preview = State(initialValue: parts.count == 2 ? RingPreview(state: parts[0], effect: parts[1]) : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "灯光",
                subtitle: "亮度、待机、布局与状态外观，改动会即时同步到灯环。"
            ) {
                StatusPill(ringStatusText, color: ringStatusColor)
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.top, 22)
            .padding(.bottom, 16)

            LightingSectionBar(selection: $section)
                .padding(.horizontal, Metrics.pagePadding)
                .padding(.bottom, 18)

            HStack(alignment: .top, spacing: Metrics.columnGap) {
                VStack(spacing: 14) {
                    liveCard
                    contextCard
                }
                .frame(width: 232)

                panel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.bottom, 24)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .confirmationDialog("恢复默认灯光设置？", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("恢复", role: .destructive) { model.resetConfig() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会覆盖亮度、布局、动效、配色和来源设置。")
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                now = Date()
            }
        }
        .onChange(of: section) { _, _ in
            clearPreview()
        }
        .onDisappear {
            clearPreview()
        }
        // A Window scene keeps its content alive after the red button orders the
        // window out, so onDisappear alone would leave the preview running on
        // the ring. These notifications make the close immediate.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            clearPreview(for: note.object as? NSWindow)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification)) { note in
            clearPreview(for: note.object as? NSWindow)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
            // Closing orders the window out right after it resigns key; an app
            // switch leaves it visible. Re-check on the next runloop turn.
            guard let window = note.object as? NSWindow,
                  window.title == SettingsWindow.title else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if !window.isVisible { clearPreview() }
            }
        }
        // Keep the daemon's temporary preview alive while it is on screen, and
        // post it immediately when the selection changes.
        .task(id: preview) {
            guard let preview else { return }
            guard await model.setPreview(state: preview.state, effect: preview.effect) else {
                self.preview = nil
                return
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if Task.isCancelled { return }
                // Fallback for a missed close notification.
                guard settingsWindowVisible else {
                    clearPreview()
                    return
                }
                if !(await model.setPreview(state: preview.state, effect: preview.effect)) {
                    self.preview = nil
                    return
                }
            }
        }
    }

    private var settingsWindowVisible: Bool {
        NSApp.windows.contains {
            $0.title == SettingsWindow.title && $0.isVisible && !$0.isMiniaturized
        }
    }

    /// Clear only for our own window; colour panels and menus also close.
    private func clearPreview(for window: NSWindow?) {
        guard let window, window.title == SettingsWindow.title else { return }
        clearPreview()
    }

    /// Drop the local preview and tell the daemon to restore the live frame.
    private func clearPreview() {
        guard preview != nil else { return }
        preview = nil
        Task {
            await model.clearPreview()
            // A preview POST may still be in flight; clear once more after it
            // would have landed so the ring cannot stay on a stale effect.
            try? await Task.sleep(nanoseconds: 300_000_000)
            await model.clearPreview()
        }
    }

    // MARK: - Left rail

    private var liveCard: some View {
        SettingsCard(
            preview == nil ? "实时预览" : "效果预览",
            detail: preview == nil
                ? (model.ringConnected ? "同步中" : "仅预览")
                : (model.ringConnected ? "已同步灯环" : "灯环未连接")
        ) {
            VStack(spacing: 11) {
                RingStage(size: 184, base: model.base)

                VStack(spacing: 4) {
                    Text(previewSummary ?? (model.agents.isEmpty
                        ? L10n.text("待机中")
                        : L10n.activeSessions(model.activeCount)))
                        .font(.callout.weight(.medium))
                    HStack(spacing: 5) {
                        Circle()
                            .fill(preview.map { model.config.stateColor($0.state) } ?? liveStatusColor)
                            .frame(width: 5, height: 5)
                        Text(preview == nil
                            ? liveStatusText
                            : L10n.previewFoot(synced: model.ringConnected))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var previewSummary: String? {
        guard let preview else { return nil }
        return L10n.effectLine(
            Theme.stateLabel(preview.state),
            model.effectLabel(for: preview.state, id: preview.effect)
        )
    }

    private var contextCard: some View {
        SettingsCard(contextTitle) {
            contextContent
        }
    }

    private var contextTitle: String {
        if section == .states, preview != nil { return "效果说明" }
        return switch section {
        case .display: "亮度概览"
        case .standby: "待机概览"
        case .layout: "布局示意"
        case .states: "配色概览"
        }
    }

    @ViewBuilder
    private var contextContent: some View {
        if section == .states, let preview {
            effectPreviewContext(preview)
        } else {
            switch section {
            case .display:
                displayContext
            case .standby:
                standbyContext
            case .layout:
                layoutContext
            case .states:
                statesContext
            }
        }
    }

    private var displayContext: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(L10n.text(nightActive ? "夜间亮度" : "有效亮度"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("\(Int((effectiveBrightness * 100).rounded()))%")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.07))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.55), Color.accentColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(5, proxy.size.width * effectiveBrightness))
                }
            }
            .frame(height: 6)

            Divider()

            FactRow(label: "配色", value: accentLabel)
            FactRow(label: "夜间", value: nightSummary)
            FactRow(label: "电流上限", value: "\(Int(model.config.display.currentLimitMa)) mA")
        }
    }

    private var standbyContext: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: standbySymbol(model.config.display.standby))
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(model.standbyAccentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(standbyLabel)
                        .font(.callout.weight(.medium))
                    Text(standbyBlurb(model.config.display.standby))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Divider()

            FactRow(label: "待机配色", value: standbyPaletteLabel)
            FactRow(
                label: "动画速度",
                value: model.config.display.standby == "dot"
                    ? L10n.text("静止")
                    : String(format: "%.1f×", model.config.display.standbySpeed)
            )
            FactRow(
                label: "当前状态",
                value: model.agents.isEmpty ? L10n.text("显示待机") : L10n.text("会话进行中")
            )
        }
    }

    private var layoutContext: some View {
        VStack(alignment: .leading, spacing: 10) {
            LayoutStrip(
                segments: Int(model.config.layout.maxAgents.rounded()),
                gapLeds: Int(model.config.layout.gapLeds.rounded()),
                mode: model.config.layout.mode,
                colors: layoutSwatches
            )

            Text(L10n.segmentSummary(
                max: Int(model.config.layout.maxAgents.rounded()),
                gap: Int(model.config.layout.gapLeds.rounded())
            ))
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            FactRow(label: "分配方式", value: layoutLabel(model.config.layout.mode))
            if model.config.layout.mode == "rotate" {
                FactRow(
                    label: "轮播间隔",
                    value: L10n.seconds(Int(model.config.layout.rotateSeconds))
                )
            }
            FactRow(
                label: "空闲会话",
                value: model.config.layout.showIdle ? L10n.text("占一段") : L10n.text("不显示")
            )
        }
    }

    private var statesContext: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("会话配色")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                Text(accentLabel)
                    .font(.callout.weight(.medium))
            }

            HStack(spacing: 4) {
                ForEach(Array(accentSwatches.enumerated()), id: \.offset) { item in
                    Circle()
                        .fill(item.element)
                        .frame(width: 8, height: 8)
                }
                Spacer(minLength: 0)
            }

            Divider()

            Text("提醒状态")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(["waiting", "done", "error"], id: \.self) { key in
                HStack(spacing: 7) {
                    Circle()
                        .fill(model.config.stateColor(key))
                        .frame(width: 7, height: 7)
                    Text(Theme.stateLabel(key))
                        .font(.caption)
                    Spacer(minLength: 6)
                    Text(model.effectLabel(for: key, id: effectID(for: key)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func effectPreviewContext(_ preview: RingPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: Theme.stateSymbol(preview.state))
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(model.config.stateColor(preview.state))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Theme.stateLabel(preview.state))
                        .font(.callout.weight(.medium))
                    Text(model.effectLabel(for: preview.state, id: preview.effect))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if let hint = effectHint(preview.state, preview.effect) {
                Text(LocalizedStringKey(hint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FactRow(label: "动效速度", value: speedLabel(preview.state))

            Divider()

            Button {
                clearPreview()
            } label: {
                Label("返回实时预览", systemImage: "arrow.uturn.backward")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private func effectHint(_ state: String, _ effect: String) -> String? {
        model.effectOptions(for: state).first(where: { $0.id == effect })?.hint
    }

    // MARK: - Right panel

    private var panel: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                Group {
                    switch section {
                    case .display: displayPanel
                    case .standby: standbyPanel
                    case .layout: layoutPanel
                    case .states: statesPanel
                    }
                }
                .id(section)
                .transition(.opacity)

                resetFooter
            }
            .padding(.bottom, 4)
        }
        .scrollIndicators(.automatic)
    }

    private var resetFooter: some View {
        HStack {
            Spacer()
            Button("恢复默认灯光设置…") { confirmingReset = true }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("覆盖亮度、布局、动效、配色和来源设置")
            Spacer()
        }
        .padding(.top, 2)
    }

    // MARK: - Bounded descriptors

    var stateKeys: [String] {
        ["thinking", "tool", "editing", "waiting", "done", "error"]
    }

    var reminderKeys: [String] {
        ["waiting", "done", "error"]
    }

    let layoutModes: [(id: String, label: String, icon: String, blurb: String)] = [
        ("split", "等分", "square.split.2x1", "每个会话占一段"),
        ("focus", "聚焦最紧急", "scope", "只看最需要处理"),
        ("rotate", "轮播", "arrow.triangle.2.circlepath", "轮流显示各组"),
    ]

    // MARK: - Derived state

    private var ringStatusColor: Color {
        if !model.connected { return Theme.red }
        return model.ringConnected ? Theme.green : Theme.amber
    }

    private var ringStatusText: String {
        guard model.connected else { return L10n.text("守护进程离线") }
        guard model.ringConnected else { return L10n.text("灯环未连接") }
        return L10n.ringStatus(model.ringFPS)
    }

    private var liveStatusColor: Color {
        if !model.connected { return Theme.red }
        return model.ringConnected ? Theme.green : Theme.amber
    }

    private var liveStatusText: String {
        guard model.connected else { return L10n.text("守护进程未连接") }
        guard model.ringConnected else { return L10n.text("灯环未连接 · 预览仍可用") }
        return L10n.ringStatus(model.ringFPS, synced: true)
    }

    var nightActive: Bool {
        let night = model.config.display.nightMode
        guard night.enabled else { return false }
        // The daemon treats an empty window (start == end) as disabled.
        guard night.startMinute != night.endMinute else { return false }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: now)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if night.startMinute < night.endMinute {
            return minute >= night.startMinute && minute < night.endMinute
        }
        return minute >= night.startMinute || minute < night.endMinute
    }

    var effectiveBrightness: Double {
        if nightActive {
            return min(model.config.display.brightness, model.config.display.nightMode.brightness)
        }
        return model.config.display.brightness
    }

    var accentLabel: String {
        model.accentLabel(id: model.config.display.accent)
    }

    /// The accent tile swatches; also used by the rail overview.
    var accentSwatches: [Color] {
        model.accentSwatches(model.config.display.accent)
    }

    /// The layout schematic should look like the ring: identity palettes use
    /// the six state colours, every other accent uses its own swatches.
    var layoutSwatches: [Color] {
        if model.accentKind(model.config.display.accent) == "state" {
            return stateKeys.map { model.config.stateColor($0) }
        }
        return accentSwatches
    }

    func speedValue(_ state: String) -> Double {
        switch state {
        case "thinking": model.config.motion.speeds.thinking
        case "tool": model.config.motion.speeds.tool
        case "editing": model.config.motion.speeds.editing
        case "waiting": model.config.motion.speeds.waiting
        case "done": model.config.motion.speeds.done
        case "error": model.config.motion.speeds.error
        default: 1
        }
    }

    func speedLabel(_ state: String) -> String {
        String(format: "%.1f×", speedValue(state))
    }

    var nightSummary: String {
        let night = model.config.display.nightMode
        guard night.enabled else { return L10n.text("关闭") }
        guard night.startMinute != night.endMinute else { return L10n.text("未生效") }
        return "\(clock(night.startMinute))–\(clock(night.endMinute))"
    }

    var standbyLabel: String {
        model.standbyLabel(id: model.config.display.standby)
    }

    var standbyPaletteLabel: String {
        model.paletteLabel(id: model.config.display.standbyPalette)
    }

    var powerCaption: String {
        if model.config.display.currentLimitMa < 500 {
            return L10n.text("上限偏低，亮画面会被明显压暗；24 颗全白约 1.44 A。")
        }
        return L10n.text("估算电流超过上限时整帧等比压暗；24 颗全白约 1.44 A。")
    }

    func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    func standbySymbol(_ id: String) -> String {
        switch id {
        case "orbit": "circle.dashed"
        case "breathe": "wind"
        default: "circle.fill"
        }
    }

    func standbyBlurb(_ id: String) -> String {
        switch id {
        case "orbit": L10n.text("光珠绕环慢行")
        case "breathe": L10n.text("随机明暗呼吸")
        default: L10n.text("一颗灯安静停驻")
        }
    }

    func layoutLabel(_ id: String) -> String {
        L10n.text(layoutModes.first { $0.id == id }?.label ?? "等分")
    }

    func layoutBlurb(_ id: String) -> String {
        L10n.layoutBlurb(id, seconds: Int(model.config.layout.rotateSeconds))
    }

    func stateHex(_ key: String) -> String {
        model.config.stateColors[key] ?? "#888888"
    }

    func effectID(for state: String) -> String {
        let effects = model.config.motion.effects
        switch state {
        case "thinking": return effects.thinking
        case "tool": return effects.tool
        case "editing": return effects.editing
        case "waiting": return effects.waiting
        case "done": return effects.done
        case "error": return effects.error
        default: return "solid"
        }
    }

    // MARK: - Bindings

    func binding<T>(_ path: WritableKeyPath<RingConfig, T>) -> Binding<T> {
        Binding(
            get: { model.config[keyPath: path] },
            set: { value in model.updateConfig { $0[keyPath: path] = value } }
        )
    }

    /// Integer pickers must not be handed a legacy fractional value (the old
    /// sliders stored 3.31); round on read so a segment stays selected, and
    /// write the exact step on change.
    func segmentedBinding(_ path: WritableKeyPath<RingConfig, Double>) -> Binding<Double> {
        Binding(
            get: { model.config[keyPath: path].rounded() },
            set: { value in model.updateConfig { $0[keyPath: path] = value } }
        )
    }

    func speedBinding(_ state: String) -> Binding<Double> {
        Binding(
            get: { speedValue(state) },
            set: { value in
                model.updateConfig { config in
                    switch state {
                    case "thinking": config.motion.speeds.thinking = value
                    case "tool": config.motion.speeds.tool = value
                    case "editing": config.motion.speeds.editing = value
                    case "waiting": config.motion.speeds.waiting = value
                    case "done": config.motion.speeds.done = value
                    case "error": config.motion.speeds.error = value
                    default: break
                    }
                }
            }
        )
    }

    func effectBinding(_ state: String) -> Binding<String> {
        Binding(
            get: { effectID(for: state) },
            set: { value in
                model.updateConfig { config in
                    switch state {
                    case "thinking": config.motion.effects.thinking = value
                    case "tool": config.motion.effects.tool = value
                    case "editing": config.motion.effects.editing = value
                    case "waiting": config.motion.effects.waiting = value
                    case "done": config.motion.effects.done = value
                    case "error": config.motion.effects.error = value
                    default: break
                    }
                }
                preview = RingPreview(state: state, effect: value)
            }
        )
    }

    func stateColorBinding(_ key: String) -> Binding<Color> {
        Binding(
            get: { model.config.stateColor(key) },
            set: { picked in
                let hex = picked.hexString
                model.updateConfig { config in config.stateColors[key] = hex }
            }
        )
    }

    var standbyColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: model.config.display.standbyColor) ?? .blue },
            set: { picked in
                model.updateConfig { config in config.display.standbyColor = picked.hexString }
            }
        )
    }

    func timeBinding(start: Bool) -> Binding<Date> {
        Binding(
            get: {
                let minutes = start
                    ? model.config.display.nightMode.startMinute
                    : model.config.display.nightMode.endMinute
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                model.updateConfig { config in
                    if start {
                        config.display.nightMode.startMinute = minutes
                    } else {
                        config.display.nightMode.endMinute = minutes
                    }
                }
            }
        )
    }
}

// MARK: - Section bar

private struct LightingSectionBar: View {
    @Binding var selection: LightingTab.LightingSection
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LightingTab.LightingSection.allCases) { item in
                Button {
                    guard selection != item else { return }
                    withAnimation(.easeOut(duration: 0.14)) { selection = item }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(selection == item ? Color.accentColor : Color.secondary)
                        Text(LocalizedStringKey(item.title))
                            .font(.callout.weight(selection == item ? .semibold : .regular))
                            .foregroundStyle(selection == item ? Color.primary : Color.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selectedFill(for: item))
                            .shadow(
                                color: selection == item ? .black.opacity(0.07) : .clear,
                                radius: 2,
                                y: 1
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == item ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func selectedFill(for item: LightingTab.LightingSection) -> Color {
        guard selection == item else { return .clear }
        return colorScheme == .dark ? Color.white.opacity(0.10) : Surface.card
    }
}
