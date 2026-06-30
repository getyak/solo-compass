import XCTest
import SwiftUI
@testable import SoloCompass

/// Visual snapshot of the redesigned chat surface: bubble-less serif assistant
/// reply, accent-fill user bubble (no tail), and the single AgentStatusLine as
/// the live thinking source. Writes PNGs to /tmp for eyeball checks during
/// development.
@MainActor
final class ChatRedesignVisualTest: XCTestCase {

    private func write(_ image: UIImage?, _ name: String) throws {
        let img = try XCTUnwrap(image, "render produced no image for \(name)")
        XCTAssertGreaterThan(img.size.width, 0)
        XCTAssertGreaterThan(img.size.height, 0)
        if let data = img.pngData() {
            let url = URL(fileURLWithPath: "/tmp/\(name).png")
            try? data.write(to: url)
        }
    }

    private func render<V: View>(_ view: V, width: CGFloat = 390, scheme: ColorScheme = .light) -> UIImage? {
        let wrapped = view
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .background(CT.bgWarm)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: wrapped)
        renderer.scale = 2
        return renderer.uiImage
    }

    func testRedesignedConversation_light() throws {
        let view = VStack(alignment: .leading, spacing: 18) {
            MessageBubble(role: .user, text: "What's good around me?")
            MessageBubble(
                role: .assistant,
                text: "I found three quiet cafés within a 6-minute walk. **Café Zenith** is the standout — calm, fast wifi, and a long single-seater bar that turns out to be perfect for working alone.\n\nA second contender is *Blue Window*, with a 9.1 solo-score and an outdoor patio that catches the morning sun."
            )
            AgentStatusLine(label: "🔍 Searching nearby…")
            MessageBubble(role: .user, text: "Take me to Café Zenith.")
        }
        .padding(16)
        try write(render(view), "chat_redesign_light")
    }

    func testRedesignedConversation_dark() throws {
        let view = VStack(alignment: .leading, spacing: 18) {
            MessageBubble(role: .user, text: "Any sunset viewpoints?")
            MessageBubble(
                role: .assistant,
                text: "**Riverside Pier** at 19:42 — golden hour clears the bridge and you get the skyline framing the sun. Walk-able from where you are; the path is well-lit after sundown."
            )
            ReasoningSummaryChip(summary: ReasoningSummary(
                summary: "Searched 14 places · 2 matched",
                detail: [
                    "Searched places — 14 within walking range",
                    "Filtered: sunset viewpoint — 2 matched",
                    "Checked sunset time — 19:42 today"
                ]
            ))
        }
        .padding(16)
        .background(Color.black)
        try write(render(view, scheme: .dark), "chat_redesign_dark")
    }
}
