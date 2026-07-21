import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = AgentStore()
    private var statusController: StatusItemController?
    private var server: GardenServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusItemController(store: store)
        server = GardenServer(store: store, port: GardenServer.defaultPort)
        server?.start()
        LoginItem.setupOnFirstRun()
    }
}
