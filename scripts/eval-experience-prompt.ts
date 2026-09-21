#!/usr/bin/env tsx
/**
 * Evaluation harness for the experience-structuring prompt.
 *
 * Usage:
 *   pnpm tsx scripts/eval-experience-prompt.ts
 *
 * Runs the prompt against 5 synthetic Chiang Mai source samples and checks:
 * - Output shape matches Experience interface
 * - realInconveniences is never empty
 * - title is action-oriented (not a bare place name)
 * - confidence.level === 1
 * - Thin sources trigger refuse(), not a hallucinated experience
 */

import { structureExperience } from "../packages/ai/src/prompts/structure-experience";
import { DEFAULT_DEEPSEEK_MODEL } from "../packages/ai/src/client";
import type { Experience } from "../packages/core/src";

// ─── Test fixtures ─────────────────────────────────────────────────────────────

interface TestCase {
  name: string;
  input: Parameters<typeof structureExperience>[0];
  /** If true, we expect experience === null (refusal). */
  expectRefusal: boolean;
  /** Field-level checks run when experience !== null. */
  checks?: Array<(exp: Experience) => { pass: boolean; message: string }>;
}

const CASES: TestCase[] = [
  {
    name: "Rich Wikivoyage — Doi Suthep sunrise hike",
    expectRefusal: false,
    input: {
      cityCode: "cmi",
      cityName: "Chiang Mai",
      sourceType: "wikivoyage",
      sourceUrl: "https://en.wikivoyage.org/wiki/Chiang_Mai",
      rawText: `
Doi Suthep-Pui National Park rises steeply west of the city. The paved road to Doi Suthep
temple (Wat Phra That Doi Suthep) winds 15 km up to 1,073 m. Minivans (songthaew) leave
from the moat area near Tha Phae Gate daily from 06:00; the ride takes 30–40 min and costs
50 THB one way. The temple opens at 06:00 and foreigners pay a 30 THB entry fee.

Arrive by 06:30 to watch sunrise from the Naga staircase (309 steps) before tour groups
arrive around 08:30. The gilded chedi turns pale gold at dawn before warming to deep orange
as the sun clears the ridge. Monks chant at 07:00 in the wihan; visitors may observe quietly
from the back.

Inconveniences: the staircase is steep and uneven — sandals will slip on wet mornings.
Vendors at the base are aggressive; decline firmly and keep walking. During peak season
(Dec–Feb) the car park fills by 08:00 and songthaew waits can stretch to 45 min.
Modest dress required (shoulders and knees covered); sarongs available to borrow at entrance.
      `,
    },
    checks: [
      (exp) => ({
        pass: exp.realInconveniences.length > 0,
        message: "realInconveniences must not be empty",
      }),
      (exp) => ({
        pass: exp.confidence.level === 1,
        message: "confidence.level must be 1 (AI scrape)",
      }),
      (exp) => ({
        pass: !/^(wat |doi |temple$)/i.test(exp.title),
        message: "title must be action-oriented, not a bare place name",
      }),
      (exp) => ({
        pass: exp.howTo.length >= 3,
        message: "howTo must have at least 3 steps",
      }),
      (exp) => ({
        pass: exp.status === "candidate",
        message: "status must be 'candidate'",
      }),
    ],
  },
  {
    name: "Rich Reddit thread — Nimman coffee crawl",
    expectRefusal: false,
    input: {
      cityCode: "cmi",
      cityName: "Chiang Mai",
      sourceType: "reddit",
      sourceUrl: "https://www.reddit.com/r/chiangmai/comments/example",
      rawText: `
Posted by u/espresso_nomad — "The Nimman coffee crawl nobody talks about"

I spent a week doing this and it's now my go-to first morning in CMI. Start at Ristr8to
on Nimman Soi 3 (opens 08:00). Order their lab filter — 120 THB. Tiny space, maybe 10 seats,
but the bar counter gives you the best view of the roaster. Then walk 400m north to
Graph Table on Nimmanhaemin Rd — they do a signature honey process Doi Chaang for 90 THB.
Open from 08:30.

The crawl works best on weekdays. Weekends the Nimman art market takes over and the streets
are genuinely impassable by 10:00. Both shops fill up fast after 09:30 — locals AND
digital nomads compete for outlets. Ristr8to has no wifi as policy; Graph has wifi but
caps it at 2 hours. Bring your own SIM hotspot if you need to work.

Total walk: about 1.5 km, 2–3 hours including sitting time. Costs under 300 THB.
      `,
    },
    checks: [
      (exp) => ({
        pass: exp.realInconveniences.length > 0,
        message: "realInconveniences must not be empty",
      }),
      (exp) => ({
        pass: exp.category === "coffee" || exp.category === "food",
        message: "category should be coffee or food",
      }),
    ],
  },
  {
    name: "Rich blog — Sunday Walking Street",
    expectRefusal: false,
    input: {
      cityCode: "cmi",
      cityName: "Chiang Mai",
      sourceType: "blog",
      sourceUrl: "https://example-travel-blog.com/chiang-mai-sunday-walking-street",
      rawText: `
Wualai Road transforms every Sunday from 17:00 to 23:00 into one of Chiang Mai's best
night markets. Unlike the more touristy Saturday market, this one stays genuinely local —
silverwork vendors, hill-tribe textiles, and street food stalls run by the same families
for decades.

Arrive before 17:30 to walk the full length before crowds peak around 19:00. Enter from
the south end (near the Silver Temple, Wat Sri Suphan) and work north; the best silverwork
is in the first 200m. Street food picks: the khao soi at the red cart 100m from the south
entrance (60 THB), and mango sticky rice near the Wualai-Chang Moi intersection (50 THB).

Practical: bring exact change — most stalls don't break 500 THB notes. Bags get jostled
in peak crowd; keep valuables in a front-facing bag. The road closes to traffic but
motorbikes still push through — watch your ankles. Stalls pack up when they sell out,
usually by 22:00.
      `,
    },
    checks: [
      (exp) => ({
        pass: exp.realInconveniences.length > 0,
        message: "realInconveniences must not be empty",
      }),
      (exp) => ({
        pass: exp.sources.length > 0 && exp.sources[0]!.url !== undefined,
        message: "sources must include the provided URL",
      }),
    ],
  },
  {
    name: "Thin source — should REFUSE (too generic)",
    expectRefusal: true,
    input: {
      cityCode: "cmi",
      cityName: "Chiang Mai",
      sourceType: "blog",
      rawText: `
Chiang Mai is a great city in northern Thailand. There are many temples, great food,
and friendly people. You should definitely visit if you get the chance. The night markets
are fun and there are lots of things to do. Overall a wonderful destination for solo travelers.
      `,
    },
  },
  {
    name: "Thin source — should REFUSE (too short)",
    expectRefusal: true,
    input: {
      cityCode: "cmi",
      cityName: "Chiang Mai",
      sourceType: "wikivoyage",
      rawText: "Wat Chedi Luang — impressive ruined temple in the old city. Worth a visit.",
    },
  },
];

// ─── Runner ────────────────────────────────────────────────────────────────────

interface Result {
  name: string;
  passed: boolean;
  failures: string[];
  experience: Experience | null;
  refusalReason?: string;
  modelConfidence: number;
}

async function runCase(tc: TestCase): Promise<Result> {
  console.log(`\n▶ ${tc.name}`);
  const { experience, refusalReason, modelConfidence } = await structureExperience(tc.input);

  const failures: string[] = [];

  if (tc.expectRefusal) {
    if (experience !== null) {
      failures.push(`Expected refusal but got experience: "${experience.title}"`);
    } else {
      console.log(`  ✓ Refused correctly: ${refusalReason}`);
    }
  } else {
    if (experience === null) {
      failures.push(`Expected experience but got refusal: ${refusalReason}`);
    } else {
      console.log(`  title: ${experience.title}`);
      console.log(`  category: ${experience.category}`);
      console.log(`  inconveniences: ${experience.realInconveniences.length}`);
      console.log(`  model confidence: ${modelConfidence.toFixed(2)}`);

      for (const check of tc.checks ?? []) {
        const { pass, message } = check(experience);
        if (!pass) failures.push(message);
        else console.log(`  ✓ ${message}`);
      }
    }
  }

  if (failures.length > 0) {
    for (const f of failures) console.log(`  ✗ FAIL: ${f}`);
  }

  return {
    name: tc.name,
    passed: failures.length === 0,
    failures,
    experience,
    refusalReason,
    modelConfidence,
  };
}

async function main() {
  console.log("═══ Experience prompt evaluation harness ═══\n");
  console.log(`Running ${CASES.length} test cases against ${DEFAULT_DEEPSEEK_MODEL}\n`);

  if (!process.env["DEEPSEEK_API_KEY"]) {
    console.error("Error: DEEPSEEK_API_KEY env var not set");
    process.exit(1);
  }

  const results: Result[] = [];
  for (const tc of CASES) {
    results.push(await runCase(tc));
  }

  const passed = results.filter((r) => r.passed).length;
  const total = results.length;

  console.log(`\n═══ Results: ${passed}/${total} passed ═══`);
  for (const r of results) {
    const icon = r.passed ? "✅" : "❌";
    console.log(`${icon} ${r.name}`);
    for (const f of r.failures) console.log(`     → ${f}`);
  }

  if (passed < total) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
