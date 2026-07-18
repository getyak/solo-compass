# Animation Spec (v1.0)

> Scope: the three ceremonial animations. Everything else uses standard
> SwiftUI `.animation(.easeInOut(duration: 0.25))` defaults.

Ceremonial surfaces are the only places we invest in bespoke animation.
Elsewhere, restraint > flourish.

---

## 1. Time-capsule accept (P2.4 #242 — `CapsuleOpenView`)

**Beats**

1. **T=0.00s** — full-screen fade-in of `CT.capsuleGlow → CT.accentSoft`
   gradient. Duration: 0.35s, `.easeOut`.
2. **T=0.20s** — the envelope glyph (`envelope.open.fill`, size 44)
   scales from 0.75 → 1.0 and opacity 0.30 → 1.0 in 0.60s
   (`.easeOut(duration: 0.6)`).
3. **T=0.55s** — payload text fades in (opacity 0 → 1) over 1.10s
   (`.easeOut(duration: 1.1).delay(0.2)`).
4. **T=1.15s** — context line (weather, taste descriptors) fades in
   over 1.10s (`.delay(0.6)`), same easing.
5. **T=2.20s** — controls (Reply / Close) settle. No animation, they
   just appear once the header settles.

**No overshoot. No spring.** Capsule reveal must feel like something
was already there, not something dropped in.

**Failure mode**: if `Reduce Motion` is enabled, skip beats 1–4 —
render the final state instantly.

---

## 2. Blindbox reveal (P2.3 — `BlindboxOrchestrator` `.revealed` state)

**Beats** (per anchor)

1. Anchor marker's masked title (`"???"`) crossfades to the real title.
   Duration: 0.45s, `.easeInOut`.
2. Simultaneously, the map annotation halo (`CT.blindboxAmber`) expands
   from 0 → 44pt in 0.55s (`.spring(response: 0.55, dampingFraction: 0.7)`).
3. Haptic: `UIImpactFeedbackGenerator(style: .rigid)` on reveal impact.

**One flourish per anchor.** Do not add particle effects; the amber
halo carries the ceremony.

**Failure mode**: if `Reduce Motion` is enabled, crossfade only (no halo).

---

## 3. City-omen flip (P3.0 #302 — `OmenCardView`)

**Beats**

1. On "Mark done" tap: `.rotation3DEffect(.degrees(180), axis: (0, 1, 0))`
   over 0.55s, `.easeInOut`.
2. The back face is pre-mounted with `.rotation3DEffect(.degrees(180))`
   so it reads correctly once flipped.
3. Success glyph (`checkmark.seal.fill`, size 32, `CT.omenGold`) is
   the anchor visual. No secondary animation.

**Failure mode**: if `Reduce Motion` is enabled, replace the flip with
a crossfade over 0.35s.

---

## Tokens

Ceremonial-only, defined in `Views/Shared/CompareTokens.swift`:

- `CT.capsuleGlow` = `#F7DEB0` — capsule reveal.
- `CT.omenGold` = `#B8925C` — omen accent.
- `CT.blindboxAmber` = `#8A4A14` — blindbox halo + launch background.

Do NOT use these tokens on routine surfaces. Routine ambient stays with
`CT.accent` / `CT.sunGold`.

---

## Future work

- Lottie for the capsule reveal — replaces beats 2–4 with a designed
  particle sequence. Blocks on 5-frame delivery from external designer
  (#320 track).
- Blindbox recap card — the "share to IG" grade needs a subtle
  parallax; not in scope for v1.0.
