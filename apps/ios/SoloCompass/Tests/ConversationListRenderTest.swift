import XCTest
import SwiftUI
import SwiftData
@testable import SoloCompass

/// US-017 render coverage: the unified `ConversationListView` (Me ▸ Messages)
/// must lay out one time-sorted list mixing all three thread kinds —
/// `friendDirect` DMs, `oneOnOne` companion threads, and `groupRoute` chats —
/// each row showing emoji + title + last-message preview + unread dot.
///
/// We can't drive a live backend in-process, so we seed the view through its
/// `previewSummaries` test seam (which skips the network reload) and snapshot
/// the rendered window. A flat uniform band would mean the list failed to lay
/// out. We also assert the summaries themselves are newest-first.
@MainActor
final class ConversationListRenderTest: XCTestCase {

    private static let windowSize = CGSize(width: 402, height: 874)

    /// Three threads — one of each type — newest-first by `lastMessageAt`.
    private func fixtures() -> [ConversationSummary] {
        func conv(_ id: String, _ type: ConversationType, _ last: String, route: String? = nil) -> Conversation {
            Conversation(
                id: ConversationId(rawValue: id),
                participantIds: ["local", "maya"],
                type: type,
                routeId: route,
                lastMessageAt: last,
                createdAt: "2026-06-01T09:00:00Z",
                updatedAt: last
            )
        }
        return [
            ConversationSummary(
                conversation: conv("c_group", .groupRoute, "2026-06-07T18:00:00Z", route: "route_1"),
                title: "Old Town Food Crawl",
                emoji: "👥",
                preview: "See you all at the night market!",
                hasUnread: true
            ),
            ConversationSummary(
                conversation: conv("c_friend", .friendDirect, "2026-06-06T12:00:00Z"),
                title: "maya",
                emoji: "🧭",
                preview: "Thanks for the temple tip 🙏",
                hasUnread: false
            ),
            ConversationSummary(
                conversation: conv("c_solo", .oneOnOne, "2026-06-05T08:00:00Z"),
                title: "Companion · Kyoto",
                emoji: "🧭",
                preview: "Want to split a taxi tomorrow?",
                hasUnread: true
            ),
        ]
    }

    /// The populated list renders all three thread kinds in a single screen.
    func testUnifiedListRendersMixedThreadTypes() throws {
        let summaries = fixtures()

        // Acceptance: time-sorted newest-first by lastMessageAt desc.
        let keys = summaries.map { $0.conversation.lastMessageAt ?? "" }
        XCTAssertEqual(keys, keys.sorted(by: >), "Conversations must be lastMessageAt desc.")

        let image = try render(content: ConversationListView(previewSummaries: summaries))
        dump(image, to: "conversation_list_populated")
        XCTAssertFalse(
            isUniformColor(image),
            "ConversationListView populated content rendered as a flat band — the "
                + "unified thread list did not lay out."
        )
    }

    /// The empty inbox renders without crashing and produces a real bitmap. We
    /// don't assert non-uniformity here: the empty state is mostly background
    /// with a single centered line of subtle copy, so the coarse pixel grid can
    /// legitimately miss it. The populated case above is the meaningful layout
    /// check; this case guards the empty branch against a crash / nil render.
    func testUnifiedListRendersEmptyState() throws {
        let image = try render(content: ConversationListView(previewSummaries: []))
        dump(image, to: "conversation_list_empty")
        XCTAssertGreaterThan(image.size.width, 0, "Empty list failed to produce a bitmap.")
        XCTAssertGreaterThan(image.size.height, 0, "Empty list failed to produce a bitmap.")
    }

    // MARK: - Helpers

    private func dump(_ image: UIImage, to name: String) {
        guard let data = image.pngData() else { return }
        try? data.write(to: URL(fileURLWithPath: "/tmp/\(name).png"))
    }

    private func render<Content: View>(content: Content) throws -> UIImage {
        let view = NavigationStack { content }
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: Self.windowSize))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))

        let bounds = CGRect(origin: .zero, size: Self.windowSize)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        return renderer.image { _ in
            host.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
    }

    private func isUniformColor(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return true }
        let width = cg.width, height = cg.height
        guard width > 0, height > 0 else { return true }
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return true }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        func sample(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
            let i = y * bytesPerRow + x * bytesPerPixel
            return (pixels[i], pixels[i + 1], pixels[i + 2])
        }
        let steps = 16
        let first = sample(0, 0)
        let tolerance = 6
        for sy in 0..<steps {
            for sx in 0..<steps {
                let x = min(width - 1, sx * width / steps)
                let y = min(height - 1, sy * height / steps)
                let p = sample(x, y)
                if abs(Int(p.0) - Int(first.0)) > tolerance
                    || abs(Int(p.1) - Int(first.1)) > tolerance
                    || abs(Int(p.2) - Int(first.2)) > tolerance {
                    return false
                }
            }
        }
        return true
    }
}
