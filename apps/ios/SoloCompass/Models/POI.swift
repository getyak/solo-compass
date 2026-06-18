import Foundation

// MARK: - POI

/// Top-level canonical Point-of-Interest type for the iOS app.
///
/// This is a typealias for `OverpassService.POI` so 91 existing reference
/// sites (AmapPOIService, MapKitPOIService, FoursquareService, AIService,
/// MapViewModel, tests) keep compiling unchanged. New call sites and new
/// services should prefer the bare `POI` name — the eventual goal is to
/// migrate the struct definition here and drop the `OverpassService.POI`
/// qualifier (covered under audit H4).
///
/// Note: this is a typealias rather than a wrapper because the struct holds
/// the canonical shape returned by all four POI sources (Overpass, Amap,
/// MapKit, Foursquare) — none of them needs different fields, and adding a
/// wrapper layer here would have to be re-extracted at every call site.
public typealias POI = OverpassService.POI
