// GeneralTab.swift — daemon/ring diagnostics and maintenance actions.

import SwiftUI

// MARK: - 通用

struct GeneralTab: View {
    @EnvironmentObject private var model: DaemonModel
    @State private var confirmingClear = false
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private var ringConnectionText: String {
        guard model.ringConnected else { return L10n.text("未连接") }
        return L10n.ringStatus(model.ringFPS, connected: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "通用", subtitle: "守护进程、灯环与版本信息。") {
                StatusPill(
                    model.connected ? "已连接" : "未连接",
                    color: model.connected ? Theme.green : Theme.red
                )
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.top, 22)

            ScrollView(.vertical) {
                VStack(spacing: 14) {
                    SettingsCard("连接") {
                        SettingRow("守护进程", caption: model.base.absoluteString.replacingOccurrences(of: "http://", with: "")) {
                            Label(
                                LocalizedStringKey(model.connected ? "已连接" : "未连接"),
                                systemImage: model.connected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                            )
                            .font(.callout)
                            .foregroundStyle(model.connected ? Theme.green : Theme.red)
                        }

                        Divider()

                        SettingRow("灯环", caption: model.ringConnected && !model.ringIP.isEmpty ? model.ringIP : nil) {
                            VStack(alignment: .trailing, spacing: 1) {
                                Label(
                                    LocalizedStringKey(ringConnectionText),
                                    systemImage: model.ringConnected
                                        ? "checkmark.circle.fill"
                                        : "exclamationmark.triangle.fill"
                                )
                                .font(.callout)
                                .foregroundStyle(model.ringConnected ? Theme.green : Theme.amber)
                            }
                        }

                        Divider()

                        HStack(spacing: 8) {
                            Button("重启守护进程") { model.restartDaemon() }
                                .help("重启后会自动重连")
                            Button("打开网页预览") { model.openInBrowser() }
                                .help("在浏览器中打开守护进程的调试预览页")
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 2)
                    }

                    SettingsCard("语言") {
                        SettingRow(
                            "界面语言",
                            caption: "切换 App 的界面语言，立即生效。"
                        ) {
                            Picker("", selection: $appLanguage) {
                                Text("跟随系统").tag(AppLanguage.system.rawValue)
                                Text("中文").tag(AppLanguage.zh.rawValue)
                                Text("English").tag(AppLanguage.en.rawValue)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 220)
                        }
                    }

                    SettingsCard("维护") {
                        SettingRow(
                            "清除所有会话记录",
                            caption: "被杀掉的 agent 不会再发结束事件；这里可以立刻清掉。"
                        ) {
                            Button("清除", role: .destructive) { confirmingClear = true }
                                .foregroundStyle(Theme.red)
                        }
                    }

                    SettingsCard("关于") {
                        SettingRow("App 版本") {
                            Text(version).foregroundStyle(.secondary)
                        }
                        Divider()
                        SettingRow("守护进程版本") {
                            Text(model.daemonVersion.isEmpty ? "—" : model.daemonVersion)
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                        SettingRow("硬件") {
                            Text("ESP32-C3 · 24 × WS2812B").foregroundStyle(.secondary)
                        }
                        Divider()
                        SettingRow("菜单栏") {
                            Text("活跃数 · 状态提示").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, Metrics.pagePadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog("清除所有会话记录？", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("清除", role: .destructive) { model.clearSessions() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("记录会立即消失；下一次 agent 事件会重新建立。")
        }
    }
}
