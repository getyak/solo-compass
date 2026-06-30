# Solo Compass — Subscription Setup

Solo Compass Pro is delivered via **StoreKit Introductory Offer**: a 1-month
free trial attached to the monthly auto-renewing subscription. New users are
guided into the trial during onboarding (step 5 of `OnboardingView`); they can
also start it from any AI-gated entry point that triggers `PaywallView`.

This doc covers everything needed to keep that flow working end-to-end:
local simulator testing, App Store Connect configuration, and the entitlement
state machine it produces.

---

## 1. Product catalog

| Product ID                          | Period | Intro offer        |
| ----------------------------------- | ------ | ------------------ |
| `com.solocompass.pro.monthly`       | P1M    | 1 month free       |
| `com.solocompass.pro.yearly`        | P1Y    | 1 month free       |

Both products belong to the **Solo Compass Pro** subscription group so a user
can upgrade from monthly to yearly without losing access.

The introductory offer is configured at the product level (not as a code
offer) so eligibility is automatic for any Apple ID that has not previously
redeemed it within the same subscription group.

## 2. Local testing — `.storekit` config

`apps/ios/SoloCompass/Resources/Configuration.storekit` is the source of truth
for simulator + Xcode Previews. It mirrors the App Store Connect catalog and
is wired into BOTH the `Run` and `Test` actions of the `SoloCompass` scheme
via `apps/ios/project.yml`:

```yaml
schemes:
  SoloCompass:
    run:
      storeKitConfiguration: SoloCompass/Resources/Configuration.storekit
    test:
      storeKitConfiguration: SoloCompass/Resources/Configuration.storekit
```

After editing the .storekit file, run `xcodegen` from `apps/ios/` so the
generated `.xcodeproj` picks up the new config.

### Trial period

Both products specify `introductoryOffer.subscriptionPeriod: P1M`
(ISO 8601 — 1 month). Change this if you ever shorten/extend the trial.

### Resetting eligibility for repeated trials

In the simulator: **Debug → StoreKit → Manage Transactions → Delete all**.
This restores Introductory Offer eligibility so you can test the
"first month free" pitch end-to-end repeatedly.

## 3. App Store Connect configuration

Each product in App Store Connect needs the introductory offer attached to
the subscription itself (not as a promotional offer):

1. App Store Connect → My Apps → Solo Compass → Monetization → **Subscriptions**
2. Open the Solo Compass Pro group → tap the monthly subscription
3. Under **Introductory Offers**, click **Set Up Introductory Offer**
4. Configure:
   - **Type**: Free
   - **Duration**: 1 Month
   - **Eligibility**: **New subscribers** (default — anyone who hasn't
     previously redeemed any introductory offer in this subscription group)
   - **Countries / Regions**: All
5. Repeat for the yearly subscription

After updating, the catalog can take up to 24 hours to propagate to the
sandbox environment. Use Xcode → Product → Scheme → Edit Scheme → Run →
Options → "StoreKit Configuration" to point at the local file in the
meantime.

## 4. Entitlement state machine

`SubscriptionService.Entitlement` has four states. The transitions:

```
              ┌──────────────────────────────┐
              ▼                              │
   free ──(purchase intro)──→ proTrial ──(intro period ends, auto renews)──→ pro
    ▲                          │                                              │
    │                          │                                              │
    │                  (trial cancelled / non-renew)                          │
    │                          ▼                                              ▼
    └──── (refund / revoke) ── proExpired ◀── (cancel + period ends) ─────────┘
```

- **`free`** — never paid, no active or expired subscription. Default state.
- **`proTrial`** — inside the 1-month free trial. AI gates pass; UI shows
  "X days remaining" + renewal date.
- **`pro`** — active paid subscription. AI gates pass.
- **`proExpired`** — was paying, currently lapsed (cancelled or payment
  failed). AI gates fail. We don't downgrade silently to `free` so we can
  show a "Welcome back" win-back paywall.

The state is resolved by walking `Transaction.currentEntitlements` in
`SubscriptionService.refreshEntitlement`. The result is mirrored to:

1. **Keychain** (`account="entitlement"`) — survives app reinstall on same
   device, lets the UI render the right state in <16ms at cold launch
   before StoreKit returns.
2. **Supabase `profiles.entitlement_tier`** — via the `subscription_events`
   outbox enqueued by `_emitSubscriptionEventFields`. Edge functions
   (chat-proxy, synthesize-experiences) gate AI calls on this column.

## 5. UI entry points to Paywall

| Surface                       | Trigger                                                    |
| ----------------------------- | ---------------------------------------------------------- |
| Onboarding step 5             | Shown to every new user; opt-out via "Maybe later"         |
| MeSheet → EntitlementBanner   | Always visible; banner contents change by entitlement      |
| MapViewModel AI gate          | Tapping Explore/voice/etc. while `entitlement.isActive==false` |
| ExperienceDetailViewModel     | Tapping Per-place AI insight while ineligible              |
| SettingsView                  | "Subscription" row                                         |

All five paths feed into the same `PaywallView`, which auto-detects:
- **Eligible for intro offer** → CTA = "Start 1-month free trial"
- **Mid-trial** → banner shows X days remaining + manage subscription link
- **Ineligible / already Pro** → CTA = "Subscribe" (no trial promise)

This single-source-of-truth means future copy/legal tweaks happen in one
file instead of N entry points.

## 6. Apple compliance checklist

App Store Reviewer #1 considerations the paywall already satisfies:

- ✅ Trial price disclosed near the CTA (`paywall.fineprint.month` and
  `onboarding.paywall.fineprint.format` interpolate the live displayPrice)
- ✅ "Continue with Free" exit visible at all times
- ✅ Restore Purchases link visible
- ✅ Manage Subscription deep link to `apps.apple.com/account/subscriptions`
- ✅ Family Sharing enabled on both products (`familyShareable: true`)
- ✅ EULA reference in fine print
- ✅ No nag on returning users who already declined (the
  `hasSeenOnboardingPaywall` UserDefaults flag suppresses repeated
  onboarding paywall presentations)

## 7. Failure modes & recovery

- **Catalog empty at first paywall tap** — `runPurchase()` retries
  `loadProducts()` once before surfacing the `paywall.error.unavailable`
  alert.
- **Paid Apps Agreement unsigned** — products will silently 404. The
  error alert above surfaces this; check App Store Connect → Agreements,
  Tax, and Banking.
- **Returning Apple ID — no intro offer** — `isEligibleForIntroOffer`
  returns `false`; CTA falls back to the plain "Subscribe" copy; trial
  badge on the product card disappears. Onboarding paywall fineprint
  falls back to `onboarding.paywall.fineprint.fallback`.
