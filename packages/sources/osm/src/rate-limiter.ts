/**
 * Sliding-window rate limiter: max 1 request per second.
 * Callers await `acquire()` before each HTTP request.
 */
export class RateLimiter {
  private lastCallAt = 0;
  private readonly minIntervalMs: number;

  constructor(maxPerSecond = 1) {
    this.minIntervalMs = Math.ceil(1000 / maxPerSecond);
  }

  async acquire(): Promise<void> {
    const now = Date.now();
    const elapsed = now - this.lastCallAt;
    if (elapsed < this.minIntervalMs) {
      await new Promise<void>((resolve) =>
        setTimeout(resolve, this.minIntervalMs - elapsed),
      );
    }
    this.lastCallAt = Date.now();
  }
}
