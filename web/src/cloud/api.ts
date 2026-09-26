// ember cloud's account API, called through the core as one of the signed-in
// accounts. Reads are the core's `workspaces` and `workspace` topics; after a
// write the core refetches them, so nothing here keeps a cache.
import { useCallback, useRef, useState } from "react";
import type { ErrorBody } from "../core/client.ts";
import { core, useTopic, type TopicState } from "../core/react.ts";
import type { Account } from "./accounts.ts";
import type { InvitationView, MemberView, PendingInvitation, Role, UserView, WorkspaceSummary, WorkspaceView } from "../../../cloud/src/types.ts";

export type { InvitationView, MemberView, PendingInvitation, Role, UserView, WorkspaceSummary, WorkspaceView };

/** One account's `/v1/me`, as the `workspaces` topic lists it (`error` when that account could not be read). */
export interface AccountWorkspaces {
  account: Account;
  workspaces: WorkspaceSummary[];
  invitations: PendingInvitation[];
  relay_url: string | null;
  error?: ErrorBody;
}

/** Every signed-in account with its workspaces and the invitations waiting for its email. */
export function useWorkspaces(): TopicState<AccountWorkspaces[]> {
  return useTopic<AccountWorkspaces[]>({ topic: "workspaces" });
}

/** One workspace, read as whichever signed-in account belongs to it. */
export function useWorkspace(id: string): TopicState<WorkspaceView> {
  return useTopic<WorkspaceView>({ topic: "workspace", workspace: id });
}

function call<T>(sub: string, method: string, path: string, body?: unknown): Promise<T> {
  return core().call("cloud.request", body === undefined ? { account: sub, method, path } : { account: sub, method, path, body }) as Promise<T>;
}

export interface LoginSession { id: string; name: string; created_at: number; expires_at: number; current: boolean }

const ws = (id: string) => `/v1/workspaces/${encodeURIComponent(id)}`;

export const cloud = {
  createWorkspace: (sub: string, name: string) => call<WorkspaceView>(sub, "POST", "/v1/workspaces", { name }),
  renameWorkspace: (sub: string, id: string, name: string) => call<WorkspaceView>(sub, "PATCH", ws(id), { name }),
  deleteWorkspace: (sub: string, id: string) => call<{ ok: true }>(sub, "DELETE", ws(id)),
  invite: (sub: string, id: string, role: Role, email: string) =>
    call<{ token: string; url: string; expires_at: number }>(sub, "POST", `${ws(id)}/invitations`, { role, email }),
  revokeInvitation: (sub: string, id: string, invitation: string) => call<{ ok: true }>(sub, "DELETE", `${ws(id)}/invitations/${invitation}`),
  previewInvitation: (sub: string, token: string) =>
    call<{ workspace: string; name: string; role: Role; inviter: string; email: string | null }>(sub, "POST", "/v1/invitations/preview", { token }),
  acceptInvitationById: (sub: string, id: string) => call<WorkspaceView>(sub, "POST", `/v1/invitations/${id}/accept`),
  declineInvitation: (sub: string, id: string) => call<{ ok: true }>(sub, "POST", `/v1/invitations/${id}/decline`),
  acceptInvitation: (sub: string, token: string) => call<WorkspaceView>(sub, "POST", "/v1/invitations/accept", { token }),
  setRole: (sub: string, id: string, member: string, role: Role) => call<WorkspaceView>(sub, "PATCH", `${ws(id)}/members/${encodeURIComponent(member)}`, { role }),
  removeMember: (sub: string, id: string, member: string) => call<{ ok: true }>(sub, "DELETE", `${ws(id)}/members/${encodeURIComponent(member)}`),
  enroll: (sub: string, id: string, name: string) => call<{ token: string; expires_at: number; command: string }>(sub, "POST", `${ws(id)}/enrollments`, { name }),
  renameStation: (sub: string, id: string, station: string, name: string) => call<WorkspaceView>(sub, "PATCH", `${ws(id)}/stations/${station}`, { name }),
  removeStation: (sub: string, id: string, station: string) => call<{ ok: true }>(sub, "DELETE", `${ws(id)}/stations/${station}`),
  loginSessions: (sub: string) => call<{ sessions: LoginSession[] }>(sub, "GET", "/v1/auth/sessions").then((r) => r.sessions),
  revokeLoginSession: (sub: string, id: string) => call<{ ok: true }>(sub, "DELETE", `/v1/auth/sessions/${id}`),
};

export interface Action<A, T> {
  run(arg: A): void;
  busy: boolean;
  /** The last try's error, until the next try. */
  error: Error | null;
  /** What the running (or last) try was given. */
  arg: A | undefined;
  /** The last try's answer, once it succeeded. */
  result: T | undefined;
}

/** A write behind a button: whether it is running, how it ended, and what to do after it succeeded. */
export function useAction<A = void, T = unknown>(write: (arg: A) => Promise<T>, onDone?: (result: T, arg: A) => void): Action<A, T> {
  const [state, setState] = useState<{ busy: boolean; error: Error | null; arg: A | undefined; result: T | undefined }>({ busy: false, error: null, arg: undefined, result: undefined });
  // The latest closures, so `run` stays the same function across renders.
  const latest = useRef({ write, onDone });
  latest.current = { write, onDone };
  const run = useCallback((arg: A) => {
    setState({ busy: true, error: null, arg, result: undefined });
    latest.current.write(arg).then(
      (result) => { setState({ busy: false, error: null, arg, result }); latest.current.onDone?.(result, arg); },
      (error: unknown) => setState({ busy: false, error: error instanceof Error ? error : new Error(String(error)), arg, result: undefined }),
    );
  }, []);
  return { run, ...state };
}
