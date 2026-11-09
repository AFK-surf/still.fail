// Codex wraps the usage endpoint's response in an app-server JSON-RPC error. Only recognize what that response says;
// the RPC code itself (-32603) is an internal error, not an HTTP status.
export type CodexQuotaFailure = { kind: "login" | "network" | "blocked" | "status" | "other"; status?: number };

export function codexQuotaFailure(detail: string): CodexQuotaFailure {
  let said = detail;
  if (detail.startsWith("codex {")) {
    try {
      const rpc = JSON.parse(detail.slice("codex ".length));
      if (typeof rpc?.message === "string") said = rpc.message;
    } catch {}
  }
  const usage = /failed to fetch codex rate limits/i.test(said);
  const status = usage ? Number(/\bfailed:\s*([45]\d\d)\b/i.exec(said)?.[1]) : NaN;
  if (usage && (status === 401 || /\btoken_revoked\b|invalidated oauth token/i.test(said))) return { kind: "login" };
  if (usage && /\b(account|organi[sz]ation)\b.{0,80}\b(suspended|disabled|deactivated|banned|terminated)\b/i.test(said)) return { kind: "blocked" };
  if (Number.isFinite(status)) return { kind: "status", status };
  if (/timed? out|timeout|error sending request|dns error|connection (?:refused|reset)|network (?:unreachable|is unreachable)/i.test(said)) return { kind: "network" };
  return { kind: "other" };
}
