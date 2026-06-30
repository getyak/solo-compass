import XCTest
import SwiftUI
@testable import SoloCompass

/// Visual snapshot of the half-detent empty state — confirms the breathing
/// Solo orb + serif invitation + moment chip + horizontal pills + centered
/// push-to-talk mic compose into a calm "companion is waiting" doorway, not
/// a settings panel. Writes PNGs to /tmp for eyeball checks.
@MainActor
final class HalfExpandedEmptyVisualTest: XCTestCase {

    private func write(_ image: UIImage?, _ name: String) throws {
        let img = try XCTUnwrap(image, "render produced no image for \(name)")
        XCTAssertGreaterThan(img.size.width, 0)
        XCTAssertGreaterThan(img.size.height, 0)
        if let data = img.pngData() {
            let url = URL(fileURLWithPath: "/tmp/\(name).png")
            try? data.write(to: url)
        }
    }

    private func render<V: View>(_ view: V, scheme: ColorScheme = .light) -> UIImage? {
        let wrapped = view
            .frame(width: 390, height: 440)
            .background(scheme == .dark ? Color.black : CT.bgWarm)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: wrapped)
        renderer.scale = 2
        return renderer.uiImage
    }

    private var suggestions: [HalfExpandedEmptyState.Suggestion] {
        [
            .init(label: "附近", icon: "mappin.and.ellipse", tint: CT.accent, fullPrompt: "附近有什么好玩的？"),
            .init(label: "咖啡", icon: "cup.and.saucer.fill", tint: CT.sunGoldDeep, fullPrompt: "找一家安静的咖啡馆"),
            .init(label: "落日", icon: "sun.horizon.fill", tint: CT.sunGoldDeep, fullPrompt: "附近哪里看落日好？"),
            .init(label: "今晚", icon: "moon.stars.fill", tint: Color(.sRGB, red: 0x6B / 255, green: 0x4E / 255, blue: 0x7D / 255, opacity: 1), fullPrompt: "帮我计划今晚的行程"),
        ]
    }

    func testHalfExpanded_idle_light() throws {
        let view = HalfExpandedEmptyState(
            nowChipText: "午后柔和 · 适合走走",
            suggestions: suggestions,
            onSendPrompt: { _ in },
            onMicPress: { _ in },
            isMicListening: false
        )
        try write(render(view), "half_expanded_idle_light")
    }

    func testHalfExpanded_listening_light() throws {
        let view = HalfExpandedEmptyState(
            nowChipText: "夜色温柔 · 适合慢慢走",
            suggestions: suggestions,
            onSendPrompt: { _ in },
            onMicPress: { _ in },
            isMicListening: true
        )
        try write(render(view), "half_expanded_listening_light")
    }

    func testHalfExpanded_idle_dark() throws {
        let view = HalfExpandedEmptyState(
            nowChipText: "夜色温柔",
            suggestions: suggestions,
            onSendPrompt: { _ in },
            onMicPress: { _ in },
            isMicListening: false
        )
        try write(render(view, scheme: .dark), "half_expanded_idle_dark")
    }
}
