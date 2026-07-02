import Foundation
import Observation

/// ④ Self-eval Rubric — in-memory ring buffer for the most recent
/// `RubricReport`s.
///
/// Design principles:
/// - **Bounded and cheap.** Keeps the last `capacity` reports so a long
///   session doesn't leak memory. Default 20 turns is enough for the
///   UI trend strip; ⑧ sc-loop will replay past reports for lens
///   analysis but never needs the entire history.
/// - **@Observable so SwiftUI can re-render.** Any view that wants to
///   surface "last turn was a .fail" can bind directly.
/// - **No persistence.** Reports are session-local: the point of the
///   rubric is to catch drift *inside* the current chat, not build a
///   long-term training signal. Persistence lives in a later journal
///   slice — this file must stay dependency-free.
@Observable
@MainActor
public final class RubricStore {

    public let capacity: Int
    public private(set) var reports: [RubricReport] = []

    public init(capacity: Int = 20) {
        // Guard against pathological configs — a capacity of 0 would
        // silently drop everything and hide bugs.
        self.capacity = max(1, capacity)
    }

    /// Append a new report; if the buffer is full, drop the oldest.
    public func record(_ report: RubricReport) {
        reports.append(report)
        while reports.count > capacity {
            reports.removeFirst()
        }
    }

    public func clear() {
        reports.removeAll(keepingCapacity: true)
    }

    /// The most recent report, if any. Used by UI badges + ⑧.
    public var latest: RubricReport? { reports.last }

    /// Rolling average of `overall` across the buffer. A cheap trend
    /// indicator; ⑧ sc-loop uses the delta between successive averages
    /// to decide whether the current turn improved on the prior one.
    public var rollingOverall: Double {
        guard !reports.isEmpty else { return 0 }
        let sum = reports.map { Double($0.overall) }.reduce(0, +)
        return sum / Double(reports.count)
    }

    /// Reports currently sitting in `.fail`. UI can badge these; ⑧ can
    /// pick one to re-run through a diverse-lens critic.
    public var failingReports: [RubricReport] {
        reports.filter { $0.verdict == .fail }
    }
}
