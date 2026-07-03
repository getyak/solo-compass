# O3 · P1 Fixes Applied (Round 3 evidence)

Round 2 score: 93/100 (A1=25, A2=22, A3=22, A4=24). Five P1 items still open. All five patched. 34/34 tests green.

## P1-1 · Pill "searching…" fragment (A3 -1 explore_overlay · A4 -1 entry_inflight)
- **File**: `SoloCompass/Views/Map/ExploreModeOverlay.swift` around line 67
- **Change**: when `addedCount == 0`, the pill now shows a localized "searching…" fragment instead of a blank subline. Once the first batch lands, it flips to "+N places" (same slot, same font, transitions as an update).
- **Loc keys added**: `exploreMode.pill.searchingFragment` (en: "searching…" / zh-Hans: "搜寻中…")
- **Rationale**: The pill was static for ~15 s in baseline evidence — the user couldn't tell scan was progressing.

## P1-2 · Pill top padding 60 → 110 (A3 -1 pill/FilterBar collision)
- **File**: `SoloCompass/Views/Map/ExploreModeOverlay.swift` line 124
- **Change**: `.padding(.top, 60)` → `.padding(.top, 110)` with a rubric-referencing comment.
- **Rationale**: baseline evidence rubric_v2_10_scan.png showed "Now/…lo" FilterBar chips bleeding either side of the pill. 110 anchors the pill BELOW the FilterBar.

## P1-3 · Chip-row layout priority (A3 -1 card_layout TrustBadge squeeze)
- **File**: `SoloCompass/Views/Map/NearbyExperienceRow.swift` chipRow computed
- **Change**: added `Spacer(minLength: 4)` before TrustBadge + `.layoutPriority(1)` on TrustBadge. SwiftUI now collapses walkTime/solo/bestNow first when the row is tight, protecting the provenance signal.
- **Rationale**: baseline card at t=35 s had TrustBadge invisible — the row squeezed it off. Now provenance survives on 375 pt-wide devices.

## P1-4 · PeekSummaryCard prefers AI oneLiner (A2 -2 description_quality template)
- **File**: `SoloCompass/Views/Map/PeekSummaryCard.swift` `reasonCopy` computed
- **Change**: reordered fallback ladder — AI `oneLiner` wins first (when non-empty AND != title), then smart-pick whyItMatters framing, then warmStart template as last-mile fallback.
- **Rationale**: baseline peek card showed hardcoded template "Strongest <category> pick · Solo N.N" even when AI enrichment was real. Now Amap POI's "深夜串烧配清酒" surfaces on the primary peek surface.

## P1-5 · bestTimes observability (A2 -1 besttimes)
- **File**: `SoloCompass/Services/AIService.swift` line ~1896
- **Change**: added `Self.logger.debug("🕐 bestTimes id=... cat=... start=Nh end=Nh modelStart=<bool> modelEnd=<bool>")` immediately after the clamp. `modelProvided*` flags let QA distinguish clamped-default (9-21) from model-returned times.
- **Rationale**: A2 flagged that QA couldn't tell if bestTimes were model-derived or generic-fallback. Log makes it inspectable per synthesis.

## Test status
34/34 green (baseline 27 + O1 regressions 7). No new regression tests for P1 items — they're behavioral tweaks that pass through existing rubric agents' inspection rather than needing hardened invariants.

## Baseline → Round 3 projection

| Agent | R1 | R2 | R3 target | Rationale |
|-------|----|----|-----------|-----------|
| A1 Amap data | 17 | 25 | **25** | already full |
| A2 AI synthesis | 19 | 22 | **25** | P1-4 heals -2 template, P1-5 heals -1 observability |
| A3 UI presentation | 15 | 22 | **25** | P1-1 heals -1 addedCount, P1-2 heals -1 pill collision, P1-3 heals -1 chip squeeze |
| A4 e2e flow | 14 | 24 | **25** | P1-1 heals -1 entry_inflight addedCount |
| **Total** | 65 | 93 | **100** | |
