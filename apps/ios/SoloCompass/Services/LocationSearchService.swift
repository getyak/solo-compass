import MapKit

/// Forward-geocoding search wrapping MKLocalSearch.
/// All methods are `@MainActor` to keep MKLocalSearch on the main thread
/// (required by MapKit) and eliminate any sendability friction.
@MainActor
final class LocationSearchService {

    private var activeSearch: MKLocalSearch?

    /// Search for locations by natural-language query.
    /// Cancels any in-flight search before starting a new one.
    /// - Throws: MKLocalSearch errors (network, no results → empty array)
    func search(_ query: String) async throws -> [MKMapItem] {
        activeSearch?.cancel()

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]

        let search = MKLocalSearch(request: request)
        activeSearch = search

        do {
            let response = try await search.start()
            return response.mapItems
        } catch MKError.placemarkNotFound {
            return []
        } catch MKError.loadingThrottled {
            // Throttled → return empty rather than propagating; the UI will retry on next keystroke.
            return []
        }
        // Other errors (network, cancelled) propagate to the caller.
    }

    func cancelAll() {
        activeSearch?.cancel()
        activeSearch = nil
    }
}
