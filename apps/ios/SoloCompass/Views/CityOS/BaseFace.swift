import SwiftUI

/// 游民基地 · which face the Base card/panel shows for a city. One persistent
/// entry whose content follows the traveler's lifecycle — the entry itself
/// never appears or disappears (v1's inferred-entry mistake); only the face
/// changes:
///
///   Plan   人还没去 — visa policy, weather, work-readiness, kit preview
///   Arrive 刚落地   — essentials first, entry-date confirm starts the countdown
///   Live   住下了   — today's work spot, events; visa shrinks to a ring
///   Recall 离开/回顾 — the visited/verify loop
///
/// Pure function of the existing CityMode + CityStage so it is trivially
/// testable and adds no new state.
enum BaseFace: String, CaseIterable {
    case plan
    case arrive
    case live
    case recall

    /// Derive the face from the city's mode and (Live-mode) stage. Plan and
    /// Recall modes map directly; Live splits on the stay's stage — land/settle
    /// read as "arriving", leave reads as "recalling", and a stage-less Live
    /// city (no entry date yet) rests at the steady-state `live` face.
    static func derive(mode: CityMode, stage: CityStage?) -> BaseFace {
        switch mode {
        case .plan:
            return .plan
        case .recall:
            return .recall
        case .live:
            switch stage {
            case .land, .settle: return .arrive
            case .leave:         return .recall
            case .live, nil:     return .live
            }
        }
    }

    /// Uppercase chip label (计划 / 抵达 / 在地 / 回顾).
    var tagText: String {
        NSLocalizedString("cityos.base.tag.\(rawValue)", comment: "Base face tag")
    }

    /// Chip tint. Plan keeps the sanctioned cool-blue register flip; the two
    /// in-city faces stay in the amber family; recall mutes down.
    var tagColor: Color {
        switch self {
        case .plan:   return CT.modePlanBlue
        case .arrive: return CT.sunGoldDeep
        case .live:   return CT.accent
        case .recall: return CT.fgMuted
        }
    }

    /// Leading SF Symbol for the face's headline row.
    var symbol: String {
        switch self {
        case .plan:   return "airplane.departure"
        case .arrive: return "shippingbox.fill"
        case .live:   return "laptopcomputer"
        case .recall: return "eye"
        }
    }

    /// Whether this face carries the visa countdown ring. Information must
    /// exit with the lifecycle, not just enter: a Plan face has no stay to
    /// count and a Recall face's stay is over — a stale ring there counts
    /// down a visa that no longer binds the traveler.
    var showsCountdown: Bool {
        self == .arrive || self == .live
    }
}
