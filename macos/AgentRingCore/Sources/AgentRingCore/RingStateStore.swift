import Foundation

/// Per-session state machine, ported from `daemon/src/state.mjs`.
///
/// The store owns one record per live session. Rendering and persistence read
/// `snapshot()`; the HTTP server will call `ingest()` for every `/ingest` event.
public actor RingStateStore {
    public static let defaultDoneHoldMs: Double = 8_000
    public static let defaultStaleMs: Double = 10 * 60 * 1_000
    public static let defaultIdleTTLMs: Double = 45 * 60 * 1_000
    public static let defaultEndedGraceMs: Double = 3 * 60 * 1_000
    public static let doneRegressionGuardMs: Double = 45 * 1_000

    public typealias Now = @Sendable () -> Double

    private struct Record {
        var key: String
        var source: String
        var sessionId: String?
        var cwd: String?
        var label: String
        var state: RingState
        var tool: String?
        var since: Double
        var updated: Double
        var ended: Double?
    }

    private var records: [String: Record] = [:]
    private let now: Now

    public init(now: @escaping Now = { Date().timeIntervalSince1970 * 1_000 }) {
        self.now = now
    }

    public var count: Int { records.count }

    @discardableResult
    public func ingest(_ event: RingEvent) -> IngestResult {
        let source = event.source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            return IngestResult(ok: false, reason: "missing source")
        }

        let ts = now()
        let key = key(for: event, source: source)
        var record = records[key]

        // Heartbeats only refresh liveness: they must not create a record,
        // revive an ended one, or change what the ring shows.
        if event.event == "control" {
            guard var existing = record else {
                return IngestResult(ok: true, ignored: true, heartbeat: true)
            }
            existing.updated = ts
            records[key] = existing
            return IngestResult(ok: true, state: existing.state, heartbeat: true)
        }

        if event.event == "session-end" {
            guard var existing = record else {
                return IngestResult(ok: true, removed: true)
            }
            existing.state = .done
            existing.since = ts
            existing.updated = ts
            existing.ended = ts
            existing.tool = nil
            records[key] = existing
            return IngestResult(ok: true, state: .done)
        }

        if record == nil {
            record = Record(
                key: key,
                source: source,
                sessionId: nonEmpty(event.sessionId),
                cwd: nonEmpty(event.cwd),
                label: nonEmpty(event.label) ?? Self.label(for: event.cwd),
                state: .idle,
                tool: nil,
                since: ts,
                updated: ts,
                ended: nil
            )
            records[key] = record
        }

        guard var current = record else {
            return IngestResult(ok: false, reason: "missing record")
        }

        if let cwd = nonEmpty(event.cwd) { current.cwd = cwd }
        if let label = nonEmpty(event.label) {
            current.label = label
        } else if let cwd = nonEmpty(event.cwd) {
            current.label = Self.label(for: cwd)
        }
        current.updated = ts
        current.ended = nil

        // A late tool event must not flip a finished turn back to running.
        if current.state == .done,
           (event.event == "tool-start" || event.event == "tool-end"),
           ts - current.since < Self.doneRegressionGuardMs {
            records[key] = current
            return IngestResult(ok: true, state: .done, ignored: true)
        }

        // DSH reports a failed turn and an idle status back to back; the idle
        // status must not paint the failure green.
        if event.event == "turn-end", current.state == .error {
            records[key] = current
            return IngestResult(ok: true, state: .error, ignored: true)
        }

        let next = Self.state(for: event)
        if event.event == "tool-start", let tool = nonEmpty(event.tool) {
            current.tool = tool
        }
        if event.event == "waiting", let tool = nonEmpty(event.tool) {
            current.tool = tool
        }
        if ["turn-start", "turn-end", "session-start"].contains(event.event) {
            current.tool = nil
        }

        let target: RingState?
        if event.event == "tool-start" {
            target = nonEmpty(event.kind).flatMap(RingState.init(rawValue:))
                ?? Self.classifyTool(event.tool)
        } else {
            target = next
        }

        if let target, target != current.state {
            current.state = target
            current.since = ts
        }
        records[key] = current
        return IngestResult(ok: true, state: current.state)
    }

    public func snapshot(
        doneHoldMs: Double = defaultDoneHoldMs,
        staleMs: Double = defaultStaleMs,
        endedGraceMs: Double = defaultEndedGraceMs
    ) -> RingSnapshot {
        let ts = now()
        var agents: [RingAgentSnapshot] = []

        for (key, record) in records {
            var state = record.state
            if state == .done, ts - record.since > doneHoldMs {
                state = .idle
            }
            // A turn that stops reporting is not proof of work: degrade it
            // instead of pinning the ring on running after a plugin crash.
            // Waiting is exempt because an approval may legitimately wait.
            if state.isActive, ts - record.updated > staleMs {
                state = .idle
            }
            if let ended = record.ended, ts - ended > endedGraceMs {
                records.removeValue(forKey: key)
                continue
            }
            if state == .idle, ts - record.updated > Self.defaultIdleTTLMs {
                records.removeValue(forKey: key)
                continue
            }
            agents.append(RingAgentSnapshot(
                key: record.key,
                source: record.source,
                sessionId: record.sessionId,
                label: record.label,
                cwd: record.cwd,
                tool: record.tool,
                state: state,
                sinceMs: ts - record.since,
                updatedMs: ts - record.updated
            ))
        }

        agents.sort {
            $0.state.priority != $1.state.priority
                ? $0.state.priority > $1.state.priority
                : $0.updatedMs > $1.updatedMs
        }
        return RingSnapshot(
            ts: ts,
            leds: 24,
            active: agents.filter { $0.state != .idle }.count,
            agents: agents
        )
    }

    @discardableResult
    public func forget(sessionId: String) -> Int {
        let keys = records.compactMap { key, record in
            record.sessionId == sessionId ? key : nil
        }
        for key in keys { records.removeValue(forKey: key) }
        return keys.count
    }

    public func serialize() -> [StoredAgent] {
        records.values.map { record in
            StoredAgent(
                key: record.key,
                source: record.source,
                sessionId: record.sessionId,
                cwd: record.cwd,
                label: record.label,
                state: record.state.rawValue,
                tool: record.tool,
                since: record.since,
                updated: record.updated,
                ended: record.ended
            )
        }
    }

    public func hydrate(_ stored: [StoredAgent]) {
        for item in stored where !item.key.isEmpty {
            let state = item.state == "running"
                ? RingState.tool
                : (RingState(rawValue: item.state) ?? .idle)
            records[item.key] = Record(
                key: item.key,
                source: item.source.isEmpty ? "unknown" : item.source,
                sessionId: item.sessionId,
                cwd: item.cwd,
                label: item.label ?? Self.label(for: item.cwd),
                state: state,
                tool: item.tool,
                since: item.since,
                updated: item.updated,
                ended: item.ended
            )
        }
    }

    @discardableResult
    public func clear() -> Int {
        let count = records.count
        records.removeAll()
        return count
    }

    // MARK: - Helpers

    private func key(for event: RingEvent, source: String) -> String {
        let ident = nonEmpty(event.sessionId)
            ?? nonEmpty(event.cwd)
            ?? "default"
        return "\(source):\(ident)"
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    public static func label(for cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return "session" }
        let trimmed = cwd.replacingOccurrences(
            of: "/+$",
            with: "",
            options: .regularExpression
        )
        let parts = trimmed.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard let last = parts.last else { return "/" }
        return last.isEmpty ? "/" : String(last)
    }

    public static func classifyTool(_ name: String?) -> RingState {
        let tool = (name ?? "").lowercased()
        guard !tool.isEmpty else { return .tool }
        let editing = [
            "apply_patch", "edit", "write", "patch", "create_file",
            "str_replace", "multi_edit", "insert",
        ]
        return editing.contains(where: tool.contains) ? .editing : .tool
    }

    private static func state(for event: RingEvent) -> RingState? {
        switch event.event {
        case "session-start": .idle
        case "turn-start", "thinking": .thinking
        case "tool-start": .tool
        case "tool-end": .thinking
        case "waiting": .waiting
        case "turn-end": .done
        case "error": .error
        default: nil
        }
    }
}
