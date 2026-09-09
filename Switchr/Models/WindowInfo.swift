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

    static func focusMatch(pid: pid_t, title: String, bounds: CGRect, candidates: [WindowCandidate]) -> WindowCandidate? {
        if let match = match(id: nil, pid: pid, title: title, bounds: bounds, candidates: candidates) { return match }
        // Minimized window frames may change. Only a unique nonempty title is safe.
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let sameTitle = candidates.filter { $0.pid == pid && $0.title.trimmingCharacters(in: .whitespacesAndNewlines) == title }
        return sameTitle.count == 1 ? sameTitle[0] : nil
    }

    static func unrepresentedDocuments(candidates: [WindowCandidate], listedIDs: Set<CGWindowID>) -> [WindowCandidate] {
        var seen = listedIDs
        return candidates.filter {
            // Untitled Window Server surfaces include menu bars, app snapshots,
            // and invisible helper windows. Untitled real AX documents are already listed.
            $0.bounds.width >= 80 && $0.bounds.height >= 80 &&
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            seen.insert($0.id).inserted
        }
    }

    static func listingID(number: CGWindowID?, matchedID: CGWindowID?, usedIDs: Set<CGWindowID>, fallbackID: CGWindowID) -> CGWindowID? {
        if let number {
            return usedIDs.contains(number) ? nil : number
        }
        if let matchedID, !usedIDs.contains(matchedID) { return matchedID }
        return fallbackID
    }

    static func isDocument(role: String?, subrole: String?) -> Bool {
        role == "AXWindow" && (subrole == "AXStandardWindow" || subrole == "AXDialog")
    }
}

struct SwitcherGridLayout {
    let columns: Int
    let rows: Int
    let cardWidth: CGFloat
    let rowHeight: CGFloat
    let width: CGFloat
    let height: CGFloat

    init(count: Int, screen: CGSize, permissionFooter: Bool) {
        let available = max(200, min(1480, screen.width - 64))
        let capacity = max(1, Int((available - 88 + 12) / 236))
        columns = min(max(1, count), capacity)
        width = min(available, CGFloat(columns) * 236 + 76)
        cardWidth = min(208, max(60, (width - 88 - CGFloat(columns - 1) * 12) / CGFloat(columns) - 16))
        rows = max(1, (count + columns - 1) / columns)
        rowHeight = cardWidth * 0.82 + 126
        let naturalHeight = CGFloat(rows) * rowHeight + CGFloat(rows - 1) * 16 + 84 + (permissionFooter ? 28 : 0)
        height = min(naturalHeight, max(180, screen.height - 64))
    }
}
