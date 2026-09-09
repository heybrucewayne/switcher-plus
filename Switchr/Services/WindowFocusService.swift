import AppKit
import ApplicationServices
import OSLog

@MainActor
final class WindowFocusService {
    private var pendingFocus: Task<Void, Never>?

    func focus(_ window: WindowInfo, element: AXUIElement?) {
        pendingFocus?.cancel()
        guard let application = NSRunningApplication(processIdentifier: window.ownerPID) else { return }
        application.unhide()
        application.activate(options: [])
        pendingFocus = Task { [weak self] in
            var target = element
            for _ in 0..<24 {
                guard !Task.isCancelled, !application.isTerminated, let self else { return }
                // Refresh references after activation/Space changes; retain a valid
                // known element if AXWindows has not caught up yet.
                target = self.resolve(window) ?? target
                if let target, self.restoreAndRaise(target, pid: window.ownerPID) {
                    return
                }
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
            Logger(subsystem: "com.switchr.app", category: "WindowFocus")
                .error("Selected window did not confirm restored/focused pid=\(window.ownerPID)")
        }
    }

    private func restoreAndRaise(_ element: AXUIElement, pid: pid_t) -> Bool {
        let minimized = (attribute(element, kAXMinimizedAttribute) as? NSNumber)?.boolValue
        if minimized == true {
            let result = AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            // Restoring is asynchronous; raising during the Dock animation can fail.
            guard result == .success else { return false }
            return false
        }
        let raised = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute as CFString, element)
        return raised == .success && (attribute(element, kAXMainAttribute) as? NSNumber)?.boolValue == true
    }

    private func resolve(_ window: WindowInfo) -> AXUIElement? {
        let app = AXUIElementCreateApplication(window.ownerPID)
        AXUIElementSetMessagingTimeout(app, 0.2)
        guard let elements = attribute(app, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
        var candidates: [WindowCandidate] = []
        for (index, element) in elements.enumerated() {
            if (attribute(element, "AXWindowNumber") as? NSNumber)?.uint32Value == window.id { return element }
            guard WindowMatching.isDocument(role: attribute(element, kAXRoleAttribute) as? String,
                                            subrole: attribute(element, kAXSubroleAttribute) as? String) else { continue }
            var origin = CGPoint.zero
            var size = CGSize.zero
            if let value = attribute(element, kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID() { AXValueGetValue(value as! AXValue, .cgPoint, &origin) }
            if let value = attribute(element, kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() { AXValueGetValue(value as! AXValue, .cgSize, &size) }
            candidates.append(WindowCandidate(id: CGWindowID(index), pid: window.ownerPID,
                                              title: attribute(element, kAXTitleAttribute) as? String ?? "", bounds: CGRect(origin: origin, size: size)))
        }
        guard let match = WindowMatching.focusMatch(pid: window.ownerPID, title: window.title, bounds: window.bounds, candidates: candidates) else { return nil }
        return elements[Int(match.id)]
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
