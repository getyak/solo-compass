# Metrics Validation Plan (#392)

Owner: growth analyst
Timeline: post 100% rollout (Stage 3 of `docs/GRADUAL_ROLLOUT.md`)

Purpose: verify the v1.0 sharing/CAC hypotheses that motivated the
Phase 3 sprint (`docs/V_NEXT_DESIGN.md` §3 targets).

## Success targets (Phase 3 exit)

| Metric                           | Baseline (pre v1.0) | v1.0 target     | Kill signal  |
| -------------------------------- | ------------------- | --------------- | ------------ |
| Self-reported share rate / month | 1.5%                | **5%**          | < 2.5%       |
| CAC via referral                 | $X                  | **-30%**        | flat / worse |
| Pro conversion                   | Y%                  | **2× baseline** | < 1.2×       |

Baseline numbers freeze at Stage 0. Snapshot them here before
promoting to 10%:

```
share_rate_baseline: TBD (record 2026-xx-xx)
cac_baseline:        TBD
pro_conv_baseline:   TBD
```

## Event → target mapping

The `AnalyticsService.EventName` catalog aligns 1:1 with the targets.
Wire the analytics dashboard so each panel reads the exact event name
listed here:

| Target              | Event stream                                                                                                                                   |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Self-reported share | `brag_card_shared` + `ost_shared` + `insight_card_shared` (add these three EventName cases if not yet present at the point of this validation) |
| CAC via referral    | UTM-tagged install referrer → `paywall_shown` `iap_success` funnel; join at device id                                                          |
| Pro conversion      | `paywall_shown` → `iap_initiated` → `iap_success` funnel; window = 24h                                                                         |

Any event stream missing from the current `AnalyticsService.EventName`
enum blocks the validation — file a follow-up to add it (deterministic
1-line change per stream).

## Validation procedure

1. **Day 0** (Stage 3 start): snapshot baselines in the block above.
2. **Day 14**: pull actuals from analytics dashboard, compare row-by-row.
3. **Day 21**: pull actuals again — sustained lift or one-off spike?
4. **Day 30**: file a note in `docs/V_NEXT_DESIGN.md` §3 with the
   observed vs targeted comparison.

## Guard rails

- If a metric hits the kill signal, DO NOT ship follow-up features
  that assume the hypothesis holds. Instead, run a diagnostic pass
  before Phase 4 planning.
- Every metric row above must have at least ONE independent data
  source (server-side event stream + client-side confirmation) — don't
  ship a decision on a single log line.

## Deliverables

- [ ] Baselines recorded in this file with a date.
- [ ] Day-14 comparison table appended.
- [ ] Day-30 verdict + reference back to Phase 4 planning notes.
