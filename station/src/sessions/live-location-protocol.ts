import type { RuntimeKind } from "../agents/runtime.ts";
import type { TranscriptLocationHints } from "../read/transcript.ts";
import { createHash } from "node:crypto";

export type LiveSource = { id: string; runtime: string; profile: string | null };
export type LiveLocationProfile = { id: string; home: string };
type IdentityFields = { runtime: string; runtimeSessionId: string | null; cwd: string | null; workspace: string; profile: string | null; ws: string | null };
export type LiveSession = IdentityFields & { token: string };
export type LiveLocationIdentity = IdentityFields & { tokenHash: string };
// The reader does not send a session's token across threads. Its digest distinguishes a replacement under the same key.
export function locationIdentity(row: IdentityFields, token: string): LiveLocationIdentity {
  return { runtime: row.runtime, runtimeSessionId: row.runtimeSessionId, cwd: row.cwd, workspace: row.workspace,
    profile: row.profile, ws: row.ws, tokenHash: createHash("sha256").update(token).digest("hex") };
}
export type LiveLocation = { runtime: RuntimeKind; paths: { path: string; runtime: RuntimeKind }[]; current: boolean } | null;
export type LocateRequest = { type: "locate"; id: number; key: string; profiles: LiveLocationProfile[] };
export type LocateReply = { type: "hints"; id: number; hints: TranscriptLocationHints } | { type: "accepted"; id: number; accepted: boolean } | { type: "cancel"; id: number };
export type LocateMessage =
  | { type: "hints"; id: number; sources: LiveSource[] }
  | { type: "batch"; id: number; paths: { path: string; runtime: RuntimeKind }[]; current: boolean; hints: TranscriptLocationHints }
  | { type: "done"; id: number; identity: LiveLocationIdentity | null; runtime: RuntimeKind | null; current: boolean }
  | { type: "error"; id: number; error: string };
