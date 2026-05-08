const RETRYABLE_STATUS_CODES = new Set([429, 502, 503, 504]);
const NON_RETRYABLE_STATUS_CODES = new Set([400, 401, 403, 422]);

function isRetryable(error: unknown): boolean {
  if (error instanceof TypeError) return true;
  if (error != null && typeof error === "object") {
    const status = (error as Record<string, unknown>)["status"];
    if (typeof status === "number") {
      if (NON_RETRYABLE_STATUS_CODES.has(status)) return false;
      if (RETRYABLE_STATUS_CODES.has(status)) return true;
    }
  }
  return false;
}

export interface RetryOptions {
  maxAttempts?: number;
  backoffSecs?: number[];
  signal?: AbortSignal;
}

export async function withRetry<T>(fn: () => Promise<T>, opts?: RetryOptions): Promise<T> {
  const maxAttempts = opts?.maxAttempts ?? 3;
  const backoffSecs = opts?.backoffSecs ?? [0, 2, 6];

  let lastError: unknown;
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    if (opts?.signal?.aborted) {
      throw opts.signal.reason ?? new DOMException("Aborted", "AbortError");
    }
    try {
      return await fn();
    } catch (err) {
      lastError = err;
      if (!isRetryable(err)) throw err;
      if (attempt < maxAttempts - 1) {
        const delaySecs = backoffSecs[attempt] ?? 0;
        if (delaySecs > 0) {
          await new Promise<void>((resolve, reject) => {
            const timer = setTimeout(resolve, delaySecs * 1000);
            if (opts?.signal) {
              opts.signal.addEventListener("abort", () => {
                clearTimeout(timer);
                reject(opts.signal!.reason ?? new DOMException("Aborted", "AbortError"));
              });
            }
          });
        }
      }
    }
  }
  throw lastError;
}
