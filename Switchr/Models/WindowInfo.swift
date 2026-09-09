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

    var hasDistinctTitle: Bool {
        let normalizedOwner = ownerName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let normalizedTitle = displayTitle.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return !normalizedTitle.isEmpty && normalizedTitle != normalizedOwner
    }
}

// Shared by Window Server discovery and ScreenCaptureKit. Never select the first
// same-titled window: applications can have multiple genuine untitled documents.
struct WindowCandidate: Sendable {
    let id: CGWindowID
    let pid: pid_t
    let title: String
    let bounds: CGRect
}

enum WindowMatching {
    static func match(id: CGWindowID?, pid: pid_t, title: String, bounds: CGRect, candidates: [WindowCandidate]) -> WindowCandidate? {
        let owned = candidates.filter { $0.pid == pid }
        if let id, let exact = owned.first(where: { $0.id == id }) { return exact }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let ranked = owned.compactMap { candidate -> (WindowCandidate, Int)? in
            let sizeError = max(abs(candidate.bounds.width - bounds.width), abs(candidate.bounds.height - bounds.height))
            let positionError = max(abs(candidate.bounds.minX - bounds.minX), abs(candidate.bounds.minY - bounds.minY))
            let sameTitle = !title.isEmpty && candidate.title.trimmingCharacters(in: .whitespacesAndNewlines) == title
            // Window chrome can differ slightly between AX and capture surfaces.
            if sizeError <= 16 && positionError <= 16 { return (candidate, 100 + (sameTitle ? 30 : 0)) }
            if sameTitle && sizeError <= 64 { return (candidate, 80) }
            return nil
        }.sorted { $0.1 > $1.1 }
        guard let best = ranked.first else { return nil }
        guard ranked.count == 1 || best.1 > ranked[1].1 else { return nil }
        return best.0
    }

    static func isDocument(role: String?, subrole: String?) -> Bool {
        role == "AXWindow" && (subrole == "AXStandardWindow" || subrole == "AXDialog")
    }
}
