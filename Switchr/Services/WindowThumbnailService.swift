import CoreGraphics
import ScreenCaptureKit

actor WindowThumbnailService {
    private var cache: [CGWindowID: CGImage] = [:]

    func image(for id: CGWindowID, maximumSize: CGSize = CGSize(width: 420, height: 260)) async -> CGImage? {
        if let cached = cache[id] { return cached }
        guard PermissionManager.screenRecordingGranted else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            guard let window = content.windows.first(where: { $0.windowID == id }) else { return nil }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            configuration.width = Int(maximumSize.width)
            configuration.height = Int(maximumSize.height)
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            cache[id] = image
            return image
        } catch { return nil }
    }

    func clear() { cache.removeAll(keepingCapacity: true) }
}
