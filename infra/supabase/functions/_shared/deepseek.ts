// deepseek — pure, zero-dependency wire helpers shared by every
// DeepSeek-compatible Edge Function (chat-proxy, compile-city-brief,
// enrich-user-experience, synthesize-experiences) and their vitest unit
// tests (Node).
//
// NOTHING here imports anything: no supabase-js, no Deno globals, no fetch.
// It owns the built-in model default, legacy-id normalization, top-level
// thinking-mode control (DeepSeek V4.1 enables "high" thinking by default),
// and the OpenAI-compatible request/response shape so all four functions
// stay in lock-step.
//
// Docs: https://api-docs.deepseek.com/guides/thinking_mode/ — thinking is
// disabled with a top-level `thinking: {"type":"disabled"}` wire field. The
// app's tool loops do not retain `reasoning_content`, so built-in routes
// disable it to preserve non-thinking latency/tool compatibility. It must be
// top-level, never nested under `extra_body`.

/** Built-in DeepSeek model for all Solo Compass AI routes. */
export const DEFAULT_DEEPSEEK_MODEL = "deepseek-flash";

/** OpenAI-compatible DeepSeek base URL (no trailing slash). */
export const DEFAULT_DEEPSEEK_BASE_URL = "https://api.deepseek.com/v1";

/**
 * Model ids that predate the V4.1 Flash default. A saved legacy selection or
 * an old `DEEPSEEK_MODEL` secret must not silently keep a built-in default
 * route on an outdated model, so they normalize to `deepseek-flash`.
 */
export const LEGACY_DEEPSEEK_MODELS: ReadonlySet<string> = new Set([
  "deepseek-chat",
  "deepseek-reasoner",
  "deepseek-v4-pro",
  "deepseek-v4-flash",
]);

/** Map legacy / empty model ids to the built-in default; pass others through. */
export function normalizeDeepSeekModel(raw?: string | null): string {
  const model = (raw ?? "").trim();
  if (!model || LEGACY_DEEPSEEK_MODELS.has(model)) return DEFAULT_DEEPSEEK_MODEL;
  return model;
}

/** Normalize a DeepSeek base URL, stripping trailing slashes. */
export function deepSeekBaseUrl(raw?: string | null): string {
  const base = (raw ?? "").trim() || DEFAULT_DEEPSEEK_BASE_URL;
  return base.replace(/\/+$/, "");
}

/**
 * Build the OpenAI-compatible `/chat/completions` body sent to DeepSeek.
 *
 * Built-in server paths are service-paid DeepSeek routes, so this is
 * authoritative: it resolves a non-legacy model and **always** disables
 * thinking, overriding any client/init value. A top-level
 * `thinking: {"type":"disabled"}` is emitted (never nested under
 * `extra_body`). Explicit OpenAI/custom provider support belongs to direct
 * configured client paths, not this helper.
 */
export function buildDeepSeekChatBody(init: Record<string, unknown>): Record<string, unknown> {
  const model = normalizeDeepSeekModel(
    typeof init["model"] === "string" ? (init["model"] as string) : undefined,
  );
  return { ...init, model, thinking: { type: "disabled" } };
}

/** Extract assistant text from an OpenAI-compatible chat-completions reply. */
export function parseDeepSeekContent(json: unknown): string {
  const choices = (json as { choices?: Array<{ message?: { content?: unknown } }> } | null)
    ?.choices;
  const content = choices?.[0]?.message?.content;
  return typeof content === "string" ? content : "";
}

/** Extract token usage, defaulting missing counters to zero. */
export function parseDeepSeekUsage(json: unknown): {
  prompt_tokens: number;
  completion_tokens: number;
} {
  const usage = (
    json as { usage?: { prompt_tokens?: unknown; completion_tokens?: unknown } } | null
  )?.usage;
  return {
    prompt_tokens: typeof usage?.prompt_tokens === "number" ? usage.prompt_tokens : 0,
    completion_tokens: typeof usage?.completion_tokens === "number" ? usage.completion_tokens : 0,
  };
}

/**
 * Parse the first `[ … ]` JSON array out of a model reply that may be wrapped
 * in prose or markdown fences. Returns null when no valid array is present.
 */
export function parseJsonArrayFromText(text: string): unknown[] | null {
  const start = text.indexOf("[");
  const end = text.lastIndexOf("]");
  if (start === -1 || end === -1 || end <= start) return null;
  try {
    const parsed: unknown = JSON.parse(text.substring(start, end + 1));
    return Array.isArray(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

/**
 * Parse the first `{ … }` JSON object out of a model reply that may be wrapped
 * in prose or markdown fences. Returns null when no valid object is present.
 */
export function parseJsonObjectFromText(text: string): Record<string, unknown> | null {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start === -1 || end === -1 || end <= start) return null;
  try {
    const parsed: unknown = JSON.parse(text.substring(start, end + 1));
    return parsed !== null && typeof parsed === "object" && !Array.isArray(parsed)
      ? (parsed as Record<string, unknown>)
      : null;
  } catch {
    return null;
  }
}
