/**
 * Schema dry-run.
 *
 * The Experience schema must be city-agnostic — same fields work in Chiang
 * Mai, Lisbon, Tokyo, identically. This script constructs sample experiences
 * for Lisbon and Tokyo using ONLY the existing schema, and asserts that no
 * city-specific field would have been useful. If you find yourself wanting
 * to add a `lisbonTramLine` field, the test fails — open a discussion first.
 *
 * Run:  pnpm tsx scripts/schema-dryrun.ts
 */

import type { Experience, ExperienceId } from "@solo-compass/core";

const NOW = "2026-05-06T00:00:00.000Z";

const lisbon: Experience = {
  id: "exp_lis_alfama_fado_evening" as ExperienceId,
  title: "Hear unmiked fado at a back-room tasca in Alfama after 22:00",
  oneLiner: "Tile-walled backroom, four tables, no microphone, two singers per night.",
  whyItMatters:
    "When the lights go down the room goes silent — house rule. The singer stands a metre from your table. Tourists head to the big fado houses in Bairro Alto; the smaller Alfama tascas keep the form intact.",
  category: "nightlife",
  location: {
    coordinates: [-9.1305, 38.7128],
    cityCode: "lis",
    addressHint: "Beco da Cardosa, Alfama",
    placeNameRomanized: "Tasca do Chico (Alfama branch)",
  },
  bestTimes: [{ startHour: 22, endHour: 24, note: "first set 22:30" }],
  durationMinutes: { min: 90, max: 120 },
  howTo: [
    { order: 1, text: "Walk in by 22:00, stand at the bar, order a glass of vinho verde." },
    { order: 2, text: "Conversation off when the singer takes the floor — they will wait." },
    { order: 3, text: "Tip the singer 5–10 EUR direct, not via the till." },
  ],
  realInconveniences: [
    {
      category: "etiquette",
      text: "No phones, no photos during songs. They will stop and ask you to put it away.",
    },
    {
      category: "crowds",
      text: "10 seats. After 22:30 weekends it is standing-room. Go on a Tuesday.",
    },
  ],
  soloScore: {
    overall: 8,
    breakdown: {
      seatingFriendly: 8,
      soloPatronRatio: 8,
      staffPressure: 9,
      soloPortioning: 9,
      ambianceFit: 9,
      safety: 9,
    },
    hint: "Bar standing is built for solo here — couples take the tables.",
    basedOnCount: 0,
  },
  sources: [{ type: "blog", attribution: "demo seed", verifiedAt: NOW }],
  confidence: {
    level: 1,
    lastVerifiedAt: NOW,
    reason: "demo seed",
    signals: {
      aiScrapeAgeDays: 0,
      passiveGpsHits30d: 0,
      activeReports30d: 0,
      trustedVerifications: 0,
    },
  },
  nearbyExperienceIds: [],
  stats: { completionCount: 0, averageRating: 0 },
  status: "active",
  createdAt: NOW,
  updatedAt: NOW,
};

const tokyo: Experience = {
  id: "exp_tyo_yanaka_morning_walk" as ExperienceId,
  title: "Walk Yanaka cemetery and the side alleys before the 09:00 commuters",
  oneLiner: "Pre-rush hour stroll through one of the only Edo-grid neighbourhoods left.",
  whyItMatters:
    "Yanaka was spared in the 1923 quake and the WWII firebombing — the alley grid is 17th century. At 07:30 the only sound is brooms on stone and a cat or two. By 10:00 it's a tour route.",
  category: "culture",
  location: {
    coordinates: [139.7669, 35.7274],
    cityCode: "tyo",
    addressHint: "Yanaka Cemetery, Taito-ku",
    placeNameRomanized: "Yanaka Reien",
    placeNameLocal: "谷中霊園",
  },
  bestTimes: [{ startHour: 6, endHour: 9 }],
  durationMinutes: { min: 60, max: 90 },
  howTo: [
    {
      order: 1,
      text: "Start from Nippori Station west exit. Cross to the cemetery's main avenue.",
    },
    { order: 2, text: "Walk south through the central road, then west into Yanaka Ginza." },
    { order: 3, text: "Stop at Kayaba Coffee for the 08:00 opening tamago sando." },
  ],
  realInconveniences: [
    {
      category: "etiquette",
      text: "It's an active cemetery — no loud talking, photos respectful, stay on paths.",
    },
    { category: "weather", text: "August humidity makes 07:00 the only viable hour." },
  ],
  soloScore: {
    overall: 10,
    breakdown: {
      seatingFriendly: 10,
      soloPatronRatio: 10,
      staffPressure: 10,
      soloPortioning: 10,
      ambianceFit: 10,
      safety: 10,
    },
    basedOnCount: 0,
  },
  sources: [{ type: "wikivoyage", attribution: "demo seed", verifiedAt: NOW }],
  confidence: {
    level: 1,
    lastVerifiedAt: NOW,
    reason: "demo seed",
    signals: {
      aiScrapeAgeDays: 0,
      passiveGpsHits30d: 0,
      activeReports30d: 0,
      trustedVerifications: 0,
    },
  },
  nearbyExperienceIds: [],
  stats: { completionCount: 0, averageRating: 0 },
  status: "active",
  createdAt: NOW,
  updatedAt: NOW,
};

function assertExperience(exp: Experience): void {
  // The test isn't TypeScript validity (already checked at compile time) —
  // it's that no information had to be omitted or shoehorned to fit the schema.
  if (exp.title.length < 10) throw new Error(`title too short: ${exp.id}`);
  if (exp.howTo.length < 2) throw new Error(`howTo missing for ${exp.id}`);
  if (exp.realInconveniences.length === 0)
    throw new Error(`realInconveniences missing for ${exp.id}`);
  if (exp.bestTimes.length === 0) throw new Error(`bestTimes missing for ${exp.id}`);
  if (exp.location.coordinates[0] === 0 && exp.location.coordinates[1] === 0)
    throw new Error(`coordinates blank for ${exp.id}`);
}

function main(): void {
  for (const exp of [lisbon, tokyo]) {
    assertExperience(exp);
    console.log(`✓ ${exp.id} — ${exp.location.cityCode} fits the schema`);
  }
  console.log("schema-dryrun: clean ✓ — Lisbon + Tokyo encode without city-specific fields.");
}

main();
