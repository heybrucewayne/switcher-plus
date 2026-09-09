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
        if let element { raise(element, pid: window.ownerPID) }
        application.activate(options: [])
        if let element {
            raise(element, pid: window.ownerPID)
            return
        }
        // Inactive-Space windows may have no AX element until activation changes
        // Spaces. Resolve the selected surface again while that transition settles.
        pendingFocus = Task { [weak self] in
            for _ in 0..<12 {
                guard !Task.isCancelled, !application.isTerminated else { return }
                if let element = self?.resolve(window) {
                    self?.raise(element, pid: window.ownerPID)
                    return
                }
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
            Logger(subsystem: "com.switchr.app", category: "WindowFocus")
                .error("Could not resolve selected window after activation pid=\(window.ownerPID)")
        }
    }

    private func raise(_ element: AXUIElement, pid: pid_t) {
        AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute as CFString, element)
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
        guard let match = WindowMatching.match(id: nil, pid: window.ownerPID, title: window.title, bounds: window.bounds, candidates: candidates) else { return nil }
        return elements[Int(match.id)]
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
