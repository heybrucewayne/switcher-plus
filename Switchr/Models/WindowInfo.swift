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

    static func isAuxiliaryWindow(bundleID: String?, title: String) -> Bool {
        guard bundleID == "com.apple.mail" else { return false }
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Mail's ICMCD maintenance tool is not a mailbox/message/composer window.
        return ["icloud mail temizleme", "icloud mail cleanup", "icloud mail cleaner"].contains(normalized)
    }

    static func focusMatch(pid: pid_t, title: String, bounds: CGRect, candidates: [WindowCandidate]) -> WindowCandidate? {
        if let match = match(id: nil, pid: pid, title: title, bounds: bounds, candidates: candidates) { return match }
        // Minimized window frames may change. Only a unique nonempty title is safe.
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let sameTitle = candidates.filter { $0.pid == pid && $0.title.trimmingCharacters(in: .whitespacesAndNewlines) == title }
        return sameTitle.count == 1 ? sameTitle[0] : nil
    }

    static func previewMatch(id: CGWindowID, pid: pid_t, title: String, bounds: CGRect, candidates: [WindowCandidate]) -> WindowCandidate? {
        if let exact = candidates.first(where: { $0.pid == pid && $0.id == id }) { return exact }
        if let strict = match(id: nil, pid: pid, title: title, bounds: bounds, candidates: candidates) { return strict }

        let owned = candidates.filter { $0.pid == pid }
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ranked = owned.compactMap { candidate -> (WindowCandidate, Double)? in
            let sizeError = max(abs(candidate.bounds.width - bounds.width), abs(candidate.bounds.height - bounds.height))
            guard sizeError <= 180 else { return nil }
            let positionError = max(abs(candidate.bounds.minX - bounds.minX), abs(candidate.bounds.minY - bounds.minY))
            let sameTitle = !normalizedTitle.isEmpty && candidate.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedTitle
            let score = (sameTitle ? 120.0 : 0.0) + max(0, 100 - Double(sizeError)) + max(0, 30 - Double(positionError) * 0.1)
            return (candidate, score)
        }.sorted { $0.1 > $1.1 }

        guard let best = ranked.first else { return nil }
        // A single same-process surface is safe even when AX and ScreenCaptureKit
        // use different titles or coordinate spaces. Never guess between ties.
        guard ranked.count == 1 || best.1 - ranked[1].1 >= 14 else { return nil }
        return best.0
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
        let availableHeight = max(180, screen.height - 64)
        let itemCount = max(1, count)
        let footer = permissionFooter ? 28 : 0
        let minimumCardWidth: CGFloat = 72
        let maximumColumns = max(1, min(itemCount, Int((available - 76) / (minimumCardWidth + 28))))

        var best: (columns: Int, rows: Int, cardWidth: CGFloat, rowHeight: CGFloat, width: CGFloat, height: CGFloat)?
        for candidateColumns in 1...maximumColumns {
            let candidateRows = max(1, (itemCount + candidateColumns - 1) / candidateColumns)
            let widthLimited = (available - 88 - CGFloat(candidateColumns - 1) * 12) / CGFloat(candidateColumns) - 16
            let rowBudget = (availableHeight - 84 - CGFloat(footer) - CGFloat(candidateRows - 1) * 16) / CGFloat(candidateRows)
            let heightLimited = (rowBudget - 112) / 0.82
            let candidateCardWidth = min(208, widthLimited, heightLimited)
            guard candidateCardWidth >= minimumCardWidth else { continue }

            let candidateRowHeight = candidateCardWidth * 0.82 + 112
            let candidateWidth = min(available, CGFloat(candidateColumns) * (candidateCardWidth + 16) + CGFloat(candidateColumns - 1) * 12 + 88)
            let candidateHeight = CGFloat(candidateRows) * candidateRowHeight + CGFloat(candidateRows - 1) * 16 + 84 + CGFloat(footer)
            let candidate: (columns: Int, rows: Int, cardWidth: CGFloat, rowHeight: CGFloat, width: CGFloat, height: CGFloat) =
                (candidateColumns, candidateRows, candidateCardWidth, candidateRowHeight, candidateWidth, candidateHeight)
            guard let current = best else {
                best = candidate
                continue
            }
            if candidate.cardWidth > current.cardWidth + 0.5 ||
                (abs(candidate.cardWidth - current.cardWidth) <= 0.5 && candidate.rows < current.rows) ||
                (abs(candidate.cardWidth - current.cardWidth) <= 0.5 && candidate.rows == current.rows && candidate.columns < current.columns) {
                best = candidate
            }
        }

        if let best {
            columns = best.columns
            rows = best.rows
            cardWidth = best.cardWidth
            rowHeight = best.rowHeight
            width = best.width
            height = min(best.height, availableHeight)
        } else {
            // Extremely crowded or very short screens keep the old scrollable fallback.
            columns = maximumColumns
            rows = max(1, (itemCount + columns - 1) / columns)
            cardWidth = min(208, max(60, (available - 88 - CGFloat(columns - 1) * 12) / CGFloat(columns) - 16))
            rowHeight = cardWidth * 0.82 + 112
            width = min(available, CGFloat(columns) * (cardWidth + 16) + CGFloat(columns - 1) * 12 + 88)
            let naturalHeight = CGFloat(rows) * rowHeight + CGFloat(rows - 1) * 16 + 84 + CGFloat(footer)
            height = min(naturalHeight, availableHeight)
        }
    }
}
