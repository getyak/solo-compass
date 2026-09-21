import { distanceMeters } from "@solo-compass/core";

export interface PlaceMatchCandidate {
  readonly sourceId: string;
  readonly title: string;
  readonly coordinates?: readonly [longitude: number, latitude: number];
}

export interface ExperienceAnchor {
  readonly experienceId: string;
  readonly placeName: string;
  readonly coordinates: readonly [longitude: number, latitude: number];
}

export interface EntityMatch {
  readonly experienceId: string;
  readonly confidence: number;
  readonly method: "external_id" | "name_and_distance";
}

const MAX_DISTANCE_METERS = 200;
const MIN_SCORE = 0.62;
const AMBIGUITY_MARGIN = 0.08;

/** Conservative linker: ambiguous candidates stay unlinked for later review. */
export function matchCandidateToExperience(
  candidate: PlaceMatchCandidate,
  anchors: readonly ExperienceAnchor[],
): EntityMatch | null {
  const sourceTail = candidate.sourceId.split(":").at(-1);
  if (sourceTail) {
    const direct = anchors.find((anchor) => anchor.experienceId === `exp_osm_${sourceTail}`);
    if (direct)
      return { experienceId: direct.experienceId, confidence: 0.99, method: "external_id" };
  }
  if (!candidate.coordinates) return null;

  const scored = anchors
    .map((anchor) => {
      const meters = distanceMeters(candidate.coordinates!, anchor.coordinates);
      const name = nameSimilarity(candidate.title, anchor.placeName);
      const distance = Math.max(0, 1 - meters / MAX_DISTANCE_METERS);
      return { anchor, meters, score: 0.7 * name + 0.3 * distance };
    })
    .filter((item) => item.meters <= MAX_DISTANCE_METERS && item.score >= MIN_SCORE)
    .sort((left, right) => right.score - left.score);

  const best = scored[0];
  if (!best) return null;
  const second = scored[1];
  if (second && best.score - second.score < AMBIGUITY_MARGIN) return null;
  return {
    experienceId: best.anchor.experienceId,
    confidence: Math.min(0.95, best.score),
    method: "name_and_distance",
  };
}

function nameSimilarity(left: string, right: string): number {
  const leftTokens = tokens(left);
  const rightTokens = tokens(right);
  if (leftTokens.size === 0 || rightTokens.size === 0) return 0;
  const intersection = [...leftTokens].filter((token) => rightTokens.has(token)).length;
  const union = new Set([...leftTokens, ...rightTokens]).size;
  const jaccard = intersection / union;
  const leftJoined = [...leftTokens].join(" ");
  const rightJoined = [...rightTokens].join(" ");
  const containment = leftJoined.includes(rightJoined) || rightJoined.includes(leftJoined) ? 1 : 0;
  return Math.max(jaccard, containment);
}

function tokens(value: string): Set<string> {
  return new Set(
    value
      .normalize("NFKC")
      .toLocaleLowerCase()
      .replace(/[\p{P}\p{S}]+/gu, " ")
      .split(/\s+/)
      .map((token) => token.trim())
      .filter(Boolean),
  );
}
