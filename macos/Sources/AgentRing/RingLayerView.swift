// RingLayerView.swift — 24 CALayers fed by the daemon /frame or /preview endpoint.

import AppKit
import QuartzCore
import SwiftUI

/// Renders the daemon's `/frame` bytes with 24 CALayers.
///
/// The preview is deliberately not a second implementation of the ring: layout,
/// effects, gamma and the power budget all live in the daemon, so what you see
/// here is exactly what the ESP32 will push to the strip.
@MainActor
final class RingFrameView: NSView {
    private let ledCount = 24
    private var dots: [CALayer] = []
    private var loop: Task<Void, Never>?
    /// Bumped when the URL changes so a frame from the previous endpoint is
    /// dropped instead of flashing after an effect-preview switch.
    private var generation = 0

    private(set) var frameURL = URL(string: "http://127.0.0.1:7801/frame")!

    func setFrameURL(_ url: URL) {
        guard frameURL != url else { return }
        frameURL = url
        generation &+= 1
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // The SwiftUI preview draws a narrow ring track behind this view.
        // Keep the dot shadows unclipped so their glow can spill over both
        // the inner and outer edges of that track.
        layer?.masksToBounds = false

        for _ in 0..<ledCount {
            let dot = CALayer()
            dot.shadowOffset = .zero
            dot.shadowOpacity = 0
            dot.actions = [
                "backgroundColor": NSNull(), "opacity": NSNull(),
                "shadowOpacity": NSNull(), "shadowColor": NSNull(),
            ]
            layer?.addSublayer(dot)
            dots.append(dot)
        }

    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loop?.cancel()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            loop?.cancel()
            loop = nil
        } else {
            startLoop()
        }
    }

    override func layout() {
        super.layout()
        let side = min(bounds.width, bounds.height)
        // Proportional to the RingStage track so the same renderer works at the
        // 184 pt lighting rail, the preview page and any future size.
        let radius = max(30, side * 0.403)
        let dotSize = max(8, radius * 0.093 * 2)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let track = trackColor.cgColor

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, dot) in dots.enumerated() {
            let angle = Double(index) / Double(ledCount) * 2 * .pi - .pi / 2
            dot.bounds = CGRect(x: 0, y: 0, width: dotSize, height: dotSize)
            dot.cornerRadius = dotSize / 2
            dot.position = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            dot.backgroundColor = track
            dot.shadowRadius = dotSize * 0.75
        }
        CATransaction.commit()
        Task { await tick() }
    }

    private var isDark: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// Unlit LED bodies: a quiet track, not a row of black dots.
    private var trackColor: NSColor {
        isDark
            ? NSColor.white.withAlphaComponent(0.10)
            : NSColor.black.withAlphaComponent(0.08)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
        Task { await tick() }
    }

    // MARK: - Frame loop

    private func startLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
        }
    }

    private func tick() async {
        guard window?.isVisible == true else { return }
        let requestedGeneration = generation
        let url = frameURL

        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        request.cachePolicy = .reloadIgnoringLocalCacheData

        guard let (data, _) = try? await AgentRingSession.shared.data(for: request) else {
            return
        }
        guard requestedGeneration == generation, !Task.isCancelled else { return }
        if data.count >= ledCount * 3 {
            apply(data)
        }
    }

    private func apply(_ data: Data) {
        guard window?.isVisible == true else { return }
        let size = dots.first?.bounds.width ?? 12
        // Resolve appearance once per frame instead of once per LED.
        let isDark = self.isDark
        let track = trackColor.cgColor

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for index in 0..<ledCount {
            let dot = dots[index]
            let r = CGFloat(data[index * 3]) / 255
            let g = CGFloat(data[index * 3 + 1]) / 255
            let b = CGFloat(data[index * 3 + 2]) / 255
            let brightness = max(r, max(g, b))

            if brightness <= 0.004 {
                dot.backgroundColor = track
                dot.opacity = 1
                dot.shadowOpacity = 0
                continue
            }

            // The frame carries brightness inside the RGB values. Compositing the
            // hue at that intensity avoids near-black dots on a light card: dim
            // LEDs become a pale tint instead of dark circles.
            let pure = NSColor(
                srgbRed: r / brightness,
                green: g / brightness,
                blue: b / brightness,
                alpha: 1
            )
            dot.backgroundColor = pure.cgColor
            // Power curve: faint LEDs almost blend into the card instead of
            // outlining the whole ring, while the bright segment stays vivid.
            let intensity = min(1, brightness / 0.55)
            // On a light card faint LEDs must almost vanish, or the whole ring
            // turns into grey dots; on a dark card they can stay a bit stronger.
            let floor: CGFloat = isDark ? 0.10 : 0.05
            let curve: CGFloat = isDark ? 1.05 : 1.5
            dot.opacity = Float(floor + (1 - floor) * pow(intensity, curve))
            dot.shadowColor = pure.cgColor
            if brightness > 0.18 {
                // A stronger coloured halo keeps lit LEDs readable on a light
                // card, where a mid-tone colour alone looks flat.
                dot.shadowOpacity = Float(min(0.95, 0.35 + brightness * 0.9))
                dot.shadowRadius = size * 1.15
            } else {
                dot.shadowOpacity = 0
            }
        }
        CATransaction.commit()
    }
}

/// One synthetic state/effect the motion page wants to watch. The daemon
/// renders it through `/preview`, so this still is not a second renderer.
struct RingPreview: Equatable {
    let state: String
    let effect: String
}

struct RingCanvas: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> RingFrameView {
        let view = RingFrameView()
        view.setFrameURL(url)
        return view
    }

    func updateNSView(_ nsView: RingFrameView, context: Context) {
        nsView.setFrameURL(url)
    }
}

struct RingView: View {
    var base = URL(string: "http://127.0.0.1:7801")!

    var body: some View {
        // Always the live frame: effect previews are daemon state now, so the
        // rail shows exactly what the physical ring receives.
        RingCanvas(url: base.appendingPathComponent("frame"))
            .accessibilityLabel("Agent status ring")
    }
}
