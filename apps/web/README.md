# apps/web

> Next.js + Mapbox. Web is **not** a stripped iOS app — it has its own job.

## What this app is for

The web app serves four scenarios the iOS app cannot:

1. **Pre-trip research center** — desktop, multiple tabs, deep planning
2. **Zero-install try** — phone browser, "let me see this before installing"
3. **Post-trip sharing** — public URLs, OG images, recap pages
4. **SEO entry** — Google indexes us; iOS App Store doesn't

**Read [`docs/WEB_DESIGN.md`](../../docs/WEB_DESIGN.md) before opening any web PR.** That document is the definitive answer to "what does the web do?" — including the anti-goals list (what web should *not* do).

## Status

🚧 Foundation phase. Not yet running. See open issues:
- #41 — umbrella scenario tracking
- #42 — Scenario A (desktop research view)
- #43 — Scenario B (mobile zero-install funnel)
- #44 — Scenario C (recap pages)
- #45 — Scenario D (SEO static pages)
- #4 — bare map screen (foundation work)

## Stack

- **Framework**: Next.js 15 (App Router, RSC, mix of SSG + SSR)
- **Map**: Mapbox GL JS (custom warm-toned style)
- **Styling**: Tailwind + shadcn/ui
- **State**: URL-as-state, no Redux
- **Auth**: Supabase magic-link email (optional, never gating content)
- **Deploy**: Vercel

## Development

```bash
# from repo root
pnpm install
pnpm --filter @solo-compass/web dev
```

Open http://localhost:3000.

## Mobile responsive, not separate

There is **no separate mobile site**. The same Next.js app responds to mobile viewports via Tailwind breakpoints. Mobile is Scenario B (zero-install try) — not a second product.
