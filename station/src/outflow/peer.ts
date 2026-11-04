// What a station reads of another of its workspace's for a program granted the whole workspace there, and how it
// answers one that asks it (docs/data-outflow.md, docs/station-peers.md: `outflow.read`).
import { type Bytes, withBytes } from "../mesh/bus.ts";
import { oneBytes } from "../mesh/files.ts";
import type { Lang } from "../ops/i18n.ts";
import { type Operate, notOperated } from "./server.ts";

/// What another station of the workspace asks of this one's data for a program granted there.
export const READ = "outflow.read";
const OPS = ["outflowUsage", "outflowChats", "outflowMessages"];
/// What another station of the workspace has done here as a member, for a program granted `operate` there.
export const OPERATE = "outflow.operate";
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

/// What answers another station's `outflow.operate`: the request of the admin API it names, as the member it names,
/// in the workspace it asks in; the answer's body as the bytes after its head.
export function peerOperate(operate: Operate) {
  return async (_peer: string, request: any, workspace?: string) => {
    if (typeof workspace !== "string" || workspace === "") throw new Error("which workspace is not known");
    const call = request?.call;
    if (typeof call?.actor !== "string" || typeof call?.method !== "string" || typeof call?.path !== "string") throw new Error("no such request");
    if (notOperated(call.path)) throw new Error("not given to a program");
    // What a station says of a person is not a role here: another station gets a member at most.
    const answer = await operate({ ...call, station: null, role: "member", body: Buffer.from(typeof call.body === "string" ? call.body : "", "base64") });
    return withBytes({ status: answer.status, headers: answer.headers, size: answer.body.length }, oneBytes(answer.body));
  };
}

/// What reads this station's own chats for a program granted here: those of its home workspace, named by its id when
/// known, as a chat made in the app says its workspace (only the chats that say none would be read otherwise).
export function homeRead(read: (op: string, args: unknown, lang: Lang) => Promise<string>, home: () => string | null) {
  return (op: string, args: unknown, lang: Lang) => {
    const ws = home();
    return read(op, ws === null ? args : { ...(args as object), ws: { workspace: ws, home: true } }, lang);
  };
}

/// The bytes after an answer, as text (at most ANSWER_MAX).
export async function textOf(bytes: Bytes, encoding: BufferEncoding = "utf8"): Promise<string> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of bytes) {
    size += chunk.length;
    if (size > ANSWER_MAX) throw new Error("that station's answer is too long");
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString(encoding);
}

