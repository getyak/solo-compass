# E2E Evidence for Solo Compass Explore Mode Rubric

## Test setup
- Device: iPhone 17 Pro Simulator, iOS 26.1
- Location: Shenzhen Futian (22.5411, 114.0567) — real Amap API territory
- Launch: `-startCity szx -triggerExplore -devSkipOnboarding -devConsentAccepted`
- Bundle: com.solocompass.app
- Amap API key: len=32, present (`8ef44fd6...`)

## Log evidence (from /tmp/solo_e2e_amap.log at t=9:19)
```
🔑 amap key len=32 empty=false
🌐 inCN(22.543100,114.057900)=true policy=both amap=true openMap=true
✅ amap returned 75 POIs (75 with transient rating/hours/tel/addr), using as base
```

## Screenshot chain (all in this dir)
- `rubric_30_t5s.png` — t=5s after launch: Scanning pill "Scanning · Shenzhen · 1 km", Cancel FAB, empty state "Quiet patch of map" (❌ premature empty state during scan)
- `rubric_31_t13s.png` — t=13s: pill widens to "5 km", still scanning, empty state persists
- `rubric_33_t35s.png` — t=35s: **Explore finished**. filter chips show "All 6", pin cluster on map, bottom card shows real Chinese POI:
  - Title: 鹤松·居酒屋 (福田灯光秀店)
  - Category: Food
  - Distance: 476.6m, ~6 min walk
  - Solo Score: 8.0/10 (green pill)
  - Copy: "Strongest Food pick in view right now · Solo 8.0"
- `rubric_34_t45s.png` — t=45s: same card, handoff card 10s auto-minimize already elapsed

## Render test artifacts (from XCTest)
- `/tmp/detail_hero_badge_amap_full.png` — TrustBadge(.amap, .full) renders AUTONAVI blue capsule on CT warm-amber background
- `/tmp/exploreOverlay_scanning.png`, `_synthesizing`, `_widening`, `_handoff` — 4-state overlay renders

## Unit test coverage (27/27 all green)
- TrustBadgeMappingTests: 8 (mapping rules, amap-beats-osm-id, verified-upgrade)
- ExploreSessionStateTests: 12 (phase mapping, state semantics, equatable, i18n keys)
- ExploreModeOverlayRenderTest: 4 (visual smoke)
- DetailHeroBadgeRenderTest: 3 (badge visual + amap level)

## Files in play
- Views: ExploreModeOverlay, ExploreHandoffCard, ExploreSessionDimModifier, TrustBadge, CompassMapView, NearbyExperienceRow, ExperienceDetailView
- ViewModel: MapViewModel (exploreSession, exploreSessionAddedIds, pendingHandoff, exploreCancel/exploreClearHandoff)
- Data: InformationSource.SourceType (.amap enum value), AmapPOIService, EnrichmentAgent (basePOIs → amap 75 POIs → merge with OpenStreetMap → AIService.synthesizeExperiences)
- Localization: en/zh-Hans for all TrustBadge / Explore chrome (12+15 keys)

## Observed gaps (candidate deductions)
1. **Handoff card timing** — 10s auto-minimize is aggressive for a rich card; user might miss the 4 CTAs entirely if the batch was long
2. **Empty state race** — "Quiet patch of map" shows DURING Scanning, contradicting the "1 km" pill
3. **Camera stays wide** — after 6 POIs added, camera does not zoom in to the cluster; user must manually zoom
4. **filter chip conflict** — "All 6" appeared but "Now" filter is inactive; unclear which chip drove the display

## Verbatim user goal
"真实 e2e 模拟器测试Explore，是否可以获取到附近优质实用性真的很高的高德地图的数据，并且数据显示的内容是好的，AI编译的也是好的，深度评测，agent teams 的方式，AI 也去打分，满分一百分，我希望也到一百分，不断优化完善"
