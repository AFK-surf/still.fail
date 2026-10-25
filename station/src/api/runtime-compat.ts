// A station must not send a closed-enum runtime to a client that cannot decode it. New clients advertise their
// runtime vocabulary; requests without it retain the pre-Hermes wire vocabulary. Project metadata only,
// following its schema: never rewrite user messages, tool inputs/results, files, previews or module payloads.
import { StringDecoder } from "node:string_decoder";
import { runtimeView, OMIT } from "../read/runtime-view.ts";
export { runtimeView } from "../read/runtime-view.ts";
import type { Ty } from "../../../client/core-ts/src/shapes/dsl.ts";
import { RUNTIME_KINDS } from "../agents/runtime.ts";
import { error, type Answer, type Request } from "./request.ts";
import { tr } from "../ops/i18n.ts";

export const RUNTIMES_HEADER = "stillfail-runtimes";
const LEGACY = ["claude", "codex", "dsh", "grok", "cursor", "devin"];
const object = (v: unknown): v is Record<string, any> => v !== null && typeof v === "object" && !Array.isArray(v);
export function clientRuntimes(headers: Record<string, string>): Set<string> {
  const value = Object.entries(headers).find(([k]) => k.toLowerCase() === RUNTIMES_HEADER)?.[1];
  return new Set(value === undefined ? LEGACY : value.split(",").map(s => s.trim()).filter(s => /^[a-z][a-z0-9-]{0,39}$/.test(s)));
}

function entriesView(value: unknown, supported: Set<string>): unknown {
  if (!object(value) || !Array.isArray(value.entries)) return value;
  return { ...value, entries: value.entries.map((entry: unknown) => {
    if (!object(entry) || typeof entry.authorRuntime !== "string" || supported.has(entry.authorRuntime)) return entry;
    const copy = { ...entry }; delete copy.authorRuntime; return copy;
  }) };
}

function shapeFor(path: string): Ty | undefined {
  if (path === "/overview") return "Overview";
  if (path === "/sessions") return { vec: "Session" };
  if (/^\/sessions\/[^/]+$/.test(path)) return "SessionDetail";
  if (path === "/threads") return { vec: "ChatThread" };
  if (/^\/threads\/[^/]+$/.test(path)) return "ChatThread";
  if (path === "/chats") return { vec: "ChatItem" };
  return undefined;
}

const EVENTS: Record<string, Ty> = { overview: "Overview", session: "Session", chat: "ChatItem", "thread-view": "ChatThread" };
function frame(text: string, supported: Set<string>): string {
  const lines = text.split("\n");
  const event = lines.find(l => l.startsWith("event: "))?.slice(7);
  const i = lines.findIndex(l => l.startsWith("data: "));
  const type = event && EVENTS[event];
  if (i < 0 || (!type && event !== "thread")) return text;
  const value = JSON.parse(lines[i]!.slice(6));
  const view = event === "thread" ? entriesView(value, supported) : runtimeView(type!, value, supported);
  if (view === OMIT && event === "session") {
    // Keep the event's id for resumable streams and remove an obsolete cached session.
    lines[lines.findIndex(l => l.startsWith("event: "))] = "event: session-removed";
    lines[i] = `data: ${JSON.stringify({ key: value.key })}`;
  } else lines[i] = `data: ${JSON.stringify(view === OMIT ? null : view)}`;
  return lines.join("\n");
}

async function* events(body: AsyncIterable<Buffer>, supported: Set<string>) {
  const decoder = new StringDecoder("utf8");
  let pending = "";
  for await (const chunk of body) {
    pending += decoder.write(chunk);
    let end;
    while ((end = pending.indexOf("\n\n")) >= 0) {
      yield Buffer.from(frame(pending.slice(0,end), supported) + "\n\n");
      pending = pending.slice(end+2);
    }
  }
  pending += decoder.end();
  if (pending) yield Buffer.from(frame(pending, supported));
}

export function runtimeCompatible(r: Request, answer: Answer): Answer {
  if (answer.status < 200 || answer.status >= 300) return answer;
  const supported = clientRuntimes(r.headers);
  if (RUNTIME_KINDS.every(k => supported.has(k))) return answer;
  const path = r.path.replace(/\/+$/, "");
  if (path === "/events" && !Buffer.isBuffer(answer.body)) return { ...answer, body: events(answer.body, supported) };
  if (!Buffer.isBuffer(answer.body) || !(answer.headers["content-type"] ?? "").startsWith("application/json")) return answer;
  // Project after idempotent response caching, including each answer in a batch. Reusing a write key from a
  // different client must neither repeat the write nor reuse the previous client's filtered view.
  if (path === "/batch") {
    const gets = JSON.parse(r.body.toString("utf8"))?.gets;
    const raw = JSON.parse(answer.body.toString("utf8"));
    if (!Array.isArray(gets) || !Array.isArray(raw?.answers)) return answer;
    const answers = raw.answers.map((a: any, i: number) => {
      if (typeof gets[i] !== "string") return a;
      const projected = runtimeCompatible({ ...r, method: "GET", path: gets[i].split("?")[0] },
        { status: a.status, headers: { "content-type": "application/json" }, body: Buffer.from(JSON.stringify(a.body)) });
      return { ...a, status: projected.status, body: JSON.parse(String(projected.body)) };
    });
    const headers = { ...answer.headers }; delete headers["content-length"];
    return { ...answer, headers, body: Buffer.from(JSON.stringify({ ...raw, answers })) };
  }
  let type = shapeFor(path);
  // Account writes return an overview, sometimes wrapped with the newly created id. Read-only old clients must
  // not be broken by an unrelated account edit either. Files/preview/module replies never enter this branch.
  const entries = /^\/threads\/[^/]+\/entries$/.test(path);
  const account = /^\/(profiles|logins|automatic-decisions|archiving|connects|slack|feishu|me\/slack)(\/|$)/.test(path);
  if (!type && !account && !entries) return answer;
  const raw = JSON.parse(answer.body.toString("utf8"));
  let view: unknown;
  if (entries) view = entriesView(raw, supported);
  else if (account && object(raw)) {
    view = "overview" in raw ? { ...raw, overview: runtimeView("Overview", raw.overview, supported) } : runtimeView("Overview", raw, supported);
  } else view = runtimeView(type!, raw, supported);
  if (view === OMIT) return error(426, tr(r.lang, "station.admin.updateClientForRuntime"));
  const headers = { ...answer.headers }; delete headers["content-length"];
  return { ...answer, headers, body: Buffer.from(JSON.stringify(view)) };
}
