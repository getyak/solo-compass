import SwiftUI
import UIKit

/// Renders a `ShareCardView` into a `UIImage` at the style's target pixel size.
/// Uses SwiftUI `ImageRenderer` (iOS 17+ requirement matches project deployment target).
@MainActor
enum ShareCardRenderer {

    enum RenderError: Error {
        case imageGenerationFailed
        case pngEncodingFailed
        case fileWriteFailed
    }

    /// Render at the style's target pixel size. The card view is laid out at `renderSize`
    /// (half-pixel) and ImageRenderer's `scale` multiplies up to full pixels.
    static func renderImage(payload: ShareCardPayload, style: ShareCardStyle) throws -> UIImage {
        let view = ShareCardView(payload: payload, style: style)
        let renderer = ImageRenderer(content: view)
        renderer.scale = style.renderScale
        renderer.isOpaque = true
        guard let image = renderer.uiImage else {
            throw RenderError.imageGenerationFailed
        }
        return image
    }

    /// Render and write a PNG to the temporary directory, returning the file URL.
    /// Caller does not need to clean up; iOS clears `NSTemporaryDirectory` periodically.
    static func renderTempPNG(payload: ShareCardPayload, style: ShareCardStyle) throws -> URL {
        let image = try renderImage(payload: payload, style: style)
        guard let data = image.pngData() else {
            throw RenderError.pngEncodingFailed
        }
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let filename = "solocompass-\(style.rawValue)-\(UUID().uuidString.prefix(8)).png"
        let url = dir.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw RenderError.fileWriteFailed
        }
        return url
    }
}
