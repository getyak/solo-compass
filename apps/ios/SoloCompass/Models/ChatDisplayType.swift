import Foundation

/// Visual component types the LLM can request when calling chat tools.
/// Based on Google Maps Agentic UI Toolkit's four inline UI outcome types.
///
/// The LLM specifies a display_type in its tool call arguments; ChatSheet
/// maps it to the corresponding SwiftUI view. This replaces content-based
/// inference with explicit selection.
public enum ChatDisplayType: String, Codable, CaseIterable, Sendable {
    /// Compact POI card with name, category, score, and a tap-to-detail action.
    /// Equivalent to Google's "Place Detail" outcome.
    case placeCard = "place_card"

    /// Small inline MapKit snapshot (~120pt) showing pins for recommended places.
    /// Equivalent to Google's "Inline Maps" outcome.
    case miniMap = "mini_map"

    /// Route preview card with ordered stops, estimated duration, and adopt button.
    /// Equivalent to Google's "Inline Map + Route" outcome.
    case routePreview = "route_preview"

    /// Rich photo/imagery card for a single place with hero image.
    /// Equivalent to Google's "Inline Map Detail" outcome.
    case photoDetail = "photo_detail"

    /// Plain text response with no visual card attachment.
    case textOnly = "text_only"
}

/// Emphasis level for display components -- controls card size and position.
public enum ChatDisplayEmphasis: String, Codable, Sendable {
    /// Full-width card, prominent placement.
    case primary
    /// Compact card, secondary placement (e.g. in a horizontal scroll).
    case secondary
}

/// Parsed display parameters from a tool call's arguments.
/// Tool router extracts these before executing the tool action.
public struct ChatDisplayParams: Equatable, Sendable {
    public let displayType: ChatDisplayType
    public let emphasis: ChatDisplayEmphasis

    public init(
        displayType: ChatDisplayType = .placeCard,
        emphasis: ChatDisplayEmphasis = .primary
    ) {
        self.displayType = displayType
        self.emphasis = emphasis
    }

    /// Parse display params from tool call arguments JSON.
    /// Falls back to placeCard/primary if fields are missing.
    public static func from(arguments: [String: Any]) -> ChatDisplayParams {
        let typeStr = arguments["display_type"] as? String ?? "place_card"
        let emphasisStr = arguments["emphasis"] as? String ?? "primary"
        return ChatDisplayParams(
            displayType: ChatDisplayType(rawValue: typeStr) ?? .placeCard,
            emphasis: ChatDisplayEmphasis(rawValue: emphasisStr) ?? .primary
        )
    }
}
