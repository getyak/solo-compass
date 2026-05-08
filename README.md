# Solo Compass · 独行罗盘

> A living map for solo travelers.
>
> 为独自旅行者设计的"活地图"——打开就是地图,地图上自动显示周边值得做的事。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![pnpm](https://img.shields.io/badge/pnpm-workspaces-orange)](https://pnpm.io/workspaces)
[![Status](https://img.shields.io/badge/status-pre--alpha-red)](https://github.com/kubbot/solo-compass)

---

## What this is

Not another travel app. Not a Google Maps clone. Not a small-red-book replacement.

A **map-first**, **experience-as-unit**, **AI-curated** companion for people traveling alone — where every dot on the map is a _thing worth doing_, not just _a place that exists_.

**Three design pillars (non-negotiable):**

| Layer      | Role | Principle                                                       |
| ---------- | ---- | --------------------------------------------------------------- |
| Map        | Root | Always the home screen. No tabs, no drawer, no onboarding flow. |
| Experience | Unit | Not "places" — concrete, time-bound, story-rich things to do.   |
| AI         | Soul | Filters candidates from 1000 to 5. Never decides for the user.  |

> AI doesn't travel for you. AI helps you travel better.

For the full product brief, see [`docs/PRODUCT_BRIEF.md`](./docs/PRODUCT_BRIEF.md).

---

## Repo layout (monorepo)

```
solo-compass/
├── apps/
│   ├── web/              # Pre-MVP: Next.js + Mapbox (Phase 2)
│   ├── ios/              # Native iOS app (Phase 3)
│   └── bot/              # Telegram bot for low-cost validation
├── packages/
│   ├── core/             # Shared domain types: Experience, Place, User, etc.
│   ├── ai/               # Prompts, recommendation engine, Claude wrappers
│   ├── data/             # OSM/Wikivoyage ingestion, schema, seeders
│   └── ui/               # Shared design tokens (web only — iOS uses native)
├── docs/                 # Product brief, architecture, decisions
├── scripts/              # Cold-start data pipelines, dev tooling
└── seeds/                # Hand-curated seed experiences (Chiang Mai 50)
```

**Boundary discipline:** `core/`, `ai/`, `data/` are platform-agnostic and have no UI dependencies. Each app pulls only what it needs. You can run _any one app_ without the others.

---

## Quickstart

> Requires Node 20+, pnpm 9+. iOS app requires Xcode 15+ (added in Phase 3).

```bash
# Clone
git clone https://github.com/kubbot/solo-compass.git
cd solo-compass

# Install all workspaces
pnpm install

# Copy env templates
cp .env.example .env.local
# Then fill in: ANTHROPIC_API_KEY, MAPBOX_TOKEN, SUPABASE_URL, SUPABASE_KEY

# Run the web app (Phase 2)
pnpm --filter @solo-compass/web dev

# Run the bot (low-cost validation)
pnpm --filter @solo-compass/bot dev
```

See [`CONTRIBUTING.md`](./CONTRIBUTING.md) for development workflow.

---

## Phases

This project follows a strict **validate-before-build** roadmap. Each phase has a clear stop/go gate.

| Phase | What                                                         | Duration   | Stop/go gate                                   |
| ----- | ------------------------------------------------------------ | ---------- | ---------------------------------------------- |
| 0     | Field week — go to Chiang Mai, do 7 experiences, write seeds | 1 week     | 7 experiences with emotional weight            |
| 1     | Notion DB + Figma prototype — show to 10 friends             | 2–3 weeks  | 30s comprehension test passes                  |
| 2     | **Web Pre-MVP** — Next.js + Mapbox, manual check-in          | 4 weeks    | 30+ users in Chiang Mai, week-1 retention >40% |
| 3     | iOS native — background GPS, push notifications, real magic  | 2–3 months | Production launch                              |

**Currently in: pre-Phase 0.**

The data layer (`packages/data`, `packages/core`) and AI layer (`packages/ai`) are being built first because they're shared by every phase.

---

## Tech stack

- **Monorepo**: pnpm workspaces + Turborepo
- **Language**: TypeScript everywhere except iOS (Swift)
- **Web**: Next.js 15 (App Router), Mapbox GL JS, Tailwind
- **iOS**: SwiftUI + MapKit (Phase 3)
- **Bot**: Telegraf
- **DB**: Supabase (Postgres + PostGIS for geospatial)
- **AI**: Anthropic Claude API
- **Data sources**: OpenStreetMap (Overpass), Wikivoyage, Wikipedia, Reddit, YouTube transcripts

---

## Why open source?

Because the **data schema** is more valuable than the data itself, and we want the schema to become a standard.

If "experience-as-unit" is the right abstraction for travel, it should outlive any one product. The codebase here defines what an experience _is_ — anyone can fork the data layer and build a different front-end.

What we keep proprietary (in private repos):

- Curated seed experiences for each city
- Prompt engineering for content quality
- User-generated experience corpus

---

## Secret scanning

Every push and pull request is automatically scanned for accidentally committed secrets using [gitleaks](https://github.com/gitleaks/gitleaks).

**Run locally before pushing:**

```bash
# Install gitleaks (macOS)
brew install gitleaks

# Scan the working tree (no git history required)
gitleaks detect --source . --no-git
```

**What the `.gitleaks.toml` allowlist exempts — and why:**

| Pattern             | File           | Reason                                                                                   |
| ------------------- | -------------- | ---------------------------------------------------------------------------------------- |
| `pk.eyJ…`           | `.env.example` | Mapbox public-token placeholder; not a real secret, intentionally shown as a format hint |
| `xxxxx.supabase.co` | `.env.example` | Supabase placeholder URL; `xxxxx` is obviously not a real project ID                     |
| `sk-replace-me`     | `.env.example` | Literal placeholder string; not a key that could authenticate against any API            |

Real values must never be committed. Copy `.env.example` to `.env` (gitignored) and fill in actual keys there.

---

## License

MIT — see [`LICENSE`](./LICENSE).

---

## Status

Pre-alpha. Don't use this in production. The schema will change.

If you're a solo traveler in Chiang Mai and want to be a seed user, open an issue tagged `seed-user`.

---

_Built by [@cubxxw](https://github.com/cubxxw) and friends. Started 2026._
