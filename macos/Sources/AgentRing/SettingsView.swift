// SettingsView.swift — the sidebar shell around the settings pages.
//
// A fixed-width settings window: a quiet sidebar for navigation, one page on
// the right. The sidebar carries the live daemon/ring state so the user never
// has to leave a page to know whether changes are reaching the hardware.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: DaemonModel
    @State private var tab: Tab

    enum Tab: String, CaseIterable, Identifiable {
        case preview, options, sources, general

        var id: String { rawValue }

        var title: String {
            switch self {
            case .preview: "预览"
            case .options: "灯光"
            case .sources: "来源"
            case .general: "通用"
            }
        }

        var symbol: String {
            switch self {
            case .preview: "circle.dotted"
            case .options: "slider.horizontal.3"
            case .sources: "antenna.radiowaves.left.and.right"
            case .general: "gearshape"
            }
        }

        var shortcut: KeyEquivalent {
            switch self {
            case .preview: KeyEquivalent("1")
            case .options: KeyEquivalent("2")
            case .sources: KeyEquivalent("3")
            case .general: KeyEquivalent("4")
            }
        }

        var shortcutHint: String {
            switch self {
            case .preview: "⌘1"
            case .options: "⌘2"
            case .sources: "⌘3"
            case .general: "⌘4"
            }
        }
    }

    init() {
        let requested = ProcessInfo.processInfo.environment["AGENTRING_TAB"] ?? ""
        _tab = State(initialValue: Tab(rawValue: requested) ?? .preview)
    }

    /// Dev-only: a taller window lets a long page be reviewed in one
    /// screenshot, the same way AGENTRING_TAB pins the page.
    private var windowHeight: CGFloat {
        guard let raw = ProcessInfo.processInfo.environment["AGENTRING_WINDOW_HEIGHT"],
              let value = Double(raw), value > 400 else { return 680 }
        return value
    }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(selection: $tab)
                .frame(width: Metrics.sidebarWidth)
                .background(Surface.sidebar)

            Divider()

            Group {
                switch tab {
                case .preview: PreviewTab()
                case .options: LightingTab()
                case .sources: SourcesTab()
                case .general: GeneralTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Surface.page)
        }
        .frame(width: 920, height: windowHeight)
        .background(Surface.page)
        .background(WindowBehaviourFixer())
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @EnvironmentObject private var model: DaemonModel
    @Binding var selection: SettingsView.Tab

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 18)

            VStack(spacing: 2) {
                ForEach(SettingsView.Tab.allCases) { item in
                    SidebarItem(
                        title: item.title,
                        symbol: item.symbol,
                        selected: selection == item,
                        badge: badge(for: item)
                    ) {
                        selection = item
                    }
                    .keyboardShortcut(item.shortcut, modifiers: .command)
                    .help("\(L10n.text(item.title))（\(item.shortcutHint)）")
                }
            }
            .padding(.horizontal, 14)

            Spacer(minLength: 12)

            Divider()
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 8) {
                statusRow(
                    color: model.connected ? Theme.green : Theme.red,
                    text: model.connected ? "守护进程已连接" : "守护进程未连接"
                )
                statusRow(color: ringColor, text: ringText)
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Text("AgentRing \(version)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
    }

    private var brand: some View {
        HStack(spacing: 11) {
            BrandMark(size: 27)
            VStack(alignment: .leading, spacing: 1) {
                Text("AgentRing")
                    .font(.system(size: 14, weight: .semibold))
                Text("灯环控制台")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var ringColor: Color {
        if !model.connected { return Theme.red }
        return model.ringConnected ? Theme.green : Theme.amber
    }

    private var ringText: String {
        guard model.connected else { return L10n.text("灯环状态未知") }
        guard model.ringConnected else { return L10n.text("灯环未连接") }
        return L10n.ringStatus(model.ringFPS)
    }

    private func badge(for tab: SettingsView.Tab) -> SidebarItem.Badge? {
        guard tab == .preview else { return nil }
        if model.waitingCount > 0 {
            return .init(text: "\(model.waitingCount)", color: Theme.amber)
        }
        if model.errorCount > 0 {
            return .init(text: "\(model.errorCount)", color: Theme.red)
        }
        return nil
    }

    private func statusRow(color: Color, text: String) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.5), radius: 2)
            Text(LocalizedStringKey(text))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SidebarItem: View {
    struct Badge {
        let text: String
        let color: Color
    }

    let title: String
    let symbol: String
    let selected: Bool
    let badge: Badge?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(width: 18)
                Text(LocalizedStringKey(title))
                    .font(.callout)
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                Spacer(minLength: 6)
                if let badge {
                    Text(badge.text)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(badge.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(badge.color.opacity(0.14)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(fill)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.1), value: hovering)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var fill: Color {
        if selected { return Color.accentColor.opacity(0.12) }
        return hovering ? Color.primary.opacity(0.045) : .clear
    }
}

/// A settings window is opened on request and must not come back at the next
/// launch with the app's saved state.
private struct WindowBehaviourFixer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        Configurator()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.configure(nsView.window) }
    }

    private final class Configurator: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                WindowBehaviourFixer.configure(self.window)
            }
        }
    }

    /// Keep the window chrome in the same neutral as the page instead of the
    /// default titlebar tint, and drop the hairline under the title.
    private static func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.isRestorable = false
        window.backgroundColor = NSColor(Theme.pageBackground)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.titleVisibility = .hidden
        // The title bar is hidden, so let the user move the window from any
        // non-control area (the sidebar and page background).
        window.isMovableByWindowBackground = true
    }
}
