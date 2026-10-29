// What a station reads of another of its workspace's for a program granted the whole workspace there, and how it
// answers one that asks it (docs/data-outflow.md, docs/station-peers.md: `outflow.read`).
import { type Bytes, withBytes } from "../mesh/bus.ts";
import { oneBytes } from "../mesh/files.ts";
import type { Lang } from "../ops/i18n.ts";

/// What another station of the workspace asks of this one's data for a program granted there.
export const READ = "outflow.read";
const OPS = ["outflowUsage", "outflowChats", "outflowMessages"];
/// An answer of another station's read, at most.
const ANSWER_MAX = 64 * 1024 * 1024;

/// What answers another station's `outflow.read`: the read it names of this station's chats of the workspace it asks
/// in, the answer's JSON as the bytes after its head. `read`: the station's reads (read/ops.ts); `home`: its home
/// workspace now.
export function peerRead(read: (op: string, args: unknown, lang: Lang) => Promise<string>, home: () => string | null, lang: () => Lang) {
  return async (_peer: string, request: any, workspace?: string) => {
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

