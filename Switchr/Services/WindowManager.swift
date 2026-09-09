import AppKit
import CoreGraphics

final class WindowManager {
    private let excludedBundleIDs = Set([Bundle.main.bundleIdentifier].compactMap { $0 })

    func windows() -> [WindowInfo] {
        guard let rawWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }

        return rawWindows.compactMap { dictionary in
            guard
                let number = dictionary[kCGWindowNumber as String] as? NSNumber,
                let pidValue = dictionary[kCGWindowOwnerPID as String] as? NSNumber,
                let ownerName = dictionary[kCGWindowOwnerName as String] as? String,
                let boundsDictionary = dictionary[kCGWindowBounds as String] as? [String: Any],
                let x = (boundsDictionary["X"] as? NSNumber)?.doubleValue,
                let y = (boundsDictionary["Y"] as? NSNumber)?.doubleValue,
                let width = (boundsDictionary["Width"] as? NSNumber)?.doubleValue,
                let height = (boundsDictionary["Height"] as? NSNumber)?.doubleValue,
                let layer = dictionary[kCGWindowLayer as String] as? Int,
                layer == 0,
                width >= 80, height >= 60,
                dictionary[kCGWindowIsOnscreen as String] as? Bool != false
            else { return nil }

            let pid = pid_t(pidValue.intValue)
            guard let application = NSRunningApplication(processIdentifier: pid), !application.isTerminated else { return nil }
            let bundleIdentifier = application.bundleIdentifier
            guard !excludedBundleIDs.contains(bundleIdentifier ?? "") else { return nil }

            let title = (dictionary[kCGWindowName as String] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            // A titled document window is useful; untitled windows are allowed only for familiar app windows.
            guard !ownerName.isEmpty, !ownerName.hasPrefix("Window Server") else { return nil }
            let bounds = CGRect(x: x, y: y, width: width, height: height)
            return WindowInfo(id: CGWindowID(number.uint32Value), ownerPID: pid, ownerName: ownerName, title: title, bounds: bounds, layer: layer, isMinimized: false, bundleIdentifier: bundleIdentifier)
        }
    }

    func icon(for window: WindowInfo) -> NSImage? {
        NSRunningApplication(processIdentifier: window.ownerPID)?.icon
    }
}
