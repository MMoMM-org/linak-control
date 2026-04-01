import SwiftUI
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bleController = BLEController()
        let configStore = ConfigStore()
        deskManager = DeskManager(bleController: bleController, configStore: configStore)

        ipcServer = IPCServer(deskManager: deskManager, configStore: configStore)
        try? ipcServer.start()

        viewModel = DeskViewModel(deskManager: deskManager, configStore: configStore)
        menuBarController = MenuBarController(viewModel: viewModel)
        menuBarController.setup()

        Task {
            let config = try? configStore.load()
            if let uuid = config?.pairedDeskUUID, let peripheralId = UUID(uuidString: uuid) {
                try? await deskManager.connect(peripheralId: peripheralId)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ipcServer?.stop()
    }
}
