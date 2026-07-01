import Foundation
import Observation
import os

/// P3.4 #341: composes the year-end Travel Book manifest.
///
/// **What this ships**: the manifest — chapter list, page count, cover
/// caption, ISO 8601 date. Real PDF layout + Lulu / Shutterfly API
/// upload lives in a follow-up commit once a printer partner is chosen
/// (#340 spike, out of code scope).
///
/// The manifest is enough for:
/// - Archive tab year-end banner (#342) to render a "your 2026 book, N
///   chapters" teaser.
/// - Paywall / product listing to show a page count estimate.
///
/// Determinism: same visits + same anchor year → same manifest. Chapter
/// order is chronological, one chapter per week, so a re-render never
/// swaps chapters around.
@MainActor
@Observable
public final class BookComposeService {

    public static let shared = BookComposeService()

    private let log = OSLog(subsystem: "com.solocompass.app", category: "Book")

    public init() {}

    /// Compose the manifest for a given year. Chapters are weekly buckets;
    /// weeks with zero visits are dropped so the printed book doesn't
    /// carry empty pages. Approximate page count = 2 (cover + intro) +
    /// per-chapter pages.
    public func compose(
        forYear year: Int,
        visits: [VisitRecord],
        experiences: [Experience] = [],
        calendar: Calendar = Calendar.current
    ) -> BookManifest {
        let scoped = visits.filter { calendar.component(.year, from: $0.visitedAt) == year }
        let grouped = Dictionary(grouping: scoped) { visit -> Int in
            let comp = calendar.dateComponents([.weekOfYear], from: visit.visitedAt)
            return comp.weekOfYear ?? 0
        }
        let chapters: [BookChapter] = grouped
            .sorted { $0.key < $1.key }
            .compactMap { (weekOfYear, visitsInWeek) -> BookChapter? in
                guard !visitsInWeek.isEmpty else { return nil }
                let start = visitsInWeek.map { $0.visitedAt }.min() ?? Date()
                let expTitles = visitsInWeek.compactMap { v in
                    experiences.first(where: { $0.id == v.experienceId })?.title
                }
                return BookChapter(
                    weekOfYear: weekOfYear,
                    startDate: start,
                    visitCount: visitsInWeek.count,
                    experienceTitles: Array(Set(expTitles)).sorted()
                )
            }

        let approxPageCount = 2 + chapters.count * 2
        let cover = "One year, told slowly. \(chapters.count) chapters."

        return BookManifest(
            year: year,
            approxPageCount: approxPageCount,
            chapters: chapters,
            coverCaption: cover,
            createdAt: Date()
        )
    }
}

public struct BookChapter: Codable, Hashable, Sendable, Identifiable {
    public let weekOfYear: Int
    public let startDate: Date
    public let visitCount: Int
    public let experienceTitles: [String]

    public var id: Int { weekOfYear }
}

public struct BookManifest: Codable, Hashable, Sendable {
    public let year: Int
    public let approxPageCount: Int
    public let chapters: [BookChapter]
    public let coverCaption: String
    public let createdAt: Date
}
