import type { Coordinates } from "@solo-compass/core";

export type Stage = "idle" | "awaiting_location" | "awaiting_intent";

export interface Session {
  stage: Stage;
  location?: Coordinates;
  lastIntent?: string;
  /** Cached last ranking so callback queries can resolve detail by index. */
  lastRankedIds?: string[];
}

const SESSIONS = new Map<number, Session>();

export function getSession(userId: number): Session {
  let s = SESSIONS.get(userId);
  if (!s) {
    s = { stage: "idle" };
    SESSIONS.set(userId, s);
  }
  return s;
}

export function resetSession(userId: number): void {
  SESSIONS.set(userId, { stage: "idle" });
}
