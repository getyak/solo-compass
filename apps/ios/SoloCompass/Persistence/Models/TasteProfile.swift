import Foundation
import SwiftData

/// Singleton model — one row per user, capturing their "vibe profile" as a
/// dense embedding vector + human-readable descriptors. Drives reverse-feed
/// curation (`✦ 我的菜` filter), private picks (Pro), and re-ranking of
/// nearby experiences without re-tagging every Experience by hand.
///
/// Singleton semantics are enforced at the store layer (not the @Model layer)
/// because SwiftData has no "max one row" attribute. The pattern: on write,
/// the TasteStore deletes any pre-existing row in the same transaction before
/// inserting the new one. This keeps the row count predictable at exactly 0
/// (uninitialised) or 1 (live).
///
/// The `embedding` blob is a packed array of `Float` (32-bit, not Double) —
/// 32-bit halves the on-disk size and matches what most vision/text models
/// emit natively, so we don't lose precision in the cast. Typical dimension
/// is 256-1536 depending on which model `AIService.generateTasteProfile` is
/// configured with; the dimension is implicit (length / 4 bytes).
///
/// Created/updated by AIService.generateTasteProfile (P1.2 #122) from the
/// onboarding 3-photo vibe step, then continuously refined by
/// TasteUpdateService (P1.2 #123) every 5 VisitRecord rows. Confidence climbs
/// from 0.3 (cold start, photos only) toward 0.95 as visit data accumulates.
@Model
public final class TasteProfile {
    @Attribute(.unique) public var id: UUID
    /// Packed `[Float]` (32-bit) embedding. Length implies dimension.
    public var embedding: Data
    /// Human-readable taste descriptors, e.g. ["arty", "quiet", "sunlit"]. JSON-encoded.
    public var descriptorsBlob: Data
    /// Calibrated confidence in the profile (0.0-1.0). Used by reranking to
    /// blend Taste signal weight against base Solo Score — low-confidence
    /// profiles barely affect rankings until enough visit data lands.
    public var confidence: Double
    public var updatedAt: Date
    /// Identifiers of the source vibe photos (Apple Photos local-identifier
    /// strings or computed perceptual hashes). JSON-encoded `[String]`.
    /// Optional because the user may have skipped the photo step. Kept so the
    /// onboarding can show "you picked these" for review without re-asking.
    public var sourceVibePhotosBlob: Data?

    public init(
        id: UUID = UUID(),
        embedding: Data,
        descriptorsBlob: Data,
        confidence: Double,
        updatedAt: Date = Date(),
        sourceVibePhotosBlob: Data? = nil
    ) {
        self.id = id
        self.embedding = embedding
        self.descriptorsBlob = descriptorsBlob
        self.confidence = confidence
        self.updatedAt = updatedAt
        self.sourceVibePhotosBlob = sourceVibePhotosBlob
    }

    // MARK: - Codec helpers

    /// Pack a `[Float]` embedding into a flat `Data` blob (little-endian on
    /// every Apple device, so endianness need not be normalised).
    public static func encodeEmbedding(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Decode the embedding blob back to `[Float]`. Returns `[]` if the byte
    /// count isn't a multiple of `Float` (corrupt row) so callers can fall
    /// back to neutral ranking rather than crash.
    public var embeddingVector: [Float] {
        let stride = MemoryLayout<Float>.size
        guard embedding.count % stride == 0 else { return [] }
        return embedding.withUnsafeBytes { raw -> [Float] in
            let buffer = raw.bindMemory(to: Float.self)
            return Array(buffer)
        }
    }

    /// Decode the JSON-encoded descriptors blob. Returns `[]` on decode
    /// failure so missing descriptors degrade gracefully into "no labels".
    public var descriptors: [String] {
        (try? JSONDecoder().decode([String].self, from: descriptorsBlob)) ?? []
    }

    /// JSON-encode descriptors for storage. Throws on encoder failure so the
    /// store layer can surface persistence errors rather than persist garbage.
    public static func encodeDescriptors(_ descriptors: [String]) throws -> Data {
        try JSONEncoder().encode(descriptors)
    }

    /// Decode the source-photos blob. Returns `nil` (not `[]`) on missing
    /// blob to distinguish "no photo step taken" from "photos cleared."
    public var sourceVibePhotos: [String]? {
        guard let sourceVibePhotosBlob else { return nil }
        return try? JSONDecoder().decode([String].self, from: sourceVibePhotosBlob)
    }
}
