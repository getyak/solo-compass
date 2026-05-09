import Foundation
import SwiftData

/// Cached AI synthesis result keyed by SHA256 of the canonical input
/// (sorted osmIds + cityCode + locale + model name). Used by `AIService`
/// (Epic B US-B2) to skip re-running Claude on the same POI batch within
/// 30 days.
///
/// `experiencesJSON` is the encoded `[Experience]` array so the cache
/// survives changes to nested struct shapes (decoded through the same
/// `JSONDecoder.iso8601Decoder` we use everywhere).
@Model
public final class AISynthesisCacheRecord {
    @Attribute(.unique) public var cacheKey: String
    public var experiencesJSON: Data
    public var synthesizedAt: Date
    public var modelName: String

    public init(cacheKey: String, experiencesJSON: Data, synthesizedAt: Date = Date(), modelName: String) {
        self.cacheKey = cacheKey
        self.experiencesJSON = experiencesJSON
        self.synthesizedAt = synthesizedAt
        self.modelName = modelName
    }
}
