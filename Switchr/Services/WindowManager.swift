import AppKit
import ApplicationServices

@MainActor
final class WindowManager {
    private(set) var elements: [CGWindowID: AXUIElement] = [:]

    func windows() -> [WindowInfo] {
        let raw = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let candidates: [WindowCandidate] = raw.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let id = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let dictionary = entry[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { return nil }
            return WindowCandidate(id: id, pid: pid, title: entry[kCGWindowName as String] as? String ?? "", bounds: bounds)
        }
        var result: [WindowInfo] = []
        elements.removeAll()
        var fallbackID = CGWindowID.max
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.2)
            guard let axWindows = attribute(appElement, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            var seenElements: [AXUIElement] = []
            for element in axWindows {
                guard !seenElements.contains(where: { CFEqual($0, element) }) else { continue }
                seenElements.append(element)
                guard WindowMatching.isDocument(role: attribute(element, kAXRoleAttribute) as? String,
                                                subrole: attribute(element, kAXSubroleAttribute) as? String) else { continue }
                let minimized = (attribute(element, kAXMinimizedAttribute) as? NSNumber)?.boolValue ?? false
                let title = attribute(element, kAXTitleAttribute) as? String ?? ""
                var position = CGPoint.zero
                var size = CGSize.zero
                if let value = attribute(element, kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
                    AXValueGetValue(value as! AXValue, .cgPoint, &position)
                }
                if let value = attribute(element, kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
                    AXValueGetValue(value as! AXValue, .cgSize, &size)
                }
                guard size.width >= 80, size.height >= 60 else { continue }
                let bounds = CGRect(origin: position, size: size)
                let number = (attribute(element, "AXWindowNumber") as? NSNumber)?.uint32Value
                let match = WindowMatching.match(id: number, pid: app.processIdentifier, title: title, bounds: bounds, candidates: candidates)
                // AX is the source of truth for listing across Spaces. A window
                // does not need a currently available capture surface to appear.
                // Only a native number is authoritative for deduplication: two
                // different Spaces can contain windows with identical geometry.
                guard let id = WindowMatching.listingID(number: number, matchedID: match?.id,
                                                        usedIDs: Set(elements.keys), fallbackID: fallbackID) else { continue }
                if id == fallbackID { fallbackID -= 1 }
                elements[id] = element
                result.append(WindowInfo(id: id, ownerPID: app.processIdentifier, ownerName: app.localizedName ?? "Application", title: title, bounds: bounds, layer: 0, isMinimized: minimized, bundleIdentifier: app.bundleIdentifier))
            }
        }
        let order = raw.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
        let ranks = Dictionary(order.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        return result.enumerated().sorted {
            let left = ranks[$0.element.id] ?? Int.max
            let right = ranks[$1.element.id] ?? Int.max
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
