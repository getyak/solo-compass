/**
 * DeepSeek client factory — DeepSeek is OpenAI protocol-compatible, so we
 * point the OpenAI SDK at DeepSeek's base URL.
 *
 * Reads from process.env:
 *   DEEPSEEK_API_KEY    (required at runtime — throws when actually called)
 *   DEEPSEEK_BASE_URL   (defaults to https://api.deepseek.com/v1)
 *   DEEPSEEK_MODEL      (defaults to deepseek-v4-pro)
 */

import OpenAI from "openai";

export const DEFAULT_DEEPSEEK_BASE_URL = "https://api.deepseek.com/v1";
export const DEFAULT_DEEPSEEK_MODEL = "deepseek-v4-pro";

export function deepseekModel(): string {
  return process.env["DEEPSEEK_MODEL"] || DEFAULT_DEEPSEEK_MODEL;
}

export function deepseekBaseURL(): string {
  return process.env["DEEPSEEK_BASE_URL"] || DEFAULT_DEEPSEEK_BASE_URL;
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
