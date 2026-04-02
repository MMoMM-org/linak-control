// DeskViewModel.swift
// LinakControlKit — ObservableObject bridging DeskManager to SwiftUI.

import Foundation
import ServiceManagement

// MARK: - DeskViewModel

/// Main-actor view model that bridges `DeskManager` to SwiftUI.
///
/// Subscribes to `DeskManager.stateStream` and maps snapshots to `@Published`
/// properties. All action methods fire-and-forget into async tasks; errors are
/// silently swallowed because the UI has no meaningful recovery path beyond
/// retrying.
@MainActor
public final class DeskViewModel: ObservableObject {

    // MARK: - Published state

    @Published public var connectionState: ConnectionState = .disconnected
    @Published public var heightMM: Int?
    @Published public var heightDisplay: String = "—"
    @Published public var isMoving: Bool = false
    @Published public var moveDirection: MoveDirection?
    @Published public var presets: [PresetPosition] = (1...4).map { PresetPosition(index: $0) }
    @Published public var activePreset: Int?
    @Published public var targetPreset: Int?
    @Published public var unit: HeightUnit = .cm
    @Published public var deskOffsetMM: Int = 0
    @Published public var autoRunUp: RunMode = .manual
    @Published public var autoRunDown: RunMode = .manual

    // MARK: - First-run state

    /// True when no desk has been paired yet (first-run scenario).
    @Published public var isFirstRun: Bool = false

    /// Desks discovered during an active BLE scan.
    @Published public var discoveredDesks: [DiscoveredDesk] = []

    /// Name of the currently connected desk, populated from `DeskState` snapshots.
    @Published public var deskName: String?

    // MARK: - Settings state

    /// True when the settings panel is visible inside the popover.
    @Published public var showSettings: Bool = false

    /// Mirrors `AppConfig.startAtLogin`; toggling this registers/unregisters the login item.
    @Published public var startAtLogin: Bool = false

    /// Mirrors `AppConfig.hotkeysEnabled`.
    @Published public var hotkeysEnabled: Bool = false

    // MARK: - Dependencies

    private let deskManager: DeskManager
    private let configStore: ConfigStore
    private let loginItemManager: LoginItemManaging
    private var stateTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?

    /// Peripheral ID captured when the user selects a desk during first-run.
    private var selectedPeripheralId: UUID?

    /// Name of the desk selected during first-run scanning (before connection completes).
    ///
    /// Used by `FirstRunConnectingView` to show the desk name while the handshake runs.
    @Published public var selectedDeskName: String?

    // MARK: - Init

    public init(
        deskManager: DeskManager,
        configStore: ConfigStore,
        loginItemManager: LoginItemManaging = LoginItemManager()
    ) {
        self.deskManager = deskManager
        self.configStore = configStore
        self.loginItemManager = loginItemManager
        let config = (try? configStore.load()) ?? .default
        isFirstRun = config.pairedDeskUUID == nil
        unit = config.unit
        deskOffsetMM = config.deskOffsetMM
        autoRunUp = config.autoRunUp
        autoRunDown = config.autoRunDown
        startAtLogin = config.startAtLogin
        hotkeysEnabled = config.hotkeysEnabled
        startObservingStateStream()
    }

    deinit {
        stateTask?.cancel()
        scanTask?.cancel()
    }

    // MARK: - Actions

    public func goToPreset(index: Int) {
        Task { try? await deskManager.goToPreset(index: index) }
    }

    public func moveUp() {
        Task { try? await deskManager.moveUp(mode: autoRunUp) }
    }

    public func moveDown() {
        Task { try? await deskManager.moveDown(mode: autoRunDown) }
    }

    public func stop() {
        Task { try? await deskManager.stop() }
    }

    public func savePreset(index: Int) {
        Task { try? await deskManager.savePreset(index: index) }
    }

    /// Starts a BLE scan and collects discovered desks into `discoveredDesks`.
    ///
    /// Clears any previously discovered desks before starting. Fire-and-forget;
    /// the published `discoveredDesks` array updates as desks are found.
    public func startScan() {
        scanTask?.cancel()
        discoveredDesks = []
        let manager = deskManager
        scanTask = Task { [weak self] in
            let stream = await manager.scan()
            for await desk in stream {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    guard let self else { return }
                    // Deduplicate by peripheral ID — BLE may report the same desk multiple times.
                    if !self.discoveredDesks.contains(where: { $0.peripheralId == desk.peripheralId }) {
                        self.discoveredDesks.append(desk)
                    }
                }
            }
        }
    }

    /// Connects to a specific desk discovered during scanning.
    ///
    /// Captures the desk's peripheral ID and name for use in `completeFirstRun()`.
    /// Guards against duplicate calls (e.g. double-click). Connection state updates
    /// arrive via `stateStream`; errors are swallowed since the UI shows state changes.
    private var connectTask: Task<Void, Never>?

    public func selectDesk(_ desk: DiscoveredDesk) {
        // Ignore if already connecting/connected to this desk.
        guard connectionState != .connecting && connectionState != .connected else {
            FileLog.debug("selectDesk: ignored -- already \(connectionState)", category: "ui")
            return
        }
        selectedPeripheralId = desk.peripheralId
        selectedDeskName = desk.name
        scanTask?.cancel()
        connectTask?.cancel()
        FileLog.debug("selectDesk: connecting to '\(desk.name)'", category: "ui")
        connectTask = Task { try? await deskManager.connect(peripheralId: desk.peripheralId) }
    }

    /// Finalises the first-run pairing flow.
    ///
    /// Persists the selected desk's UUID and name to `ConfigStore`, then sets
    /// `isFirstRun = false` so `PopoverView` transitions to the normal UI.
    public func completeFirstRun() {
        guard let peripheralId = selectedPeripheralId else { return }
        let name = selectedDeskName
        Task {
            var config = (try? configStore.load()) ?? .default
            config.pairedDeskUUID = peripheralId.uuidString
            config.pairedDeskName = name
            try? configStore.save(config)
        }
        isFirstRun = false
    }

    /// Attempts to reconnect to the paired desk stored in config.
    ///
    /// Reads the paired desk UUID from `ConfigStore`. If no paired desk is
    /// configured, triggers a scan (first-run scenario).
    public func retryConnection() {
        Task {
            let config = try? configStore.load()
            guard let uuidString = config?.pairedDeskUUID,
                  let peripheralId = UUID(uuidString: uuidString) else {
                _ = await deskManager.scan()
                return
            }
            try? await deskManager.connect(peripheralId: peripheralId)
        }
    }

    /// Persists the start-at-login preference and registers or unregisters the login item.
    ///
    /// Errors from SMAppService (e.g. duplicate registration) are silently ignored;
    /// the setting is still persisted so the UI stays in sync.
    public func setStartAtLogin(_ enabled: Bool) {
        startAtLogin = enabled
        if enabled {
            try? loginItemManager.register()
        } else {
            try? loginItemManager.unregister()
        }
        Task {
            var config = (try? configStore.load()) ?? .default
            config.startAtLogin = enabled
            try? configStore.save(config)
        }
    }

    // MARK: - Settings actions

    /// Updates the height display unit, recalculates `heightDisplay`, and persists to config.
    public func updateUnit(_ newUnit: HeightUnit) {
        unit = newUnit
        heightDisplay = heightMM.map { HeightConverter.display(mm: $0 + deskOffsetMM, unit: newUnit) } ?? "—"
        persistConfig { $0.unit = newUnit }
    }

    /// Updates the desk base offset and recalculates all displayed heights.
    public func updateDeskOffset(_ mm: Int) {
        deskOffsetMM = mm
        heightDisplay = heightMM.map { HeightConverter.display(mm: $0 + mm, unit: unit) } ?? "—"
        persistConfig { $0.deskOffsetMM = mm }
    }

    /// Updates the up-movement run mode and persists to config.
    public func updateAutoRunUp(_ mode: RunMode) {
        autoRunUp = mode
        persistConfig { $0.autoRunUp = mode }
    }

    /// Updates the down-movement run mode and persists to config.
    public func updateAutoRunDown(_ mode: RunMode) {
        autoRunDown = mode
        persistConfig { $0.autoRunDown = mode }
    }

    /// Updates the start-at-login setting and persists to config (no SMAppService side-effect).
    ///
    /// Use `setStartAtLogin(_:)` when SMAppService registration is also required.
    public func updateStartAtLogin(_ enabled: Bool) {
        startAtLogin = enabled
        persistConfig { $0.startAtLogin = enabled }
    }

    /// Updates the global-hotkeys setting and persists to config.
    public func updateHotkeysEnabled(_ enabled: Bool) {
        hotkeysEnabled = enabled
        persistConfig { $0.hotkeysEnabled = enabled }
    }

    /// Clears pairing info, disconnects from the desk, and resets to first-run state.
    ///
    /// The user will be taken back through the scanning flow on next interaction.
    public func forgetAndRescan() {
        persistConfig {
            $0.pairedDeskUUID = nil
            $0.pairedDeskName = nil
        }
        Task { await deskManager.disconnect() }
        showSettings = false
        isFirstRun = true
    }

    // MARK: - Private

    /// Loads config, applies a mutation, and saves it back to disk synchronously.
    private func persistConfig(_ mutation: (inout AppConfig) -> Void) {
        var config = (try? configStore.load()) ?? .default
        mutation(&config)
        try? configStore.save(config)
    }

    private func startObservingStateStream() {
        // Capture manager strongly — the view model owns the subscription lifecycle.
        let manager = deskManager
        stateTask = Task { [weak self] in
            for await snapshot in await manager.stateStream {
                guard !Task.isCancelled else { break }
                // Task inherits @MainActor from DeskViewModel; apply is safe here.
                self?.apply(snapshot)
            }
        }
    }

    private func apply(_ snapshot: DeskState) {
        connectionState = snapshot.connectionState
        heightMM = snapshot.heightMM

        // Update offset from desk state (handshake may have provided a new one).
        if snapshot.deskOffsetMM > 0 {
            deskOffsetMM = snapshot.deskOffsetMM
        }

        let offset = deskOffsetMM
        heightDisplay = snapshot.heightMM.map {
            HeightConverter.display(mm: $0 + offset, unit: unit)
        } ?? "—"

        isMoving = snapshot.isMoving
        moveDirection = snapshot.moveDirection

        // Apply offset to preset heights for display.
        presets = snapshot.presets.map { preset in
            var adjusted = preset
            if let h = preset.heightMM {
                adjusted.heightMM = h + offset
            }
            return adjusted
        }

        activePreset = snapshot.activePreset
        targetPreset = snapshot.targetPreset
        deskName = snapshot.deskName
    }
}
