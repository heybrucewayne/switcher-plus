import AppKit
import ApplicationServices
import OSLog

final class WindowFocusService {
    private let logger = Logger(subsystem: "com.switchr.app", category: "WindowFocus")

    func focus(_ window: WindowInfo) {
        guard let application = NSRunningApplication(processIdentifier: window.ownerPID) else { return }
        application.activate(options: [.activateAllWindows])

        let appElement = AXUIElementCreateApplication(window.ownerPID)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }

        for axWindow in windows where matches(axWindow, windowID: window.id) {
            let minimized = readBool(axWindow, attribute: kAXMinimizedAttribute as CFString)
            if minimized { AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
            let result = AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
            if result != .success { logger.debug("Could not raise selected window: \(result.rawValue)") }
            _ = AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, axWindow)
            return
        }
    }

    private func matches(_ element: AXUIElement, windowID: CGWindowID) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXWindowNumber" as CFString, &value) == .success else { return false }
        return (value as? NSNumber)?.uint32Value == windowID
    }

    private func readBool(_ element: AXUIElement, attribute: CFString) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return false }
        return (value as? NSNumber)?.boolValue ?? false
    }
}
