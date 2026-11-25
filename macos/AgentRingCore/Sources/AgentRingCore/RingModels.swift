import Foundation

/// The six visible states plus idle. Raw values match the daemon and the
/// persisted state file.
public enum RingState: String, Codable, Sendable, CaseIterable {
    case thinking
    case tool
    case editing
    case waiting
    case done
    case error
    case idle

    public var priority: Int {
        switch self {
        case .waiting: 7
        case .error: 6
        case .editing: 5
        case .tool: 4
        case .thinking: 3
        case .done: 2
        case .idle: 1
        }
    }

    public var isActive: Bool {
        switch self {
        case .thinking, .tool, .editing: true
        default: false
        }
    }
}

/// The unified event vocabulary accepted by `/ingest` and the hook shims.
public struct RingEvent: Codable, Sendable, Equatable {
    public var source: String
    public var event: String
    public var sessionId: String?
    public var cwd: String?
    public var label: String?
    public var tool: String?
    /// Optional finer state for `tool-start` (`tool`/`editing`).
    public var kind: String?
    public var message: String?

    public init(
        source: String,
        event: String,
        sessionId: String? = nil,
        cwd: String? = nil,
        label: String? = nil,
        tool: String? = nil,
        kind: String? = nil,
        message: String? = nil
    ) {
        self.source = source
        self.event = event
        self.sessionId = sessionId
        self.cwd = cwd
        self.label = label
        self.tool = tool
        self.kind = kind
        self.message = message
    }
}

public struct IngestResult: Sendable, Equatable {
    public var ok: Bool
    public var state: RingState?
    public var ignored: Bool
    public var removed: Bool
    public var heartbeat: Bool
    public var reason: String?

    public init(
        ok: Bool,
        state: RingState? = nil,
        ignored: Bool = false,
        removed: Bool = false,
        heartbeat: Bool = false,
        reason: String? = nil
    ) {
        self.ok = ok
        self.state = state
        self.ignored = ignored
        self.removed = removed
        self.heartbeat = heartbeat
        self.reason = reason
    }
}

public struct RingAgentSnapshot: Sendable, Equatable, Identifiable {
    public var key: String
    public var source: String
    public var sessionId: String?
    public var label: String
    public var cwd: String?
    public var tool: String?
    public var state: RingState
    public var sinceMs: Double
    public var updatedMs: Double

    public var id: String { key }

    public init(
        key: String,
        source: String,
        sessionId: String? = nil,
        label: String,
        cwd: String? = nil,
        tool: String? = nil,
        state: RingState,
        sinceMs: Double,
        updatedMs: Double
    ) {
        self.key = key
        self.source = source
        self.sessionId = sessionId
        self.label = label
        self.cwd = cwd
        self.tool = tool
        self.state = state
        self.sinceMs = sinceMs
        self.updatedMs = updatedMs
    }
}

public struct RingSnapshot: Sendable, Equatable {
    public var ts: Double
    public var leds: Int
    public var active: Int
    public var agents: [RingAgentSnapshot]

    public init(ts: Double, leds: Int = 24, active: Int, agents: [RingAgentSnapshot]) {
        self.ts = ts
        self.leds = leds
        self.active = active
        self.agents = agents
    }
}

/// Plain-JSON form used by `state.json`, kept compatible with the Node daemon.
public struct StoredAgent: Codable, Sendable, Equatable {
    public var key: String
    public var source: String
    public var sessionId: String?
    public var cwd: String?
    public var label: String?
    public var state: String
    public var tool: String?
    public var since: Double
    public var updated: Double
    public var ended: Double?

    public init(
        key: String,
        source: String,
        sessionId: String? = nil,
        cwd: String? = nil,
        label: String? = nil,
        state: String,
        tool: String? = nil,
        since: Double,
        updated: Double,
        ended: Double? = nil
    ) {
        self.key = key
        self.source = source
        self.sessionId = sessionId
        self.cwd = cwd
        self.label = label
        self.state = state
        self.tool = tool
        self.since = since
        self.updated = updated
        self.ended = ended
    }
}

/// Codex / Claude-style hook payload → unified event. The hook shim already
/// does this in shell; the Swift core keeps the mapping for adapters that send
/// raw payloads.
public enum HookMapper {
    public static func map(_ payload: [String: Any], source: String = "codex") -> RingEvent {
        let sessionId = (payload["session_id"] as? String) ?? (payload["sessionId"] as? String)
        let cwd = payload["cwd"] as? String
        let tool = (payload["tool_name"] as? String) ?? (payload["toolName"] as? String)
        let message = payload["message"] as? String
        let name = (payload["hook_event_name"] as? String) ?? (payload["hookEventName"] as? String) ?? ""

        if name == "Notification" {
            let kind = (payload["notification_type"] as? String)
                ?? (payload["notificationType"] as? String)
                ?? ""
            return RingEvent(
                source: source,
                event: kind == "idle_prompt" ? "turn-end" : "waiting",
                sessionId: sessionId,
                cwd: cwd,
                tool: tool,
                message: message
            )
        }

        let event: String
        switch name {
        case "SessionStart": event = "session-start"
        case "UserPromptSubmit": event = "turn-start"
        case "PreToolUse": event = "tool-start"
        case "PostToolUse": event = "tool-end"
        case "PermissionRequest": event = "waiting"
        case "Stop": event = "turn-end"
        case "StopFailure": event = "error"
        case "SessionEnd": event = "session-end"
        default: event = "unknown"
        }
        return RingEvent(
            source: source,
            event: event,
            sessionId: sessionId,
            cwd: cwd,
            tool: tool,
            message: message
        )
    }
}
