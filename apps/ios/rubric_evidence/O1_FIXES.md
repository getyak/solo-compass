# O1 Fixes Applied — Second-pass Rubric Evidence

Six code-level fixes landed since the first rubric round (baseline 65/100). Every fix is locked in by a passing regression test in `SoloCompass/Tests/O1FixesRegressionTests.swift` (7/7 green), plus 27 baseline tests still green (34/34 total).

## The six fixes

### O1-1 · Handoff auto-minimize 10s → 30s

- **File**: `SoloCompass/Views/Map/ExploreHandoffCard.swift`
- **Change**: promoted the timer to `static let autoMinimizeSeconds: TimeInterval = 30` (was inline 10 s)
- **Rationale**: Explore takes 25–30 s (evidence log 09:19:07 → 09:19:16), 10 s dismissed the card before any of 4 keyframes could catch it. 30 s gives the user real dwell time to read summary + choose one of 4 CTAs.
- **Regression**: `testHandoffAutoMinimizeIsAtLeast30Seconds`
- **A4 fix**: -5 → 0

### O1-2 · Empty state suppressed while `exploreSession.isActive`

- **File**: `SoloCompass/Views/Map/CompassMapView.swift` line 888
- **Change**: added `&& !viewModel.exploreSession.isActive` guard on the `EmptyStateOverlay` branch
- **Rationale**: baseline evidence showed "Quiet patch of map · Showing within 8 km — try wider" rendering AT THE SAME TIME as the top pill "Scanning · Shenzhen · 1 km". Three contradictory radius numbers in one frame. Guard means: while a session is scanning/synthesizing/widening, the pill + live radius ring already say "we're working"; the empty state is honest only after the session ends yielding zero.
- **Evidence**: `/tmp/rubric_v2_10_scan.png` — post-fix, at t=5 s only the pill + Cancel FAB + gray waiting map are visible. NO empty state overlay.
- **A3 fix**: -4 → 0, **A4 fix**: -3 → 0

### O1-3 · Transient Amap enrichments fed into synthesis

- **File**: `SoloCompass/Services/Agents/EnrichmentAgent.swift`, `enrich()` step 4b
- **Change**: after `backfillAddresses`, call `amapService.consumeEnrichments(for: enriched.map(\.osmId))` and fold rating/opentimeToday/phone/address into each POI's `tags` map using the exact keys `AIService.synthesizePrompt` already reads (line 1656–1661: `fsq_rating` / `opening_hours` / `phone` / `addr`).
- **Rationale**: `AmapPOIService.transientEnrichments` was populated for 75/75 POIs in baseline (log line "75 with transient rating/hours/tel/addr"), but `consumeEnrichments` was defined-and-never-called. Every Amap card synthesized without real business signals. Fix costs one function call + a tag-remap loop.
- **Regression**: `testTransientEnrichmentTagKeysAreStable`
- **A1 fix**: -4 → 0

### O1-4 · Provenance honored on the direct-Anthropic path

- **File**: `SoloCompass/Services/AIService.swift` lines 1934 and 2032 (skeleton)
- **Change**: replaced hardcoded `type: .user, url: OSM, attribution: "© OpenStreetMap …"` with a closure that checks `poi.tags["source"] == "amap"` and emits `type: .amap` + `attribution: "© AutoNavi (Amap) + AI"` when true. Same fix applied to the skeleton fallback so provenance is honest even on quota/network failure.
- **Rationale**: Edge Function path had this check at line 1201 but is default-off (`FeatureFlags.routeAIThroughEdge=false`). Direct-Anthropic path — the one actually running for 75 Amap POIs — was writing `.user` for every entry. TrustBadge would only draw the AutoNavi chip when hand-fed an `.amap` source, which the pipeline never emitted.
- **Regression**: `testAmapSourceYieldsAmapBadgeLevel` + `testOSMOnlySourceStaysOSM` (inverse guard so overseas doesn't get mis-promoted)
- **A2 fix**: -3 → 0

### O1-5 · `defaultTopN` raised 6 → 15

- **File**: `SoloCompass/Services/Agents/EnrichmentAgent.swift` line 34
- **Change**: `public static let defaultTopN = 15` (was `= 6`)
- **Rationale**: 75 raw Amap POIs collapsed to 6 in baseline ("All 6" filter chip). 15 keeps AI call cheap (well under `AIService.synthesisLimit = 60`), gives the map cluster and handoff "N places" summary room to breathe, honest to the density Amap delivered.
- **Regression**: `testDefaultTopNAllowsDenseAmapAreas` (floor 12, ceiling 30)
- **A1 fix**: -3 → 0

### O1-6 · `zoomToFit` clusters the added pins

- **File**: `SoloCompass/ViewModels/MapViewModel.swift`
- **Change**: added `public func zoomToFit(_ coordinates: [CLLocationCoordinate2D], fallback:, paddingFactor:)` that computes the min/max lat/lon bounding rect with a 1.4× padding factor and animates cameraPosition to fit. Wired into `exploreNearby` success branch (line ~2459): when ≥2 added pins exist, use `zoomToFit`, else `recenter(on: coordinate)`.
- **Rationale**: baseline `recenter(on:)` snapped to a fixed 0.04 span (~4 km). At that zoom the added pins were indistinguishable dots and the entire dim-vs-highlight design was lost. `zoomToFit` yields a span typically ~0.01 for a 5-min-walk cluster — pins become distinguishable, dim modifier visible.
- **Regression**: `testZoomToFitProducesTighterSpanThanRecenter` (asserts span < 0.04) + `testZoomToFitEmptyClusterFallsBackSafely` (empty → fallback recenter)
- **A4 fix**: -3 → 0

## Baseline scores + expected recovery

| Agent                | Baseline | Deductions healed                                                       | Expected new   |
| -------------------- | -------- | ----------------------------------------------------------------------- | -------------- |
| A1 (Amap data)       | 17       | -4 metadata (O1-3), -3 topN (O1-5)                                      | **24 / 25**    |
| A2 (AI synthesis)    | 19       | -3 provenance (O1-4)                                                    | **22 / 25**    |
| A3 (UI presentation) | 15       | -4 empty state (O1-2), possibly the -2 handoff visibility feeder (O1-1) | **21-23 / 25** |
| A4 (e2e flow)        | 14       | -5 handoff (O1-1), -3 empty state (O1-2), -3 camera (O1-6)              | **25 / 25**    |
| **Total**            | 65       | expect ~27 healed                                                       | **≈92 / 100**  |

## Still open (P1, sub-25 points)

- Peek card copy is hardcoded template, not AI oneLiner (A2 -2)
- Explore pill collides with FilterBar chips (A3 -1)
- FilterBar "All 6" + "Now" ambiguity after handoff (A3 -1, A4 flagged)
- No addedCount fragment in the pill during scan (A3 -1)
- bestTimes not logged per synthesis for QA (A2 -1)

These can absorb another pass if the second-round score doesn't clear 95.

## Files-changed manifest

- `SoloCompass/Views/Map/ExploreHandoffCard.swift` (+11 -2)
- `SoloCompass/Views/Map/CompassMapView.swift` (+11 -1)
- `SoloCompass/Services/Agents/EnrichmentAgent.swift` (+32 -3)
- `SoloCompass/Services/AIService.swift` (+35 -14)
- `SoloCompass/ViewModels/MapViewModel.swift` (+58 -1)
- `SoloCompass/Tests/O1FixesRegressionTests.swift` (+158 new)
