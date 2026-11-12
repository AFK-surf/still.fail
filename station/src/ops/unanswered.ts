// Whether a request got no answer at all, as against an answer that says no: what is tried again, as the way there
// may come back, where a refusal stands until something changes.

/// A socket's errors where the other side was not reached (through a proxy, https.request says them as they are).
const UNREACHED = new Set(["ECONNREFUSED", "ECONNRESET", "ECONNABORTED", "ENOTFOUND", "EAI_AGAIN", "ETIMEDOUT", "EHOSTUNREACH", "ENETUNREACH", "EPIPE"]);

/// Whether a request got no answer at all: no way there (fetch's "fetch failed", a socket's error) or none in time.
export function unanswered(error: unknown): boolean {
  if (!(error instanceof Error)) return false;
  return error.name === "TimeoutError" || (error instanceof TypeError && error.message === "fetch failed") || UNREACHED.has(String((error as NodeJS.ErrnoException).code));
}
