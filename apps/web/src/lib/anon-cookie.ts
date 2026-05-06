/**
 * Opaque anonymous-user cookie. First-party only. No PII, no fingerprinting,
 * no cross-domain sharing. Used to deduplicate completions.
 *
 * Server-side helpers — read or mint the cookie inside a route handler.
 */

import { cookies } from "next/headers";

const COOKIE_NAME = "sc_anon";
const ONE_YEAR_SECONDS = 60 * 60 * 24 * 365;

/** Returns the existing cookie value, or null when absent. */
export async function readAnonId(): Promise<string | null> {
  const store = await cookies();
  return store.get(COOKIE_NAME)?.value ?? null;
}

/**
 * Returns the existing cookie or mints a new one. The returned value should
 * be set on the response via `setAnonCookie` whenever it was newly minted.
 */
export async function readOrMintAnonId(): Promise<{ id: string; minted: boolean }> {
  const existing = await readAnonId();
  if (existing) return { id: existing, minted: false };
  const id = crypto.randomUUID();
  return { id, minted: true };
}

/** Cookie attributes used when writing back via NextResponse. */
export const anonCookieOptions = {
  name: COOKIE_NAME,
  httpOnly: true,
  sameSite: "lax" as const,
  secure: process.env.NODE_ENV === "production",
  path: "/",
  maxAge: ONE_YEAR_SECONDS,
};
