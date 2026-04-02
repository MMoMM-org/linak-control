// DeskManager.swift
// LinakControlKit — Central state coordinator for the LINAK DPG1C desk.

import Foundation

// MARK: - DeskManager

/// Actor that owns all desk state and orchestrates BLE operations.
///
/// Single source of truth per ADR-3. All state mutations occur inside the actor.
/// Observers receive a stream of `DeskState` snapshots via `stateStream`.
public actor DeskManager {

    // MARK: - Dependencies

    let bleController: any BLEControllerProtocol
    let configStore: ConfigStore
    let clock: any ClockProtocol

    // MARK: - State

    var state: DeskState
    private var heightNotificationTask: Task<Void, Never>?
    var movementTask: Task<Void, Never>?
    var presetMoveTask: Task<Void, Never>?
    var reconnectionTask: Task<Void, Never>?
    var heartbeatTask: Task<Void, Never>?
    var lastUserAction: ContinuousClock.Instant?
    var isUserInitiatedDisconnect: Bool = false

    // MARK: - State observation

    private let stateContinuation: AsyncStream<DeskState>.Continuation

    /// Emits a new `DeskState` snapshot every time state changes.
    public let stateStream: AsyncStream<DeskState>

    // MARK: - Init

    public init(
        bleController: any BLEControllerProtocol,
        configStore: ConfigStore,
        clock: any ClockProtocol = SystemClock()
    ) {
        self.bleController = bleController
        self.configStore = configStore
        self.clock = clock
        self.state = DeskState()

        var cont: AsyncStream<DeskState>.Continuation!
        stateStream = AsyncStream { continuation in
            cont = continuation
        }
        stateContinuation = cont
    }

    // MARK: - State access

    /// Returns the current desk state snapshot.
    public var currentState: DeskState {
        state
    }

    // MARK: - Connection lifecycle

    /// Scans for nearby LINAK desks and emits each discovered peripheral.
    ///
    /// Updates connection state to `.scanning` and delegates to the BLE controller.
    /// The returned stream terminates when the BLE controller finishes scanning.
    public func scan() -> AsyncStream<DiscoveredDesk> {
        updateState { $0.connectionState = .scanning }
        return bleController.scanForPeripherals()
    }

    /// Connects to a desk peripheral and performs the DPG1C handshake.
    ///
    /// State transitions: `.connecting` → `.connected` on success,
    /// `.connecting` → `.disconnected` on failure.
    ///
    /// - Parameter peripheralId: CoreBluetooth peripheral UUID from a scan result.
    /// - Throws: `BLEError` or `DeskError` on connection or handshake failure.
    public func connect(peripheralId: UUID) async throws {
        FileLog.debug("connect: starting for \(peripheralId)", category: "core")
        isUserInitiatedDisconnect = false
        updateState { $0.connectionState = .connecting }

        do {
            FileLog.debug("connect: BLE connect...", category: "core")
            try await bleController.connect(peripheralId: peripheralId)
            FileLog.debug("connect: BLE connected, starting handshake...", category: "core")
            let result = try await performHandshake(using: bleController)
            FileLog.debug("connect: handshake complete, applying result", category: "core")
            applyHandshakeResult(result, peripheralId: peripheralId)
            startHeightNotificationListener()
            startHeartbeat()
            FileLog.debug("connect: DONE -- state=connected", category: "core")
        } catch {
            FileLog.debug("connect: FAILED -- \(error)", category: "core")
            updateState { $0.connectionState = .disconnected }
            throw error
        }
    }

    /// Disconnects from the desk and resets state.
    ///
    /// Cancels the height notification listener, heartbeat, and any pending reconnection.
    /// Preset labels from config are preserved.
    public func disconnect() async {
        isUserInitiatedDisconnect = true
        heightNotificationTask?.cancel()
        heightNotificationTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        reconnectionTask?.cancel()
        reconnectionTask = nil
        bleController.disconnect()
        resetToDisconnected()
    }

    // MARK: - Movement (implementation in DeskManager+Movement.swift)

    /// Moves the desk upward using the given run mode.
    ///
    /// - Throws: `DeskError.notConnected` if not currently connected.
    public func moveUp(mode: RunMode) async throws {
        try await startMovement(.up, mode: mode)
    }

    /// Moves the desk downward using the given run mode.
    ///
    /// - Throws: `DeskError.notConnected` if not currently connected.
    public func moveDown(mode: RunMode) async throws {
        try await startMovement(.down, mode: mode)
    }

    /// Stops all desk movement.
    ///
    /// Cancels any active manual movement or preset move, writes stop, and clears movement state.
    ///
    /// - Throws: `DeskError.notConnected` if not currently connected.
    public func stop() async throws {
        try requireConnected()
        await cancelMovementTask()
        cancelPresetMoveTask()
        try await writeStopCommand()
        updateState {
            $0.isMoving = false
            $0.moveDirection = nil
            $0.targetPreset = nil
        }
    }

    // MARK: - Presets (implementation in DeskManager+Presets.swift)

    /// Moves the desk to the position stored in a preset slot.
    ///
    /// - Parameter index: Preset slot number (1–4).
    /// - Throws: `DeskError.notConnected`, `DeskError.presetNotSet`, or `DeskError.targetOutOfRange`.
    public func goToPreset(index: Int) async throws {
        try await executeGoToPreset(index: index)
    }

    /// Saves the current desk height to a preset slot.
    ///
    /// - Parameter index: Preset slot number (1–4).
    /// - Throws: `DeskError.notConnected` if not connected; `DeskError.presetNotSet`
    ///   if the index is out of range or no current height is known.
    public func savePreset(index: Int) async throws {
        try requireConnected()
        try await executeSavePreset(index: index)
    }

    // MARK: - Settings

    /// Applies updated app configuration, saving it to disk.
    ///
    /// Preset labels are refreshed in the current state immediately.
    ///
    /// - Throws: Errors from `ConfigStore.save(_:)`.
    public func updateSettings(_ config: AppConfig) throws {
        try configStore.save(config)
        applyPresetLabels(from: config)
        stateContinuation.yield(state)
    }
}

// MARK: - Private helpers

extension DeskManager {

    /// Applies a mutation closure to `state` and yields the updated snapshot.
    func updateState(_ mutation: (inout DeskState) -> Void) {
        mutation(&state)
        stateContinuation.yield(state)
    }

    /// Populates state from a handshake result and persists pairing info.
    private func applyHandshakeResult(_ result: HandshakeResult, peripheralId: UUID) {
        let config = (try? configStore.load()) ?? .default

        for i in 0..<state.presets.count {
            state.presets[i].heightMM = result.presetHeights.count > i ? result.presetHeights[i] : nil
            state.presets[i].label = presetLabel(index: i + 1, config: config)
        }

        state.heightMM = result.currentHeight
        state.connectionState = .connected
        state.deskName = config.pairedDeskName

        persistPairingInfo(peripheralId: peripheralId, existingConfig: config)
        stateContinuation.yield(state)
    }

    /// Saves the paired desk UUID to config.
    private func persistPairingInfo(peripheralId: UUID, existingConfig: AppConfig) {
        var updated = existingConfig
        updated.pairedDeskUUID = peripheralId.uuidString
        try? configStore.save(updated)
    }

    /// Starts the background task that listens to height characteristic notifications.
    private func startHeightNotificationListener() {
        let stream = bleController.notifications(for: DeskUUID.height)
        heightNotificationTask = Task { [weak self] in
            guard let self else { return }
            for await data in stream {
                guard !Task.isCancelled else { break }
                await self.handleHeightNotification(data)
            }
        }
    }

    /// Processes a single height notification packet.
    private func handleHeightNotification(_ data: Data) {
        guard let (heightMM, speedMMS) = parseHeightNotification(data) else { return }
        state.heightMM = heightMM
        state.speedMMS = speedMMS
        state.isMoving = speedMMS != 0
        state.moveDirection = moveDirection(for: speedMMS)
        state.activePreset = activePreset(
            height: heightMM,
            presets: state.presets,
            isMoving: state.isMoving
        )
        stateContinuation.yield(state)
    }

    /// Maps a speed value to a move direction, or nil when stationary.
    private func moveDirection(for speedMMS: Int) -> MoveDirection? {
        if speedMMS > 0 { return .up }
        if speedMMS < 0 { return .down }
        return nil
    }

    /// Resets state to disconnected, preserving preset labels from config.
    private func resetToDisconnected() {
        let config = (try? configStore.load()) ?? .default
        var fresh = DeskState()
        for i in 0..<fresh.presets.count {
            fresh.presets[i].label = presetLabel(index: i + 1, config: config)
        }
        state = fresh
        stateContinuation.yield(state)
    }

    /// Refreshes preset labels in the current state from a config snapshot.
    private func applyPresetLabels(from config: AppConfig) {
        for i in 0..<state.presets.count {
            state.presets[i].label = presetLabel(index: i + 1, config: config)
        }
    }

    /// Returns the configured label for a preset slot (1-based index).
    private func presetLabel(index: Int, config: AppConfig) -> String? {
        switch index {
        case 1: return config.preset1Label
        case 2: return config.preset2Label
        case 3: return config.preset3Label
        case 4: return config.preset4Label
        default: return nil
        }
    }

    /// Throws `DeskError.notConnected` unless the desk is currently connected.
    func requireConnected() throws {
        guard state.connectionState == .connected else {
            throw DeskError.notConnected
        }
    }
}
