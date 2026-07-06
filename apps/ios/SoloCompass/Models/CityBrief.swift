import Foundation

// MARK: - City OS v2 · city-brief value types (PRD solo-city-os-v2 §4–5)
//
// Server truth lives in Supabase `city_kits` / `city_events` (public-read RLS,
// written only by the compile-city-brief pipeline). These value types decode
// the server row shape directly — CodingKeys below ARE the column names — so
// the same decoder handles both the bundled seed JSON and the REST payload.

/// The traveler's relationship with a city: currently there, planning a visit,
/// or looking back after leaving. Switching mode switches the whole aggregation
/// context (PRD §4.1) — it is not a filter.
public enum CityMode: String, Codable, Sendable, CaseIterable {
    case live
    case plan
    case recall
}

/// A structured action attached to a landing-kit row, interpreted by the
/// client (e.g. schedule a visa-expiry reminder, render tappable emergency
/// numbers). Mirrors the `action` jsonb column of `city_kits`.
public struct CityKitAction: Codable, Equatable, Sendable {
    /// One dialable emergency contact, kept offline-usable (PRD §5.2).
    public struct EmergencyNumber: Codable, Equatable, Sendable {
        /// Display label, e.g. "警察".
        public let label: String
        /// Dialable number string, e.g. "191".
        public let number: String

        /// Creates an emergency contact entry.
        public init(label: String, number: String) {
            self.label = label
            self.number = number
        }
    }

    /// Action discriminator: `"visa_reminder"` or `"emergency_numbers"`.
    public let type: String
    /// Visa validity in days for `visa_reminder` actions (e.g. 30 for 落地签).
    public let visaDays: Int?
    /// Tax-residency threshold in days for `visa_reminder` actions (183).
    public let taxLineDays: Int?
    /// Dialable contacts for `emergency_numbers` actions.
    public let numbers: [EmergencyNumber]?

    enum CodingKeys: String, CodingKey {
        case type
        case visaDays = "visa_days"
        case taxLineDays = "tax_line_days"
        case numbers
    }

    /// Creates a kit-row action.
    public init(type: String, visaDays: Int? = nil, taxLineDays: Int? = nil, numbers: [EmergencyNumber]? = nil) {
        self.type = type
        self.visaDays = visaDays
        self.taxLineDays = taxLineDays
        self.numbers = numbers
    }
}

/// One row of the 落地包 landing kit: a curated, solo-lens-annotated essential
/// (connectivity / money / visa / safety) with verification provenance.
/// Decodes a `city_kits` server row (CodingKeys = column names).
public struct CityKitItem: Codable, Equatable, Sendable, Identifiable {
    /// The four kit sections. Raw values match the `city_kits.section`
    /// check constraint exactly — do not rename.
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case net
        case money
        case visa
        case safety

        /// SF Symbol used for the row icon.
        public var symbolName: String {
            switch self {
            case .net:    return "wifi"
            case .money:  return "dollarsign.circle"
            case .visa:   return "person.text.rectangle"
            case .safety: return "shield"
            }
        }
    }

    /// Stable identity: one row per (city, section).
    public var id: String { "\(cityCode).\(kind.rawValue)" }

    /// Lowercase city code, e.g. "vte" (DB convention; iOS canonical "VTE"
    /// is lowercased before queries).
    public let cityCode: String
    /// Which of the four kit sections this row is.
    public let kind: Kind
    /// Row title, e.g. "联网".
    public let name: String
    /// Main copy, e.g. "Airalo 老挝 eSIM · 或 Unitel 门店".
    public let main: String
    /// 独行透镜 one-liner — judgment applied to the sourced facts.
    public let lens: String?
    /// Server-declared health ("green"/"yellow"/"red"/"gray"). Advisory only;
    /// render via `CityBriefHealth.health(lastVerifiedAt:serverHealth:now:)`.
    public let serverHealth: String?
    /// When the pipeline (or a curator) last re-verified this row.
    public let lastVerifiedAt: Date?
    /// Optional deep link (Airalo / Wise / GeoSure …).
    public let linkURL: URL?
    /// Short label for the deep link, used in the "已为你打开 …" toast.
    public let linkLabel: String?
    /// Optional structured action (visa reminder, emergency numbers).
    public let action: CityKitAction?

    enum CodingKeys: String, CodingKey {
        case cityCode = "city_code"
        case kind = "section"
        case name
        case main = "body"
        case lens = "lens_line"
        case serverHealth = "health"
        case lastVerifiedAt = "last_verified_at"
        case linkURL = "link_url"
        case linkLabel = "link_label"
        case action
    }

    /// Creates a kit row (primarily for tests and previews).
    public init(
        cityCode: String,
        kind: Kind,
        name: String,
        main: String,
        lens: String? = nil,
        serverHealth: String? = nil,
        lastVerifiedAt: Date? = nil,
        linkURL: URL? = nil,
        linkLabel: String? = nil,
        action: CityKitAction? = nil
    ) {
        self.cityCode = cityCode
        self.kind = kind
        self.name = name
        self.main = main
        self.lens = lens
        self.serverHealth = serverHealth
        self.lastVerifiedAt = lastVerifiedAt
        self.linkURL = linkURL
        self.linkLabel = linkLabel
        self.action = action
    }
}

/// One 在地 local happening — event, festival, market, or a travel-affecting
/// notice — with a solo-friendliness judgment and honest provenance.
/// Decodes a `city_events` server row (CodingKeys = column names).
public struct CityEvent: Codable, Equatable, Sendable, Identifiable {
    /// Deterministic server id: `evt_{city}_{slug}_{yyyymmdd}`.
    public let id: String
    /// Lowercase city code, e.g. "vte".
    public let cityCode: String
    /// Event name as sourced, e.g. "那伽火球节前导市集".
    public let name: String
    /// Display time string in the traveler's terms, e.g. "周五傍晚".
    public let whenLabel: String
    /// Event start, when the source stated one.
    public let startsAt: Date?
    /// Event end — drives client-side expiry (`CityBriefHealth.isExpired`).
    public let endsAt: Date?
    /// Solo-friendliness 0–10 (SoloScore rubric applied to the event);
    /// nil for notices.
    public let soloScore: Double?
    /// One-line "一个人去合不合适" judgment.
    public let soloNote: String?
    /// Server-declared health; advisory only (see `CityBriefHealth`).
    public let serverHealth: String?
    /// Provenance label, e.g. "主办方页面 · 7月3日" or "人工策展".
    public let seenLabel: String?
    /// Map latitude; nil for events without a fixed venue.
    public let lat: Double?
    /// Map longitude; nil for events without a fixed venue.
    public let lng: Double?
    /// Limited-time chip text, e.g. "仅本周".
    public let limitedLabel: String?
    /// Category slug ("culture"/"market"/…/"notice").
    public let category: String?
    /// The source page this item was curated from (anti-hallucination invariant).
    public let sourceURL: URL?

    /// True for travel-affecting notices (road closures, strikes) — rendered
    /// in the warning treatment, never scored for solo-friendliness.
    public var isNotice: Bool { category == "notice" }

    enum CodingKeys: String, CodingKey {
        case id
        case cityCode = "city_code"
        case name
        case whenLabel = "when_label"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case soloScore = "solo_score"
        case soloNote = "solo_note"
        case serverHealth = "health"
        case seenLabel = "seen_label"
        case lat
        case lng
        case limitedLabel = "limited_label"
        case category
        case sourceURL = "source_url"
    }

    /// Creates an event (primarily for tests and previews).
    public init(
        id: String,
        cityCode: String,
        name: String,
        whenLabel: String,
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        soloScore: Double? = nil,
        soloNote: String? = nil,
        serverHealth: String? = nil,
        seenLabel: String? = nil,
        lat: Double? = nil,
        lng: Double? = nil,
        limitedLabel: String? = nil,
        category: String? = nil,
        sourceURL: URL? = nil
    ) {
        self.id = id
        self.cityCode = cityCode
        self.name = name
        self.whenLabel = whenLabel
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.soloScore = soloScore
        self.soloNote = soloNote
        self.serverHealth = serverHealth
        self.seenLabel = seenLabel
        self.lat = lat
        self.lng = lng
        self.limitedLabel = limitedLabel
        self.category = category
        self.sourceURL = sourceURL
    }
}

// MARK: - Pure health / expiry / daily-pick logic

/// Client-side freshness rules for city-brief content. Pure and clock-injected
/// so every threshold is unit-testable (mirrors `Confidence.health`, which the
/// PRD's "信心贯穿一切" rule extends to kit rows and events).
public enum CityBriefHealth {
    /// Combines server-declared health with local age decay. The server value
    /// is a floor that can only be *downgraded* by staleness, never upgraded:
    /// - no `lastVerifiedAt` → `.questioned` (unverifiable is dishonest to green-light)
    /// - older than 60 days → `.mayBeGone` (same cliff as `Confidence.health`)
    /// - fresher than 30 days → the server floor (green→healthy, yellow→fading,
    ///   red→questioned, gray/unknown→fading)
    /// - 30–60 days → capped at `.fading` (except red, which stays `.questioned`)
    public static func health(lastVerifiedAt: Date?, serverHealth: String?, now: Date = Date()) -> HealthStatus {
        guard let verified = lastVerifiedAt else { return .questioned }
        let ageDays = now.timeIntervalSince(verified) / 86_400
        if ageDays > 60 { return .mayBeGone }
        let floor: HealthStatus
        switch serverHealth {
        case "green":  floor = .healthy
        case "yellow": floor = .fading
        case "red":    floor = .questioned
        default:       floor = .fading
        }
        if ageDays < 30 { return floor }
        return floor == .questioned ? .questioned : .fading
    }

    /// Whether an event should no longer be shown. Past `endsAt` → expired;
    /// with no `endsAt`, falls back to `startsAt` + 1 day; with neither, the
    /// event is kept (the server schema makes `ends_at` NOT NULL, so this is
    /// belt-and-braces for hand-written fixtures).
    public static func isExpired(_ event: CityEvent, now: Date = Date()) -> Bool {
        if let ends = event.endsAt { return ends < now }
        if let starts = event.startsAt { return starts.addingTimeInterval(86_400) < now }
        return false
    }

    /// The deterministic 今日城市签 pick: among unexpired, non-notice events,
    /// prefer the highest solo score; break ties with a stable FNV-1a hash of
    /// `(event.id + local day key)` so the pick is identical all day and across
    /// launches (Swift's `hashValue` is process-seeded and unusable here).
    public static func dailyPick(from events: [CityEvent], now: Date = Date(), calendar: Calendar = .current) -> CityEvent? {
        let candidates = events.filter { !isExpired($0, now: now) && !$0.isNotice }
        guard !candidates.isEmpty else { return nil }
        let comps = calendar.dateComponents([.year, .month, .day], from: now)
        let dayKey = String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
        return candidates.max { lhs, rhs in
            let lhsScore = lhs.soloScore ?? 0
            let rhsScore = rhs.soloScore ?? 0
            if lhsScore != rhsScore { return lhsScore < rhsScore }
            return stableHash(lhs.id + dayKey) < stableHash(rhs.id + dayKey)
        }
    }

    /// FNV-1a 64-bit — deterministic across processes, unlike `Hasher`.
    static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}
