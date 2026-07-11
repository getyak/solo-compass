import Foundation
import Observation
import SwiftData
import os

/// City OS v2 content plane (PRD §5.2–5.3): loads the 落地包 kit rows and
/// 在地 events for the selected city.
///
/// Read path is strictly cache-first and offline-honest:
/// 1. publish the SwiftData cache immediately (`CityBriefCacheRecord`),
/// 2. if the cache is stale (>6h) and backend sync is on, refresh from the
///    public-read `city_kits` / `city_events` tables and republish,
/// 3. with neither cache nor network, fall back to the bundled Vientiane
///    seed so DEBUG/simulator and fresh installs still render every surface.
///
/// Any failed or short-circuited fetch (offline, `FF_BACKEND_SYNC` off →
/// empty `Data`, not signed in) means "no update" — it must NEVER clear the
/// cache. Freshness honesty comes from `CityBriefHealth`, not from hiding
/// content.
@MainActor
@Observable
public final class CityBriefService {
    private static let logger = Logger(subsystem: "com.solocompass", category: "CityBriefService")
    private static let refreshTTL: TimeInterval = 6 * 3_600

    /// Kit rows for the currently loaded city (empty until `load` runs).
    public private(set) var kit: [CityKitItem] = []
    /// All cached events for the currently loaded city, including ones that
    /// have expired since fetch — render through `activeEvents(now:)`.
    public private(set) var events: [CityEvent] = []
    /// Lowercase code of the currently loaded city.
    public private(set) var loadedCityCode: String?

    private let modelContext: ModelContext
    private let supabase: SupabaseClient
    private let seedLoader: (String) -> Data?

    /// Creates the service.
    /// - Parameters:
    ///   - container: SwiftData container (tests pass `makeInMemory()`).
    ///   - supabase: REST client (defaults to the shared singleton).
    ///   - seedLoader: bundled-seed lookup by lowercase city code; the default
    ///     reads `seed_city_brief_<code>.json` from the main bundle.
    public init(
        container: ModelContainer = SoloCompassModelContainer.shared,
        supabase: SupabaseClient = .shared,
        seedLoader: ((String) -> Data?)? = nil
    ) {
        self.modelContext = ModelContext(container)
        self.supabase = supabase
        self.seedLoader = seedLoader ?? { code in
            guard let url = Bundle.main.url(forResource: "seed_city_brief_\(code)", withExtension: "json") else {
                return nil
            }
            return try? Data(contentsOf: url)
        }
    }

    /// Whether any kit content exists for the city (cache or bundled seed) —
    /// the auto-surface guard checks this before pushing the sheet.
    public func hasKit(for cityCode: String) -> Bool {
        let code = CityOSStore.normalizedCityKey(cityCode)
        if loadedCityCode == code { return !kit.isEmpty }
        if let record = cachedRecord(for: code) {
            return !((try? Self.decoder.decode([CityKitItem].self, from: record.kitJSON))?.isEmpty ?? true)
        }
        return seedLoader(code) != nil
    }

    /// Events that are still current (unexpired), for map markers and sheets.
    public func activeEvents(now: Date = Date()) -> [CityEvent] {
        events.filter { !CityBriefHealth.isExpired($0, now: now) }
    }

    /// The deterministic 今日城市签 pick for the loaded city.
    public func dailyPick(now: Date = Date()) -> CityEvent? {
        CityBriefHealth.dailyPick(from: events, now: now)
    }

    /// Loads content for a city: cache first, then a TTL-gated network
    /// refresh, then the bundled seed as last resort.
    public func load(cityCode: String, now: Date = Date()) async {
        let code = CityOSStore.normalizedCityKey(cityCode)
        loadedCityCode = code

        var cacheFetchedAt: Date?
        if let record = cachedRecord(for: code) {
            publish(kitJSON: record.kitJSON, eventsJSON: record.eventsJSON, cityCode: code)
            cacheFetchedAt = record.fetchedAt
        } else {
            kit = []
            events = []
        }

        let cacheIsFresh = cacheFetchedAt.map { now.timeIntervalSince($0) < Self.refreshTTL } ?? false
        if !cacheIsFresh {
            await refresh(code: code, now: now)
        }

        // Neither cache nor network produced anything → bundled seed.
        if kit.isEmpty && events.isEmpty, let seed = seedLoader(code) {
            applySeed(seed, cityCode: code)
        }
    }

    // MARK: - Network refresh

    private func refresh(code: String, now: Date) async {
        let kitResult = await supabase.get(table: "city_kits", query: [
            URLQueryItem(name: "city_code", value: "eq.\(code)"),
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "section"),
        ])
        let nowISO = ISO8601DateFormatter().string(from: now)
        let eventsResult = await supabase.get(table: "city_events", query: [
            URLQueryItem(name: "city_code", value: "eq.\(code)"),
            URLQueryItem(name: "status", value: "eq.active"),
            URLQueryItem(name: "ends_at", value: "gt.\(nowISO)"),
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "starts_at.asc.nullsfirst"),
        ])

        guard case let .success(kitData) = kitResult,
              case let .success(eventsData) = eventsResult,
              !kitData.isEmpty || !eventsData.isEmpty else {
            // Offline / flag-off short-circuit (empty Data) / not signed in:
            // no update — keep whatever the cache or seed already gave us.
            return
        }

        // Decode off the main actor. `CityBriefService` is `@MainActor`, so a
        // plain `Self.decoder.decode(...)` here ran on the main thread — and
        // `refresh` fires on every city switch, a high-frequency interaction.
        // Both result types are `Sendable` and `Self.decoder` is an immutable
        // static, so the decode is safe to hop to a detached task.
        async let kitDecode = Self.decode([CityKitItem].self, from: kitData)
        async let eventsDecode = Self.decode([CityEvent].self, from: eventsData)
        guard let freshKit = await kitDecode,
              let freshEvents = await eventsDecode else {
            Self.logger.error("city-brief decode failed for \(code, privacy: .public) — keeping cache")
            return
        }
        guard !freshKit.isEmpty || !freshEvents.isEmpty else { return }

        kit = freshKit
        events = freshEvents
        upsertCache(code: code, kitJSON: kitData, eventsJSON: eventsData, fetchedAt: now)
    }

    // MARK: - Cache / seed plumbing

    private func cachedRecord(for code: String) -> CityBriefCacheRecord? {
        let descriptor = FetchDescriptor<CityBriefCacheRecord>(
            predicate: #Predicate { $0.cityCode == code }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func upsertCache(code: String, kitJSON: Data, eventsJSON: Data, fetchedAt: Date) {
        if let record = cachedRecord(for: code) {
            record.kitJSON = kitJSON
            record.eventsJSON = eventsJSON
            record.fetchedAt = fetchedAt
        } else {
            modelContext.insert(CityBriefCacheRecord(cityCode: code, kitJSON: kitJSON, eventsJSON: eventsJSON, fetchedAt: fetchedAt))
        }
        do {
            try modelContext.save()
        } catch {
            Self.logger.error("city-brief cache save failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func publish(kitJSON: Data, eventsJSON: Data, cityCode: String) {
        kit = (try? Self.decoder.decode([CityKitItem].self, from: kitJSON)) ?? []
        events = (try? Self.decoder.decode([CityEvent].self, from: eventsJSON)) ?? []
    }

    /// Bundled seed format: `{"kit": [<city_kits rows>], "events": [<city_events rows>]}` —
    /// the exact server row shape, so one decoder serves both paths.
    private struct SeedPayload: Decodable {
        let kit: [CityKitItem]
        let events: [CityEvent]
    }

    private func applySeed(_ data: Data, cityCode: String) {
        guard let payload = try? Self.decoder.decode(SeedPayload.self, from: data) else {
            Self.logger.error("bundled city-brief seed decode failed for \(cityCode, privacy: .public)")
            return
        }
        kit = payload.kit
        events = payload.events
    }

    /// PostgREST timestamps come back as ISO 8601, sometimes with fractional
    /// seconds ("2026-07-06T12:34:56.789+00:00") — plain `.iso8601` rejects
    /// the fractional form, so try both.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = fractional.date(from: raw) ?? plain.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unparseable ISO 8601 date: \(raw)")
        }
        return decoder
    }()

    /// Decode `Data` into a `Sendable` array off the main actor using the shared
    /// fractional-seconds-tolerant `decoder`. Returns nil on failure so callers
    /// keep whatever the cache already published.
    nonisolated static func decode<T: Decodable & Sendable>(
        _ type: [T].Type,
        from data: Data
    ) async -> [T]? {
        await Task.detached(priority: .userInitiated) {
            try? decoder.decode(type, from: data)
        }.value
    }
}
