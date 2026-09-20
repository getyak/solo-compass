/**
 * Regression tests for the DeepSeek client defaults + wire helpers.
 *
 * Covers the deepseek-flash migration: the built-in default, legacy model-id
 * normalization, and the top-level `thinking: {"type":"disabled"}` wire field
 * (never nested under `extra_body`). No live API calls.
 */

import { describe, it, expect, afterEach } from "vitest";
import {
  DEFAULT_DEEPSEEK_BASE_URL,
  DEFAULT_DEEPSEEK_MODEL,
  DEEPSEEK_THINKING_DISABLED,
  createDeepseekClient,
  deepseekBaseURL,
  deepseekModel,
  normalizeDeepseekModel,
  withDeepSeekThinkingDisabled,
} from "../client";

const LEGACY_IDS = ["deepseek-chat", "deepseek-reasoner", "deepseek-v4-pro", "deepseek-v4-flash"];

describe("deepseek model defaults", () => {
  afterEach(() => {
    delete process.env["DEEPSEEK_MODEL"];
    delete process.env["DEEPSEEK_BASE_URL"];
    delete process.env["DEEPSEEK_API_KEY"];
  });

  it("defaults to deepseek-flash", () => {
    expect(DEFAULT_DEEPSEEK_MODEL).toBe("deepseek-flash");
    expect(deepseekModel()).toBe("deepseek-flash");
  });

  it("normalizes every legacy model id to deepseek-flash", () => {
    for (const id of LEGACY_IDS) {
      expect(normalizeDeepseekModel(id)).toBe("deepseek-flash");
    }
  });

  it("does not let a legacy DEEPSEEK_MODEL env var pin an old model", () => {
    for (const id of LEGACY_IDS) {
      process.env["DEEPSEEK_MODEL"] = id;
      expect(deepseekModel()).toBe("deepseek-flash");
    }
  });

  it("preserves an explicitly configured non-legacy model id", () => {
    process.env["DEEPSEEK_MODEL"] = "my-fine-tune";
    expect(deepseekModel()).toBe("my-fine-tune");
    expect(normalizeDeepseekModel("deepseek-v4.1-experimental")).toBe("deepseek-v4.1-experimental");
  });

  it("treats blank/whitespace model ids as the built-in default", () => {
    expect(normalizeDeepseekModel("")).toBe("deepseek-flash");
    expect(normalizeDeepseekModel("   ")).toBe("deepseek-flash");
    expect(normalizeDeepseekModel(undefined)).toBe("deepseek-flash");
  });

  it("defaults the base URL to the DeepSeek OpenAI-compatible endpoint", () => {
    expect(DEFAULT_DEEPSEEK_BASE_URL).toBe("https://api.deepseek.com/v1");
    expect(deepseekBaseURL()).toBe("https://api.deepseek.com/v1");
  });
});

describe("thinking-disabled wire field", () => {
  it("places thinking at the top level and never under extra_body", () => {
    const params = withDeepSeekThinkingDisabled({
      model: "deepseek-flash",
      messages: [{ role: "user", content: "hi" }],
    });
    expect(params.thinking).toEqual({ type: "disabled" });
    expect(params.thinking).toBe(DEEPSEEK_THINKING_DISABLED);
    expect((params as Record<string, unknown>)["extra_body"]).toBeUndefined();
  });

  it("does not mutate the input params", () => {
    const input = { model: "deepseek-flash", messages: [] };
    const output = withDeepSeekThinkingDisabled(input);
    expect((input as Record<string, unknown>)["thinking"]).toBeUndefined();
    expect(output).not.toBe(input);
  });
});

describe("createDeepseekClient", () => {
  afterEach(() => {
    delete process.env["DEEPSEEK_API_KEY"];
    delete process.env["DEEPSEEK_BASE_URL"];
  });

  it("throws a clear error when no key is configured", () => {
    delete process.env["DEEPSEEK_API_KEY"];
    expect(() => createDeepseekClient()).toThrow(/DEEPSEEK_API_KEY is not set/);
  });

  it("points the OpenAI SDK at DeepSeek", () => {
    const client = createDeepseekClient("sk-test");
    expect(client.baseURL).toBe("https://api.deepseek.com/v1");
  });

  it("honors DEEPSEEK_BASE_URL", () => {
    process.env["DEEPSEEK_BASE_URL"] = "https://proxy.example.com/v1";
    const client = createDeepseekClient("sk-test");
    expect(client.baseURL).toBe("https://proxy.example.com/v1");
  });
});
