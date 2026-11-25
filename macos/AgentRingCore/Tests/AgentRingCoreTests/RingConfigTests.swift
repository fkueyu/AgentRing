import XCTest
@testable import AgentRingCore

final class RingConfigTests: XCTestCase {
    private func decode(_ json: String) throws -> RingConfig {
        try JSONDecoder().decode(RingConfig.self, from: Data(json.utf8))
    }

    func testEmptyConfigUsesDefaults() throws {
        let config = try decode("{}")
        XCTAssertEqual(config.version, 3)
        XCTAssertEqual(config.display.accent, "state")
        XCTAssertEqual(config.display.brightness, 0.5)
        XCTAssertEqual(config.layout.mode, "split")
        XCTAssertEqual(config.motion.effects.thinking, "breathe")
        XCTAssertEqual(config.sources["codex"]?.color, "#10a37f")
        XCTAssertEqual(config.stateColors["waiting"], "#ffaa28")
    }

    func testDisplayValuesClampAndFallback() throws {
        let config = try decode("""
        {"display":{"brightness":2,"gamma":0.1,"currentLimitMa":9999,"accent":"bogus","rainbowSpeed":9}}
        """)
        XCTAssertEqual(config.display.brightness, 1)
        XCTAssertEqual(config.display.gamma, 0.8)
        XCTAssertEqual(config.display.currentLimitMa, 2000)
        XCTAssertEqual(config.display.accent, "state")
        XCTAssertEqual(config.display.rainbowSpeed, 2)
    }

    func testLegacyRainbowStandbyIsLifted() throws {
        let config = try decode("""
        {"display":{"standby":"rainbow"}}
        """)
        XCTAssertEqual(config.display.standby, "orbit")
        XCTAssertEqual(config.display.standbyPalette, "rainbow")
    }

    func testColorsAreNormalizedOrFallBack() throws {
        let config = try decode("""
        {"display":{"standbyColor":"#ABCDEF"},"stateColors":{"thinking":"abc","done":"#00FF00"},"sources":{"codex":{"color":"nope"},"newtool":{"enabled":false,"color":"#112233"}}}
        """)
        XCTAssertEqual(config.display.standbyColor, "#abcdef")
        XCTAssertEqual(config.stateColors["thinking"], "#4d6bfe")
        XCTAssertEqual(config.stateColors["done"], "#00ff00")
        XCTAssertEqual(config.sources["codex"]?.color, "#10a37f")
        XCTAssertEqual(config.sources["newtool"]?.enabled, false)
        XCTAssertEqual(config.sources["newtool"]?.color, "#112233")
    }

    func testLayoutRoundsAndClamps() throws {
        let config = try decode("""
        {"layout":{"maxAgents":4.6,"gapLeds":9,"rotateSeconds":100,"showIdle":true}}
        """)
        XCTAssertEqual(config.layout.maxAgents, 5)
        XCTAssertEqual(config.layout.gapLeds, 3)
        XCTAssertEqual(config.layout.rotateSeconds, 60)
        XCTAssertTrue(config.layout.showIdle)
    }

    func testEffectsAndSpeedsAreValidated() throws {
        let config = try decode("""
        {"motion":{"speeds":{"thinking":9},"effects":{"thinking":"pulse","tool":"pulse"},"doneHoldSeconds":1,"staleMinutes":100}}
        """)
        XCTAssertEqual(config.motion.speeds.thinking, 3)
        XCTAssertEqual(config.motion.effects.thinking, "breathe")
        XCTAssertEqual(config.motion.effects.tool, "pulse")
        XCTAssertEqual(config.motion.doneHoldSeconds, 2)
        XCTAssertEqual(config.motion.staleMinutes, 60)
    }

    func testNightModeClamps() throws {
        let config = try decode("""
        {"display":{"nightMode":{"enabled":true,"startMinute":-5,"endMinute":2000,"brightness":1}}}
        """)
        XCTAssertTrue(config.display.nightMode.enabled)
        XCTAssertEqual(config.display.nightMode.startMinute, 0)
        XCTAssertEqual(config.display.nightMode.endMinute, 1439)
        XCTAssertEqual(config.display.nightMode.brightness, 0.5)
    }

    func testRoundTrip() throws {
        let config = try decode("""
        {"display":{"accent":"mint","brightness":0.7},"layout":{"mode":"focus"},"sources":{"codex":{"enabled":false,"color":"#112233"}}}
        """)
        let data = try JSONEncoder().encode(config)
        let restored = try JSONDecoder().decode(RingConfig.self, from: data)
        XCTAssertEqual(restored, config)
    }

    func testMalformedPartialValueFallsBackToDefaults() throws {
        let config = try decode("""
        {"display":{"brightness":"bright"}}
        """)
        XCTAssertEqual(config.display.brightness, 0.5)
    }
}
