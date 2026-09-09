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
            var target = element ?? WindowAccess.cached(id: window.id, pid: window.ownerPID)
            if target == nil {
                target = await RemoteWindowLookup.shared.find(pid: window.ownerPID, windowID: window.id)?.element
            }
            if let target { WindowAccess.remember(target, pid: window.ownerPID) }
            var requestedReopen = false
            if target == nil, let url = application.bundleURL {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                configuration.createsNewApplicationInstance = false
                do {
                    _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                    requestedReopen = true
                } catch {
                    Logger(subsystem: "com.switchr.app", category: "WindowFocus").error("Application reopen failed pid=\(window.ownerPID)")
                }
            }
            for _ in 0..<24 {
                guard !Task.isCancelled, !application.isTerminated, let self else { return }
                // Refresh references after activation/Space changes; retain a valid
                // known element if AXWindows has not caught up yet.
                if target == nil { target = self.resolve(window) }
                if target == nil, requestedReopen {
                    // A closed Window Server snapshot cannot be restored. After a
                    // reopen event, use the app's newly focused main window.
                    let appElement = AXUIElementCreateApplication(window.ownerPID)
                    if let value = self.attribute(appElement, kAXFocusedWindowAttribute),
                       CFGetTypeID(value) == AXUIElementGetTypeID() {
                        target = (value as! AXUIElement)
                    }
                }
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
            guard result == .success else {
                Logger(subsystem: "com.switchr.app", category: "WindowFocus").error("Unminimize failed pid=\(pid) AX=\(result.rawValue)")
                return false
            }
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
            if WindowAccess.number(of: element) == window.id { return element }
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

// Optional macOS SPI: resolve a genuine AX handle for a selected off-Space
// surface. Look up symbols at runtime so unsupported systems fail gracefully.
enum WindowAccess {
    static func number(of element: AXUIElement) -> CGWindowID? {
        guard let handle = dlopen(nil, RTLD_LAZY) else { return nil }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "_AXUIElementGetWindow") else { return nil }
        typealias ReadID = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> Int32
        var id: CGWindowID = 0
        return unsafeBitCast(symbol, to: ReadID.self)(element, &id) == 0 && id != 0 ? id : nil
    }

    @MainActor private static var saved: [CGWindowID: (pid_t, AXUIElement)] = [:]
    @MainActor static func remember(_ element: AXUIElement, pid: pid_t) {
        guard let id = number(of: element) else { return }
        if saved.count > 256 { saved.removeAll() }
        saved[id] = (pid, element)
    }
    @MainActor static func cached(id: CGWindowID, pid: pid_t) -> AXUIElement? {
        guard let pair = saved[id], pair.0 == pid, number(of: pair.1) == id else { return nil }
        return pair.1
    }
}

private struct WindowElementHandle: @unchecked Sendable {
    let element: AXUIElement
}

private actor RemoteWindowLookup {
    static let shared = RemoteWindowLookup()

    func find(pid: pid_t, windowID: CGWindowID) -> WindowElementHandle? {
        guard AXIsProcessTrusted(), let library = dlopen(nil, RTLD_LAZY) else { return nil }
        defer { dlclose(library) }
        guard let createSymbol = dlsym(library, "_AXUIElementCreateWithRemoteToken"),
              let numberSymbol = dlsym(library, "_AXUIElementGetWindow") else { return nil }
        typealias Create = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
        typealias ReadID = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> Int32
        let create = unsafeBitCast(createSymbol, to: Create.self)
        let readID = unsafeBitCast(numberSymbol, to: ReadID.self)
        let deadline = Date().addingTimeInterval(1.5)
        for candidateID in UInt64(0)..<1000 {
            guard !Task.isCancelled, Date() < deadline else { return nil }
            var token = Data()
            var owner = pid.littleEndian
            var reserved: UInt32 = 0
            var kind: UInt32 = 0x636f636f
            var identifier = candidateID.littleEndian
            withUnsafeBytes(of: &owner) { token.append(contentsOf: $0) }
            withUnsafeBytes(of: &reserved) { token.append(contentsOf: $0) }
            withUnsafeBytes(of: &kind) { token.append(contentsOf: $0) }
            withUnsafeBytes(of: &identifier) { token.append(contentsOf: $0) }
            guard let element = create(token as CFData)?.takeRetainedValue() else { continue }
            AXUIElementSetMessagingTimeout(element, 0.03)
            var number: CGWindowID = 0
            guard readID(element, &number) == 0, number == windowID else { continue }
            var role: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
                  role as? String == kAXWindowRole else { continue }
            return WindowElementHandle(element: element)
        }
        return nil
    }
}
