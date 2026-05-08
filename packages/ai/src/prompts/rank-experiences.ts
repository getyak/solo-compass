import type OpenAI from "openai";
import {
  type Coordinates,
  type Experience,
  distanceMeters,
  walkingMinutes,
} from "@solo-compass/core";
import { createDeepseekClient, deepseekModel } from "../client";
import { withCostTracking } from "../cost-tracker";
import { withRetry } from "../retry";

export interface RankExperiencesInput {
  /** [longitude, latitude] — GeoJSON order. */
  userLocation: Coordinates;
  /** Transcribed voice or typed text describing what the user wants. */
  userIntent: string;
  /** Pool of experiences to rank from. */
  availableExperiences: Experience[];
  /** Local hour 0–23 in the user's current city. */
  currentHour: number;
  /** Caller label passed through to cost tracking, e.g. "nearby" or "bot:voice". */
  route?: string;
}

export interface RankedExperience {
  experience: Experience;
  /** 0–100. Higher = better match. */
  score: number;
  /** One sentence explaining why this matches. */
  reason: string;
  /** Estimated walking time from user location, minutes. */
  walkingMinutes: number;
}

export interface RankExperiencesResult {
  ranked: RankedExperience[];
}

const SYSTEM_PROMPT = `You rank solo-travel experiences for a single user request.

PRINCIPLES (in priority order):
1. Intent fit — does the experience match what the user said they feel like doing?
2. Time-of-day fit — is the current hour inside one of the experience's bestTimes windows? Penalize hard if the experience is closed or wrong-time (e.g. sunset spot at 10am).
3. Proximity — closer is better, but a perfect-fit 25 min walk beats a poor-fit 5 min walk.
4. Solo-friendliness — soloScore.overall matters; never recommend something that pressures couples/groups.

OUTPUT RULES:
- Output ONLY a JSON object with NO markdown fences, NO extra text.
- The JSON object must have exactly one key: "ranked" — an array of up to 3 items ordered best-first.
- Each item: { "experienceId": string, "score": number (0-100), "reason": string (≤140 chars, specific, no emojis) }
- Use the experienceId field exactly as given. Never invent ids.
- If fewer than 3 candidates exist, return what you have.
- Voice is calm and factual. No "amazing", no "you'll love", no exclamation marks.

Example output (use this exact shape):
{"ranked":[{"experienceId":"exp_abc","score":87,"reason":"Quiet temple courtyard perfect for a solo morning walk away from crowds."}]}`;

function summarizeExperience(exp: Experience, walkMin: number): string {
  const bestTimes =
    exp.bestTimes.length === 0
      ? "anytime"
      : exp.bestTimes
          .map((t) => `${t.startHour}–${t.endHour}${t.note ? ` (${t.note})` : ""}`)
          .join(", ");
  const inconveniences = exp.realInconveniences
    .slice(0, 2)
    .map((r) => `${r.category}: ${r.text}`)
    .join("; ");
  return [
    `id: ${exp.id}`,
    `title: ${exp.title}`,
    `category: ${exp.category}`,
    `oneLiner: ${exp.oneLiner}`,
    `bestTimes: ${bestTimes}`,
    `durationMin: ${exp.durationMinutes.min}–${exp.durationMinutes.max}m`,
    `walkingMinutes: ${walkMin}`,
    `soloScore: ${exp.soloScore.overall}/10`,
    inconveniences ? `inconveniences: ${inconveniences}` : "",
  ]
    .filter(Boolean)
    .join("\n");
}

/** Strip ```json ... ``` or ``` ... ``` fences that some models emit despite instructions. */
function stripFences(raw: string): string {
  return raw
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```\s*$/, "")
    .trim();
}

export async function rankExperiences(
  input: RankExperiencesInput,
  client?: OpenAI,
): Promise<RankExperiencesResult> {
  const { userLocation, userIntent, availableExperiences, currentHour, route = "rank" } = input;

  if (availableExperiences.length === 0) {
    return { ranked: [] };
  }

  const withWalking = availableExperiences.map((exp) => {
    const meters = distanceMeters(userLocation, exp.location.coordinates);
    return { exp, walkMin: walkingMinutes(meters), meters };
  });

  // Pre-prune: if there are many candidates, send only the closest ~20 to the model.
  const pruned = withWalking
    .slice()
    .sort((a, b) => a.meters - b.meters)
    .slice(0, 20);

  const candidatesText = pruned
    .map((c, i) => `--- candidate ${i + 1} ---\n${summarizeExperience(c.exp, c.walkMin)}`)
    .join("\n\n");

  const userMessage = `User location: [${userLocation[0]}, ${userLocation[1]}] (lng, lat)
Current local hour: ${currentHour} (0–23)
User intent: "${userIntent}"

Candidate experiences (already filtered to nearest ~20):

${candidatesText}

Rank the top 3 best matches. Output ONLY the JSON object.`;

  const deepseek = client ?? createDeepseekClient();

  const response = await withRetry(() =>
    withCostTracking(route, async () => {
      const msg = await deepseek.chat.completions.create({
        model: deepseekModel(),
        max_tokens: 1024,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: userMessage },
        ],
      });
      const usage = msg.usage ?? { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 };
      return { result: msg, usage, model: msg.model };
    }),
  );

  const raw = response.choices[0]?.message.content ?? "";
  let parsed: { ranked: Array<{ experienceId: string; score: number; reason: string }> };
  try {
    parsed = JSON.parse(stripFences(raw)) as typeof parsed;
  } catch {
    return { ranked: [] };
  }

  if (!Array.isArray(parsed.ranked)) {
    return { ranked: [] };
  }

  const byId = new Map(withWalking.map((c) => [c.exp.id as string, c]));
  const ranked: RankedExperience[] = [];
  for (const item of parsed.ranked) {
    const match = byId.get(item.experienceId);
    if (!match) continue;
    ranked.push({
      experience: match.exp,
      score: Math.max(0, Math.min(100, item.score)),
      reason: item.reason,
      walkingMinutes: match.walkMin,
    });
    if (ranked.length === 3) break;
  }

  return { ranked };
}
