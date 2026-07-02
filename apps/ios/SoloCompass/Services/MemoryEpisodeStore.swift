import Foundation

/// ③ Memory三层 — slice A: pure in-memory episode store + BM25-lite keyword
/// search. Populated on session end; queried by the `recall_memory` tool.
///
/// Design principles:
/// - **Zero token cost on the hot path.** Nothing about this layer lands in
///   the system prompt. The model reaches for it explicitly via
///   `recall_memory(query:)` when it thinks the user is referencing past
///   context.
/// - **No SwiftData yet.** Slice A stores episodes in memory only so we can
///   ship the API surface + prove the retrieval quality without a schema
///   migration. Slice B (later) swaps the storage for a `MemoryEpisode`
///   `@Model` with the same interface.
/// - **Explainable retrieval.** BM25 (Okapi) with plain-token matching so a
///   test can assert that a query surfaces the expected episode. No
///   embeddings — data volume doesn't need them for months.
///
/// Episodes are IMMUTABLE snapshots — never edited after insertion. Deletion
/// is the only mutation, wired through `ForgetMeService` so a user can
/// nuke a range.
@MainActor
final class MemoryEpisodeStore {

    // MARK: - Value types

    /// One durable memory: an atomic thing worth recalling later.
    /// Coarser than a message, finer than a session — usually one meaningful
    /// exchange (place visited, decision made, preference stated).
    struct Episode: Equatable, Codable, Identifiable, Sendable {
        let id: UUID
        /// ISO 8601 UTC — matches every other timestamp in the project.
        let occurredAt: Date
        /// City code where the episode happened, if resolvable. Nil for
        /// global-scope chats (no map anchor).
        let cityCode: String?
        /// Short title — used in the tool result. Model-writable.
        let title: String
        /// One paragraph natural-language summary of what happened. This is
        /// what the model reads when recall returns.
        let body: String
        /// Free-form tags: places, mood, category. Feed the retrieval scorer.
        let tags: [String]

        init(
            id: UUID = UUID(),
            occurredAt: Date,
            cityCode: String? = nil,
            title: String,
            body: String,
            tags: [String] = []
        ) {
            self.id = id
            self.occurredAt = occurredAt
            self.cityCode = cityCode
            self.title = title
            self.body = body
            self.tags = tags
        }
    }

    struct Hit: Equatable {
        let episode: Episode
        let score: Double
    }

    // MARK: - Storage

    /// In-memory store — Slice A. `internal` so `ForgetMeService`
    /// can range-delete without going through a tombstone protocol.
    private(set) var episodes: [Episode] = []

    init() {}

    // MARK: - Mutation

    func insert(_ ep: Episode) {
        episodes.append(ep)
    }

    /// Wipe. Called by `ForgetMeService` (and by tests). Idempotent.
    func removeAll() {
        episodes.removeAll(keepingCapacity: true)
    }

    /// Delete episodes older than `cutoff`. Used to trim the store after a
    /// user asks to "forget everything before yesterday".
    func removeOlder(than cutoff: Date) {
        episodes.removeAll { $0.occurredAt < cutoff }
    }

    // MARK: - Retrieval

    /// Score-and-rank episodes against a natural-language query. Uses a
    /// simplified BM25 variant that stays legible and testable:
    ///
    ///   score(ep) = Σ_t (idf(t) · tf(t, doc) / (tf + k1 · (1 − b + b · dl/avgdl)))
    ///
    /// with k1=1.5, b=0.75. Fields (title, body, tags) are stacked into one
    /// bag-of-tokens per episode so a hit on the tag list weights the same
    /// as a hit in the body — that's what we want for recall (a mood tag
    /// like "hungover" is at least as diagnostic as a body phrase).
    func search(
        query: String,
        cityCode: String? = nil,
        limit: Int = 3
    ) -> [Hit] {
        let queryTokens = Self.tokenize(query)
        guard !queryTokens.isEmpty else { return [] }

        let corpus = cityCode.map { code in
            episodes.filter { $0.cityCode == nil || $0.cityCode == code }
        } ?? episodes
        guard !corpus.isEmpty else { return [] }

        let docs: [(ep: Episode, tokens: [String])] = corpus.map { ep in
            (ep, Self.tokenize("\(ep.title) \(ep.body) \(ep.tags.joined(separator: " "))"))
        }

        let avgdl: Double = {
            let total = docs.reduce(0) { $0 + $1.tokens.count }
            return docs.isEmpty ? 0 : Double(total) / Double(docs.count)
        }()

        // Doc frequency per query token.
        let n = Double(docs.count)
        let df: [String: Double] = Dictionary(uniqueKeysWithValues:
            queryTokens.map { t in
                (t, Double(docs.filter { $0.tokens.contains(t) }.count))
            }
        )

        // BM25 params — literature standard.
        let k1 = 1.5, b = 0.75

        let scored: [Hit] = docs.map { doc in
            let dl = Double(doc.tokens.count)
            var score = 0.0
            for t in queryTokens {
                let f = Double(doc.tokens.filter { $0 == t }.count)
                guard f > 0 else { continue }
                let dft = df[t] ?? 0
                // Robertson–Spärck Jones IDF, clamped ≥ 0 so common
                // stopwords can't push scores negative.
                let idf = max(0, log((n - dft + 0.5) / (dft + 0.5) + 1))
                score += idf * (f * (k1 + 1)) / (f + k1 * (1 - b + b * (dl / max(1, avgdl))))
            }
            return Hit(episode: doc.ep, score: score)
        }

        return scored
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Tokenizer

    /// Cheap tokenizer: lowercase, split on Unicode word boundaries. CJK is
    /// handled by pass-through: each Han character becomes its own token,
    /// which matches how users query ("咖啡" → ["咖", "啡"] AND both must
    /// appear together in title/body for a hit). Correct enough for slice A;
    /// slice B can plug in a real segmenter.
    static func tokenize(_ s: String) -> [String] {
        let lower = s.lowercased()
        var out: [String] = []
        var current = ""

        for scalar in lower.unicodeScalars {
            if isCJKScalar(scalar) {
                if !current.isEmpty { out.append(current); current = "" }
                out.append(String(scalar))
            } else if scalar.properties.isAlphabetic || CharacterSet.decimalDigits.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else {
                if !current.isEmpty { out.append(current); current = "" }
            }
        }
        if !current.isEmpty { out.append(current) }
        return out.filter { !$0.isEmpty }
    }

    private static func isCJKScalar(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        return (0x4E00...0x9FFF).contains(v)
            || (0x3400...0x4DBF).contains(v)
            || (0x3040...0x309F).contains(v)
            || (0x30A0...0x30FF).contains(v)
            || (0xAC00...0xD7AF).contains(v)
    }
}
