// The workspace's statistics as a Comma connect sends them (stats.ts): this station's, read here, and each other
// station's of the workspace, read of it over the mesh (`outflow.read`, the name stations of every version answer),
// and how a station answers another's read.
import { type Bytes, bytesOf, withBytes } from "../mesh/bus.ts";
import { oneBytes } from "../mesh/files.ts";
import type { Lang } from "../ops/i18n.ts";
import type { Read, StationRows } from "./stats.ts";

type Json = any;

/// What another station of the workspace asks of this one's statistics.
export const READ = "outflow.read";
const OPS = ["outflowUsage", "outflowChats", "outflowMessages"];
/// The Router of the Comma connect on another station of the workspace writing in one of this station's chats.
export const SAY = "comma.say";
/// An answer of another station's read, at most.
const ANSWER_MAX = 64 * 1024 * 1024;
/// Chats a read takes at once.
const CHATS_PAGE = 1000;
/// Bound the simultaneous peer reads: each answer can itself be large.
const PEER_READS = 2;

/// What answers another station's `outflow.read`: the read it names of this station's chats of the workspace it asks
/// in, the answer's JSON as the bytes after its head. `read`: the station's reads (read/ops.ts); `home`: its home
/// workspace now.
export function peerRead(read: (op: string, args: unknown, lang: Lang) => Promise<string>, home: () => string | null, lang: () => Lang) {
  return async (_peer: string, request: Json, workspace?: string) => {
    const op = typeof request?.op === "string" ? request.op : "";
    if (!OPS.includes(op)) throw new Error("no such read");
    if (typeof workspace !== "string" || workspace === "") throw new Error("which workspace is not known");
    const args = request?.args !== null && typeof request?.args === "object" ? request.args : {};
    const said = lang();
    const text = await read(op, { ...args, lang: said, ws: { workspace, home: workspace === home() } }, said);
    const bytes = Buffer.from(text, "utf8");
    return withBytes({ size: bytes.length }, oneBytes(bytes));
  };
}

/// The bytes after an answer, as text (at most ANSWER_MAX).
export async function textOf(bytes: Bytes): Promise<string> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of bytes) {
    size += chunk.length;
    if (size > ANSWER_MAX) throw new Error("that station's answer is too long");
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString("utf8");
}

export type WorkspaceReads = {
  /// The home workspace now, null before the station joined one.
  home: () => string | null;
  /// This station's read: as the reader pool answers it.
  here: (op: string, args: Json) => Promise<string>;
  /// The other stations of the home workspace, by id; throws when the roster is not known now.
  others: () => Promise<string[]>;
  /// Another station's read.
  there: (station: string, op: string, args: Json) => Promise<string>;
};

/// One station's usage and chats of the home workspace from `from` until `to`, by `ask`.
async function stationRows(ask: (op: string, args: Json) => Promise<string>, from: number, to: number): Promise<{ usage: Json; chats: Json[] }> {
  const usage = JSON.parse(await ask("outflowUsage", { from, to, tz: 0 }));
  // A partial answer must not make this station's previously indexed rows look absent.
  const nullableText = (value: unknown) => value === null || typeof value === "string";
  if (!Array.isArray(usage?.rows) || usage.rows.some((row: Json) =>
    typeof row?.day !== "string" || typeof row?.session !== "string" || typeof row?.runtime !== "string" ||
    !nullableText(row?.person) || !nullableText(row?.account) || !nullableText(row?.model))) {
    throw new Error("that station's usage answer is incomplete");
  }
  const chats: Json[] = [];
  let before: string | null = null;
  const cursors = new Set<string>();
  for (;;) {
    const page = JSON.parse(await ask("outflowChats", { since: from, limit: CHATS_PAGE, ...(before === null ? {} : { before }) }));
    if (!Array.isArray(page?.chats) || page.chats.some((chat: Json) => typeof chat?.thread !== "number")) {
      throw new Error("that station's chat answer is incomplete");
    }
    chats.push(...page.chats);
    // Older stations returned all chats without pagination fields.
    if (page.more === undefined || page.more === false) break;
    if (page.more !== true || typeof page.next !== "string" || page.next === "" || cursors.has(page.next)) {
      throw new Error("that station's chat cursor does not continue");
    }
    cursors.add(page.next);
    before = page.next;
  }
  return { usage, chats };
}

/// What a build reads: this station's rows, and each other station's of the workspace that answers.
export function workspaceRead(w: WorkspaceReads): Read {
  return async (from, to) => {
    const home = w.home();
    const ws = home === null ? {} : { ws: { workspace: home, home: true } };
    const stations: StationRows[] = [await stationRows((op, args) => w.here(op, { ...args, ...ws }), from, to)];
    const unread: string[] = [];
    const others = home === null ? [] : await w.others();
    const results: (StationRows | null)[] = Array.from({ length: others.length }, () => null);
    let next = 0;
    await Promise.all(Array.from({ length: Math.min(PEER_READS, others.length) }, async () => {
      for (;;) {
        const at = next++;
        const station = others[at];
        if (station === undefined) return;
        try {
          results[at] = { station, ...(await stationRows((op, args) => w.there(station, op, args), from, to)) };
        } catch {
          // Keep this station's previous rows when it cannot answer.
        }
      }
    }));
    // Completion order must not change the order in which the index gives revisions to the rows.
    for (let i = 0; i < others.length; i++) {
      const result = results[i];
      if (result !== null && result !== undefined) stations.push(result);
      else unread.push(others[i]!);
    }
    return { stations, unread };
  };
}

/// Another station's answer to a read, as text.
export async function answerText(got: Json): Promise<string> {
  const bytes = bytesOf(got);
  if (bytes === null) throw new Error("that station answered without its data");
  return textOf(bytes);
}
