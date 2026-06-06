import SwiftUI
import UIKit

// MARK: - RouteShareRenderer

/// Renders `RouteShareCardView` to a `UIImage` / temp PNG.
///
/// `map` style is async because it first obtains an `MKMapSnapshotter` basemap;
/// on snapshot failure it transparently falls back to the `trace` style so the
/// pipeline never returns a blank or throws to the UI. The returned
/// `RenderResult` reports which style actually rendered so the sheet can show a
/// "fell back to minimal line" hint.
@MainActor
enum RouteShareRenderer {
    enum RenderError: Error {
        case imageGenerationFailed
        case pngEncodingFailed
        case fileWriteFailed
    }

    struct RenderResult {
        let image: UIImage
        /// The style that was actually rendered (may differ from requested on fallback).
        let effectiveStyle: RouteShareStyle
        /// True when a `.map` request had to fall back to `.trace`.
        let didFallback: Bool
    }

    /// Render the card for `style`. Handles the map-snapshot + fallback chain.
    static func render(payload: RouteSharePayload, style: RouteShareStyle) async -> RenderResult {
        let size = RouteShareCardView.renderSize
        let scale = RouteShareCardView.renderScale

        // Map style: try the basemap snapshot first.
        if style == .map, payload.hasAnyCoordinate {
            if let basemap = try? await RouteMapSnapshotter.snapshot(
                coordinates: payload.coordinates,
                size: size,
                scale: scale
            ), let image = rasterize(payload: payload, style: .map, basemap: basemap) {
                return RenderResult(image: image, effectiveStyle: .map, didFallback: false)
            }
            // Snapshot failed → fall back to trace.
            if let image = rasterize(payload: payload, style: .trace, basemap: nil) {
                return RenderResult(image: image, effectiveStyle: .trace, didFallback: true)
            }
        }

        // Trace / gradient-fallback path (also covers map with no coords).
        let resolved: RouteShareStyle = (style == .map && !payload.hasAnyCoordinate) ? .trace : style
        if let image = rasterize(payload: payload, style: resolved, basemap: nil) {
            return RenderResult(image: image, effectiveStyle: resolved, didFallback: style != resolved)
        }

        // Last-ditch: empty image so we never crash the UI (should be unreachable).
        return RenderResult(image: UIImage(), effectiveStyle: resolved, didFallback: true)
    }

    /// Synchronous SwiftUI → UIImage rasterisation for a fully-resolved card.
    private static func rasterize(payload: RouteSharePayload, style: RouteShareStyle, basemap: UIImage?) -> UIImage? {
        let view = RouteShareCardView(payload: payload, style: style, basemap: basemap)
        let renderer = ImageRenderer(content: view)
        renderer.scale = RouteShareCardView.renderScale
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Render and persist a temp PNG (the system-share path).
    static func renderTempPNG(payload: RouteSharePayload, style: RouteShareStyle) async throws -> (URL, RenderResult) {
        let result = await render(payload: payload, style: style)
        guard let data = result.image.pngData() else { throw RenderError.pngEncodingFailed }
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let filename = "solocompass-route-\(UUID().uuidString.prefix(8)).png"
        let url = dir.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw RenderError.fileWriteFailed
        }
        return (url, result)
    }
}
