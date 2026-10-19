// A failure notice reported from the chat (its 上报): a person who takes what went wrong for still.fail's own sends it
// to the team as a bug report (docs/feedback.md), made here of what the station knows of it. POST
// /threads/:id/report `{n}` (the notice's entry), answered `{number, duplicate?}`; a read-only member may report too,
// as nothing on the station changes.
import { createHash } from "node:crypto";
import { closeSync, fstatSync, openSync, readSync } from "node:fs";
import { type Request, error, json } from "../api/request.ts";
import type { Route } from "../api/admin.ts";
import { tr } from "../ops/i18n.ts";
import { scrubPaths } from "../ops/telemetry.ts";
import { platform } from "../platform/index.ts";
import type { EntryRow, SessionRow, ThreadRow, TurnSummary } from "../store/rows.ts";
import type { Store } from "../store/store.ts";

type Json = any;

export const REPORT_PATH = /^\/*threads\/+([^/]+)\/+report$/;

/// How much of the station's log is read back from its end, and how much of it goes with a report (the cloud keeps
/// at most 64 KB).
const LOG_TAIL = 8 * 1024 * 1024;
const LOG_LINES = 300;
const LOG_MOST = 48 * 1024;
/// The log read from before the failed turn began (or the notice, when no turn is found), and after the notice.
const BEFORE_MS = 60_000;
const NO_TURN_MS = 30 * 60_000;
const AFTER_MS = 60_000;

const ARCH: Record<string, string> = { arm64: "aarch64", x64: "x86_64" };

/// What a report is made with besides the store: the station's log as it ends (its last `most` bytes; null when there
/// is none), the versions of the station and its runtimes, the names of the variables its agents run with, a
/// session's page, and the home directory scrubbed from what is sent.
export type ReportDeps = {
  logTail: (most: number) => string | null;
  versions: () => Record<string, string>;
  envNames: () => string[];
  link: (session: string) => string | null;
  home: string;
};

/// The station's log as it ends: its last `most` bytes, from the first whole line.
export function readTail(path: string, most: number): string | null {
  let fd: number;
  try {
    fd = openSync(path, "r");
  } catch {
    return null;
  }
  try {
    const size = fstatSync(fd).size;
    const from = Math.max(0, size - most);
    const buf = Buffer.alloc(size - from);
    readSync(fd, buf, 0, buf.length, from);
    const text = buf.toString("utf8");
    return from === 0 ? text : text.slice(text.indexOf("\n") + 1);
  } finally {
    closeSync(fd);
  }
}

/// The session whose turn failed as the notice says: of the thread's, the one whose failed turn ended nearest before it
/// (the notice is posted as the turn ends); with no such turn, the thread's only session or its first.
export function failedTurnOf(store: Store, thread: number, at: number): { session: SessionRow; turn: TurnSummary | null } | null {
  let best: { session: SessionRow; turn: TurnSummary; off: number } | null = null;
  const sessions = store.threadSessions(thread).flatMap((m) => store.getSession(m.session) ?? []);
  for (const session of sessions) {
    for (const { summary } of store.listTurns(session.key)) {
      if (summary.outcome !== "failed" || summary.endedAt === null) continue;
      const off = at - summary.endedAt;
      if (off < -5_000 || off > 10 * 60_000) continue;
      if (best === null || Math.abs(off) < best.off) best = { session, turn: summary, off: Math.abs(off) };
    }
  }
  if (best !== null) return { session: best.session, turn: best.turn };
  return sessions.length > 0 ? { session: sessions[0]!, turn: null } : null;
}

/// The station's log lines about the session from `from` to `to`: those that name it, its runtime's sessions or its
/// profile, and its runtime's warnings and errors; the last LOG_LINES of them, at most LOG_MOST bytes, homes scrubbed.
export function logLines(text: string, from: number, to: number, names: string[], runtime: string, home: string): string {
  const own = new RegExp(`^\\S+\\s+(WARN|ERROR) agents::${runtime.replace(/[^a-z0-9_-]/gi, "")}\\b`);
  const kept: string[] = [];
  for (const line of text.split("\n")) {
    const at = Date.parse(line.slice(0, line.indexOf(" ")));
    if (!Number.isFinite(at) || at < from || at > to) continue;
    if (own.test(line) || names.some((n) => line.includes(n))) kept.push(scrubPaths(line, home));
  }
  let out = kept.slice(-LOG_LINES);
  while (out.length > 0 && Buffer.byteLength(out.join("\n")) > LOG_MOST) out = out.slice(Math.ceil(out.length / 10));
  return out.join("\n");
}

const quoted = (text: string) => text.split("\n").map((l) => `> ${l}`).join("\n");

/// The report of the notice `entry` in `thread`, reported by `viewer`.
export function noticeReport(store: Store, thread: ThreadRow, entry: EntryRow, viewer: { name: string; email: string }, deps: ReportDeps): Json {
  const text = (entry.text ?? "").replace(/^⚠️\s*/u, "").trim();
  const found = failedTurnOf(store, thread.id, entry.at);
  const session = found?.session ?? null;
  const turn = found?.turn ?? null;
  const first = text.split("\n").find((l) => l.trim() !== "")?.trim() ?? "";
  const title = [...first].slice(0, 200).join("");
  const key = createHash("sha256").update(`notice\n${session?.key ?? ""}\n${thread.id}\n${entry.n}`).digest().subarray(0, 16).toString("hex");
  const versions = deps.versions();
  const env = deps.envNames();
  const iso = (ms: number) => new Date(ms).toISOString();
  const body = [
    "Reported from a failure notice in a chat (its 上报), by a person who takes it for a problem in still.fail.",
    "",
    "**Notice**",
    quoted(text),
    "",
    `**When**: ${iso(entry.at)}`,
    ...(turn !== null ? [`**Turn**: ${turn.kind}, ${iso(turn.startedAt)} to ${turn.endedAt !== null ? iso(turn.endedAt) : "?"}`, ...(turn.detail ? [`**Failure**: ${turn.detail}`] : [])] : ["**Turn**: none found"]),
    ...(session !== null ? [`**Agent**: ${session.runtime}, profile ${session.profile}${session.model ? `, model ${session.model}` : ""}`] : []),
    `**Versions**: ${Object.entries(versions).map(([k, v]) => `${k} ${v}`).join(", ") || "unknown"}`,
    `**Variables set for agents** (names only): ${env.length > 0 ? env.join(", ") : "none"}`,
  ].join("\n");
  const context: Json = { notice: { thread: thread.id, n: entry.n }, os: platform.os, arch: ARCH[process.arch] ?? process.arch, software: versions, agentEnv: env };
  if (session !== null) {
    Object.assign(context, { session: session.key, connect: session.connect, runtime: session.runtime, profile: session.profile });
    if (session.model !== null) context.model = session.model;
    const link = deps.link(session.key);
    if (link !== null) context.link = link;
  }
  context.thread = `${thread.channel}/${thread.threadTs}`;
  const out: Json = { key, title: title || "failure notice", body, area: "station", reporter: `${viewer.name} (${viewer.email}), from the chat`, context };
  if (session?.ws) out.workspace = session.ws;
  const tail = session !== null ? deps.logTail(LOG_TAIL) : null;
  if (tail !== null && session !== null) {
    const from = (turn?.startedAt ?? entry.at - NO_TURN_MS) - BEFORE_MS;
    const names = [session.key, ...store.runtimeSessions(session.key), `profile=${session.profile}`];
    const logs = logLines(tail, from, entry.at + AFTER_MS, names, session.runtime, deps.home);
    if (logs !== "") out.logs = logs;
  }
  return out;
}

/// The route, sending with `send` (the feedback part's: to still.fail cloud, its answer `{number, duplicate?}`).
export function reportRoutes(store: Store, deps: ReportDeps, send: (report: Json) => Promise<Json>): Route[] {
  return [
    {
      method: "POST",
      pattern: REPORT_PATH,
      handle: async (r: Request, [rawId]) => {
        const id = Number(rawId);
        const thread = /^\d+$/.test(rawId ?? "") && Number.isSafeInteger(id) ? store.getThread(id) : null;
        if (thread === null) return error(404, `unknown thread ${rawId}`);
        let n: unknown;
        try {
          n = r.body.length === 0 ? undefined : JSON.parse(r.body.toString("utf8"))?.n;
        } catch {
          return error(400, "invalid JSON");
        }
        if (typeof n !== "number" || !Number.isSafeInteger(n) || n < 1) return error(400, tr(r.lang, "station.admin.badN"));
        const entry = store.entriesBetween(thread.id, n, n)[0];
        if (entry === undefined || entry.authorKind !== "ember" || !/^⚠️/u.test(entry.text ?? "")) return error(404, tr(r.lang, "station.feedback.notAFailure"));
        const report = noticeReport(store, thread, entry, r.viewer, deps);
        let answer: Json;
        try {
          answer = await send(report);
        } catch (e) {
          return error(502, tr(r.lang, "station.feedback.notSent", { error: (e as Error).message }));
        }
        const number = answer?.number;
        if (typeof number !== "number" || !Number.isInteger(number) || number < 0) return error(502, tr(r.lang, "station.feedback.notSent", { error: JSON.stringify(answer) }));
        return json(200, JSON.stringify({ number, ...(answer?.duplicate === true ? { duplicate: true } : {}) }));
      },
    },
  ];
}
