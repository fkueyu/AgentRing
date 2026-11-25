// DesignSystem.swift — layout tokens and the shared settings chrome.
//
// The settings window is a small control surface: a quiet sidebar, one
// scrollable page and cards that group controls by intent. Everything visual
// lives here so the tabs stay consistent when one of them is redesigned.

import AppKit
import SwiftUI

enum Metrics {
    static let sidebarWidth: CGFloat = 196
    static let pagePadding: CGFloat = 28
    static let cardRadius: CGFloat = 12
    static let cardPadding: CGFloat = 16
    static let columnGap: CGFloat = 22
}

enum Surface {
    static let page = Theme.pageBackground
    static let card = Theme.cardBackground
    static let sidebar = Theme.sidebarBackground
    static let stroke = Theme.cardStroke
    static let subtleFill = Color.primary.opacity(0.045)
}

/// The ring from macos/Resources/Logo.png, rebuilt as a vector so it stays
/// crisp in the sidebar and needs no bundle lookup.
struct BrandMark: View {
    var size: CGFloat = 26

    var body: some View {
        Circle()
            .strokeBorder(
                AngularGradient(
                    colors: [
                        Color(red: 0.48, green: 0.36, blue: 1.0),
                        Color(red: 0.18, green: 0.61, blue: 1.0),
                        Color(red: 0.16, green: 0.90, blue: 0.77),
                        Color(red: 0.48, green: 0.36, blue: 1.0),
                    ],
                    center: .center
                ),
                lineWidth: size * 0.155
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Cards

/// A rounded settings group with an optional small header. Controls are laid
/// out full-width inside so sliders get room to breathe.
struct SettingsCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    private let title: String?
    private let detail: String?
    private let stretch: Bool
    private let content: Content

    init(
        _ title: String? = nil,
        detail: String? = nil,
        stretch: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.stretch = stretch
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(LocalizedStringKey(title))
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 8)
                    if let detail {
                        Text(LocalizedStringKey(detail))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, Metrics.cardPadding)
                .padding(.top, 13)
                .padding(.bottom, 10)
            }

            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(.horizontal, Metrics.cardPadding)
            .padding(.top, title == nil ? Metrics.cardPadding : 0)
            .padding(.bottom, Metrics.cardPadding)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: stretch ? CGFloat.infinity : nil,
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(Surface.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Surface.stroke, lineWidth: 1)
        )
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.22 : 0.035),
            radius: colorScheme == .dark ? 12 : 7,
            y: 2
        )
    }
}

// MARK: - Headers and status

struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    private let trailing: Trailing

    init(title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 21, weight: .semibold))
                Text(LocalizedStringKey(subtitle))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// A small capsule used for live status in page headers.
struct StatusPill: View {
    let color: Color
    let text: String

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.5), radius: 2)
            Text(LocalizedStringKey(text))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Rows

/// Label + optional help + a trailing control, the basic settings row.
struct SettingRow<Accessory: View>: View {
    private let title: String
    private let caption: String?
    private let accessory: Accessory

    init(_ title: String, caption: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.caption = caption
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.callout)
                if let caption {
                    Text(LocalizedStringKey(caption))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            accessory
        }
    }
}

/// A full-width slider row: title and value on top, the track underneath. This
/// gives every slider the same hit area and keeps the values aligned.
struct SliderRow: View {
    let title: String
    var caption: String?
    var icon: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    let display: String

    init(
        _ title: String,
        caption: String? = nil,
        icon: String? = nil,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        display: String
    ) {
        self.title = title
        self.caption = caption
        self.icon = icon
        self._value = value
        self.range = range
        self.display = display
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(LocalizedStringKey(title))
                    .font(.callout)
                Spacer(minLength: 8)
                Text(display)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            HStack(spacing: 9) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)
                }
                Slider(value: $value, in: range)
            }
            if let caption {
                Text(LocalizedStringKey(caption))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A two-line fact used in the contextual overview card.
struct FactRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Text(LocalizedStringKey(label))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(LocalizedStringKey(value))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Choices

/// A selectable tile used for standby effects, layouts and colour modes.
struct ChoiceTile: View {
    let icon: String
    let title: String
    let caption: String
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    Spacer(minLength: 4)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .transition(.opacity.combined(with: .scale))
                    }
                }
                Text(LocalizedStringKey(title))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(LocalizedStringKey(caption))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
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

/// Colour well row with a sample dot and the hex value.
struct ColorRow: View {
    let title: String
    let hex: String
    @Binding var color: Color
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .shadow(color: color.opacity(0.35), radius: 2)
            Text(LocalizedStringKey(title))
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: 6)
            if !compact {
                Text(hex.uppercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            ColorPicker("", selection: $color, supportsOpacity: false)
                .labelsHidden()
                .help("\(title) \(hex.uppercased())")
        }
    }
}

// MARK: - Ring stage

/// The shared ring presentation: a narrow circular track with the live LEDs on
/// its centreline. The radius is proportional so the same view works at 184 pt
/// in the lighting rail and at 280 pt on the preview page.
struct RingStage: View {
    var size: CGFloat = 268
    var base = URL(string: "http://127.0.0.1:7801")!

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: size * 0.134)
                .frame(width: size * 0.940, height: size * 0.940)
                .shadow(color: .black.opacity(0.04), radius: 10, y: 4)

            RingView(base: base)
                .frame(width: size, height: size)
        }
        .frame(width: size + 4, height: size + 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Agent 状态环"))
    }
}

// MARK: - Layout schematic

/// A 24-LED skeleton used to show how the ring is divided. It mirrors the
/// spacing rules (equal segments with a gap between them) without pretending to
/// be the real renderer.
struct LayoutStrip: View {
    let segments: Int
    let gapLeds: Int
    let mode: String
    let colors: [Color]

    private let ledCount = 24

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(layout.enumerated()), id: \.offset) { item in
                Group {
                    if let color = item.element.color {
                        Capsule().fill(color)
                    } else {
                        Capsule()
                            .fill(Color.primary.opacity(0.025))
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(L10n.segmentSummary(max: segments, gap: gapLeds)))
    }

    private struct Pixel {
        let color: Color?
    }

    private var layout: [Pixel] {
        let count = max(1, min(8, segments))
        let gap = max(0, min(3, gapLeds))
        let usable = max(count, ledCount - gap * (count - 1))
        var sizes = Array(repeating: usable / count, count: count)
        for index in 0..<(usable % count) {
            sizes[index] += 1
        }

        var pixels: [Pixel] = []
        for segment in 0..<count {
            let color = color(for: segment, of: count)
            for _ in 0..<sizes[segment] {
                pixels.append(Pixel(color: color))
            }
            if segment < count - 1 {
                for _ in 0..<gap {
                    pixels.append(Pixel(color: nil))
                }
            }
        }
        while pixels.count < ledCount {
            pixels.append(Pixel(color: nil))
        }
        return Array(pixels.prefix(ledCount))
    }

    private func color(for segment: Int, of count: Int) -> Color {
        let base = colors.isEmpty ? [Theme.stateColor("thinking")] : colors
        switch mode {
        case "focus":
            return segment == 0 ? base[0] : base[0].opacity(0.14)
        case "rotate":
            return base[segment % base.count].opacity(segment == 0 ? 1 : 0.45)
        default:
            return base[segment % base.count]
        }
    }
}
