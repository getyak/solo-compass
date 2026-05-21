import Foundation

// MARK: - API response types

private struct SoloScoreResponse: Decodable {
    struct Dimensions: Decodable {
        let wifi: Double
        let noise: Double
        let seating: Double
        let staff: Double
        let lighting: Double
        let safety: Double
    }
    let experience_id: String
    let dimensions: Dimensions
    let sample_count: Int
    let confidence: Double
}

// MARK: - ReviewsService

/// Fetches aggregated solo-score dimensions from the backend API.
/// Falls back to the local seed SoloScore on any network or API failure.
/// In Release builds without SOLO_API_BASE_URL set, short-circuits immediately to avoid
/// 30-second localhost timeouts on users' devices.
@MainActor
public final class ReviewsService {
    public static let shared = ReviewsService()

    private let session: URLSession
    private let baseURL: URL
    // True when running in a Release build with no backend configured.
    private let isUnconfigured: Bool

    public init(session: URLSession = .shared, baseURL: URL? = nil) {
        self.session = session
        if let url = baseURL {
            self.baseURL = url
            self.isUnconfigured = false
        } else {
            let envURL = ProcessInfo.processInfo.environment["SOLO_API_BASE_URL"]
                .flatMap { URL(string: $0) }
#if DEBUG
            self.baseURL = envURL ?? URL(string: "http://localhost:8080")!
            self.isUnconfigured = false
#else
            if let url = envURL {
                self.baseURL = url
                self.isUnconfigured = false
            } else {
                // No backend configured in Release — skip network entirely.
                self.baseURL = URL(string: "about:blank")!
                self.isUnconfigured = true
            }
#endif
        }
    }

    /// Fetches the backend solo-score for `experienceId`.
    /// - Returns: A `SoloScore` built from aggregated review dimensions, or the provided `fallback`.
    /// - Throws: Only re-throws if `fallback` is nil; otherwise swallows errors and returns fallback.
    func fetchSoloScore(experienceId: String, fallback: SoloScore? = nil) async throws -> SoloScore {
        // In Release builds with no SOLO_API_BASE_URL, avoid a 30-second timeout to localhost.
        if isUnconfigured {
            if let fb = fallback { return fb }
            throw ReviewsServiceError.notFound(experienceId)
        }

        let url = baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("experiences")
            .appendingPathComponent(experienceId)
            .appendingPathComponent("solo-score")

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                throw ReviewsServiceError.unexpectedResponse
            }
            if http.statusCode == 404 {
                if let fb = fallback { return fb }
                throw ReviewsServiceError.notFound(experienceId)
            }
            guard http.statusCode == 200 else {
                throw ReviewsServiceError.serverError(http.statusCode)
            }
            let decoded = try JSONDecoder().decode(SoloScoreResponse.self, from: data)
            return soloScore(from: decoded, fallback: fallback)
        } catch let error as ReviewsServiceError {
            throw error
        } catch {
#if DEBUG
            print("[ReviewsService] fetchSoloScore failed for \(experienceId): \(error)")
#endif
            if let fb = fallback { return fb }
            throw error
        }
    }

    private func soloScore(from resp: SoloScoreResponse, fallback: SoloScore?) -> SoloScore {
        let d = resp.dimensions
        let breakdown = fallback?.breakdown ?? SoloScore.Breakdown(
            seatingFriendly: d.seating,
            soloPatronRatio: d.seating,
            staffPressure: d.staff,
            soloPortioning: d.seating,
            ambianceFit: (d.noise + d.lighting) / 2.0,
            safety: d.safety
        )
        let overall = [d.wifi, d.noise, d.seating, d.staff, d.lighting, d.safety]
            .reduce(0, +) / 6.0
        return SoloScore(
            overall: overall,
            breakdown: breakdown,
            hint: fallback?.hint,
            basedOnCount: resp.sample_count
        )
    }
}

// MARK: - Error type

enum ReviewsServiceError: Error, LocalizedError {
    case notFound(String)
    case serverError(Int)
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .notFound(let id): return "No solo-score data for experience \(id)"
        case .serverError(let code): return "Server error \(code)"
        case .unexpectedResponse: return "Unexpected response from reviews API"
        }
    }
}
