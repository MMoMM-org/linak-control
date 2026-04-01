// DeskViewModel.swift
// LinakControlKit — ObservableObject bridging DeskManager to SwiftUI.

import Foundation

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
    @Published public var autoRunUp: RunMode = .manual
    @Published public var autoRunDown: RunMode = .manual

    // MARK: - First-run state

    /// True when no desk has been paired yet (first-run scenario).
    @Published public var isFirstRun: Bool = false

    /// Desks discovered during an active BLE scan.
    @Published public var discoveredDesks: [DiscoveredDesk] = []

    // MARK: - Dependencies

    private let deskManager: DeskManager
    private let configStore: ConfigStore
    private var stateTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?

    // MARK: - Init

    public init(deskManager: DeskManager, configStore: ConfigStore) {
        self.deskManager = deskManager
        self.configStore = configStore
        isFirstRun = (try? configStore.load())?.pairedDeskUUID == nil
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
                await MainActor.run { self?.discoveredDesks.append(desk) }
            }
        }
    }

    /// Connects to a specific desk discovered during scanning.
    ///
    /// Fire-and-forget; errors are swallowed — connection state updates via `stateStream`.
    public func selectDesk(_ desk: DiscoveredDesk) {
        Task { try? await deskManager.connect(peripheralId: desk.peripheralId) }
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

    // MARK: - Private

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
        heightDisplay = snapshot.heightMM.map { HeightConverter.display(mm: $0, unit: unit) } ?? "—"
        isMoving = snapshot.isMoving
        moveDirection = snapshot.moveDirection
        presets = snapshot.presets
        activePreset = snapshot.activePreset
        targetPreset = snapshot.targetPreset
    }
}
