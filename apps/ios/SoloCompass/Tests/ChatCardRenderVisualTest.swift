import XCTest
import SwiftUI
@testable import SoloCompass

/// Visual render check for the new in-chat cards + reasoning panel. No snapshot
/// library ships, so we render each surface to a PNG under /tmp (eyeballed
/// during development) and assert it produces a non-empty image. Mirrors the
/// established ImageRenderer pattern in RouteCardNowReasonTests.
@MainActor
final class ChatCardRenderVisualTest: XCTestCase {

    private func write(_ image: UIImage?, _ name: String) throws {
        let img = try XCTUnwrap(image, "render produced no image for \(name)")
        XCTAssertGreaterThan(img.size.width, 0)
        XCTAssertGreaterThan(img.size.height, 0)
        if let data = img.pngData() {
            let url = URL(fileURLWithPath: "/tmp/\(name).png")
            try? data.write(to: url)
        }
    }

    private func render<V: View>(_ view: V, width: CGFloat = 390) -> UIImage? {
        let wrapped = view
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .background(CT.bgWarm)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: wrapped)
        renderer.scale = 2
        return renderer.uiImage
    }

    private var seed: [Experience] { Array(ExperienceService.hardcodedSeed.prefix(3)) }

    func testExperienceCardRenders() throws {
        let exp = try XCTUnwrap(seed.first)
        try write(render(ChatExperienceCard(experience: exp) {}), "chatcard_experience")
    }

    func testRouteProposalCardRenders() throws {
        let stops = seed
        guard stops.count >= 2 else { throw XCTSkip("need ≥2 seed places") }
        let route = Route(
            id: RouteId(rawValue: "r-proposal"),
            title: "黄昏河畔漫步",
            summary: "从老城出发,沿河走到日落观景点。",
            experienceIds: stops.map(\.id),
            cityCode: stops.first?.location.cityCode ?? "VTE",
            region: "Riverfront",
            estimatedDuration: 75,
            distanceMeters: 1400,
            pace: .relaxed,
            tags: ["nature"],
            source: .aiGenerated,
            reasonNow: "日落将至 · 30 分钟后是最佳光线"
        )
        let proposal = RouteProposal(
            route: route,
            stops: stops,
            stopReasons: stops.enumerated().map { i, _ in "第 \(i + 1) 站 · 适合此刻停留" }
        )
        try write(
            render(ChatRouteProposalCard(proposal: proposal, onAdopt: {}, onTapStop: { _ in })),
            "chatcard_route_proposal"
        )
    }

    func testReasoningTracePanelRenders() throws {
        let steps = [
            ReasoningStep(kind: .thinking, label: "正在分析当下的时间与天气…"),
            ReasoningStep(kind: .tool, label: "🔍 搜索附近的安静咖啡馆…"),
            ReasoningStep(kind: .insight, label: "找到 3 个合适的地方"),
        ]
        try write(render(ReasoningTracePanel(steps: steps)), "chatcard_reasoning_trace")
    }

    func testExperienceRailRenders() throws {
        guard seed.count >= 2 else { throw XCTSkip("need ≥2 seed places") }
        let stack = ChatCardStack(
            cards: [.experiences(id: UUID(), seed)],
            onSelectExperience: { _ in },
            onAdoptRoute: { _ in }
        )
        try write(render(stack), "chatcard_experience_rail")
    }

    // MARK: - B-batch redesign (#6 bubbles)

    /// Renders a representative conversation so the avatar-free, warm-parchment
    /// assistant bubble + accent user bubble can be eyeballed against the old
    /// white-card-with-compass-avatar look.
    func testRedesignedBubbleConversationRenders() throws {
        let convo = VStack(alignment: .leading, spacing: 10) {
            MessageBubble(role: .user, text: "帮我计划今晚的行程")
            MessageBubble(
                role: .assistant,
                text: "好的！现在是晚上，我来看看你附近有哪些适合夜晚的好去处。先看看你周围有什么："
            )
            MessageBubble(role: .tool, text: "{}", toolName: "explore_nearby")
            MessageBubble(
                role: .assistant,
                text: "找到 3 个不错的地方，**河畔夜市**离你最近，灯火很热闹，适合一个人慢慢逛。"
            )
            TypingIndicatorBubble(label: "🧭 正在串联路线…")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        try write(render(convo), "bubbles_redesigned_light")
    }
}
