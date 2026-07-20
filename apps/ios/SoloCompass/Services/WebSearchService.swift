import Foundation

/// One web page returned by a live search. The chat agent summarizes the
/// `content` snippets into a sourced answer, and the UI renders `title` + `url`
/// as tappable source-link cards (Perplexity-style provenance).
public struct WebSearchResult: Codable, Equatable, Identifiable, Sendable {
    /// Stable identity for SwiftUI lists — the URL is unique within a result set
    /// (the Edge Function dedupes by URL).
    public var id: String { url }
    public let title: String
    public let url: String
    /// Extracted page snippet. Bounded server-side so a chatty page can't blow
    /// the model's context budget.
    public let content: String

    public init(title: String, url: String, content: String) {
        self.title = title
        self.url = url
        self.content = content
    }

    /// Human-facing host label for a source card ("example.com"), stripped of a
    /// leading "www.". Falls back to the raw URL when it won't parse.
    public var host: String {
        guard let host = URL(string: url)?.host else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// Live web search for the in-chat agent, fronting the `tavily-search` Edge
/// Function so the Tavily key stays server-side.
///
/// This is the real thing the old `AIService.sendWebSearchQuery` only pretended
/// to be: that path just asked the model what it already knew from training and
/// never touched the network. Here the query reaches Tavily, and the agent gets
/// back actual pages — titles, URLs, and extracted snippets — to ground its
/// answer in current, citable sources.
///
/// Best-effort by contract: every failure mode (backend off, not signed in,
/// quota exhausted, provider error) resolves to an empty result array rather
/// than throwing, so the agent degrades to its own knowledge instead of the
/// turn erroring out.
@MainActor
public final class WebSearchService {
    public static let shared = WebSearchService()

    private let client: SupabaseClientProtocol

    public init(client: SupabaseClientProtocol = SupabaseClient.shared) {
        self.client = client
    }

    /// Topic hint passed to Tavily. `.news` biases toward recent, time-sensitive
    /// pages (events, "what's on now"); `.general` is the default.
    public enum Topic: String, Sendable {
        case general
        case news
    }

    /// Run a live web search. Returns up to a handful of deduped pages, or an
    /// empty array on any failure (never throws — see the type doc).
    ///
    /// - Parameters:
    ///   - query: The natural-language search string.
    ///   - topic: `.news` for time-sensitive queries, else `.general`.
    ///   - days: For `.news`, how far back to look (ignored otherwise).
    public func search(
        query: String,
        topic: Topic = .general,
        days: Int? = nil
    ) async -> [WebSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var payload: [String: Any] = [
            "query": trimmed,
            "topic": topic.rawValue,
        ]
        if topic == .news, let days { payload["days"] = days }

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return []
        }

        let result = await client.invoke(function: "tavily-search", body: body)
        guard case .success(let data) = result, !data.isEmpty else { return [] }

        struct Envelope: Decodable {
            let results: [WebSearchResult]?
        }
        let decoded = try? JSONDecoder().decode(Envelope.self, from: data)
        return decoded?.results ?? []
    }
}
