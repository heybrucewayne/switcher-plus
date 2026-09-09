import Foundation

@main struct WindowMatchingChecks {
    static func main() {
        let bounds = CGRect(x: 20, y: 40, width: 900, height: 600)
        let first = WindowCandidate(id: 1, pid: 42, title: "ChatGPT", bounds: bounds)
        let second = WindowCandidate(id: 2, pid: 42, title: "ChatGPT", bounds: CGRect(x: 300,y: 200,width: 700,height: 500))
        func match(_ id: UInt32?, _ title: String, _ frame: CGRect, _ candidates: [WindowCandidate]) -> UInt32? {
            WindowMatching.match(id: id, pid: 42, title: title, bounds: frame, candidates: candidates)?.id
        }
        precondition(match(2,"ChatGPT",bounds,[first,second]) == 2, "Exact surface ID wins")
        precondition(match(nil,"ChatGPT",bounds,[first,second]) == 1, "Same-titled documents remain distinct")
        precondition(match(UInt32.max,"Finder",bounds,[WindowCandidate(id: 3,pid: 42,title: "",bounds: bounds)]) == 3, "Missing CG title and synthetic ID resolve by geometry")
        precondition(match(nil,"Brave",bounds,[WindowCandidate(id: 4,pid: 42,title: "Brave",bounds: bounds.insetBy(dx: 4,dy: 4))]) == 4, "Capture chrome differences tolerated")
        precondition(match(nil,"ChatGPT",bounds,[first,WindowCandidate(id: 5,pid: 42,title: "ChatGPT",bounds: bounds)]) == nil, "Ambiguous identical windows never guessed")
        precondition(match(1,"ChatGPT",bounds,[WindowCandidate(id: 1,pid: 99,title: "ChatGPT",bounds: bounds)]) == nil, "Other process cannot supply preview")
        precondition(match(nil,"ChatGPT",CGRect(x: 0,y: 0,width: 100,height: 100),[first,second]) == nil, "Helper window cannot steal document preview")
        precondition(WindowMatching.isDocument(role: "AXWindow",subrole: "AXStandardWindow"))
        precondition(WindowMatching.isDocument(role: "AXWindow",subrole: "AXDialog"))
        precondition(!WindowMatching.isDocument(role: "AXWindow",subrole: "AXFloatingWindow"))
        precondition(!WindowMatching.isDocument(role: "AXWindow",subrole: "AXUnknown"))
        precondition(WindowMatching.listingID(number: nil, matchedID: nil, usedIDs: [], fallbackID: 999) == 999, "Other-Space document without a capture surface stays in the list")
        precondition(WindowMatching.listingID(number: nil, matchedID: 1, usedIDs: [1], fallbackID: 999) == 999, "Equal geometry across Spaces cannot collapse distinct AX windows")
        precondition(WindowMatching.listingID(number: 2, matchedID: 1, usedIDs: [1], fallbackID: 999) == 2, "Native identity wins over a geometry match from another Space")
        precondition(WindowMatching.listingID(number: 1, matchedID: nil, usedIDs: [1], fallbackID: 999) == nil, "Repeated native identity is still deduplicated")
        precondition(WindowMatching.listingID(number: nil, matchedID: 3, usedIDs: [1], fallbackID: 999) == 3, "Available unclaimed capture identity is preserved")
        let offSpace = WindowCandidate(id: 9, pid: 55, title: "Calendar", bounds: bounds)
        let helper = WindowCandidate(id: 10, pid: 55, title: "", bounds: bounds)
        let menu = WindowCandidate(id: 11, pid: 55, title: "Menu", bounds: CGRect(x: 0,y: 0,width: 1920,height: 30))
        let merged = WindowMatching.unrepresentedDocuments(candidates: [first,offSpace,offSpace,helper,menu], listedIDs: [1])
        precondition(merged.map(\.id) == [9], "Global merge adds off-Space documents but not duplicates or helper surfaces")
        precondition(WindowMatching.unrepresentedDocuments(candidates: [offSpace], listedIDs: []).count == 1, "An app missing entirely from AXWindows is still listed")
        print("18 window matching/filter checks passed")
    }
}
