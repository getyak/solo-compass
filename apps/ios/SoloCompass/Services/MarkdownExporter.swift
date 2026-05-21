import Foundation
import MapKit

/// Generates an Obsidian-compatible Markdown note for an Experience.
public enum MarkdownExporter {
    /// Returns a Markdown string for the experience.
    ///
    /// When `includeMapSnapshot` is `true` and the experience has valid
    /// coordinates, a 300×200 MKMapSnapshotter image is captured and embedded
    /// as a `data:image/png;base64,...` inline image at the top of the body.
    /// Snapshot capture is asynchronous; call the async overload when you need it.
    public static func export(_ experience: Experience, date: Date = .now) -> String {
        export(experience, date: date, includeMapSnapshot: false, snapshotData: nil)
    }

    /// Async variant that optionally captures a map snapshot before building the Markdown.
    public static func export(
        _ experience: Experience,
        date: Date = .now,
        includeMapSnapshot: Bool
    ) async -> String {
        var snapshotData: Data?
        if includeMapSnapshot, let coord = experience.coordinate {
            snapshotData = await captureSnapshot(coordinate: coord)
        }
        return export(experience, date: date, includeMapSnapshot: includeMapSnapshot, snapshotData: snapshotData)
    }

    /// Synchronous core builder; `snapshotData` is pre-captured PNG bytes or nil.
    static func export(
        _ experience: Experience,
        date: Date,
        includeMapSnapshot: Bool,
        snapshotData: Data?
    ) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let dateStr = iso.string(from: date)

        let coords = experience.location.coordinates
        let lat = coords.count >= 2 ? coords[1] : 0.0
        let lon = coords.count >= 2 ? coords[0] : 0.0

        let tags = [experience.category.rawValue, experience.location.cityCode]
            .map { "  - \($0)" }
            .joined(separator: "\n")

        let frontmatter = """
        ---
        title: "\(experience.title)"
        date: \(dateStr)
        latitude: \(lat)
        longitude: \(lon)
        city: \(experience.location.cityCode)
        category: \(experience.category.rawValue)
        solo_score: \(String(format: "%.1f", experience.soloScore.overall))
        tags:
        \(tags)
        ---
        """

        var body = "\n# \(experience.title)\n\n"
        body += "> \(experience.oneLiner)\n\n"

        if let pngData = snapshotData {
            let b64 = pngData.base64EncodedString()
            body += "![Map preview](data:image/png;base64,\(b64))\n\n"
        }

        body += "## Why it matters\n\n\(experience.whyItMatters)\n\n"

        if !experience.howTo.isEmpty {
            body += "## How to\n\n"
            for step in experience.howTo.sorted(by: { $0.order < $1.order }) {
                body += "\(step.order). \(step.text)\n"
            }
            body += "\n"
        }

        if !experience.realInconveniences.isEmpty {
            body += "## Real inconveniences\n\n"
            for inc in experience.realInconveniences {
                body += "- **\(inc.category.rawValue)**: \(inc.text)\n"
            }
            body += "\n"
        }

        if !experience.sources.isEmpty {
            body += "## Sources\n\n"
            for src in experience.sources {
                if let url = src.url {
                    body += "- [\(src.type.rawValue)](\(url.absoluteString))\n"
                } else if let attr = src.attribution {
                    body += "- \(src.type.rawValue): \(attr)\n"
                }
            }
            body += "\n"
        }

        return frontmatter + body
    }

    /// Captures a 300×200 map snapshot centred on `coordinate`. Returns PNG data, or nil on failure.
    static func captureSnapshot(coordinate: CLLocationCoordinate2D) async -> Data? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 800,
            longitudinalMeters: 800
        )
        options.size = CGSize(width: 300, height: 200)
        options.scale = 1
        let snapshotter = MKMapSnapshotter(options: options)
        do {
            let snapshot = try await snapshotter.start()
            return snapshot.image.pngData()
        } catch {
            return nil
        }
    }

    /// Encodes a Notion Web Clipper URL for opening a new Notion page pre-filled with the title.
    public static func notionWebClipperURL(title: String) -> URL? {
        var comps = URLComponents(string: "https://www.notion.so/new")
        comps?.queryItems = [
            URLQueryItem(name: "source", value: "web_clipper"),
            URLQueryItem(name: "title", value: title),
        ]
        return comps?.url
    }
}
