import XCTest
@testable import AgentRingCore

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double

    init(_ value: Double = 1_700_000_000_000) {
        self.value = value
    }

    func now() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(_ milliseconds: Double) {
        lock.lock()
        value += milliseconds
        lock.unlock()
    }
}

final class RingStateStoreTests: XCTestCase {
    func testOneSessionWalksIdleToDone() async {
        let clock = TestClock()
        let store = RingStateStore(now: clock.now)
        let base = (source: "codex", sessionId: "s1", cwd: "/tmp/project")

        await store.ingest(RingEvent(source: base.source, event: "session-start", sessionId: base.sessionId, cwd: base.cwd))
        var snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.agents.first?.state, .idle)
        XCTAssertEqual(snapshot.agents.first?.label, "project")

        await store.ingest(RingEvent(source: base.source, event: "turn-start", sessionId: base.sessionId, cwd: base.cwd))
        snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.agents.first?.state, .thinking)

        await store.ingest(RingEvent(source: base.source, event: "tool-start", sessionId: base.sessionId, cwd: base.cwd, tool: "bash"))
        snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.agents.first?.state, .tool)

        await store.ingest(RingEvent(source: base.source, event: "waiting", sessionId: base.sessionId, cwd: base.cwd, tool: "Bash"))
        snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.agents.first?.state, .waiting)
        XCTAssertEqual(snapshot.agents.first?.tool, "Bash")

        await store.ingest(RingEvent(source: base.source, event: "turn-end", sessionId: base.sessionId, cwd: base.cwd))
        snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.agents.first?.state, .done)

        clock.advance(9_000)
        snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.agents.first?.state, .idle)
    }

    func testSessionEndKeepsDoneForGraceThenDrops() async {
        let clock = TestClock()
        let store = RingStateStore(now: clock.now)
        await store.ingest(RingEvent(source: "dsh", event: "session-start", sessionId: "x"))
        await store.ingest(RingEvent(source: "dsh", event: "session-end", sessionId: "x"))

        var snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.agents.count, 1)
        XCTAssertEqual(snapshot.agents.first?.state, .done)

        clock.advance(4 * 60 * 1_000)
        snapshot = await store.snapshot()
        XCTAssertTrue(snapshot.agents.isEmpty)
    }

    func testWaitingOutranksRunningTool() async {
        let store = RingStateStore()
        await store.ingest(RingEvent(source: "codex", event: "tool-start", sessionId: "a", tool: "bash"))
        await store.ingest(RingEvent(source: "dsh", event: "waiting", sessionId: "b"))
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.agents.map(\.state), [.waiting, .tool])
    }

    func testEqualPriorityKeepsTheOlderSessionFirst() async {
        let clock = TestClock()
        let store = RingStateStore(now: clock.now)
        await store.ingest(RingEvent(source: "dsh", event: "turn-start", sessionId: "old"))
        clock.advance(1_000)
        await store.ingest(RingEvent(source: "dsh", event: "turn-start", sessionId: "new"))
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.agents.map(\.sessionId), ["old", "new"])
    }

    func testEditingToolsGetTheirOwnState() async {
        let store = RingStateStore()
        await store.ingest(RingEvent(source: "dsh", event: "tool-start", sessionId: "e", tool: "apply_patch"))
        var snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.agents.first?.state, .editing)
        await store.ingest(RingEvent(source: "dsh", event: "tool-start", sessionId: "e", tool: "bash"))
        snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.agents.first?.state, .tool)
    }

    func testLateToolEventDoesNotReviveDone() async {
        let clock = TestClock()
        let store = RingStateStore(now: clock.now)
        await store.ingest(RingEvent(source: "codex", event: "turn-start", sessionId: "g"))
        await store.ingest(RingEvent(source: "codex", event: "turn-end", sessionId: "g"))
        let finished = await store.snapshot()
        XCTAssertEqual(finished.agents.first?.state, .done)

        clock.advance(5_000)
        await store.ingest(RingEvent(source: "codex", event: "tool-end", sessionId: "g"))
        let stillDone = await store.snapshot()
        XCTAssertEqual(stillDone.agents.first?.state, .done)

        clock.advance(60_000)
        await store.ingest(RingEvent(source: "codex", event: "turn-start", sessionId: "g"))
        let restarted = await store.snapshot()
        XCTAssertEqual(restarted.agents.first?.state, .thinking)
    }

    func testSilentWorkingSessionDegradesButWaitingIsExempt() async {
        let clock = TestClock()
        let store = RingStateStore(now: clock.now)
        await store.ingest(RingEvent(source: "dsh", event: "tool-start", sessionId: "s", tool: "bash"))
        clock.advance(11 * 60 * 1_000)
        let stale = await store.snapshot(staleMs: 10 * 60 * 1_000)
        XCTAssertEqual(stale.agents.first?.state, .idle)

        await store.ingest(RingEvent(source: "dsh", event: "waiting", sessionId: "w"))
        clock.advance(60 * 60 * 1_000)
        let snapshot = await store.snapshot(staleMs: 10 * 60 * 1_000)
        XCTAssertEqual(snapshot.agents.first(where: { $0.sessionId == "w" })?.state, .waiting)
    }

    func testIdleStatusAfterFailureDoesNotPaintErrorGreen() async {
        let store = RingStateStore()
        await store.ingest(RingEvent(source: "dsh", event: "tool-start", sessionId: "e", tool: "bash"))
        await store.ingest(RingEvent(source: "dsh", event: "error", sessionId: "e"))
        await store.ingest(RingEvent(source: "dsh", event: "turn-end", sessionId: "e"))
        let errorSnapshot = await store.snapshot()
        XCTAssertEqual(errorSnapshot.agents.first?.state, .error)

        await store.ingest(RingEvent(source: "dsh", event: "turn-start", sessionId: "e"))
        let restarted = await store.snapshot()
        XCTAssertEqual(restarted.agents.first?.state, .thinking)
    }

    func testHeartbeatDoesNotCreateOrReviveSession() async {
        let store = RingStateStore()
        await store.ingest(RingEvent(source: "dsh", event: "control", sessionId: "ghost"))
        let ghost = await store.snapshot()
        XCTAssertTrue(ghost.agents.isEmpty)

        await store.ingest(RingEvent(source: "dsh", event: "session-start", sessionId: "x"))
        await store.ingest(RingEvent(source: "dsh", event: "session-end", sessionId: "x"))
        await store.ingest(RingEvent(source: "dsh", event: "control", sessionId: "x"))
        let done = await store.snapshot()
        XCTAssertEqual(done.agents.first?.state, .done)
    }

    func testSerializeHydratePreservesSession() async throws {
        let store = RingStateStore()
        await store.ingest(RingEvent(source: "codex", event: "tool-start", sessionId: "p1", cwd: "/tmp/p1", tool: "Bash"))
        let saved = await store.serialize()
        let data = try JSONEncoder().encode(saved)
        let decoded = try JSONDecoder().decode([StoredAgent].self, from: data)

        let restored = RingStateStore()
        await restored.hydrate(decoded)
        let agent = await restored.snapshot().agents.first
        XCTAssertEqual(agent?.label, "p1")
        XCTAssertEqual(agent?.state, .tool)
        XCTAssertEqual(agent?.tool, "Bash")
    }

    func testHookMapperMapsCodexPayloads() {
        XCTAssertEqual(HookMapper.map(["hook_event_name": "SessionStart"]).event, "session-start")
        XCTAssertEqual(HookMapper.map(["hook_event_name": "UserPromptSubmit"]).event, "turn-start")
        XCTAssertEqual(HookMapper.map(["hook_event_name": "PreToolUse", "tool_name": "Bash"]).event, "tool-start")
        XCTAssertEqual(HookMapper.map(["hook_event_name": "PermissionRequest"]).event, "waiting")
        XCTAssertEqual(HookMapper.map(["hook_event_name": "Stop"]).event, "turn-end")
        XCTAssertEqual(HookMapper.map(["hook_event_name": "StopFailure"]).event, "error")
        XCTAssertEqual(HookMapper.map(["hook_event_name": "SessionEnd"]).event, "session-end")
        XCTAssertEqual(
            HookMapper.map(["hook_event_name": "Notification", "notification_type": "idle_prompt"]).event,
            "turn-end"
        )
        XCTAssertEqual(HookMapper.map(["hook_event_name": "Nope"]).event, "unknown")
    }
}
