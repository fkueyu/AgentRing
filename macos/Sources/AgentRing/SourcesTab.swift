// SourcesTab.swift — the agent wiring page.
//
// The ring is only ever as connected as the tools feeding it, so this page
// answers two questions per agent: is the tool installed, and is AgentRing's
// bridge (a DSH profile plugin, a Codex hooks file, …) installed? Detection
// comes from the daemon's `/sources` probe, so adding an agent later needs one
// probe there, not a new page here.

import AppKit
import SwiftUI

struct SourcesTab: View {
    @EnvironmentObject private var model: DaemonModel
    @State private var showRest = false
    @State private var installing: String?
    @State private var installErrors: [String: String] = [:]

    /// Fallback before the first report, and while the daemon is offline.
    private let knownIDs = ["dsh", "codex", "claude"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "来源", subtitle: subtitle) {
                StatusPill(summaryText, color: summaryColor)
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.top, 22)

            ScrollView(.vertical) {
                VStack(spacing: 14) {
                    detectedCard
                    otherCard

                    if !model.connected {
                        Text("守护进程未连接，安装状态可能已经过期。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, Metrics.pagePadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Cards

    private var detectedCard: some View {
        SettingsCard(
            "Agent 接入",
            detail: model.sourceReport == nil
                ? (model.connected ? L10n.text("检测中") : L10n.text("无法检测"))
                : L10n.text("本地检测")
        ) {
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    agentRow(entry)
                    if index < entries.count - 1 {
                        Divider()
                            .padding(.vertical, 10)
                    }
                }
            }

            if let note = installNote {
                Text(LocalizedStringKey(note))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
    }

    private var otherCard: some View {
        SettingsCard("其他来源", detail: L10n.sources(otherIDs.count)) {
            if !activeOthers.isEmpty {
                VStack(spacing: 10) {
                    ForEach(activeOthers, id: \.self) { id in
                        compactRow(id)
                    }
                }
            }

            if !restOthers.isEmpty {
                if !activeOthers.isEmpty { Divider() }
                DisclosureGroup(isExpanded: $showRest) {
                    VStack(spacing: 10) {
                        ForEach(restOthers, id: \.self) { id in
                            compactRow(id)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text(L10n.restSources(restOthers.count))
                }
                .font(.caption)
            }

            Text("这些工具还没有安装检测；只要把事件上报到 `/ingest`，它们就会正常上环。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Rows

    private func agentRow(_ entry: SourceEntry) -> some View {
        let status = status(for: entry)
        let session = sessions(entry.id)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.config.color(for: entry.id))
                    .frame(width: 8, height: 8)
                Text(Theme.sourceLabel(entry.id))
                    .font(.callout.weight(.medium))
                SourceTag(text: status.text, color: status.color)
                Spacer(minLength: 8)
                ColorPicker("", selection: sourceColor(entry.id), supportsOpacity: false)
                    .labelsHidden()
                    .help(colourHelp)
                Toggle("", isOn: sourceEnabled(entry.id))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("在灯环上显示这个来源")
            }

            Text(installLine(entry))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(entry.install?.path ?? L10n.text("未检测到安装路径"))

            if model.sourceReport != nil {
                HStack(spacing: 5) {
                    Image(systemName: bridgeSymbol(entry))
                        .font(.system(size: 10))
                        .foregroundStyle(status.color)
                    Text(bridgeLine(entry, sessions: session.all))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            if let bridge = entry.bridge, let command = bridge.command {
                BridgeInstallRow(
                    command: command,
                    installable: bridge.installable ?? false,
                    installing: installing == entry.id,
                    error: installErrors[entry.id],
                    install: { Task { await install(entry.id) } }
                )
            }
        }
        .padding(.vertical, 3)
    }

    private func compactRow(_ id: String) -> some View {
        let session = sessions(id)
        return HStack(spacing: 9) {
            Circle()
                .fill(model.config.color(for: id))
                .frame(width: 8, height: 8)
            Text(Theme.sourceLabel(id))
                .font(.callout)
                .lineLimit(1)
            if !session.all.isEmpty {
                SourceTag(
                    text: session.active > 0
                        ? L10n.sessionsParenthetical(session.all.count, active: session.active)
                        : L10n.sessions(session.all.count),
                    color: session.active > 0 ? Theme.green : .secondary
                )
            }
            Spacer(minLength: 8)
            ColorPicker("", selection: sourceColor(id), supportsOpacity: false)
                .labelsHidden()
                .help(colourHelp)
            Toggle("", isOn: sourceEnabled(id))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("在灯环上显示这个来源")
        }
    }

    // MARK: - Derived state

    /// The daemon owns the registry order; before the first report only the
    /// agents this app build knows about are listed.
    private var registeredIDs: [String] {
        let reported = model.sourceReport?.entries.map(\.id) ?? []
        return reported.isEmpty ? knownIDs : reported
    }

    private var entries: [SourceEntry] {
        if let report = model.sourceReport, !report.entries.isEmpty {
            return report.entries
        }
        return registeredIDs.map(SourceEntry.unknown)
    }

    private var otherIDs: [String] {
        model.config.sources.keys.filter { !registeredIDs.contains($0) }.sorted()
    }

    private var activeOthers: [String] {
        otherIDs.filter { !sessions($0).all.isEmpty }
    }

    private var restOthers: [String] {
        otherIDs.filter { sessions($0).all.isEmpty }
    }

    private var subtitle: String {
        model.config.display.accent == "source"
            ? "每个来源的颜色就是它在环上的色相；开关决定谁上环。"
            : "安装与接入状态；开关决定谁上环，颜色在「来源色」配色下生效。"
    }

    private var summaryText: String {
        guard model.sourceReport != nil else {
            return model.connected ? "正在检测" : "无法检测"
        }
        let wired = entries.filter { $0.bridge?.state == "installed" }.count
        let waiting = entries.filter {
            ["missing", "disabled", "mismatch"].contains($0.bridge?.state ?? "")
        }.count
        var parts = [L10n.wired(wired)]
        if waiting > 0 { parts.append(L10n.waitingSources(waiting)) }
        return parts.joined(separator: " · ")
    }

    private var summaryColor: Color {
        guard model.sourceReport != nil else {
            return model.connected ? .secondary : Theme.red
        }
        return entries.contains { $0.bridge?.state == "installed" } ? Theme.green : Theme.amber
    }

    /// One note for the whole card instead of repeating it under every row.
    private var installNote: String? {
        let commands = entries.compactMap { $0.bridge?.command }
        guard !commands.isEmpty else { return nil }
        if entries.contains(where: { $0.bridge?.installable == true }) {
            return "一键接入只会追加 AgentRing hook 并自动备份；首次运行时工具可能要求确认。"
        }
        return "这些命令会修改对应工具的配置，需要你自己执行。"
    }

    private var colourHelp: String {
        L10n.text(model.config.display.accent == "source"
            ? "这个来源在环上的颜色"
            : "这个来源的颜色（只在「来源色」配色下生效）")
    }

    private func sessions(_ id: String) -> (all: [Agent], active: Int) {
        let all = model.agents.filter { $0.source == id }
        return (all, all.filter { $0.state != "idle" }.count)
    }

    private func status(for entry: SourceEntry) -> (text: String, color: Color) {
        if model.sourceReport == nil { return (L10n.text("状态未知"), .secondary) }
        if entry.error != nil { return (L10n.text("检测失败"), Theme.red) }
        guard entry.detected else { return (L10n.text("未安装"), .secondary) }
        switch entry.bridge?.state {
        case "installed": return (L10n.text("已接入"), Theme.green)
        case "disabled": return (L10n.text("未启用"), Theme.amber)
        case "mismatch": return (L10n.text("配置不匹配"), Theme.amber)
        case "missing": return (L10n.text("未接入"), Theme.amber)
        case "manual": return (L10n.text("可手动接入"), .secondary)
        default: return (L10n.text("未知"), .secondary)
        }
    }

    private func bridgeSymbol(_ entry: SourceEntry) -> String {
        switch entry.bridge?.kind {
        case "plugin": return "puzzlepiece.extension"
        case "hooks": return "link"
        default: return "circle.dashed"
        }
    }

    private func installLine(_ entry: SourceEntry) -> String {
        guard model.sourceReport != nil else { return L10n.text("无法检测（守护进程未连接）") }
        guard entry.detected, let install = entry.install else { return L10n.text("未检测到安装") }
        var parts = [L10n.text("已安装")]
        if let version = install.version, !version.isEmpty { parts.append(version) }
        if install.running == true { parts.append(L10n.text("运行中")) }
        if let profile = install.profile { parts.append(L10n.profile(profile)) }
        // Tools without a version (a CLI) still deserve a path.
        if parts.count == 1, let path = install.path { parts.append(shortPath(path)) }
        return parts.joined(separator: " · ")
    }

    private func bridgeLine(_ entry: SourceEntry, sessions: [Agent]) -> String {
        guard model.sourceReport != nil else { return "—" }
        guard let bridge = entry.bridge else { return L10n.text("未检测到接入信息") }
        var line = L10n.sourceDetail(bridge.detail ?? "—")
        guard !sessions.isEmpty else { return line }
        let active = sessions.filter { $0.state != "idle" }.count
        line += " · " + (active > 0
            ? L10n.sessionsParenthetical(sessions.count, active: active)
            : L10n.sessions(sessions.count))
        return line
    }

    private func shortPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    // MARK: - Actions

    @MainActor
    private func install(_ id: String) async {
        installing = id
        installErrors[id] = nil
        if let error = await model.installBridge(id) {
            installErrors[id] = error
        }
        installing = nil
    }

    // MARK: - Bindings

    private func sourceEnabled(_ key: String) -> Binding<Bool> {
        Binding(
            get: { model.config.sources[key]?.enabled ?? true },
            set: { value in
                model.updateConfig { config in
                    var source = config.sources[key] ?? RingConfig.Source()
                    source.enabled = value
                    config.sources[key] = source
                }
            }
        )
    }

    private func sourceColor(_ key: String) -> Binding<Color> {
        Binding(
            get: { model.config.color(for: key) },
            set: { picked in
                let hex = picked.hexString
                model.updateConfig { config in
                    var source = config.sources[key] ?? RingConfig.Source()
                    source.color = hex
                    config.sources[key] = source
                }
            }
        )
    }
}

// MARK: - Tags and commands

/// A compact status capsule for a source row.
private struct SourceTag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(LocalizedStringKey(text))
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.12)))
            .lineLimit(1)
    }
}

/// The fix for a missing bridge: a one-click installer for the sources where
/// AgentRing owns the script, plus the command for manual use. The app never
/// runs a probe's display command, only its own installer.
private struct BridgeInstallRow: View {
    let command: String
    let installable: Bool
    let installing: Bool
    let error: String?
    let install: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                if installable {
                    Button(action: install) {
                        HStack(spacing: 5) {
                            if installing {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(LocalizedStringKey(installing ? "正在接入…" : "一键接入"))
                        }
                        .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(installing)
                }

                Button {
                    copy()
                } label: {
                    Label(LocalizedStringKey(copied ? "已复制" : "复制命令"), systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(copied ? Theme.green : Color.secondary)

                Spacer(minLength: 0)
            }

            Text(command)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            if let error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(Theme.red)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            copied = false
        }
    }
}
