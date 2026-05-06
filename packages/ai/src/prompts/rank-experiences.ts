import Anthropic from "@anthropic-ai/sdk";
import {
  type Coordinates,
  type Experience,
  distanceMeters,
  walkingMinutes,
} from "@solo-compass/core";

export interface RankExperiencesInput {
  /** [longitude, latitude] — GeoJSON order. */
  userLocation: Coordinates;
  /** Transcribed voice or typed text describing what the user wants. */
  userIntent: string;
  /** Pool of experiences to rank from. */
  availableExperiences: Experience[];
  /** Local hour 0–23 in the user's current city. */
  currentHour: number;
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

const RANK_TOOL: Anthropic.Tool = {
  name: "emit_ranking",
  description:
    "Emit the top 3 experiences ranked by how well they match the user's intent, time of day, proximity, and solo-friendliness.",
  input_schema: {
    type: "object" as const,
    required: ["ranked"],
    properties: {
      ranked: {
        type: "array",
        description:
          "Exactly 3 experiences, ordered best-first. Use the experienceId from the candidate list. Never invent ids.",
        items: {
          type: "object",
          required: ["experienceId", "score", "reason"],
          properties: {
            experienceId: {
              type: "string",
              description: "The id field of one of the candidate experiences.",
            },
            score: {
              type: "number",
              minimum: 0,
              maximum: 100,
              description: "0–100. Composite of intent fit, time fit, proximity, solo-friendliness.",
            },
            reason: {
              type: "string",
              description:
                "One sentence (≤140 chars) explaining the match. Concrete, not generic. No emojis.",
            },
          },
        },
      },
    },
  },
};

const SYSTEM_PROMPT = `You rank solo-travel experiences for a single user request.

PRINCIPLES (in priority order):
1. Intent fit — does the experience match what the user said they feel like doing?
2. Time-of-day fit — is the current hour inside one of the experience's bestTimes windows? Penalize hard if the experience is closed or wrong-time (e.g. sunset spot at 10am).
3. Proximity — closer is better, but a perfect-fit 25 min walk beats a poor-fit 5 min walk.
4. Solo-friendliness — soloScore.overall matters; never recommend something that pressures couples/groups.

OUTPUT RULES:
- Return EXACTLY 3 ranked items via emit_ranking. If fewer than 3 candidates exist, return what you have.
- Use the experienceId field exactly as given. Never invent ids.
- The reason must be specific to *this* experience and *this* intent — not generic.
- Voice is calm and factual. No "amazing", no "you'll love", no exclamation marks.`;

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

export async function rankExperiences(
  input: RankExperiencesInput,
  client?: Anthropic,
): Promise<RankExperiencesResult> {
  const { userLocation, userIntent, availableExperiences, currentHour } = input;

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

Rank the top 3 best matches. Use emit_ranking.`;

  const anthropic = client ?? new Anthropic();
  const response = await anthropic.messages.create({
    model: "claude-opus-4-7",
    max_tokens: 1024,
    system: SYSTEM_PROMPT,
    tools: [RANK_TOOL],
    tool_choice: { type: "tool", name: "emit_ranking" },
    messages: [{ role: "user", content: userMessage }],
  });

  const toolUse = response.content.find((b) => b.type === "tool_use");
  if (!toolUse || toolUse.type !== "tool_use" || toolUse.name !== "emit_ranking") {
    return { ranked: [] };
  }

  const args = toolUse.input as {
    ranked: Array<{ experienceId: string; score: number; reason: string }>;
  };

  const byId = new Map(withWalking.map((c) => [c.exp.id as string, c]));
  const ranked: RankedExperience[] = [];
  for (const item of args.ranked) {
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
