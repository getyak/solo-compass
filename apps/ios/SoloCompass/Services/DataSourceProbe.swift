import Foundation
import CoreLocation
import os

// MARK: - DataSourceProbe
//
// Live connectivity check for each base POI provider, driven from the Developer
// Options panel ("Test connection"). Each probe issues ONE minimal real request
// against the same endpoint the explore pipeline uses, classifies the response,
// and reports back an ok/failed verdict, a human-readable message, and the
// round-trip latency — so a tester can tell "key wrong" from "quota hit" from
// "network down" without reading Console logs.
//
// Probes are deliberately tiny (radius ≤ 1 km, one page, one result) so they
// cost the smallest possible slice of any provider quota. Amap's in-memory ToS
// compliance is unaffected: probe results are shown once and never persisted.

/// One-shot connectivity checker for `DataSourceKind`.
///
/// `@MainActor` because `AmapPOIService`'s `buildURL` / `infocodeHint` helpers
/// are main-actor-isolated (the service itself is `@MainActor`). The network
/// wait is `await`-suspended, so this never blocks the UI thread despite the
/// isolation.
@MainActor
public enum DataSourceProbe {

    private static let logger = Logger(subsystem: "com.solocompass", category: "DataSourceProbe")

    /// Outcome of a single probe.
    public struct Result: Sendable, Equatable {
        public let ok: Bool
        /// Already-localized, tester-facing one-liner (e.g. "OK · 42 places" or
        /// "Key rejected (10001)").
        public let message: String
        /// Round-trip milliseconds, when a request actually went out.
        public let latencyMs: Int?

        public init(ok: Bool, message: String, latencyMs: Int?) {
            self.ok = ok
            self.message = message
            self.latencyMs = latencyMs
        }
    }

    // Fixed probe centers: a point known to be inside each provider's coverage.
    private static let amapProbeCenter = CLLocationCoordinate2D(latitude: 39.9087, longitude: 116.3975) // Tiananmen, Beijing
    private static let openMapProbeCenter = CLLocationCoordinate2D(latitude: 51.5079, longitude: -0.1281) // Trafalgar Square, London

    /// Probe a single provider. Never throws — every failure mode is folded into
    /// a `Result(ok: false, ...)` so the caller only has to render it.
    public static func probe(_ kind: DataSourceKind, session: URLSession = .shared) async -> Result {
        switch kind {
        case .amap:    return await probeAmap(session: session)
        case .openMap: return await probeOpenMap(session: session)
        }
    }

    // MARK: - Amap

    private static func probeAmap(session: URLSession) async -> Result {
        let key = Secrets.resolvedAmapKey
        guard !key.isEmpty else {
            return Result(
                ok: false,
                message: NSLocalizedString("dev.dataSource.probe.noKey", comment: "No key configured"),
                latencyMs: nil
            )
        }

        let gcj = CoordinateConverter.wgs84ToGcj02(amapProbeCenter)
        guard let url = AmapPOIService.buildURL(
            key: key,
            gcjCenter: gcj,
            radiusMeters: 1_000,
            category: nil,
            pageSize: 1,
            pageNum: 1
        ) else {
            return Result(ok: false, message: badRequestMessage(), latencyMs: nil)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("SoloCompass-iOS/1.0", forHTTPHeaderField: "User-Agent")

        let start = Date()
        do {
            let (data, response) = try await session.data(for: request)
            let latency = elapsedMs(since: start)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                return Result(ok: false, message: httpFailureMessage(status), latencyMs: latency)
            }
            let decoded = try JSONDecoder().decode(AmapPOIService.AroundResponse.self, from: data)
            if decoded.status == "1" {
                let count = decoded.pois?.count ?? 0
                return Result(ok: true, message: okMessage(count: count), latencyMs: latency)
            }
            // Business error (bad key / quota / signature): surface the mapped hint.
            let hint = AmapPOIService.infocodeHint(decoded.infocode)
            return Result(ok: false, message: hint, latencyMs: latency)
        } catch {
            logger.error("amap probe failed: \(String(describing: error), privacy: .public)")
            return Result(ok: false, message: networkFailureMessage(error), latencyMs: elapsedMs(since: start))
        }
    }

    // MARK: - OpenMap / Overpass

    private static func probeOpenMap(session: URLSession) async -> Result {
        guard let endpoint = URL(string: "https://overpass-api.de/api/interpreter") else {
            return Result(ok: false, message: badRequestMessage(), latencyMs: nil)
        }
        let query = OverpassService.buildQuery(
            lat: openMapProbeCenter.latitude,
            lon: openMapProbeCenter.longitude,
            radiusMeters: 500,
            limit: 1,
            category: nil
        )
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("SoloCompass-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        request.httpBody = "data=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")".data(using: .utf8)

        let start = Date()
        do {
            let (data, response) = try await session.data(for: request)
            let latency = elapsedMs(since: start)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                return Result(ok: false, message: httpFailureMessage(status), latencyMs: latency)
            }
            let pois = try OverpassService.decodePOIs(from: data)
            return Result(ok: true, message: okMessage(count: pois.count), latencyMs: latency)
        } catch {
            logger.error("openMap probe failed: \(String(describing: error), privacy: .public)")
            return Result(ok: false, message: networkFailureMessage(error), latencyMs: elapsedMs(since: start))
        }
    }

    // MARK: - Messages

    private static func okMessage(count: Int) -> String {
        let fmt = NSLocalizedString("dev.dataSource.probe.ok", comment: "Probe OK with count")
        return String(format: fmt, count)
    }

    private static func httpFailureMessage(_ status: Int) -> String {
        let fmt = NSLocalizedString("dev.dataSource.probe.httpFailed", comment: "HTTP failed status")
        return String(format: fmt, status)
    }

    private static func networkFailureMessage(_ error: Error) -> String {
        let fmt = NSLocalizedString("dev.dataSource.probe.networkFailed", comment: "Network failed")
        let reason = (error as? URLError)?.localizedDescription ?? error.localizedDescription
        return String(format: fmt, reason)
    }

    private static func badRequestMessage() -> String {
        NSLocalizedString("dev.dataSource.probe.badRequest", comment: "Could not build request")
    }

    private static func elapsedMs(since start: Date) -> Int {
        Int((Date().timeIntervalSince(start) * 1_000).rounded())
    }
}
