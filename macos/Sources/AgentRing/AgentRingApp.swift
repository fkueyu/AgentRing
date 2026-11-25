// AgentRingApp.swift — menu-bar scene, settings window and app delegate.

import SwiftUI

/// The settings window's title doubles as its identity for the lighting page,
/// which must drop a daemon preview when the window goes away.
enum SettingsWindow {
    static let title = "AgentRing 设置"
}

@main
struct AgentRingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = DaemonModel()
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue

    private var locale: Locale {
        if let raw = ProcessInfo.processInfo.environment["AGENTRING_LANGUAGE"],
           let language = AppLanguage(rawValue: raw) {
            return language.locale
        }
        return (AppLanguage(rawValue: appLanguage) ?? .system).locale
    }

    var body: some Scene {
        // The only window is the settings window: status lives in the menu bar,
        // the ring preview lives here. A plain Window scene (rather than the
        // Settings scene) keeps a stable window title, because SwiftUI's
        // Settings scene rewrites it with the selected tab's name.
        Window(SettingsWindow.title, id: "settings") {
            SettingsView()
                .environmentObject(model)
                .environment(\.locale, locale)
        }
        .defaultSize(width: 920, height: 680)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsCommand()
            }
        }

        MenuBarExtra {
            MenuContent()
                .environmentObject(model)
                .environment(\.locale, locale)
        } label: {
            HStack(spacing: 3) {
                MenuBarGlyph()
                if model.waitingCount > 0 {
                    Image(systemName: "hand.raised.fill")
                } else if model.errorCount > 0 {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                if model.activeCount > 0 {
                    Text("\(model.activeCount)")
                }
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Must be set before SwiftUI builds the scenes; otherwise a Window
        // scene in an LSUIElement app can end up background-only.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Follow the system appearance (HIG). A dev-only override exists so the
        // UI can be reviewed in both modes.
        if let forced = ProcessInfo.processInfo.environment["AGENTRING_APPEARANCE"] {
            NSApp.appearance = NSAppearance(named: forced == "dark" ? .darkAqua : .aqua)
        }

        // SwiftUI's Settings scene can come up on its own at launch. This app is
        // a menu-bar utility: no window until the user asks for one.
        if ProcessInfo.processInfo.environment["AGENTRING_OPEN_SETTINGS"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                for window in NSApp.windows where window.isVisible {
                    window.orderOut(nil)
                }
            }
        }
    }
}

struct SettingsCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("设置…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}

struct MenuContent: View {
    @EnvironmentObject private var model: DaemonModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Label("设置…", systemImage: "gearshape")
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        if model.waitingCount > 0 {
            Label(
                LocalizedStringKey(L10n.waitingApprovals(model.waitingCount, long: true)),
                systemImage: "hand.raised.fill"
            )
        }
        if model.errorCount > 0 {
            Label(
                LocalizedStringKey(L10n.errors(model.errorCount, long: true)),
                systemImage: "exclamationmark.triangle.fill"
            )
        }
        if model.connected && !model.ringConnected {
            Label("灯环未连接", systemImage: "bolt.slash.fill")
        }

        if model.agents.isEmpty {
            Text("没有 agent 会话")
        } else {
            ForEach(Array(model.agents.prefix(5))) { agent in
                Label(
                    "\(agent.label) · \(Theme.stateLabel(agent.state))",
                    systemImage: Theme.stateSymbol(agent.state)
                )
            }
        }

        Divider()

        Button {
            model.restartDaemon()
        } label: {
            Label("重启守护进程", systemImage: "arrow.clockwise")
        }
        Button {
            model.openInBrowser()
        } label: {
            Label("打开网页预览", systemImage: "safari")
        }

        Divider()

        Button("退出 AgentRing") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
