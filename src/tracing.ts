// Spans of the station's admin API, for following one user action across
// every hop (docs/telemetry.md). A request that carries a recorded W3C
// traceparent (clients send one; ember-mesh passes it on under its own span)
// becomes an OTLP span, which ember hands to ember-mesh to send to ember cloud
// with its own. No bodies, names or emails: the route with ids as `:id`,
// status and sizes.
import { randomBytes } from "node:crypto";

export interface TraceParent {
  trace: string;
  span: string;
  sampled: boolean;
}

/** `00-<trace>-<span>-<flags>`; anything else is no context. */
export function parseTraceparent(header: string | string[] | undefined): TraceParent | null {
  if (typeof header !== "string") return null;
  const match = /^([0-9a-f]{2})-([0-9a-f]{32})-([0-9a-f]{16})-([0-9a-f]{2})$/.exec(header.trim());
  if (!match || match[1] === "ff" || /^0+$/.test(match[2]!) || /^0+$/.test(match[3]!)) return null;
  return { trace: match[2]!, span: match[3]!, sampled: (parseInt(match[4]!, 16) & 1) === 1 };
}

/** Collections whose next path segment is an id, whatever it looks like (as the client core has it). */
const COLLECTIONS = new Set(["sessions", "threads", "connects", "profiles", "logins", "workspaces", "stations", "members", "enrollments", "accounts"]);

/** A request path as a span shows it: no query, ids as `:id`. */
export function route(path: string): string {
  let afterCollection = false;
  return path.split(/[?#]/)[0]!.split("/").map((segment) => {
    const word = segment.length > 0 && segment.length <= 24 && /^[a-z0-9._-]+$/.test(segment) && /[a-z]/.test(segment);
    const id = segment.length > 0 && (afterCollection || !word);
    afterCollection = !id && COLLECTIONS.has(segment);
    return id ? ":id" : segment;
  }).join("/");
}

export type SpanValue = string | number | boolean;

/** An OTLP span (JSON) of this process, under `parent`, from `startMs` (Unix ms) lasting `durationMs`. */
export function serverSpan(parent: TraceParent, name: string, startMs: number, durationMs: number, attributes: Record<string, SpanValue | undefined>, failed: boolean): object {
  const nanos = (ms: number) => (BigInt(Math.round(ms * 1000)) * 1000n).toString();
  return {
    traceId: parent.trace,
    spanId: randomBytes(8).toString("hex"),
    parentSpanId: parent.span,
    name,
    kind: 2,
    startTimeUnixNano: nanos(startMs),
    endTimeUnixNano: nanos(startMs + durationMs),
    attributes: Object.entries(attributes).filter(([, v]) => v !== undefined).map(([key, v]) => ({
      key,
      value: typeof v === "boolean" ? { boolValue: v } : typeof v === "number" ? (Number.isInteger(v) ? { intValue: String(v) } : { doubleValue: v }) : { stringValue: v },
    })),
    status: { code: failed ? 2 : 1 },
  };
}
