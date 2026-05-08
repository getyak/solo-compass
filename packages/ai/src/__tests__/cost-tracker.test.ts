import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// We must control the module environment before importing cost-tracker,
// so we use vi.mock for posthog-node and manipulate process.env per test.

const mockCapture = vi.fn();
const MockPostHog = vi.fn(() => ({ capture: mockCapture }));

vi.mock("posthog-node", () => ({
  PostHog: MockPostHog,
}));

const baseSnapshot = {
  inputTokens: 100,
  outputTokens: 50,
  estimatedUsdCents: 1,
  model: "deepseek-v4-pro",
  route: "test-route",
  durationMs: 42,
};

describe("trackCost", () => {
  beforeEach(() => {
    vi.resetModules();
    mockCapture.mockClear();
    MockPostHog.mockClear();
  });

  afterEach(() => {
    delete process.env["POSTHOG_API_KEY"];
    delete process.env["POSTHOG_HOST"];
  });

  it("does not instantiate PostHog when POSTHOG_API_KEY is unset", async () => {
    delete process.env["POSTHOG_API_KEY"];
    const { trackCost } = await import("../cost-tracker");

    trackCost(baseSnapshot);

    expect(MockPostHog).not.toHaveBeenCalled();
    expect(mockCapture).not.toHaveBeenCalled();
  });

  it("still emits stdout JSON log when POSTHOG_API_KEY is unset", async () => {
    delete process.env["POSTHOG_API_KEY"];
    const { trackCost } = await import("../cost-tracker");
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});

    trackCost(baseSnapshot);

    expect(logSpy).toHaveBeenCalledOnce();
    const logged = JSON.parse(logSpy.mock.calls[0]![0] as string) as unknown;
    expect(logged).toMatchObject({ event: "ai_cost", route: "test-route" });
    logSpy.mockRestore();
  });

  it("calls posthog.capture with expected event shape when POSTHOG_API_KEY is set", async () => {
    process.env["POSTHOG_API_KEY"] = "phc_test_key";
    const { trackCost } = await import("../cost-tracker");

    trackCost(baseSnapshot);

    expect(MockPostHog).toHaveBeenCalledOnce();
    expect(mockCapture).toHaveBeenCalledOnce();
    expect(mockCapture).toHaveBeenCalledWith({
      distinctId: "system",
      event: "ai_cost",
      properties: {
        route: baseSnapshot.route,
        usd_cents: baseSnapshot.estimatedUsdCents,
        model: baseSnapshot.model,
        input_tokens: baseSnapshot.inputTokens,
        output_tokens: baseSnapshot.outputTokens,
        duration_ms: baseSnapshot.durationMs,
      },
    });
  });

  it("uses custom POSTHOG_HOST when provided", async () => {
    process.env["POSTHOG_API_KEY"] = "phc_test_key";
    process.env["POSTHOG_HOST"] = "https://eu.posthog.com";
    const { trackCost } = await import("../cost-tracker");

    trackCost(baseSnapshot);

    expect(MockPostHog).toHaveBeenCalledWith("phc_test_key", {
      host: "https://eu.posthog.com",
    });
  });

  it("defaults POSTHOG_HOST to https://app.posthog.com", async () => {
    process.env["POSTHOG_API_KEY"] = "phc_test_key";
    delete process.env["POSTHOG_HOST"];
    const { trackCost } = await import("../cost-tracker");

    trackCost(baseSnapshot);

    expect(MockPostHog).toHaveBeenCalledWith("phc_test_key", {
      host: "https://app.posthog.com",
    });
  });

  it("swallows PostHog errors silently without throwing", async () => {
    process.env["POSTHOG_API_KEY"] = "phc_test_key";
    mockCapture.mockImplementation(() => {
      throw new Error("PostHog network failure");
    });
    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
    const { trackCost } = await import("../cost-tracker");

    expect(() => trackCost(baseSnapshot)).not.toThrow();
    expect(warnSpy).toHaveBeenCalledWith("[ai_cost] PostHog capture failed:", expect.any(Error));
    warnSpy.mockRestore();
  });
});
