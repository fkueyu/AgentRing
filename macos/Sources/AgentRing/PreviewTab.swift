// PreviewTab.swift — the live ring preview, legend and the integrated session list.

import SwiftUI

// MARK: - 预览

struct PreviewTab: View {
    @EnvironmentObject private var model: DaemonModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "预览", subtitle: "这就是灯环此刻显示的内容，和硬件收到的是同一帧。") {
                StatusPill(statusText, color: statusColor)
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.top, 22)
            .padding(.bottom, 18)

            HStack(alignment: .center, spacing: 24) {
                ringHero

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(model.agents.count) 个会话 · \(model.activeCount) 个活跃")
                            .font(.title3.weight(.semibold))
                        Text(model.agents.isEmpty
                            ? "待机 · " + model.standbyLabel(id: model.config.display.standby)
                            : "预览由守护进程实时渲染")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if model.waitingCount > 0 || model.errorCount > 0 {
                        HStack(spacing: 8) {
                            if model.waitingCount > 0 {
                                AttentionChip(
                                    symbol: "hand.raised.fill",
                                    text: "\(model.waitingCount) 个等待审批",
                                    color: Theme.amber
                                )
                            }
                            if model.errorCount > 0 {
                                AttentionChip(
                                    symbol: "exclamationmark.triangle.fill",
                                    text: "\(model.errorCount) 个报错",
                                    color: Theme.red
                                )
                            }
                        }
                    }

                    SettingsCard("状态图例", detail: "动效来自守护进程") {
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                            GridRow {
                                legendRow("thinking")
                                legendRow("waiting")
                            }
                            GridRow {
                                legendRow("tool")
                                legendRow("done")
                            }
                            GridRow {
                                legendRow("editing")
                                legendRow("error")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 292)
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.bottom, 18)

            sessionsCard
                .padding(.horizontal, Metrics.pagePadding)
                .padding(.bottom, 22)
                .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Hero

    private var ringHero: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [auraColor.opacity(0.14), auraColor.opacity(0.035), .clear],
                        center: .center,
                        startRadius: 22,
                        endRadius: 146
                    )
                )
                .frame(width: 292, height: 292)
                .blur(radius: 9)

            RingStage(size: 252, base: model.base)
        }
        .frame(width: 292, height: 292)
    }

    // MARK: - Sessions

    private var sessionsCard: some View {
        SettingsCard(
            "会话",
            detail: model.agents.isEmpty ? "待机" : "\(model.agents.count) 个 · \(model.activeCount) 活跃",
            stretch: true
        ) {
            if model.agents.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("尚无会话")
                        .font(.callout.weight(.medium))
                    Text("agent 启动后会自动出现在这里")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    ScrollView(.vertical) {
                        VStack(spacing: 0) {
                            ForEach(Array(model.agents.enumerated()), id: \.element.id) { index, agent in
                                AgentRow(agent: agent)
                                    .padding(.vertical, 9)
                                    .contextMenu {
                                        Button("移除这条记录", role: .destructive) { model.forget(agent) }
                                    }
                                if index < model.agents.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)

                    Divider()
                        .padding(.top, 10)

                    HStack(spacing: 8) {
                        Text("右键会话可移除记录")
                        Spacer(minLength: 8)
                        Text("静默 \(Int(model.config.motion.staleMinutes)) 分钟后回到空闲")
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .padding(.top, 10)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Derived state

    /// A hint of the colour currently on the ring, rather than a second
    /// coloured object on the page.
    private var auraColor: Color {
        if let agent = model.agents.first(where: { $0.state != "idle" }) {
            return model.config.stateColor(agent.state)
        }
        return model.standbyAccentColor
    }

    private func legendRow(_ state: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.config.stateColor(state))
                .frame(width: 6, height: 6)
            Text("\(Theme.stateLabel(state)) · \(model.effectLabel(for: state, id: effectID(for: state)))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func effectID(for state: String) -> String {
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

    private var statusText: String {
        if !model.connected { return "守护进程未连接" }
        if model.ringConnected {
            return model.ringFPS > 0 ? "灯环在线 · \(model.ringFPS) fps" : "灯环在线"
        }
        return "灯环未连接 · 预览仍可用"
    }

    private var statusColor: Color {
        if !model.connected { return Theme.red }
        return model.ringConnected ? Theme.green : Theme.amber
    }
}
