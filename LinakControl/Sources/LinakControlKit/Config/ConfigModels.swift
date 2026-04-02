// ConfigModels.swift
// LinakControlKit

import Foundation

// MARK: - Config Models

/// Persisted application settings. Stored as config.json in
/// ~/Library/Application Support/LinakControl/.
public struct AppConfig: Codable, Equatable {

    // MARK: Pairing

    /// CoreBluetooth peripheral identifier for the paired desk.
    public var pairedDeskUUID: String?

    /// Human-readable desk name shown in the UI.
    public var pairedDeskName: String?

    // MARK: Display

    /// Height display unit. Defaults to .cm.
    public var unit: HeightUnit

    /// Desk base offset in mm. Raw heights from the desk are relative to its internal
    /// zero point; adding this offset gives the absolute height from floor.
    public var deskOffsetMM: Int

    // MARK: Movement

    /// Up button behaviour. Defaults to .manual (hold to move).
    public var autoRunUp: RunMode

    /// Down button behaviour. Defaults to .manual (hold to move).
    public var autoRunDown: RunMode

    // MARK: System

    /// Register the app as a login item. Defaults to false.
    public var startAtLogin: Bool

    /// Enable global keyboard shortcuts. Defaults to false.
    public var hotkeysEnabled: Bool

    // MARK: Preset Labels

    /// Optional label for preset 1, e.g. "Sitting".
    public var preset1Label: String?

    /// Optional label for preset 2, e.g. "Standing".
    public var preset2Label: String?

    /// Optional label for preset 3.
    public var preset3Label: String?

    /// Optional label for preset 4.
    public var preset4Label: String?

    // MARK: Init

    public init(
        pairedDeskUUID: String? = nil,
        pairedDeskName: String? = nil,
        unit: HeightUnit = .cm,
        deskOffsetMM: Int = 0,
        autoRunUp: RunMode = .manual,
        autoRunDown: RunMode = .manual,
        startAtLogin: Bool = false,
        hotkeysEnabled: Bool = false,
        preset1Label: String? = nil,
        preset2Label: String? = nil,
        preset3Label: String? = nil,
        preset4Label: String? = nil
    ) {
        self.pairedDeskUUID = pairedDeskUUID
        self.pairedDeskName = pairedDeskName
        self.unit = unit
        self.deskOffsetMM = deskOffsetMM
        self.autoRunUp = autoRunUp
        self.autoRunDown = autoRunDown
        self.startAtLogin = startAtLogin
        self.hotkeysEnabled = hotkeysEnabled
        self.preset1Label = preset1Label
        self.preset2Label = preset2Label
        self.preset3Label = preset3Label
        self.preset4Label = preset4Label
    }

    // MARK: CodingKeys — snake_case JSON per SDD schema

    enum CodingKeys: String, CodingKey {
        case pairedDeskUUID   = "paired_desk_uuid"
        case pairedDeskName   = "paired_desk_name"
        case unit
        case deskOffsetMM     = "desk_offset_mm"
        case autoRunUp        = "auto_run_up"
        case autoRunDown      = "auto_run_down"
        case startAtLogin     = "start_at_login"
        case hotkeysEnabled   = "hotkeys_enabled"
        case preset1Label     = "preset_1_label"
        case preset2Label     = "preset_2_label"
        case preset3Label     = "preset_3_label"
        case preset4Label     = "preset_4_label"
    }

    // MARK: Decodable — tolerant of missing keys

    /// Custom decoder that provides defaults for any missing keys.
    /// Without this, adding a new field breaks decoding of old config files
    /// and all persisted settings are lost.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pairedDeskUUID = try c.decodeIfPresent(String.self, forKey: .pairedDeskUUID)
        pairedDeskName = try c.decodeIfPresent(String.self, forKey: .pairedDeskName)
        unit           = try c.decodeIfPresent(HeightUnit.self, forKey: .unit) ?? .cm
        deskOffsetMM   = try c.decodeIfPresent(Int.self, forKey: .deskOffsetMM) ?? 0
        autoRunUp      = try c.decodeIfPresent(RunMode.self, forKey: .autoRunUp) ?? .manual
        autoRunDown    = try c.decodeIfPresent(RunMode.self, forKey: .autoRunDown) ?? .manual
        startAtLogin   = try c.decodeIfPresent(Bool.self, forKey: .startAtLogin) ?? false
        hotkeysEnabled = try c.decodeIfPresent(Bool.self, forKey: .hotkeysEnabled) ?? false
        preset1Label   = try c.decodeIfPresent(String.self, forKey: .preset1Label)
        preset2Label   = try c.decodeIfPresent(String.self, forKey: .preset2Label)
        preset3Label   = try c.decodeIfPresent(String.self, forKey: .preset3Label)
        preset4Label   = try c.decodeIfPresent(String.self, forKey: .preset4Label)
    }

    // MARK: Defaults

    /// Factory default — matches SDD initial values.
    public static let `default` = AppConfig()
}

// MARK: - HeightUnit

/// Height display unit.
public enum HeightUnit: String, Codable {
    case cm
    case inch
}

// MARK: - RunMode

/// Movement button behaviour.
public enum RunMode: String, Codable {
    /// Hold the button to keep moving (release to stop).
    case manual

    /// Tap once to start; the desk runs automatically to the target.
    case auto
}
