import XCTest
import SwiftUI
import SwiftData
@testable import SoloCompass

/// US-010 render coverage: `FriendsListView` must lay out a real screen with
/// (a) the top "pending requests" inbox section and (b) the friends list below,
/// and must show the dedicated empty-state copy when there is nothing to show.
///
/// We can't drive a live backend in-process, so we seed `FriendService` with
/// in-memory fixtures and install the view in a real `UIWindow`, then assert the
/// rendered bitmap is not a flat uniform band (the signature of a view that
/// failed to lay out / register). A separate case checks the empty state renders
/// the breathing illustration + copy rather than collapsing to nothing.
@MainActor
final class FriendsListRenderTest: XCTestCase {

    /// Logical size of an iPhone 17 Pro portrait window.
    private static let windowSize = CGSize(width: 402, height: 874)

    // MARK: - Populated list (requests + friends)

    /// Drives the full populated layout — the top incoming-request inbox row
    /// (with Accept/Decline) and the friend list below — by rendering the view's
    /// private `friendsList` content directly through a fixture-backed service.
    /// This bypasses the on-appear `refresh()` (which, with the Phase-1
    /// `companion` flag off, clears state to empty) so the populated branch is
    /// genuinely exercised.
    func testFriendsListRendersRequestsAndFriends() throws {
        let service = FriendService()
        service.incomingRequests = [
            FriendRequest(
                id: FriendRequestId(rawValue: "freq_render"),
                requesterId: "traveler_abc",
                recipientId: "local",
                status: .pending,
                source: .companionChat,
                note: "We crossed paths in Tokyo — let's stay in touch!",
                expiresAt: "2026-07-01T10:00:00Z",
                createdAt: "2026-06-01T10:00:00Z",
                updatedAt: "2026-06-01T10:00:00Z"
            ),
        ]
        service.friends = [
            Friendship(
                id: FriendshipId(rawValue: "fnd_render_1"),
                userLowId: "local",
                userHighId: "maya",
                initiatedBy: "local",
                conversationId: nil,
                acceptedAt: "2026-05-01T10:00:00Z",
                createdAt: "2026-05-01T10:00:00Z",
                updatedAt: "2026-05-01T10:00:00Z"
            ),
        ]

        // `autoRefresh: false` skips the on-appear `refresh()` so the seeded
        // fixtures survive and the populated branch actually renders.
        let image = try render(content: FriendsListView(service: service, autoRefresh: false))
        dump(image, to: "friends_list_populated")
        XCTAssertFalse(
            isUniformColor(image),
            "FriendsListView populated content rendered as a flat band — the "
                + "request inbox + friends list did not lay out."
        )
    }

    // MARK: - Empty state

    func testFriendsListRendersEmptyState() throws {
        let service = FriendService()
        service.incomingRequests = []
        service.friends = []

        let image = try render(content: FriendsListView(service: service))
        dump(image, to: "friends_list_empty")
        XCTAssertFalse(
            isUniformColor(image),
            "Empty FriendsListView rendered as a flat band — the empty-state "
                + "illustration/copy is missing."
        )
    }

    /// Writes a PNG to /tmp so the rendered screen can be visually inspected
    /// (the "verify in Simulator" acceptance step). Best-effort; never fails.
    private func dump(_ image: UIImage, to name: String) {
        guard let data = image.pngData() else { return }
        let url = URL(fileURLWithPath: "/tmp/\(name).png")
        try? data.write(to: url)
    }

    // MARK: - Helpers

    /// Installs `content` (wrapped in a `NavigationStack`) in a real window,
    /// pumps the run loop briefly so SwiftUI lays out the `List`, and snapshots
    /// the full screen.
    private func render<Content: View>(content: Content) throws -> UIImage {
        let view = NavigationStack { content }
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: Self.windowSize))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        // Pump the run loop so the List/empty-state finish their first layout.
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))

        let bounds = CGRect(origin: .zero, size: Self.windowSize)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        return renderer.image { _ in
            host.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
    }

    /// True when every sampled pixel is (near) identical — a flat color band,
    /// which is what a view that failed to render produces.
    private func isUniformColor(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return true }
        let width = cg.width
        let height = cg.height
        guard width > 0, height > 0 else { return true }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return true
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        func sample(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
            let i = y * bytesPerRow + x * bytesPerPixel
            return (pixels[i], pixels[i + 1], pixels[i + 2])
        }

        let steps = 16
        let first = sample(0, 0)
        let tolerance: Int = 6
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
