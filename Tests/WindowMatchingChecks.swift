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
        print("11 window matching/filter checks passed")
    }
}
