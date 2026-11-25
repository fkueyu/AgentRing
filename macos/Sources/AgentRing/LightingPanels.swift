// LightingPanels.swift — the four control panels of the lighting studio.
//
// The split is by intent, not by field group: 显示 answers "how bright",
// 待机 answers "what the ring does when nothing runs", 布局 answers "how sessions
// share the ring", and 状态 answers "what a session looks like" — colour and
// motion in one place.

import SwiftUI

extension LightingTab {
    // MARK: - 显示

    @ViewBuilder
    var displayPanel: some View {
        VStack(spacing: 14) {
            SettingsCard("亮度", detail: nightActive ? "实际输出 \(Int((effectiveBrightness * 100).rounded()))%" : nil) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int((model.config.display.brightness * 100).rounded()))%")
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    Image(systemName: "sun.min")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Slider(value: binding(\.display.brightness), in: 0.05...1)
                        .controlSize(.large)
                    Image(systemName: "sun.max")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Divider()

                SliderRow(
                    "伽马",
                    caption: "1.0 保留原始亮度；调高会加深暗部、让过渡更硬。",
                    value: binding(\.display.gamma),
                    range: 0.8...2.6,
                    display: String(format: "%.1f", model.config.display.gamma)
                )
            }

            SettingsCard("功耗保护") {
                SliderRow(
                    "电流上限",
                    caption: powerCaption,
                    icon: "bolt.fill",
                    value: binding(\.display.currentLimitMa),
                    range: 300...2000,
                    display: "\(Int(model.config.display.currentLimitMa)) mA"
                )
            }

            SettingsCard("夜间模式", detail: nightActive ? "正在生效" : nil) {
                SettingRow("降低夜间亮度", caption: "在设定时段内把亮度压到更低，避免夜里太亮。") {
                    Toggle("", isOn: binding(\.display.nightMode.enabled))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                if model.config.display.nightMode.enabled {
                    Divider()

                    HStack(spacing: 8) {
                        Text("时段")
                            .font(.callout)
                        Spacer(minLength: 8)
                        DatePicker("", selection: timeBinding(start: true), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(.field)
                            .fixedSize()
                        Text("至")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        DatePicker("", selection: timeBinding(start: false), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(.field)
                            .fixedSize()
                    }

                    SliderRow(
                        "夜间亮度",
                        caption: "实际亮度取它与主亮度的较小值。",
                        value: binding(\.display.nightMode.brightness),
                        range: 0.02...0.4,
                        display: "\(Int((model.config.display.nightMode.brightness * 100).rounded()))%"
                    )
                }
            }
        }
    }

    // MARK: - 待机

    @ViewBuilder
    var standbyPanel: some View {
        VStack(spacing: 14) {
            SettingsCard("无会话时", detail: standbyLabel) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                    ],
                    spacing: 8
                ) {
                    ForEach(model.standbyOptions()) { option in
                        ChoiceTile(
                            icon: standbySymbol(option.id),
                            title: option.label,
                            caption: standbyBlurb(option.id),
                            selected: model.config.display.standby == option.id
                        ) {
                            model.updateConfig { $0.display.standby = option.id }
                        }
                    }
                }
            }

            SettingsCard("待机配色", detail: standbyPaletteLabel) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                    ],
                    spacing: 8
                ) {
                    ForEach(model.paletteOptions()) { option in
                        PaletteTile(
                            label: option.label,
                            colors: model.paletteSwatches(option.id),
                            selected: model.config.display.standbyPalette == option.id
                        ) {
                            model.updateConfig { $0.display.standbyPalette = option.id }
                        }
                    }
                }

                if let blurb = model.paletteBlurb(model.config.display.standbyPalette) {
                    Text(blurb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Only a mono strip has a colour to choose; the curated ramps
                // and rainbow are fixed so the picker cannot fight them.
                if model.config.display.standbyPalette == "mono" {
                    Divider()
                    ColorRow(
                        title: "灯带颜色",
                        hex: model.config.display.standbyColor,
                        color: standbyColorBinding
                    )
                }

                Divider()

                if model.config.display.standby == "dot" {
                    Text("常亮单点保持静止，速度设置对它无效。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    SliderRow(
                        "动画速度",
                        caption: "只影响待机；状态动效在「状态」里按状态单独调速。",
                        icon: "speedometer",
                        value: binding(\.display.standbySpeed),
                        range: 0.2...3,
                        display: String(format: "%.1f×", model.config.display.standbySpeed)
                    )
                }
            }
        }
    }

    // MARK: - 布局

    @ViewBuilder
    var layoutPanel: some View {
        VStack(spacing: 14) {
            SettingsCard("分配方式") {
                HStack(spacing: 8) {
                    ForEach(layoutModes, id: \.id) { option in
                        ChoiceTile(
                            icon: option.icon,
                            title: option.label,
                            caption: option.blurb,
                            selected: model.config.layout.mode == option.id
                        ) {
                            model.updateConfig { $0.layout.mode = option.id }
                        }
                    }
                }

                Text(layoutBlurb(model.config.layout.mode))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard("分段") {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("最多分段")
                            .font(.callout)
                        Spacer(minLength: 8)
                        Text("\(Int(model.config.layout.maxAgents.rounded())) 段")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    Picker("", selection: segmentedBinding(\.layout.maxAgents)) {
                        ForEach(1...8, id: \.self) { count in
                            Text("\(count)").tag(Double(count))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                }
                SettingRow("分段间隔", caption: "段之间空出的灯珠数。") {
                    Picker("", selection: segmentedBinding(\.layout.gapLeds)) {
                        ForEach(0...3, id: \.self) { count in
                            Text("\(count) 颗").tag(Double(count))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 212)
                }

                if model.config.layout.mode == "rotate" {
                    SettingRow("轮播间隔", caption: "每隔多久轮换到下一组会话。") {
                        HStack(spacing: 9) {
                            Text("\(Int(model.config.layout.rotateSeconds)) 秒")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Stepper("", value: binding(\.layout.rotateSeconds), in: 3...60, step: 1)
                                .labelsHidden()
                        }
                    }
                }

                Divider()

                SettingRow("空闲会话也占一段", caption: "关闭时只为运行中的会话留位置。") {
                    Toggle("", isOn: binding(\.layout.showIdle))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
    }

    // MARK: - 状态

    @ViewBuilder
    var statesPanel: some View {
        VStack(spacing: 14) {
            accentCard
            motionCard
            timingCard
        }
    }

    @ViewBuilder
    private var accentCard: some View {
        SettingsCard("会话配色", detail: accentLabel) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                ],
                spacing: 8
            ) {
                ForEach(model.accentOptions()) { option in
                    PaletteTile(
                        label: option.label,
                        colors: model.accentSwatches(option.id),
                        selected: model.config.display.accent == option.id,
                        showsDots: model.accentKind(option.id) == "state" || model.accentKind(option.id) == "source"
                    ) {
                        model.updateConfig { $0.display.accent = option.id }
                    }
                }
            }

            if let blurb = model.accentBlurb(model.config.display.accent) {
                Text(blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            accentColourEditors

            if model.config.display.accent == "rainbow" {
                Divider()
                SliderRow(
                    "流动速度",
                    caption: "色相沿环滚动的速度。",
                    value: binding(\.display.rainbowSpeed),
                    range: 0...2,
                    display: String(format: "%.2f", model.config.display.rainbowSpeed)
                )
            }

            Text(accentRuleCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accentRuleCaption: String {
        if model.accentKind(model.config.display.accent) == "state" {
            return "前三种是运行中的颜色，后三种同时是提醒色：等待、完成、报错在任何配色下都用它们。"
        }
        return "配色只决定运行中的外观；等待、完成、报错永远用提醒色。"
    }

    /// The wells that are actually in play for the selected accent. A colour
    /// picker that changes nothing is worse than no picker at all, so only the
    /// wells the renderer reads are shown.
    @ViewBuilder
    private var accentColourEditors: some View {
        switch model.accentKind(model.config.display.accent) {
        case "state":
            VStack(alignment: .leading, spacing: 9) {
                fieldLabel("状态色")
                colourGrid(stateKeys)
            }

        case "source":
            Text("每个工具的颜色和开关在「来源」页管理；配色方案只决定用不用它们。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        default:
            VStack(alignment: .leading, spacing: 9) {
                fieldLabel("提醒色")
                colourGrid(reminderKeys)
            }
        }
    }

    private func colourGrid(_ keys: [String]) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ],
            spacing: 9
        ) {
            ForEach(keys, id: \.self) { key in
                ColorRow(
                    title: Theme.stateLabel(key),
                    hex: stateHex(key),
                    color: stateColorBinding(key),
                    compact: true
                )
            }
        }
    }

    @ViewBuilder
    private var motionCard: some View {
        SettingsCard("状态动效", detail: "来自守护进程") {
            VStack(spacing: 9) {
                ForEach(stateKeys, id: \.self) { key in
                    HStack(spacing: 10) {
                        Button {
                            preview = RingPreview(state: key, effect: effectID(for: key))
                        } label: {
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(model.config.stateColor(key))
                                    .frame(width: 7, height: 7)
                                Text(Theme.stateLabel(key))
                                    .font(.callout)
                                Image(systemName: "play.circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(width: 120, alignment: .leading)
                        .help("在左侧预览当前效果")

                        Spacer(minLength: 4)

                        Picker("", selection: effectBinding(key)) {
                            ForEach(model.effectOptions(for: key)) { option in
                                Text(option.label).tag(option.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .frame(width: 170)

                        HStack(spacing: 3) {
                            Text(speedLabel(key))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 32, alignment: .trailing)
                            Stepper("", value: speedBinding(key), in: 0.2...3, step: 0.1)
                                .labelsHidden()
                                .controlSize(.small)
                                .help("\(Theme.stateLabel(key))的动效速度")
                        }
                        .frame(width: 74, alignment: .trailing)
                    }
                }
            }

            Text("点选效果会在左侧即时预览；每行右侧的 × 值单独调速。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var timingCard: some View {
        SettingsCard("时序") {
            SettingRow(
                "完成停留",
                caption: "显示完成效果的时间，之后回到待机或下一个会话。"
            ) {
                HStack(spacing: 9) {
                    Text("\(Int(model.config.motion.doneHoldSeconds)) 秒")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Stepper("", value: binding(\.motion.doneHoldSeconds), in: 2...30, step: 1)
                        .labelsHidden()
                }
            }

            Divider()

            SettingRow(
                "静默降级",
                caption: "超过这个时间没有事件就回到空闲；等待审批不会降级。"
            ) {
                HStack(spacing: 9) {
                    Text("\(Int(model.config.motion.staleMinutes)) 分")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Stepper("", value: binding(\.motion.staleMinutes), in: 2...60, step: 1)
                        .labelsHidden()
                }
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Palette tile

/// A compact colour-scheme tile: a short swatch plus the scheme name. Identity
/// palettes (state / source) show dots because their colours are discrete; the
/// curated ramps and rainbow show a strip because the colour actually travels.
private struct PaletteTile: View {
    let label: String
    let colors: [Color]
    let selected: Bool
    var showsDots = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                swatch

                Text(label)
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(border, lineWidth: selected ? 1.4 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: selected)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityLabel("\(label)配色")
    }

    @ViewBuilder
    private var swatch: some View {
        if showsDots {
            HStack(spacing: 4) {
                ForEach(colors.indices, id: \.self) { index in
                    Circle()
                        .fill(colors[index])
                        .frame(width: 8, height: 8)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 7)
        } else {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: stripColors,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 7)
                .overlay(
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
                )
        }
    }

    private var stripColors: [Color] {
        if colors.isEmpty { return [Theme.standby, Theme.standby] }
        if colors.count == 1 { return [colors[0], colors[0]] }
        return colors
    }

    private var fill: Color {
        if selected { return Color.accentColor.opacity(0.10) }
        return hovering ? Color.primary.opacity(0.06) : Color.primary.opacity(0.028)
    }

    private var border: Color {
        if selected { return Color.accentColor.opacity(0.55) }
        return hovering ? Color.primary.opacity(0.14) : Color.primary.opacity(0.07)
    }
}
