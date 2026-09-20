/**
 * Cost monitoring wrapper for DeepSeek (OpenAI-compatible) chat-completions.
 *
 * Logs a structured JSON line to stdout on every call so log drains can
 * aggregate spend without a dedicated metrics backend.
 */

import type OpenAI from "openai";
import { PostHog } from "posthog-node";

// ─── Pricing constants — deepseek-flash, per million tokens, in cents ─────────
// Conservative PEAK UNCACHED estimate; DeepSeek bills less off-peak and for
// cache hits, so this over-counts rather than under-counts spend.
// Official pricing: https://api-docs.deepseek.com/quick_start/pricing/
//   input  $0.30 / M (peak, uncached)
//   output $1.20 / M
const PRICE_PER_M = {
  input: 30, // $0.30 / M
  output: 120, // $1.20 / M
} as const;

const WARNING_THRESHOLD_CENTS = 500; // $5 per single call

// ─── PostHog client (lazy, module-scoped) ─────────────────────────────────────

let _posthog: PostHog | null = null;

function getPostHog(): PostHog | null {
  const apiKey = process.env["POSTHOG_API_KEY"];
  if (!apiKey) return null;
  if (!_posthog) {
    _posthog = new PostHog(apiKey, {
      host: process.env["POSTHOG_HOST"] ?? "https://app.posthog.com",
    });
  }
  return _posthog;
}

// ─── Types ────────────────────────────────────────────────────────────────────

export interface CostSnapshot {
  inputTokens: number;
  outputTokens: number;
  /** Integer cents. */
  estimatedUsdCents: number;
  model: string;
  /** Caller label, e.g. "nearby" or "bot:voice". */
  route: string;
  durationMs: number;
}

// ─── trackCost ────────────────────────────────────────────────────────────────

export function trackCost(snapshot: CostSnapshot): void {
  const logEntry = {
    event: "ai_cost",
    route: snapshot.route,
    usd_cents: snapshot.estimatedUsdCents,
    model: snapshot.model,
    input_tokens: snapshot.inputTokens,
    output_tokens: snapshot.outputTokens,
    duration_ms: snapshot.durationMs,
  };
  console.log(JSON.stringify(logEntry));

  if (snapshot.estimatedUsdCents > WARNING_THRESHOLD_CENTS) {
    console.warn(
      `[ai_cost WARNING] Single call exceeded $${(WARNING_THRESHOLD_CENTS / 100).toFixed(2)}: ` +
        `route=${snapshot.route} usd_cents=${snapshot.estimatedUsdCents}`,
    );
  }

  const ph = getPostHog();
  if (ph) {
    try {
      ph.capture({
        distinctId: "system",
        event: "ai_cost",
        properties: {
          route: snapshot.route,
          usd_cents: snapshot.estimatedUsdCents,
          model: snapshot.model,
          input_tokens: snapshot.inputTokens,
          output_tokens: snapshot.outputTokens,
          duration_ms: snapshot.durationMs,
        },
      });
    } catch (err) {
      console.warn("[ai_cost] PostHog capture failed:", err);
    }
  }
}

// ─── estimateCents ────────────────────────────────────────────────────────────

function estimateCents(usage: OpenAI.CompletionUsage): number {
  const inputCents = (usage.prompt_tokens / 1_000_000) * PRICE_PER_M.input;
  const outputCents = (usage.completion_tokens / 1_000_000) * PRICE_PER_M.output;
  return Math.round(inputCents + outputCents);
}

// ─── withCostTracking ─────────────────────────────────────────────────────────

export async function withCostTracking<T>(
  route: string,
  fn: () => Promise<{ result: T; usage: OpenAI.CompletionUsage; model: string }>,
): Promise<T> {
  const startMs = Date.now();
  const { result, usage, model } = await fn();
  const durationMs = Date.now() - startMs;

  const snapshot: CostSnapshot = {
    inputTokens: usage.prompt_tokens,
    outputTokens: usage.completion_tokens,
    estimatedUsdCents: estimateCents(usage),
    model,
    route,
    durationMs,
  };

  trackCost(snapshot);
  return result;
}
