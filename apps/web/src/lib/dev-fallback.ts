/**
 * Dev-only fallback experiences. Returned by the nearby route when
 * SUPABASE_* env vars are missing so local development without a backend
 * still shows realistic UI. Never used in production — the env check in
 * `nearby/route.ts` is the only call site.
 *
 * Coordinates clustered around Chiang Mai (the default map center).
 */

import type { Experience } from "@solo-compass/core";

function exp(args: {
  id: string;
  title: string;
  category: Experience["category"];
  coords: [number, number];
  oneLiner: string;
  soloOverall: number;
  bestTimes: Experience["bestTimes"];
  durationMin: number;
  durationMax: number;
}): Experience {
  return {
    id: args.id as Experience["id"],
    title: args.title,
    oneLiner: args.oneLiner,
    whyItMatters:
      "A small slice of the city worth showing up for — alone, on purpose. The kind of place that makes the trip feel yours.",
    category: args.category,
    location: {
      coordinates: args.coords,
      cityCode: "cmi",
      addressHint: "Chiang Mai",
    },
    bestTimes: args.bestTimes,
    durationMinutes: { min: args.durationMin, max: args.durationMax },
    howTo: [
      { order: 1, text: "Show up. No reservation needed." },
      { order: 2, text: "Take the corner seat near the window." },
      { order: 3, text: "Order one thing. Stay for as long as you want." },
    ],
    realInconveniences: [
      {
        category: "logistics",
        text: "Cash only — bring small notes.",
      },
    ],
    soloScore: {
      overall: args.soloOverall,
      breakdown: {
        seatingFriendly: 8,
        soloPatronRatio: 7,
        staffPressure: 8,
        soloPortioning: 9,
        ambianceFit: 8,
        safety: 9,
      },
      hint: "Comfortable for one, never awkward.",
      basedOnCount: 12,
    },
    sources: [
      {
        type: "field_visit",
        attribution: "Solo Compass — dev fixture",
        verifiedAt: "2026-04-01T00:00:00Z",
      },
    ],
    confidence: {
      level: 3,
      lastVerifiedAt: "2026-04-15T00:00:00Z",
      reason: "Dev fallback fixture — backend not configured locally.",
      signals: {
        aiScrapeAgeDays: 30,
        passiveGpsHits30d: 5,
        activeReports30d: 2,
        trustedVerifications: 1,
      },
    },
    nearbyExperienceIds: [],
    stats: {
      completionCount: 12,
      averageRating: 4.3,
    },
    status: "active",
    createdAt: "2026-04-01T00:00:00Z",
    updatedAt: "2026-04-15T00:00:00Z",
  };
}

export const DEV_FALLBACK_EXPERIENCES: readonly Experience[] = [
  exp({
    id: "exp_dev_ristr8to",
    title: "Sit with a flat white at Ristr8to before the crowd",
    category: "coffee",
    coords: [98.9824, 18.7905],
    oneLiner: "World-class barista shop that opens early. Window seats, no music.",
    soloOverall: 8.6,
    bestTimes: [{ startHour: 7, endHour: 10, note: "before tour buses" }],
    durationMin: 30,
    durationMax: 60,
  }),
  exp({
    id: "exp_dev_suan_dok",
    title: "Catch sunset behind the white stupas at Wat Suan Dok",
    category: "culture",
    coords: [98.9663, 18.7891],
    oneLiner: "Royal cemetery at golden hour — silent, photogenic, free.",
    soloOverall: 9.1,
    bestTimes: [{ startHour: 17, endHour: 19, note: "30 min before sunset" }],
    durationMin: 30,
    durationMax: 45,
  }),
  exp({
    id: "exp_dev_khao_soi",
    title: "Eat khao soi alone at Khao Soi Khun Yai",
    category: "food",
    coords: [98.9893, 18.7973],
    oneLiner: "Cash, no reservations, a stool at the counter — built for one.",
    soloOverall: 8.2,
    bestTimes: [{ startHour: 11, endHour: 14, note: "lunch only — closes when sold out" }],
    durationMin: 20,
    durationMax: 35,
  }),
  exp({
    id: "exp_dev_huay_kaew",
    title: "Walk the Huay Kaew falls trail before the heat",
    category: "nature",
    coords: [98.9536, 18.8089],
    oneLiner: "Forest walk at the foot of Doi Suthep, locals jog here at dawn.",
    soloOverall: 8.0,
    bestTimes: [{ startHour: 6, endHour: 9 }],
    durationMin: 45,
    durationMax: 90,
  }),
  exp({
    id: "exp_dev_warorot_dusk",
    title: "Drift through Warorot Market at closing",
    category: "hidden",
    coords: [98.9971, 18.7913],
    oneLiner: "When the day market winds down and the night market hasn't opened.",
    soloOverall: 7.6,
    bestTimes: [{ startHour: 17, endHour: 19 }],
    durationMin: 30,
    durationMax: 60,
  }),
  exp({
    id: "exp_dev_makers_lib",
    title: "Work a long afternoon at Maker's Library",
    category: "work",
    coords: [98.9778, 18.7868],
    oneLiner: "Quiet co-working with strong wifi, water included, no time limit.",
    soloOverall: 9.0,
    bestTimes: [{ startHour: 10, endHour: 18 }],
    durationMin: 120,
    durationMax: 300,
  }),
  exp({
    id: "exp_dev_riverside_jazz",
    title: "Catch the late set at North Gate Jazz Co-op",
    category: "nightlife",
    coords: [98.9881, 18.7942],
    oneLiner: "Tuesday open jam — bar seats face the band, drink minimum is fair.",
    soloOverall: 7.8,
    bestTimes: [{ startHour: 21, endHour: 24 }],
    durationMin: 60,
    durationMax: 120,
  }),
];
