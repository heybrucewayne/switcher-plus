import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = SwitcherCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }
}
