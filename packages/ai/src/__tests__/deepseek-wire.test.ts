/**
 * Offline regression tests for the pure DeepSeek wire helpers shared by the
 * Supabase Edge Functions (chat-proxy, compile-city-brief,
 * enrich-user-experience, synthesize-experiences).
 *
 * The actual Deno.serve handlers are exercised separately in
 * `deepseek-edge-functions.test.ts`. No Deno runtime or network access here.
 */

import { describe, it, expect } from "vitest";
import {
  DEFAULT_DEEPSEEK_BASE_URL,
  DEFAULT_DEEPSEEK_MODEL,
  buildDeepSeekChatBody,
  deepSeekBaseUrl,
  normalizeDeepSeekModel,
  parseDeepSeekContent,
  parseDeepSeekUsage,
  parseJsonArrayFromText,
  parseJsonObjectFromText,
} from "../../../../infra/supabase/functions/_shared/deepseek";

const LEGACY_IDS = ["deepseek-chat", "deepseek-reasoner", "deepseek-v4-pro", "deepseek-v4-flash"];

describe("edge deepseek defaults", () => {
  it("uses deepseek-flash and the DeepSeek base URL", () => {
    expect(DEFAULT_DEEPSEEK_MODEL).toBe("deepseek-flash");
    expect(DEFAULT_DEEPSEEK_BASE_URL).toBe("https://api.deepseek.com/v1");
  });

  it("normalizes legacy/empty ids and preserves custom ones", () => {
    for (const id of LEGACY_IDS) expect(normalizeDeepSeekModel(id)).toBe("deepseek-flash");
    expect(normalizeDeepSeekModel(undefined)).toBe("deepseek-flash");
    expect(normalizeDeepSeekModel("openai/gpt-4o-mini")).toBe("openai/gpt-4o-mini");
  });

  it("strips trailing slashes from the base URL", () => {
    expect(deepSeekBaseUrl("https://api.deepseek.com/v1///")).toBe("https://api.deepseek.com/v1");
    expect(deepSeekBaseUrl(null)).toBe("https://api.deepseek.com/v1");
  });
});

describe("buildDeepSeekChatBody", () => {
  it("resolves the model and disables thinking at the top level", () => {
    const body = buildDeepSeekChatBody({
      model: "deepseek-chat",
      max_tokens: 2048,
      messages: [{ role: "user", content: "hi" }],
    });
    expect(body["model"]).toBe("deepseek-flash");
    expect(body["thinking"]).toEqual({ type: "disabled" });
    expect(body["extra_body"]).toBeUndefined();
  });

  it("defaults the model when absent and keeps caller fields", () => {
    const body = buildDeepSeekChatBody({ messages: [{ role: "user", content: "hi" }] });
    expect(body["model"]).toBe("deepseek-flash");
    expect(body["messages"]).toEqual([{ role: "user", content: "hi" }]);
  });

  it("overrides an explicit caller thinking setting (server paths are authoritative)", () => {
    const body = buildDeepSeekChatBody({ thinking: { type: "enabled" }, messages: [] });
    expect(body["thinking"]).toEqual({ type: "disabled" });
  });

  it("treats an explicit null thinking as disabled", () => {
    const body = buildDeepSeekChatBody({ thinking: null, messages: [] });
    expect(body["thinking"]).toEqual({ type: "disabled" });
  });
});

describe("parseDeepSeekContent / parseDeepSeekUsage", () => {
  it("reads choices[0].message.content", () => {
    const json = { choices: [{ message: { content: "hello" } }] };
    expect(parseDeepSeekContent(json)).toBe("hello");
    expect(parseDeepSeekContent({ choices: [] })).toBe("");
    expect(parseDeepSeekContent(null)).toBe("");
  });

  it("defaults missing usage counters to zero", () => {
    expect(parseDeepSeekUsage({ usage: { prompt_tokens: 12, completion_tokens: 3 } })).toEqual({
      prompt_tokens: 12,
      completion_tokens: 3,
    });
    expect(parseDeepSeekUsage({})).toEqual({ prompt_tokens: 0, completion_tokens: 0 });
  });
});

describe("parseJsonArrayFromText", () => {
  it("extracts an array from prose/fence-wrapped output", () => {
    const text = 'Sure!\n```json\n[{"osmId":1}]\n```';
    expect(parseJsonArrayFromText(text)).toEqual([{ osmId: 1 }]);
  });

  it("returns null for non-arrays and invalid JSON", () => {
    expect(parseJsonArrayFromText('{"a":1}')).toBeNull();
    expect(parseJsonArrayFromText("not json")).toBeNull();
    expect(parseJsonArrayFromText("[1,")).toBeNull();
  });
});

describe("parseJsonObjectFromText", () => {
  it("extracts an object from prose", () => {
    expect(parseJsonObjectFromText('Here: {"whyItMatters":"x","soloOverall":7} done')).toEqual({
      whyItMatters: "x",
      soloOverall: 7,
    });
  });

  it("returns null for arrays and invalid JSON", () => {
    expect(parseJsonObjectFromText("[1,2]")).toBeNull();
    expect(parseJsonObjectFromText("nope")).toBeNull();
  });
});
