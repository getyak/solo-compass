/**
 * DeepSeek client factory — DeepSeek is OpenAI protocol-compatible, so we
 * point the OpenAI SDK at DeepSeek's base URL.
 *
 * Reads from process.env:
 *   DEEPSEEK_API_KEY    (required at runtime — throws when actually called)
 *   DEEPSEEK_BASE_URL   (defaults to https://api.deepseek.com/v1)
 *   DEEPSEEK_MODEL      (defaults to deepseek-flash)
 *
 * DeepSeek V4.1 enables "high" thinking by default. The request bodies built
 * here explicitly disable it with a top-level `thinking: {"type":"disabled"}`
 * wire field because the app's callers cap max_tokens at 256–4096 and do not
 * retain `reasoning_content`. See
 * https://api-docs.deepseek.com/guides/thinking_mode/.
 */

import OpenAI from "openai";

export const DEFAULT_DEEPSEEK_BASE_URL = "https://api.deepseek.com/v1";
export const DEFAULT_DEEPSEEK_MODEL = "deepseek-flash";

/**
 * Model ids that predate the V4.1 Flash default. A saved legacy selection or
 * an old `DEEPSEEK_MODEL` env var must not silently keep a built-in default
 * route on an outdated model.
 */
export const LEGACY_DEEPSEEK_MODELS: ReadonlySet<string> = new Set([
  "deepseek-chat",
  "deepseek-reasoner",
  "deepseek-v4-pro",
  "deepseek-v4-flash",
]);

/** Map legacy / empty model ids to the built-in default; pass others through. */
export function normalizeDeepseekModel(raw?: string | null): string {
  const model = (raw ?? "").trim();
  if (!model || LEGACY_DEEPSEEK_MODELS.has(model)) return DEFAULT_DEEPSEEK_MODEL;
  return model;
}

export function deepseekModel(): string {
  return normalizeDeepseekModel(process.env["DEEPSEEK_MODEL"]);
}

export function deepseekBaseURL(): string {
  return process.env["DEEPSEEK_BASE_URL"] || DEFAULT_DEEPSEEK_BASE_URL;
}

/**
 * DeepSeek V4.1 thinking mode is on ("high") by default. Built-in routes
 * disable it so latency and tool-call compatibility stay as before. This MUST
 * land at the top level of the wire JSON — never nested under `extra_body`.
 */
export const DEEPSEEK_THINKING_DISABLED = { type: "disabled" } as const;

/**
 * Attach DeepSeek's top-level thinking control to a chat-completions payload
 * without losing the SDK's parameter typing. The extra `thinking` field is not
 * (yet) part of the OpenAI SDK types, so we widen the object rather than risk
 * an `extra_body`-nested body that DeepSeek would ignore.
 */
export function withDeepSeekThinkingDisabled<T extends object>(
  params: T,
): T & { thinking: typeof DEEPSEEK_THINKING_DISABLED } {
  return { ...params, thinking: DEEPSEEK_THINKING_DISABLED };
}

/**
 * Create an OpenAI SDK client pointed at DeepSeek. Pass `apiKey` to override
 * the env var (mostly used in tests).
 */
export function createDeepseekClient(apiKey?: string): OpenAI {
  const key = apiKey ?? process.env["DEEPSEEK_API_KEY"];
  if (!key) {
    throw new Error("DEEPSEEK_API_KEY is not set. Copy .env.example to .env and fill it in.");
  }
  return new OpenAI({ apiKey: key, baseURL: deepseekBaseURL() });
}
