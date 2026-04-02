// DeskManager+PresetSave.swift
// LinakControlKit — Preset save operation for DeskManager.

import CoreBluetooth
import Foundation

// MARK: - Preset Save

extension DeskManager {

    /// Executes the full save-preset sequence.
    ///
    /// Called from `DeskManager.savePreset(index:)`. Separated into this extension
    /// file so it does not conflict with the T2.5 `DeskManager+Presets.swift` extension.
    ///
    /// Steps:
    /// 1. Guard index 1…4 and current height available.
    /// 2. Write save command to DPG characteristic.
    /// 3. Await DPG confirmation notification.
    /// 4. Write read-preset command and await notification.
    /// 5. Parse confirmed height; update state.
    ///
    /// - Parameter index: Preset slot number (1–4).
    /// - Throws: `DeskError.presetNotSet` for invalid index or missing height;
    ///   `DeskError.handshakeTimeout` on BLE response timeout; BLE errors on transport failure.
    func executeSavePreset(index: Int) async throws {
        guard (1...4).contains(index) else {
            throw DeskError.presetNotSet(index: index)
        }
        guard let heightMM = state.heightMM else {
            throw DeskError.presetNotSet(index: 0)
        }

        let rawValue = UInt16(heightMM * 10)
        guard let saveCommand = DeskCommand.savePreset(index: index, tenthsOfMm: rawValue) else {
            return
        }

        let dpgStream = bleController.notifications(for: DeskUUID.dpg)
        let buffer = TimedStreamBuffer(stream: dpgStream)

        try await bleController.write(data: saveCommand, to: DeskUUID.dpg, type: .withResponse)
        _ = try await buffer.next()

        guard let readCommand = DeskCommand.readPreset(index: index) else { return }
        try await bleController.write(data: readCommand, to: DeskUUID.dpg, type: .withResponse)
        let readResponse = try await buffer.next()

        let confirmedHeight = DeskProtocol.parsePresetHeight(readResponse)
        if confirmedHeight == nil {
            print("[DeskManager] savePreset: re-read returned no height for preset \(index); accepting firmware value")
        }

        updateState { s in
            s.presets[index - 1].heightMM = confirmedHeight ?? heightMM
        }
    }
}

// DPGResponseBuffer replaced by shared TimedStreamBuffer (Util/TimedStreamBuffer.swift).
