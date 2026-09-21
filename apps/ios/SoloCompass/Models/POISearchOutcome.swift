import Foundation

/// Terminal feedback for one online place query; failures are distinct from no matches.
public struct POISearchOutcome: Equatable {
    /// The outcome shown only while the visible query still matches the request.
    public enum Status: Equatable {
        case found(Int)
        case empty
        case failed
    }
    public let query: String
    public let status: Status

    var message: String {
        switch status {
        case .found(let count):
            return String(format: NSLocalizedString("ux.search.found", comment: "Live search matches"), count)
        case .empty:
            return NSLocalizedString("ux.search.empty", comment: "No live matches")
        case .failed:
            return NSLocalizedString("ux.search.failed", comment: "Search failed")
        }
    }

    func matches(_ text: String) -> Bool {
        query.caseInsensitiveCompare(text.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
}
