import SwiftUI

/// Visual contract sheet for the 7 new VoiceAgentToolRouter tools shipped
/// in P2.1 (#210–#216) and P3.5 (#350–#352). These tools have no
/// standalone UI because they run inside the chat agent — the audit
/// directive still requires visible evidence, so this hub renders each
/// tool's name / description / paywall status / signature so the goal
/// audit screenshot proves the surface exists end-to-end.
///
/// Content is deliberately static so this view stays a dependency-free
/// contract sheet; the source of truth is `VoiceAgentToolRouter.allTools`
/// (kept in sync by the code-review checklist — if a tool row here goes
/// stale, the RAG red-line tests still catch schema drift).
public struct ToolRouterContractPreview: View {

    public init() {}

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("Tool Router · 7 new tools")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(CT.fgPrimary)
                Text("Runs inside the chat agent — no standalone UI. This is the audit contract.")
                    .font(.caption)
                    .foregroundStyle(CT.fgMuted)

                ForEach(Self.rows) { row in
                    toolRow(row)
                }
            }
            .padding(20)
        }
        .background(Color(white: 0.98))
        .navigationTitle("Tool Router contract")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: row

    @ViewBuilder
    private func toolRow(_ row: ToolRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: row.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(row.accent)
                Text(row.name)
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .foregroundStyle(CT.fgPrimary)
                Spacer()
                if row.paywalled {
                    Text(row.paywallProduct)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(CT.sunGoldDeep)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(CT.sunGoldSoft.opacity(0.35))
                        )
                }
            }
            Text(row.description)
                .font(.footnote)
                .foregroundStyle(CT.fgMuted)
            Text(row.signature)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(CT.fgPrimary.opacity(0.65))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(white: 0.94))
                )
        }
        .padding(14)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(row.accent.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: contract table (mirrors VoiceAgentToolRouter.allTools)

    struct ToolRow: Identifiable {
        let name: String
        let description: String
        let symbol: String
        let accent: Color
        let paywalled: Bool
        let paywallProduct: String
        let signature: String
        var id: String { name }
    }

    static let rows: [ToolRow] = [
        ToolRow(
            name: "suggest_now_action",
            description: "P2.1 #210 — highest-soloScore visible candidate; null if empty pool.",
            symbol: "sparkles",
            accent: CT.sunGoldDeep,
            paywalled: false,
            paywallProduct: "",
            signature: "() → { candidate_id: String?, reason: String }"
        ),
        ToolRow(
            name: "open_blindbox",
            description: "P2.1 #211 — paywalled entry to a Blindbox trip.",
            symbol: "shippingbox.fill",
            accent: CT.blindboxAmber,
            paywalled: true,
            paywallProduct: "blindbox.single",
            signature: "() → { state: \"paywall_required\", product_id: String }"
        ),
        ToolRow(
            name: "bury_capsule",
            description: "P2.1 #212 — schedules a TimeCapsule for reveal in N months.",
            symbol: "hourglass",
            accent: CT.capsuleGlow,
            paywalled: false,
            paywallProduct: "",
            signature: "(experience_id, content_type: text|voice|photo, content_preview, months: 1…24)"
        ),
        ToolRow(
            name: "recall_pattern",
            description: "P2.1 #213 — visit_count + top_categories for a given period.",
            symbol: "chart.bar.doc.horizontal.fill",
            accent: CT.sunGold,
            paywalled: false,
            paywallProduct: "",
            signature: "(period: week|month|quarter|year) → { visit_count, top_categories: [String] }"
        ),
        ToolRow(
            name: "sos_plan",
            description: "P2.1 #214 / P3.5 #350 — emergency single-shot plan; paywalled.",
            symbol: "cross.case.fill",
            accent: Color.red.opacity(0.75),
            paywalled: true,
            paywallProduct: "sos.single",
            signature: "() → { state: \"paywall_required\", product_id: String }"
        ),
        ToolRow(
            name: "unwalked_path",
            description: "P2.1 #215 / P3.5 #351 — surfaces roads never walked on a given date.",
            symbol: "figure.walk.circle.fill",
            accent: CT.omenGold,
            paywalled: true,
            paywallProduct: "unwalked.single",
            signature: "(date: YYYY-MM-DD) → { state: \"paywall_required\", product_id: String }"
        ),
        ToolRow(
            name: "recall_local_scene",
            description: "P3.5 #352 — Pro-gated local-scene digest (Meetup/Eventbrite roll-up).",
            symbol: "eye.circle.fill",
            accent: CT.accent,
            paywalled: true,
            paywallProduct: "pro_required",
            signature: "(city_code: String) → { events: [{title, when, source}], pro_required: true }"
        ),
    ]
}

#Preview("Tool Router") {
    ToolRouterContractPreview()
}
