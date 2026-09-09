import CoreGraphics
import ScreenCaptureKit
import OSLog

actor WindowThumbnailService {
    private struct Entry {
        let image: CGImage
        let date: Date
        let candidate: WindowCandidate
    }
    private var cache: [CGWindowID: Entry] = [:]
    private var content: SCShareableContent?
    private var contentDate = Date.distantPast
    private let logger = Logger(subsystem: "com.switchr.app", category: "Preview")

    func image(for windowInfo: WindowInfo) async -> CGImage? {
        guard PermissionManager.screenRecordingGranted else { cache.removeAll(); return nil }
        let cachedMatch = WindowMatching.match(id: windowInfo.id, pid: windowInfo.ownerPID, title: windowInfo.title, bounds: windowInfo.bounds, candidates: cache.values.map(\.candidate))
        let previous = cachedMatch.flatMap { cache[$0.id] }
        if let previous, windowInfo.isMinimized || Date().timeIntervalSince(previous.date) < 3 { return previous.image }
        do {
            if content == nil || Date().timeIntervalSince(contentDate) > 2 {
                content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                contentDate = Date()
            }
            let available = content?.windows.filter { $0.windowLayer == 0 } ?? []
            let candidates = available.compactMap { window -> WindowCandidate? in
                guard let pid = window.owningApplication?.processID else { return nil }
                return WindowCandidate(id: window.windowID, pid: pid, title: window.title ?? "", bounds: window.frame)
            }
            guard let match = WindowMatching.match(id: windowInfo.id, pid: windowInfo.ownerPID, title: windowInfo.title, bounds: windowInfo.bounds, candidates: candidates),
                  let window = available.first(where: { $0.windowID == match.id }) else {
                logger.debug("No capture surface for pid=\(windowInfo.ownerPID) minimized=\(windowInfo.isMinimized)")
                return previous?.image
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            let bounds = filter.contentRect
            let ratio = min(840 / max(bounds.width, 1), 560 / max(bounds.height, 1))
            configuration.width = max(1, Int(bounds.width * ratio))
            configuration.height = max(1, Int(bounds.height * ratio))
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            configuration.scalesToFit = true
            configuration.preservesAspectRatio = true
            configuration.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            cache[match.id] = Entry(image: image, date: Date(), candidate: match)
            if cache.count > 100, let oldest = cache.min(by: { $0.value.date < $1.value.date })?.key { cache.removeValue(forKey: oldest) }
            return image
        } catch {
            logger.error("Capture failed pid=\(windowInfo.ownerPID), code=\((error as NSError).code)")
            return previous?.image
        }
    }

    func refreshVisibleWindows() async {
        guard PermissionManager.screenRecordingGranted else { cache.removeAll(); return }
        guard let snapshot = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return }
        for window in snapshot.windows where window.windowLayer == 0 {
            guard let app = window.owningApplication, app.processID != ProcessInfo.processInfo.processIdentifier else { continue }
            if Task.isCancelled { return }
            _ = await image(for: WindowInfo(id: window.windowID, ownerPID: app.processID, ownerName: app.applicationName, title: window.title ?? "", bounds: window.frame, layer: 0, isMinimized: false, bundleIdentifier: app.bundleIdentifier))
        }
    }
}
