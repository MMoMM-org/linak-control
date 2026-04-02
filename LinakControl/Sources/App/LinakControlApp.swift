import SwiftUI
import ServiceManagement
import LinakControlKit

@main
struct LinakControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var deskManager: DeskManager!
    private var ipcServer: IPCServer!
    private var menuBarController: MenuBarController!
    private var viewModel: DeskViewModel!
    private var connectionObserverTask: Task<Void, Never>?
    private var hotkeyManager: HotkeyManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        FileLog.reset()
        FileLog.debug("=== LinakControl launch ===", category: "app")

        let bleController = BLEController()
        let configStore = ConfigStore()
        deskManager = DeskManager(bleController: bleController, configStore: configStore)

        ipcServer = IPCServer(deskManager: deskManager, configStore: configStore)
        try? ipcServer.start()

        let loginItemManager = LoginItemManager()
        viewModel = DeskViewModel(deskManager: deskManager, configStore: configStore, loginItemManager: loginItemManager)
        menuBarController = MenuBarController(viewModel: viewModel)
        menuBarController.setup(autoOpen: viewModel.isFirstRun)

        let notificationService = NotificationService()
        notificationService.requestPermission()
        let observer = ConnectionStateObserver(
            deskManager: deskManager,
            notificationPoster: notificationService
        )
        connectionObserverTask = observer.start()

        hotkeyManager = HotkeyManager(deskManager: deskManager, configStore: configStore)

        Task {
            let config = try? configStore.load()

            // Sync login item registration with persisted preference.
            if config?.startAtLogin == true {
                try? loginItemManager.register()
            }

            // Enable global hotkeys if the user previously activated them.
            if config?.hotkeysEnabled == true {
                hotkeyManager.enable()
            }

            if let uuid = config?.pairedDeskUUID, let peripheralId = UUID(uuidString: uuid) {
                // Retry connect up to 3 times with increasing delay.
                // The desk may need time to wake from sleep after app launch.
                for attempt in 1...3 {
                    do {
                        try await deskManager.connect(peripheralId: peripheralId)
                        break
                    } catch {
                        FileLog.debug("auto-connect attempt \(attempt)/3 failed: \(error)", category: "app")
                        if attempt < 3 {
                            try? await Task.sleep(for: .seconds(Double(attempt) * 2))
                        }
                    }
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.disable()
        ipcServer?.stop()
        connectionObserverTask?.cancel()
    }
}
