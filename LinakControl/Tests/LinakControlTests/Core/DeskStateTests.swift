import XCTest
@testable import LinakControlKit

final class DeskStateTests: XCTestCase {

    // MARK: - DeskState Default Initializer

    func testDefaultInitializerCreatesDisconnectedState() {
        let state = DeskState()
        XCTAssertEqual(state.connectionState, .disconnected)
    }

    func testDefaultInitializerIsNotMoving() {
        let state = DeskState()
        XCTAssertFalse(state.isMoving)
    }

    func testDefaultInitializerHasFourEmptyPresetSlots() {
        let state = DeskState()
        XCTAssertEqual(state.presets.count, 4)
        XCTAssertEqual(state.presets.map(\.index), [1, 2, 3, 4])
        for preset in state.presets {
            XCTAssertNil(preset.heightMM, "Preset \(preset.index) should have no height set")
            XCTAssertNil(preset.label, "Preset \(preset.index) should have no label set")
        }
    }

    func testDefaultInitializerHasNilOptionals() {
        let state = DeskState()
        XCTAssertNil(state.deskName)
        XCTAssertNil(state.heightMM)
        XCTAssertNil(state.speedMMS)
        XCTAssertNil(state.moveDirection)
        XCTAssertNil(state.targetPreset)
        XCTAssertNil(state.activePreset)
    }

    // MARK: - ConnectionState Cases

    func testConnectionStateHasAllFiveCases() {
        // Exhaustive switch ensures the compiler catches any missing case
        let cases: [ConnectionState] = [.disconnected, .scanning, .connecting, .connected, .busy]
        for state in cases {
            switch state {
            case .disconnected, .scanning, .connecting, .connected, .busy:
                break
            }
        }
        XCTAssertEqual(cases.count, 5)
    }

    // MARK: - activePreset — SDD Traced Walkthrough

    func testActivePreset_exactMatch_returnsPresetIndex() {
        // heightMM=1105, presets=[730,1105,900,1200], isMoving=false → 2
        let presets = makePresets([730, 1105, 900, 1200])
        XCTAssertEqual(activePreset(height: 1105, presets: presets, isMoving: false), 2)
    }

    func testActivePreset_withinTolerance_returnsPresetIndex() {
        // heightMM=1103, presets=[730,1105,900,1200], isMoving=false → 2 (diff=2mm)
        let presets = makePresets([730, 1105, 900, 1200])
        XCTAssertEqual(activePreset(height: 1103, presets: presets, isMoving: false), 2)
    }

    func testActivePreset_isMoving_returnsNil() {
        // heightMM=1105, presets=[730,1105,900,1200], isMoving=true → nil
        let presets = makePresets([730, 1105, 900, 1200])
        XCTAssertNil(activePreset(height: 1105, presets: presets, isMoving: true))
    }

    func testActivePreset_multipleMatches_returnsLowestIndex() {
        // heightMM=730, presets=[730,nil,730,1200], isMoving=false → 1 (both 1 and 3 match)
        let presets = [
            PresetPosition(index: 1, heightMM: 730),
            PresetPosition(index: 2, heightMM: nil),
            PresetPosition(index: 3, heightMM: 730),
            PresetPosition(index: 4, heightMM: 1200)
        ]
        XCTAssertEqual(activePreset(height: 730, presets: presets, isMoving: false), 1)
    }

    func testActivePreset_noMatchWithinTolerance_returnsNil() {
        // heightMM=850, presets=[730,1105,900,1200], isMoving=false → nil (closest is 900, diff=50mm)
        let presets = makePresets([730, 1105, 900, 1200])
        XCTAssertNil(activePreset(height: 850, presets: presets, isMoving: false))
    }

    // MARK: - activePreset — All Presets Unset

    func testActivePreset_allPresetsUnset_returnsNil() {
        let presets = (1...4).map { PresetPosition(index: $0, heightMM: nil) }
        XCTAssertNil(activePreset(height: 1000, presets: presets, isMoving: false))
    }

    // MARK: - activePreset — Tolerance Boundary

    func testActivePreset_exactly5mmAway_matches() {
        let presets = makePresets([1000, nil, nil, nil])
        XCTAssertEqual(activePreset(height: 1005, presets: presets, isMoving: false), 1)
        XCTAssertEqual(activePreset(height: 995, presets: presets, isMoving: false), 1)
    }

    func testActivePreset_6mmAway_doesNotMatch() {
        let presets = makePresets([1000, nil, nil, nil])
        XCTAssertNil(activePreset(height: 1006, presets: presets, isMoving: false))
        XCTAssertNil(activePreset(height: 994, presets: presets, isMoving: false))
    }
}

// MARK: - Helpers

/// Builds a 4-slot preset array from an array of optional heights.
/// Nil values represent unset presets. Index is 1-based.
private func makePresets(_ heights: [Int?]) -> [PresetPosition] {
    precondition(heights.count == 4, "makePresets requires exactly 4 heights")
    return heights.enumerated().map { offset, height in
        PresetPosition(index: offset + 1, heightMM: height)
    }
}
