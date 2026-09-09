import AppKit
import CoreGraphics

struct WindowInfo: Identifiable, Hashable, Sendable {
    let id: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let title: String
    let bounds: CGRect
    let layer: Int
    let isMinimized: Bool
    let bundleIdentifier: String?

    var displayTitle: String { title.isEmpty ? ownerName : title }
}
