// still.fail cloud's account API: what the pages have done there, by name, done by the core as one of the signed-in
// accounts. Reads are the core's `workspaces` and `workspace` topics; after a
// write the core refetches them, so nothing here keeps a cache.
import { useCallback, useRef, useState } from "react";
import type { ErrorBody } from "../core/client.ts";
import { core, useTopic, type TopicState } from "../core/react.ts";
import { prefs, setPrefs } from "../prefs.ts";
import type { Account } from "./accounts.ts";
import type { AddedView, Admission, AdminUser, AdminWorkspace, FeedbackStatus, InvitationView, InviteCodeView, MeView, MemberView, PendingInvitation, Role, UserView, WorkspaceSummary, WorkspaceView } from "../../../cloud/src/types.ts";

export type { AddedView, Admission, AdminUser, AdminWorkspace, FeedbackStatus, InvitationView, InviteCodeView, MeView, MemberView, PendingInvitation, Role, UserView, WorkspaceSummary, WorkspaceView };

/** One account's `/v1/me`, as the `workspaces` topic lists it (`error` when that account could not be read). */
export interface AccountWorkspaces {
  account: Account;
  workspaces: WorkspaceSummary[];
  invitations: PendingInvitation[];
  relay_url: string | null;
  /** The account's `/v1/me` has answered; until then (or after a failure) an empty list says nothing. */
  loaded: boolean;
  /** still.fail cloud lets this account use the beta apps (its `/v1/me` says `user.beta`). */
  beta?: boolean;
  /** In the beta app, an account still.fail cloud has not let into the beta: what to say (the core's), with a way out. */
  blocked?: string;
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

/** Has the core do `name` (client/core/src/ops.rs) on still.fail cloud as the account `sub`, with `params`. */
function op<T>(sub: string, name: string, params: Record<string, unknown> = {}): Promise<T> {
  return core().call(name, { ...params, account: sub }) as Promise<T>;
}

export interface LoginSession { id: string; name: string; created_at: number; expires_at: number; current: boolean }

export const cloud = {
  /** `code`: an invite code, for an account not let in yet (still.fail is invite-only). */
  createWorkspace: (sub: string, name: string, code?: string) => op<WorkspaceView>(sub, "workspace.create", code ? { name, invite_code: code } : { name }),
  renameWorkspace: (sub: string, id: string, name: string) => op<WorkspaceView>(sub, "workspace.rename", { workspace: id, name }),
  deleteWorkspace: (sub: string, id: string) => op<{ ok: true }>(sub, "workspace.delete", { workspace: id }),
  invite: (sub: string, id: string, role: Role, email: string) =>
    op<{ token: string; url: string; expires_at: number }>(sub, "workspace.invite", { workspace: id, role, email }),
  /** Adds people by email: members at once, or from their first sign-in; no invitation to accept. */
  addMembers: (sub: string, id: string, role: Role, emails: string[]) =>
    op<{ joined: string[]; added: string[]; already: string[]; view: WorkspaceView }>(sub, "workspace.addMembers", { workspace: id, role, emails }),
  removeAdded: (sub: string, id: string, email: string) => op<WorkspaceView>(sub, "workspace.removeAdded", { workspace: id, email }),
  revokeInvitation: (sub: string, id: string, invitation: string) => op<{ ok: true }>(sub, "workspace.revokeInvitation", { workspace: id, invitation }),
  previewInvitation: (sub: string, token: string) =>
    op<{ workspace: string; name: string; role: Role; inviter: string; email: string | null }>(sub, "invitation.preview", { token }),
  acceptInvitationById: (sub: string, id: string) => op<WorkspaceView>(sub, "invitation.accept", { id }),
  declineInvitation: (sub: string, id: string) => op<{ ok: true }>(sub, "invitation.decline", { id }),
  acceptInvitation: (sub: string, token: string) => op<WorkspaceView>(sub, "invitation.accept", { token }),
  setRole: (sub: string, id: string, member: string, role: Role) => op<WorkspaceView>(sub, "workspace.setRole", { workspace: id, member, role }),
  removeMember: (sub: string, id: string, member: string) => op<{ ok: true }>(sub, "workspace.removeMember", { workspace: id, member }),
  enroll: (sub: string, id: string, name: string) => op<{ token: string; expires_at: number; install: string; command: string }>(sub, "workspace.enroll", { workspace: id, name }),
  renameStation: (sub: string, id: string, station: string, name: string) => op<WorkspaceView>(sub, "workspace.renameStation", { workspace: id, station, name }),
  removeStation: (sub: string, id: string, station: string) => op<{ ok: true }>(sub, "workspace.removeStation", { workspace: id, station }),
  revokeLoginSession: (sub: string, id: string) => op<{ ok: true }>(sub, "loginSession.revoke", { id }),
};

/** The admin's console (on its own host, src/admin/); every call is a 404 for other accounts. */
export const admin = {
  me: (sub: string) => op<{ email: string }>(sub, "admin.me"),
  /** Each with its sign-up link on the web app. */
  createCode: (sub: string, note: string, days: number) => op<InviteCodeView & { url: string }>(sub, "admin.createCode", { note, days }),
  revokeCode: (sub: string, code: string) => op<{ ok: true }>(sub, "admin.revokeCode", { code }),
  /** Lets the account `user` into the test channel (app.youdid.wtf), or out of it. */
  setBeta: (sub: string, user: string, on: boolean) => op<{ sub: string; beta: boolean }>(sub, "admin.setBeta", { user, on }),
  /** Gives the account `user` the right to create workspaces, as an invite code would, or takes it back. */
  setMayCreate: (sub: string, user: string, on: boolean) => op<{ sub: string; may_create: boolean }>(sub, "admin.setMayCreate", { user, on }),
  /** Blocks the account `user` (signed out everywhere, kept out), or lets it back. */
  block: (sub: string, user: string, on: boolean) => op<{ blocked: boolean }>(sub, "admin.block", { user, on }),
  deleteWorkspace: (sub: string, workspace: string) => op<{ ok: true }>(sub, "admin.deleteWorkspace", { workspace }),
  /** Where a bug report stands. */
  feedbackStatus: (sub: string, id: string, status: FeedbackStatus) => op<{ ok: true }>(sub, "admin.feedbackStatus", { id, status }),
};

// still.fail cloud's invite-code errors in Chinese; the core passes their codes through (see CoreError).
const INVITE_ERRORS: Record<string, string> = {
  invite_code_required: "新建 workspace 要有邀请码，被邀请加入别人的 workspace 不用",
  invite_code_invalid: "这个邀请码不对，检查一下有没有输错",
  invite_code_used: "这个邀请码已经被用过了",
  invite_code_expired: "这个邀请码已经过期了",
};

const codeOf = (error: Error | null) => (error as { code?: string } | null)?.code ?? "";

/** Whether creating a workspace failed for want of a (good) invite code. */
export const needsInviteCode = (error: Error | null): boolean => codeOf(error) in INVITE_ERRORS;

// Its limits: what an account may create, and how many a workspace holds.
const LIMIT_ERRORS: Record<string, string> = {
  too_many_workspaces: "一个账号最多新建 5 个 workspace",
  too_many_members: "一个 workspace 最多邀请 5 个人",
};

export const errorText = (error: Error): string => INVITE_ERRORS[codeOf(error)] ?? LIMIT_ERRORS[codeOf(error)] ?? error.message;

/** Where a tab kept the code before the core did (moved into it the first time it is read). */
const INVITE_KEY = "stillfail.invite";

/**
 * The invite code this device arrived with (`/?invite=CODE`), kept by the core (prefs.ts): the page it came to may
 * first send it to Google to sign in, or on to a workspace before the code is asked for. The core lets it go once a
 * workspace is made.
 */
export function inviteCode(): string {
  // None on a page built to HTML (the site's demo has the workspace's pages: demo/prerender.tsx).
  if (typeof location === "undefined") return "";
  let given = new URLSearchParams(location.search).get("invite");
  try {
    given ??= sessionStorage.getItem(INVITE_KEY);
    sessionStorage.removeItem(INVITE_KEY);
  } catch { /* no storage */ }
  // Kept after this render (the prefs' watchers are redrawn by it).
  if (given && prefs().invite !== given) queueMicrotask(() => setPrefs({ invite: given }));
  return given ?? prefs().invite ?? "";
}

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
