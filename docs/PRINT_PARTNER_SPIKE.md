# Print Partner Spike — Travel Book Fulfilment (#340)

Owner: business ops
Duration: 1 calendar week (spike, not implementation)

## Goal

Pick ONE print partner for the year-end Travel Book fulfilment
(`BookComposeService` → PDF → printed hardback), sign the initial
contract, and freeze the following variables before Phase 3 UI polish
starts:

1. Unit COGS at 100-page hardback
2. Per-order fulfilment latency
3. Regional shipping availability (US / EU / SEA at minimum)
4. Cover / spine template constraints (bleed, spine width formula)
5. API surface — REST? SFTP file drop? Manual portal?

## Candidates

### Lulu Direct
- Pros: mature REST API, per-order print-on-demand, no minimum, global.
- Cons: higher unit cost than bulk, cover templates strict.
- Rate card: https://developers.lulu.com/home/print-pricing
- API docs: https://developers.lulu.com/api-reference

### Shutterfly
- Pros: consumer brand recognition, US/EU fulfilment, mature photo book
  product.
- Cons: partner API is B2B, needs enterprise onboarding, longer contract
  cycle.

### 一印 (Yiyin)
- Pros: SEA + China fulfilment, cheapest at scale.
- Cons: no public REST API, integration via email + XLS batch drop,
  latency 3–4 weeks.

## Decision matrix

Score each on 1–5, weight by column header. Total > 20 = go.

| Candidate  | COGS (×4) | Latency (×3) | API (×3) | Regions (×2) | Total |
|------------|-----------|--------------|----------|--------------|-------|
| Lulu       |           |              |          |              |       |
| Shutterfly |           |              |          |              |       |
| 一印        |           |              |          |              |       |

## Spike deliverables

- [ ] Signed NDA with the leading candidate.
- [ ] Sample book printed via their pipeline using our real
  `BookManifest` fixture (see `V_NEXT_ServiceSkeletonTests.test_book_weeklyChapters`).
- [ ] COGS + shipping + duty math sheet (Google Sheet, link here).
- [ ] Contract terms drafted with legal review notes attached.

## Downstream unblocks

Once the spike closes:
- `#341 BookComposeService` gains its final `uploadManifest(_:)` call.
- `#342 Archive tab year-end banner` UI copy finalised with real price.
- Paywall gains a "Print book — $XX.XX" tier that the AnalyticsService
  funnel needs to observe (`iap_initiated` with `product_id:
  "physical.travelbook"`).

## Non-goals

- Not committing to bespoke book covers this cycle — reuse the
  omenGold + serif treatment already in `docs/ANIMATION_SPEC.md`.
- Not building a "gift" workflow — v1.0 = self-order only.
