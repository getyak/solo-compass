# App Store Connect IAP Setup — v1.0 Consumables (#304 and friends)

Owner: release captain

## Product registration checklist

Every consumable below MUST be registered in App Store Connect BEFORE
the feature can be exercised on-device.

| Product ID                                   | Type       | Retail | Constant in code                              |
| -------------------------------------------- | ---------- | ------ | --------------------------------------------- |
| `com.solocompass.consumable.blindbox.single` | Consumable | $1.99  | `SubscriptionService.blindboxSingleProductID` |
| `com.solocompass.consumable.sos.single`      | Consumable | $2.99  | `SubscriptionService.sosSingleProductID`      |
| `com.solocompass.consumable.unwalked.single` | Consumable | $4.99  | `SubscriptionService.unwalkedSingleProductID` |
| `com.solocompass.consumable.omen.reroll`     | Consumable | $0.99  | `SubscriptionService.omenRerollProductID`     |
| `com.solocompass.consumable.ost.reroll`      | Consumable | $0.99  | `SubscriptionService.ostRerollProductID`      |
| `com.solocompass.consumable.brag.video`      | Consumable | $1.99  | `SubscriptionService.bragVideoProductID`      |

Each needs:

- Localised name + description (en, zh-Hans at minimum).
- Screenshot reflecting the actual v1.0 UI surface.
- Review notes explaining the consumable's function.

## Purchase flow spec — Omen reroll (#304) as canonical example

The Omen reroll is the smallest of the six purchase flows; use it as
the reference implementation and copy for the other five.

### Sequence

1. User taps "Reroll" on `OmenCardView` (present only when
   `omenRerollUsedToday` < 3).
2. Client calls `SubscriptionService.purchase(productID:)` with the
   `omenRerollProductID` constant.
3. StoreKit2 presents the paywall sheet natively.
4. On success:
   - `AnalyticsService.track(.iapSuccess, properties: ["product_id":
.string(SubscriptionService.omenRerollProductID)])`.
   - `OmenComposeService.compose(...)` is called with a new seed
     (mix in `omenRerollUsedToday + 1`).
   - Card flips back to front + animates in the new omen line.
5. On failure or cancel:
   - `AnalyticsService.track(.iapFailed, properties: ["product_id":
.string(SubscriptionService.omenRerollProductID)])`.
   - Toast: "Couldn't process that. Try again in a moment."

### Rate limit

Per PRD `#304` the reroll is capped at 3 per calendar day. Persist the
counter under UserDefaults key `com.solocompass.omen.reroll.count.<yyyy-MM-dd>`,
mirroring the pattern used by `LiveActivityService.consumeDailyBudget`.

### Testing

- Sandbox Apple ID must be linked in Settings → App Store.
- StoreKit configuration file (`StoreKitTestingConfig.storekit`) must
  include the same product IDs so unit tests can exercise the flow
  without hitting real StoreKit.

## Sandbox verification checklist

Before submitting for App Store review:

- [ ] All 6 product IDs return `.approved` from `Product.products(for:)`
- [ ] Purchase succeeds in sandbox for each
- [ ] Refund flow: `Transaction.currentEntitlements` reflects refunded
      consumables correctly
- [ ] Restore purchases button behaves cleanly (consumables cannot be
      restored — the button must communicate this rather than error)
