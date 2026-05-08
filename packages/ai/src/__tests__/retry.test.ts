import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { withRetry } from "../retry";

function apiError(status: number): Error {
  const err = new Error(`HTTP ${status}`) as Error & { status: number };
  (err as unknown as Record<string, unknown>)["status"] = status;
  return err;
}

describe("withRetry", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("returns immediately on first-try success", async () => {
    const fn = vi.fn().mockResolvedValue("ok");
    const result = await withRetry(fn);
    expect(result).toBe("ok");
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it("retries on 429 and succeeds on second attempt", async () => {
    const fn = vi.fn().mockRejectedValueOnce(apiError(429)).mockResolvedValue("ok");

    const promise = withRetry(fn, { backoffSecs: [0, 0, 0] });
    await vi.runAllTimersAsync();
    const result = await promise;

    expect(result).toBe("ok");
    expect(fn).toHaveBeenCalledTimes(2);
  });

  it("retries on TypeError (network error) and succeeds on third attempt", async () => {
    const fn = vi
      .fn()
      .mockRejectedValueOnce(new TypeError("fetch failed"))
      .mockRejectedValueOnce(new TypeError("fetch failed"))
      .mockResolvedValue("data");

    const promise = withRetry(fn, { backoffSecs: [0, 0, 0] });
    await vi.runAllTimersAsync();
    const result = await promise;

    expect(result).toBe("data");
    expect(fn).toHaveBeenCalledTimes(3);
  });

  it("gives up after maxAttempts and throws the last error", async () => {
    const err = apiError(503);
    const fn = vi.fn().mockRejectedValue(err);

    const resultPromise = withRetry(fn, { maxAttempts: 3, backoffSecs: [0, 0, 0] }).catch(
      (e: unknown) => e,
    );
    await vi.runAllTimersAsync();

    const caught = await resultPromise;
    expect(caught).toBe(err);
    expect(fn).toHaveBeenCalledTimes(3);
  });

  it("does NOT retry on 401", async () => {
    const err = apiError(401);
    const fn = vi.fn().mockRejectedValue(err);

    await expect(withRetry(fn)).rejects.toThrow(err);
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it("does NOT retry on 400", async () => {
    const fn = vi.fn().mockRejectedValue(apiError(400));
    await expect(withRetry(fn)).rejects.toThrow();
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it("does NOT retry on 403", async () => {
    const fn = vi.fn().mockRejectedValue(apiError(403));
    await expect(withRetry(fn)).rejects.toThrow();
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it("does NOT retry on 422", async () => {
    const fn = vi.fn().mockRejectedValue(apiError(422));
    await expect(withRetry(fn)).rejects.toThrow();
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it("retries on 502, 503, 504", async () => {
    for (const status of [502, 503, 504]) {
      const fn = vi.fn().mockRejectedValueOnce(apiError(status)).mockResolvedValue("ok");
      const promise = withRetry(fn, { backoffSecs: [0, 0, 0] });
      await vi.runAllTimersAsync();
      await expect(promise).resolves.toBe("ok");
      expect(fn).toHaveBeenCalledTimes(2);
    }
  });

  it("respects custom maxAttempts", async () => {
    const err = apiError(429);
    const fn = vi.fn().mockRejectedValue(err);
    const resultPromise = withRetry(fn, { maxAttempts: 2, backoffSecs: [0, 0] }).catch(
      (e: unknown) => e,
    );
    await vi.runAllTimersAsync();
    const caught = await resultPromise;
    expect(caught).toBe(err);
    expect(fn).toHaveBeenCalledTimes(2);
  });

  it("waits backoffSecs between retries", async () => {
    const fn = vi
      .fn()
      .mockRejectedValueOnce(apiError(429))
      .mockRejectedValueOnce(apiError(429))
      .mockResolvedValue("ok");

    const promise = withRetry(fn, { maxAttempts: 3, backoffSecs: [2, 6] });

    // Before any timers fire, only the first call has been made and failed
    expect(fn).toHaveBeenCalledTimes(1);

    await vi.advanceTimersByTimeAsync(2000);
    expect(fn).toHaveBeenCalledTimes(2);

    await vi.advanceTimersByTimeAsync(6000);
    expect(fn).toHaveBeenCalledTimes(3);

    await expect(promise).resolves.toBe("ok");
  });
});
