// SettingsControls.swift — shared rows, badges and attention chips.

import SwiftUI

// MARK: - Controls

struct AgentRow: View {
    @EnvironmentObject private var model: DaemonModel
    let agent: Agent

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.config.color(for: agent.source))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(agent.label)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(Theme.sourceLabel(agent.source))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)
            StateBadge(state: agent.state)
        }
        .padding(.vertical, 4)
        .help(agent.cwd ?? agent.label)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        if let tool = agent.tool, !tool.isEmpty { return tool }
        if let cwd = agent.cwd, !cwd.isEmpty {
            return (cwd as NSString).abbreviatingWithTildeInPath
        }
        return "—"
    }
}

struct AttentionChip: View {
    let symbol: String
    let text: String
    let color: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.14)))
            .accessibilityElement(children: .combine)
    }
}

struct StateBadge: View {
    let state: String

    var body: some View {
        Text(Theme.stateLabel(state))
            .font(.caption2.weight(.medium))
            .foregroundStyle(Theme.stateColor(state))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.stateColor(state).opacity(0.12)))
    }
}
