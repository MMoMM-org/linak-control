// BLEController.swift
// LinakControlKit — CoreBluetooth implementation of BLEControllerProtocol.

import CoreBluetooth
import Foundation

// MARK: - BLEController

/// Wraps `CBCentralManager` and bridges CoreBluetooth delegate callbacks to async/await.
///
/// Thread safety is enforced via a dedicated serial `DispatchQueue`.
/// The class is marked `@unchecked Sendable` because mutating state is always
/// accessed on `bleQueue`, not through Swift concurrency primitives.
public final class BLEController: NSObject, BLEControllerProtocol, @unchecked Sendable {

    // MARK: - Private state

    private let bleQueue = DispatchQueue(label: "com.linakcontrol.ble", qos: .userInitiated)

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var discoveredCharacteristics: [CBUUID: CBCharacteristic] = [:]

    // Scan stream
    private var scanContinuation: AsyncStream<DiscoveredDesk>.Continuation?

    // State stream
    private var stateContinuation: AsyncStream<BLEState>.Continuation?

    // Write continuations keyed by characteristic UUID
    private var writeContinuations: [CBUUID: CheckedContinuation<Void, Error>] = [:]

    // Read continuations keyed by characteristic UUID
    private var readContinuations: [CBUUID: CheckedContinuation<Data, Error>] = [:]

    // Notify enable/disable continuations keyed by characteristic UUID
    private var notifyContinuations: [CBUUID: CheckedContinuation<Void, Error>] = [:]

    // Notification value streams keyed by characteristic UUID
    private var notificationContinuations: [CBUUID: AsyncStream<Data>.Continuation] = [:]

    // Connect continuation — resolves after service+characteristic discovery
    private var connectContinuation: CheckedContinuation<Void, Error>?

    // MARK: - BLEControllerProtocol — stateStream

    public let stateStream: AsyncStream<BLEState>

    // MARK: - Init

    override public init() {
        var stateCont: AsyncStream<BLEState>.Continuation!
        stateStream = AsyncStream { continuation in
            stateCont = continuation
        }
        super.init()
        stateContinuation = stateCont
        centralManager = CBCentralManager(delegate: self, queue: bleQueue)
    }

    // MARK: - BLEControllerProtocol — scan

    public func scanForPeripherals() -> AsyncStream<DiscoveredDesk> {
        AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }
            bleQueue.async {
                self.scanContinuation?.finish()
                self.scanContinuation = continuation
                self.centralManager.scanForPeripherals(
                    withServices: [DeskUUID.controlService],
                    options: nil
                )
            }
        }
    }

    public func stopScan() {
        bleQueue.async { [weak self] in
            guard let self else { return }
            centralManager.stopScan()
            scanContinuation?.finish()
            scanContinuation = nil
        }
    }

    // MARK: - BLEControllerProtocol — connect / disconnect

    public func connect(peripheralId: UUID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            bleQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: BLEError.connectionFailed)
                    return
                }

                guard let peripheral = centralManager
                    .retrievePeripherals(withIdentifiers: [peripheralId]).first
                else {
                    continuation.resume(throwing: BLEError.connectionFailed)
                    return
                }

                self.connectContinuation = continuation
                self.connectedPeripheral = peripheral
                peripheral.delegate = self
                self.centralManager.connect(peripheral, options: nil)
            }
        }
    }

    public func disconnect() {
        bleQueue.async { [weak self] in
            guard let self, let peripheral = connectedPeripheral else { return }
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    // MARK: - BLEControllerProtocol — write

    public func write(
        data: Data,
        to characteristicUUID: CBUUID,
        type: CBCharacteristicWriteType
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            bleQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: BLEError.notConnected)
                    return
                }
                guard let peripheral = connectedPeripheral else {
                    continuation.resume(throwing: BLEError.notConnected)
                    return
                }
                guard let characteristic = discoveredCharacteristics[characteristicUUID] else {
                    continuation.resume(throwing: BLEError.characteristicNotFound(characteristicUUID))
                    return
                }

                if type == .withResponse {
                    writeContinuations[characteristicUUID] = continuation
                } else {
                    // withoutResponse: fire-and-forget; resolve immediately
                    continuation.resume()
                }
                peripheral.writeValue(data, for: characteristic, type: type)
            }
        }
    }

    // MARK: - BLEControllerProtocol — read

    public func read(_ characteristicUUID: CBUUID) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            bleQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: BLEError.notConnected)
                    return
                }
                guard let peripheral = connectedPeripheral else {
                    continuation.resume(throwing: BLEError.notConnected)
                    return
                }
                guard let characteristic = discoveredCharacteristics[characteristicUUID] else {
                    continuation.resume(throwing: BLEError.characteristicNotFound(characteristicUUID))
                    return
                }
                readContinuations[characteristicUUID] = continuation
                peripheral.readValue(for: characteristic)
            }
        }
    }

    // MARK: - BLEControllerProtocol — notifications

    public func notifications(for characteristicUUID: CBUUID) -> AsyncStream<Data> {
        AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }
            bleQueue.async {
                self.notificationContinuations[characteristicUUID]?.finish()
                self.notificationContinuations[characteristicUUID] = continuation
            }
        }
    }

    public func setNotifyValue(_ enabled: Bool, for characteristicUUID: CBUUID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            bleQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: BLEError.notConnected)
                    return
                }
                guard let peripheral = connectedPeripheral else {
                    continuation.resume(throwing: BLEError.notConnected)
                    return
                }
                guard let characteristic = discoveredCharacteristics[characteristicUUID] else {
                    continuation.resume(throwing: BLEError.characteristicNotFound(characteristicUUID))
                    return
                }
                notifyContinuations[characteristicUUID] = continuation
                peripheral.setNotifyValue(enabled, for: characteristic)
            }
        }
    }

    // MARK: - Private helpers

    private func cleanUpOnDisconnect() {
        connectedPeripheral = nil
        discoveredCharacteristics = [:]
        connectContinuation?.resume(throwing: BLEError.connectionFailed)
        connectContinuation = nil
        for (_, cont) in writeContinuations { cont.resume(throwing: BLEError.notConnected) }
        writeContinuations = [:]
        for (_, cont) in readContinuations { cont.resume(throwing: BLEError.notConnected) }
        readContinuations = [:]
        for (_, cont) in notifyContinuations { cont.resume(throwing: BLEError.notConnected) }
        notifyContinuations = [:]
        for (_, cont) in notificationContinuations { cont.finish() }
        notificationContinuations = [:]
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEController: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state: BLEState
        switch central.state {
        case .unknown:       state = .unknown
        case .resetting:     state = .resetting
        case .unsupported:   state = .unsupported
        case .unauthorized:  state = .unauthorized
        case .poweredOff:    state = .poweredOff
        case .poweredOn:     state = .poweredOn
        @unknown default:    state = .unknown
        }
        stateContinuation?.yield(state)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"
        let desk = DiscoveredDesk(
            peripheralId: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue
        )
        scanContinuation?.yield(desk)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([
            DeskUUID.controlService,
            DeskUUID.dpgService,
            DeskUUID.referenceOutputService,
            DeskUUID.referenceInputService
        ])
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let err = error.map { BLEError.connectFailure($0) } ?? BLEError.connectionFailed
        connectContinuation?.resume(throwing: err)
        connectContinuation = nil
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        cleanUpOnDisconnect()
    }
}

// MARK: - CBPeripheralDelegate

extension BLEController: CBPeripheralDelegate {

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            connectContinuation?.resume(throwing: BLEError.connectFailure(error))
            connectContinuation = nil
            return
        }
        guard let services = peripheral.services, !services.isEmpty else {
            connectContinuation?.resume(throwing: BLEError.connectionFailed)
            connectContinuation = nil
            return
        }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            connectContinuation?.resume(throwing: BLEError.connectFailure(error))
            connectContinuation = nil
            return
        }
        for characteristic in service.characteristics ?? [] {
            discoveredCharacteristics[characteristic.uuid] = characteristic
        }

        // Resolve connect when all expected services have reported their characteristics
        let allServices = peripheral.services ?? []
        let allDiscovered = allServices.allSatisfy { $0.characteristics != nil }
        if allDiscovered {
            connectContinuation?.resume()
            connectContinuation = nil
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let continuation = writeContinuations.removeValue(forKey: characteristic.uuid) else { return }
        if let error {
            continuation.resume(throwing: BLEError.writeFailure(error))
        } else {
            continuation.resume()
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        // Read continuation takes priority over notification stream
        if let readCont = readContinuations.removeValue(forKey: characteristic.uuid) {
            if let error {
                readCont.resume(throwing: BLEError.readFailure(error))
            } else {
                readCont.resume(returning: characteristic.value ?? Data())
            }
            return
        }

        // Feed notification stream
        if let data = characteristic.value {
            notificationContinuations[characteristic.uuid]?.yield(data)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let continuation = notifyContinuations.removeValue(forKey: characteristic.uuid) else { return }
        if let error {
            continuation.resume(throwing: BLEError.notifyFailure(error))
        } else {
            continuation.resume()
        }
    }
}
