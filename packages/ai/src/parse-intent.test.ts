import { describe, expect, it } from "vitest";

import { parseIntent } from "./parse-intent";

describe("parseIntent budget parsing", () => {
  it("parses generic USD amounts and leaves baht to the currency conversion", () => {
    expect(parseIntent("something under 25").budgetMax).toBe(25);
    expect(parseIntent("less than 19.5 please").budgetMax).toBe(20);
    expect(parseIntent("under 330 baht").budgetMax).toBe(10);
  });

  it("handles an adversarial numeric input in linear time", () => {
    const startedAt = performance.now();
    const result = parseIntent(`under ${"9".repeat(100_000)}x`);
    const elapsedMs = performance.now() - startedAt;

    expect(result.budgetMax).toBeUndefined();
    expect(result.rawText).toHaveLength(100_007);
    expect(elapsedMs).toBeLessThan(1_000);
  });
});
