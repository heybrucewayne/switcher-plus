import AppKit
import ApplicationServices

@MainActor
final class WindowFocusService {
    func focus(_ window: WindowInfo, element: AXUIElement?) {
        guard let application = NSRunningApplication(processIdentifier: window.ownerPID) else { return }
        application.unhide()
        if let element {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
        application.activate(options: [])
        if let element {
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            let app = AXUIElementCreateApplication(window.ownerPID)
            AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, element)
        }
    }
}
