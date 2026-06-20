# System Improvement Plan — Data, Agent, Chat, End-to-End

**Status:** Draft · **Date:** 2026-06-17 · **Scope:** Full-stack architecture evolution
**Based on:** Deep research (22 sources, 109 claims extracted, 25 verified, 11 confirmed with adversarial 3-vote)

---

## Executive Summary

Solo Compass's multi-source POI pipeline, AI synthesis layer, and chat-map hybrid UX are architecturally sound but under-optimized. This document synthesizes adversarially-verified research findings into concrete improvement recommendations across four dimensions:

1. **Data Sources** — expand domestic/international coverage, activate dormant TS adapters
2. **Agent Pipeline** — hybrid LLM routing, structured intermediates, cost optimization
3. **Chat Interaction** — display-type-as-tool-parameter pattern, inline UI components
4. **End-to-End** — caching strategy, ranking evolution, observability

Each section states: current state → confirmed finding → concrete action → priority.

---

## 1. Data Sources: Domestic China + International

### 1.1 Current State

```
explore coordinate
  ├─ China mainland → AmapPOIService (GCJ-02, memory-only cache) + MapKit
  └─ Overseas       → OverpassService (OSM) + MapKit + Foursquare enrichment
```

- Amap v5/place/around: 75 results/query, 3 pages, 5000 free calls/month
- OSM/Overpass: unlimited but sparse in China (260 vs 2244 POIs for same radius)
- `packages/sources` (TS adapters: OSM, Wikivoyage, Google Places) — designed, never activated
- Foursquare enrichment: free tier often returns nil
- WebSearchEnrichmentSource: exists but disabled (cost)

### 1.2 Confirmed Finding: China Regulatory Constraints

> **Foreign investors are completely forbidden from CNDM (Compilation of Navigation Digital Maps) business.** Map data must be stored within China; outbound transfer requires MNR approval and likely CAC security assessment as "important data."
>
> — Zhong Lun Law Firm analysis, June 2025; corroborated by 2024 Negative List (effective Nov 1 2024)
> — Confidence: HIGH (6-0 adversarial vote)

**Validation of current architecture:**

- Amap-only branch for mainland China ✅ (legally mandatory, not optional)
- NSCache in-memory-only caching ✅ (Amap ToS §3.5/§4.12.2)
- AI-synthesized Experience objects persisted, raw Amap fields not ✅ (correct legal boundary)

**Action item:** Ensure Supabase backend NEVER stores raw Amap POI data server-side — only synthesized Experience objects. Add a CI lint or code review check for any SwiftData write path touching `source: "amap"` raw fields.

### 1.3 Improvement Roadmap

#### Phase 1: Activate TS Framework (Priority: HIGH)

The `packages/sources` framework is fully designed but never called in production (see `data-source-quality.md`). Activate it as the **batch enrichment pipeline** (server-side), complementing iOS's real-time pipeline:

```
TS pipeline (batch, server-side):
  getActiveAdapters() → [OsmAdapter, WikivoyageAdapter, GooglePlacesAdapter]
    → fetch(coordinates) → Candidate[]
    → AI structured extraction → Experience[]
    → Supabase upsert

iOS pipeline (real-time, client-side):
  explore tap → Overpass|Amap → Foursquare merge → AI synthesis → display + cache
```

**Key design tension:** TS `Candidate` has only `rawText` (AI parses structure); iOS has structured fields (AI only synthesizes). Resolution: extend `Candidate` with optional structured fields, keep AI as fallback parser.

#### Phase 2: Source Expansion

| Source                                  | Region | Value                                          | Priority | Estimated Effort                    |
| --------------------------------------- | ------ | ---------------------------------------------- | -------- | ----------------------------------- |
| Wikivoyage adapter (already written)    | Global | Narrative travel guides, solo-relevant context | HIGH     | 1 day (activation)                  |
| Google Places adapter (already written) | Global | Real-time ratings, hours, photos               | HIGH     | 2 days (activation + BudgetTracker) |
| Amap pricing optimization               | China  | Monitor 5000/mo free tier consumption          | MEDIUM   | 0.5 day                             |
| Baidu Maps / Tencent Maps               | China  | Redundancy + cross-validation                  | LOW      | Research needed                     |
| UGC platforms (Xiaohongshu, Dianping)   | China  | Experience-quality content                     | FUTURE   | API access uncertain                |

#### Phase 3: Real-Time Signals

| Signal                       | Source                                               | Use Case                           |
| ---------------------------- | ---------------------------------------------------- | ---------------------------------- |
| Foot traffic / popular times | Google Places `currentOpeningHours` + `popularTimes` | "Is this busy right now?"          |
| Weather context              | Open-Meteo (free, no key)                            | Filter outdoor experiences in rain |
| Event data                   | Eventbrite / local event APIs                        | Time-sensitive experiences         |
| User-generated micro-surveys | Existing `MicroSurveyRecord`                         | Solo-specific signal feedback loop |

### 1.4 Open Question

> What are the concrete rate limits and pricing tiers for Amap v5/place/around vs Baidu Maps vs Tencent Maps at 10K-100K queries/month? Do any offer startup programs?

**Action:** Before Phase 2, benchmark actual monthly Amap consumption and research Baidu/Tencent pricing. Current 5000/mo free tier supports ~166 explore taps/day — sufficient for early stage.

---

## 2. Agent Pipeline: Hybrid LLM Architecture

### 2.1 Current State

```
Production path (iOS):
  VoiceAgentOrchestrator → AIService.sendAgentMessage() → tool-use loop
    Tools: explore_nearby, filter_by_category, show_details,
           save_to_favorites, dismiss_recommendation

Synthesis path:
  EnrichmentAgent → multi-source POI merge → DeepSeek/Claude synthesis → Experience

Dead code (decided for deletion, see agent-pipeline.md):
  AgentRouter → IntentAgent → QueryAgent → GuideAgent
```

### 2.2 Confirmed Finding: Hybrid LLM Pipeline Superiority

> **Hybrid approach (structured JSON/YAML intermediates + template-guided generation) achieves 78.5% success rate**, significantly outperforming pure LLM-only (66.2%) and direct prompting (29.2%). **DeepSeek-AI (236B) leads at 93.3%** for structured tasks, ahead of Claude 3.5 Sonnet (80.0%) and GPT-4o Mini (60.0%).
>
> — arxiv.org/abs/2509.13487, peer-reviewed, 260 experiments × 13 LLMs
> — Confidence: HIGH (6-0 adversarial vote)

**Caveat:** DeepSeek model tested (V2, 236B MoE with 21B activated) is not the current DeepSeek version Solo Compass uses. Results may not generalize perfectly.

### 2.3 Improvement: Multi-Model Routing

Current: DeepSeek for synthesis, Claude for chat agent. Both called directly via AIService.

Proposed: Formalize model routing based on task type:

```swift
enum AITaskType {
    case classification     // Intent detection, category mapping
    case structuredExtract  // POI field extraction from raw text
    case narrativeSynth     // Experience description generation
    case conversational     // Chat agent dialogue
    case ranking            // Solo score computation
}

// Routing matrix:
// classification     → DeepSeek (fast, cheap, 93.3% structured accuracy)
// structuredExtract  → DeepSeek (structured JSON mode)
// narrativeSynth     → Claude (narrative quality, personality)
// conversational     → Claude (tool-use, multi-turn context)
// ranking            → Local heuristic (solo_score formula) → ML model (Phase 2)
```

**Key insight from research:** The pipeline's intermediate representation should be a **typed JSON schema**, not free text. Solo Compass already partially does this with `OverpassService.POI` as the canonical type — formalize this for ALL pipeline stages.

### 2.4 Improvement: Structured Intermediate Schema

Define explicit intermediate types for each pipeline stage:

```
Stage 1: Raw POI fetch → [OverpassService.POI]          (existing, canonical)
Stage 2: Multi-source merge → [MergedPOI]               (add: sourceWeights, conflictFlags)
Stage 3: AI classification → [ClassifiedPOI]             (add: category, soloRelevance score)
Stage 4: AI synthesis → [Experience]                      (existing, final output)
```

Add `MergedPOI` intermediate type that carries source provenance:

```swift
struct MergedPOI {
    let base: OverpassService.POI
    let enrichments: [SourceEnrichment]  // source name + weight + fields
    let conflictFlags: [FieldConflict]   // when sources disagree on hours/name
    let mergeConfidence: Double          // 0-1 based on source agreement
}
```

### 2.5 Improvement: Prompt Caching Strategy

The 3-stage agent pipeline (even with AgentRouter deleted, VoiceAgentOrchestrator's tool-use loop has repeated system prompts) can benefit from prompt caching:

| Provider  | Mechanism                                                      | Savings                                 | Applicability                        |
| --------- | -------------------------------------------------------------- | --------------------------------------- | ------------------------------------ |
| Anthropic | `cache_control: {"type": "ephemeral"}` on system prompt blocks | ~90% input token cost on repeated turns | VoiceAgentOrchestrator system prompt |
| DeepSeek  | Automatic prompt prefix caching                                | ~80% (varies)                           | EnrichmentAgent synthesis prompts    |

**Action:** Tag system prompts in `AIService.swift` with cache hints. Measure before/after cost per chat session and synthesis batch.

### 2.6 Open Question

> What is the optimal prompt caching strategy given Anthropic's prompt caching can reduce costs by 90% for repeated system prompts, and how does this interact with DeepSeek's pricing model?

**Action:** Instrument `AIService` to log input/output token counts per call. After 1 week of data, calculate breakeven for caching vs. no-caching.

---

## 3. Chat-Map Interaction Design

### 3.1 Current State

```
ChatSheet → ChatOrchestrator → AIService (tool-use loop)
  Tools: explore_nearby, filter_by_category, show_details,
         save_to_favorites, dismiss_recommendation

Inline UI: ChatCard, RouteProposal, ReasoningStep, ReasoningSummaryChip
Navigation: show_details sets lastEffect (no longer seizes map camera)
Route: build_route tool creates ordered experience sequences
```

### 3.2 Confirmed Finding: Google Agentic UI Toolkit Pattern

> **Google's Agentic UI Toolkit provides four inline UI outcome types**: Place Detail (compact POI cards), Inline Maps (point/area localization), Inline Map + Route (navigation/journey previews), Inline Map Detail (rich imagery context). Uses **system instructions to guide LLMs on component selection** without hard-coded logic.
>
> — developers.google.com/maps/ai/agentic-ui-toolkit (April 2026)
> — Confidence: MEDIUM (7-0 merged vote, but experimental/pre-GA)

**Direct mapping to Solo Compass components:**

| Google UI Type     | Solo Compass Equivalent | Status                              |
| ------------------ | ----------------------- | ----------------------------------- |
| Place Detail       | `ChatCard`              | ✅ Exists                           |
| Inline Map + Route | `RouteProposal`         | ✅ Exists                           |
| Inline Maps        | —                       | ❌ Missing: mini-map embed in chat  |
| Inline Map Detail  | —                       | ❌ Missing: rich photo/imagery card |

### 3.3 Improvement: Display-Type-as-Tool-Parameter

Currently, the chat system infers card type from content structure. Google's approach is better: **let the LLM explicitly choose which visual component to render** via a tool parameter.

Current (implicit):

```swift
// GuideAgent returns JSON, ChatSheet pattern-matches to pick view
if response.contains("route") { show RouteProposal }
else if response.contains("experience") { show ChatCard }
```

Proposed (explicit):

```swift
// Add display_type to tool call schema
tools: [
    {
        name: "show_recommendation",
        parameters: {
            experience_id: String,
            display_type: "place_card" | "mini_map" | "route_preview" | "photo_detail",
            emphasis: "primary" | "secondary"  // controls card size/position
        }
    }
]
```

This makes the 3-tool pipeline more composable: the LLM decides presentation, not hard-coded if/else.

### 3.4 Improvement: Mini-Map Inline Component

Add a `ChatMapEmbed` SwiftUI view that renders a small MapKit snapshot inline in chat:

```swift
struct ChatMapEmbed: View {
    let center: CLLocationCoordinate2D
    let pins: [ExperiencePin]
    let span: MKCoordinateSpan
    // ~120pt height, non-interactive, tap to expand on main map
}
```

Use case: "show me cafes near here" → inline mini-map with 3-5 pins + tappable cards below.

### 3.5 Confirmed Finding: RAG-Augmented Route Planning

> **EvoRAG, an evolutionary framework synergizing diverse trajectories with LLM reasoning, achieves state-of-the-art on TP-RAG benchmark** (2,348 queries, 85,575 POIs, 18,784 trajectory references). Integrating retrieved trajectories improves spatial efficiency but faces robustness challenges from conflicting references.
>
> — arxiv.org/abs/2504.08694, EMNLP 2025
> — Confidence: HIGH (9-0 merged vote)

**Application to Solo Compass routes:**

Current route generation: LLM orders experiences by proximity + time-of-day heuristics. No retrieval component.

Proposed enhancement (Phase 2):

1. **Retrieve** similar routes from user history or curated travel blogs
2. **Evaluate** trajectory suggestions with AI agent (conflict detection)
3. **Evolve** iteratively based on user feedback ("swap lunch spot", "add a break")

Start simple: when user requests a route, retrieve the 3 most similar past routes (by city + category overlap) and include them as context for the LLM synthesis prompt.

---

## 4. End-to-End System Optimization

### 4.1 Confirmed Finding: Ranking Evolution Roadmap

> **Airbnb's Experience search ranking evolved through 4 stages:** Stage 1 (offline GBDT, 50K examples, 25 features, +13% bookings), Stage 2 (250K examples, ~50 features, +7.9%), Stage 3 (online scoring, 2M+ examples, 90 features, +5.1%), Stage 4 (business rules integration).
>
> — medium.com/airbnb-engineering, Feb 2019 (dated but definitive case study)
> — Confidence: HIGH (3-0 vote)

**Solo Compass ranking evolution roadmap:**

| Stage       | Data Scale            | Features                                     | Approach                             | When     |
| ----------- | --------------------- | -------------------------------------------- | ------------------------------------ | -------- |
| **Current** | ~500 seed experiences | solo_score + category + time-of-day          | Rule-based formula                   | Now      |
| **Stage 1** | 5K+ experiences       | + user taps/saves/route-adds                 | Lightweight GBDT (on-device or edge) | 10K MAU  |
| **Stage 2** | 50K+ interactions     | + dwell time, chat queries, weather          | Feature expansion, offline model     | 50K MAU  |
| **Stage 3** | 500K+ interactions    | + collaborative filtering, real-time signals | Online scoring, personalized         | 100K MAU |

**Key insight:** Even Stage 1 with 50K training examples delivered +13% bookings for Airbnb. Solo Compass can start collecting interaction signals NOW (tap, save, route-add, dismiss) for future training data, even while using rule-based ranking.

### 4.2 Caching Strategy

#### Geohash-Indexed Experience Cache (existing)

```
ExperienceRepository.writeExploreCache → SwiftData (geohash-indexed)
  ├─ Overseas: full cache, TTL based on lastVerifiedAt
  └─ China: SKIP (Amap ToS prohibition) — real-time only
```

#### Proposed: Differential TTL by Field Volatility

| Field Group              | Volatility | Suggested TTL | Rationale               |
| ------------------------ | ---------- | ------------- | ----------------------- |
| Location, category, name | Very low   | 30 days       | Rarely changes          |
| Description, solo_score  | Low        | 14 days       | AI synthesis stable     |
| Opening hours, pricing   | Medium     | 3 days        | Business updates weekly |
| Foot traffic, "open now" | High       | 15 minutes    | Real-time signal        |
| Weather-dependent flags  | High       | 1 hour        | Weather changes hourly  |

**Implementation:** Add `fieldFreshness: [String: Date]` to cached Experience, refresh only stale field groups instead of full re-synthesis.

### 4.3 Cold-Start Ranking

**Open question from research:** How to rank when a user arrives in a new city with no interaction history?

**Proposed approach (content-based, no user history needed):**

1. Solo Score (existing) — AI-computed relevance for solo travelers
2. Time-of-day match — `bestTimes` vs current hour
3. Distance decay — closer experiences ranked higher
4. Category diversity — ensure top-5 spans ≥3 categories
5. Source confidence — multi-source corroborated experiences rank higher

This is sufficient for Phase 1. Collaborative filtering (Stage 2+) requires interaction data that doesn't exist yet.

### 4.4 Observability for AI Features

Currently: no systematic measurement of AI synthesis quality or user satisfaction.

Proposed instrumentation:

| Metric                      | Collection Point                    | Purpose                                       |
| --------------------------- | ----------------------------------- | --------------------------------------------- |
| Synthesis success rate      | AIService completion handler        | % of explore taps that produce ≥3 experiences |
| Token cost per session      | AIService (log input/output tokens) | Cost optimization baseline                    |
| Chat turn count             | ChatOrchestrator                    | Conversation depth before action              |
| Tool call distribution      | VoiceAgentOrchestrator              | Which tools users trigger most                |
| Experience tap-through rate | MapViewModel pin tap → detail open  | Quality signal for ranking                    |
| Route adoption rate         | RouteStore                          | % of AI-generated routes that get started     |
| Stale data reports          | Detail view "report issue" button   | Data freshness signal                         |

**Implementation:** Sentry breadcrumbs (already integrated) for event tracking; aggregate in Supabase analytics table.

---

## 5. Priority Matrix

| #   | Improvement                                              | Effort  | Impact                                      | Priority |
| --- | -------------------------------------------------------- | ------- | ------------------------------------------- | -------- |
| 1   | Activate TS source adapters (Wikivoyage + Google Places) | 3 days  | HIGH — doubles data richness                | P0       |
| 2   | Display-type-as-tool-parameter in chat                   | 2 days  | MEDIUM — composable chat UX                 | P1       |
| 3   | Prompt caching (Anthropic cache hints)                   | 1 day   | MEDIUM — ~50% cost reduction                | P1       |
| 4   | Multi-model routing formalization                        | 2 days  | MEDIUM — cost + quality optimization        | P1       |
| 5   | Interaction signal collection (taps, saves, dismisses)   | 2 days  | HIGH — future ranking foundation            | P1       |
| 6   | AI observability instrumentation                         | 1 day   | HIGH — can't improve what you can't measure | P1       |
| 7   | Differential TTL caching                                 | 3 days  | MEDIUM — freshness + performance            | P2       |
| 8   | ChatMapEmbed inline component                            | 2 days  | LOW — nice UX enhancement                   | P2       |
| 9   | RAG-augmented route planning                             | 5 days  | MEDIUM — better routes                      | P2       |
| 10  | GBDT ranking (Stage 1)                                   | 2 weeks | HIGH — but needs interaction data first     | P3       |
| 11  | Baidu/Tencent Maps research                              | 1 day   | LOW — Amap sufficient for now               | P3       |

---

## 6. Research Sources

### Confirmed (adversarially verified, HIGH confidence)

| #   | Source                                                                                                                                      | Finding                                                                         | Vote |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- | ---- |
| 1   | [arxiv.org/abs/2509.13487](https://arxiv.org/abs/2509.13487)                                                                                | Hybrid LLM pipeline (JSON intermediates) 78.5% success; DeepSeek leads at 93.3% | 6-0  |
| 2   | [Zhong Lun Law Firm / Lexology](https://www.lexology.com/library/detail.aspx?g=9f755dba-12a6-47b5-8b47-c16200cb6d58)                        | China CNDM prohibition + data residency mandatory                               | 6-0  |
| 3   | [Google Maps Agentic UI Toolkit](https://developers.google.com/maps/ai/agentic-ui-toolkit)                                                  | 4 inline UI types, display-type-as-parameter pattern                            | 7-0  |
| 4   | [arxiv.org/abs/2504.08694](https://arxiv.org/abs/2504.08694)                                                                                | EvoRAG / TP-RAG benchmark for trajectory-augmented travel planning (EMNLP 2025) | 9-0  |
| 5   | [Airbnb Engineering Blog](https://medium.com/airbnb-engineering/machine-learning-powered-search-ranking-of-airbnb-experiences-110b4b1a0789) | 4-stage ranking evolution from 50K GBDT to 2M+ online scoring                   | 3-0  |

### Additional Sources Consulted (22 total, 5 search angles)

- China POI compliance: JetRuby, Intellias, Wikipedia geo restrictions, Geoapify comparison, Foursquare pricing
- LLM pipeline: DigitalApplied routing guide, Web2MD prompt caching, arxiv POI embedding paper
- Conversational map UX: Mapbox conversational maps blog, Google Maps AI Kit, Peschinskiy AI assistants guide
- Mobile geospatial: various (rate-limited during verification)
- Travel AI competitive: various (rate-limited during verification)

### Research Caveats

1. **Google Agentic UI Toolkit is experimental/pre-GA** — may change or be discontinued
2. **DeepSeek model tested differs from current version** — benchmark numbers may not transfer directly
3. **China regulatory landscape is evolving** — validate against current enforcement before major architecture changes
4. **Airbnb study is from 2019** — their current system has likely evolved beyond what was published
5. **Rate limiting affected verification coverage** — 14/25 claims had 0-0 votes (all abstain due to API limits), not refuted

---

## Appendix A: Open Questions for Future Research

1. **Amap/Baidu/Tencent pricing comparison** at startup scale (10K-100K queries/month)
2. **SwiftData cache TTL strategy** — how to balance freshness vs re-synthesis cost for different field volatility
3. **Prompt caching economics** — Anthropic vs DeepSeek cost model interaction for the 3-stage pipeline
4. **Cold-start ranking** — collaborative filtering vs content-based for new-city scenarios
5. **UGC platform APIs** — Xiaohongshu/Dianping/Meituan API availability and ToS for travel content extraction
6. **Offline-first architecture** — when to pre-download experience data for areas without connectivity
