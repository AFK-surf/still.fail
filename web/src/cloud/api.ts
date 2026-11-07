import { bindCloudOperations } from "../core/operations.ts";
// still.fail cloud's account API: what the pages have done there, by name, done by the core as one of the signed-in
// accounts. Reads are the core's `workspaces` and `workspace` topics; after a
// write the core refetches them, so nothing here keeps a cache.
import { useAction as useOperation } from "../action.ts";
import { core } from "../core/react.ts";
import type { AddedView, Admission, AdminUser, AdminWorkspace, FeedbackStatus, InvitationView, InviteCodeView, MeView, MemberView, PendingInvitation, Role, UserView, WayView, WorkspaceSummary, WorkspaceView } from "../../../cloud/src/types.ts";

export type { AddedView, Admission, AdminUser, AdminWorkspace, FeedbackStatus, InvitationView, InviteCodeView, MeView, MemberView, PendingInvitation, Role, UserView, WayView, WorkspaceSummary, WorkspaceView };

/** Has the core do `name` (client/core-ts/src/ops.ts) on still.fail cloud as the account `sub`, with `params`. */
const operations = (account: string) => bindCloudOperations((name, params) => core().call(name, { ...params, account }));

/** The admin's console (on its own host, src/admin/); every call is a 404 for other accounts. */
export const admin = {
  me: (sub: string) => operations(sub).adminMe<{ email: string }>(),
  /** Each with its sign-up link on the web app. */
  /** With `beta`, whoever redeems it is let into the test channel too. */
  createCode: (sub: string, note: string, days: number, beta = false) => operations(sub).adminCreateCode<InviteCodeView & { url: string }>({ note, days, ...(beta ? { beta } : {}) }),
  revokeCode: (sub: string, code: string) => operations(sub).adminRevokeCode<{ ok: true }>({ code }),
  /** Lets the account `user` into the test channel (app.youdid.wtf), or out of it. */
  setBeta: (sub: string, user: string, on: boolean) => operations(sub).adminSetBeta<{ sub: string; beta: boolean }>({ user, on }),
  /** Gives the account `user` the right to create workspaces, as an invite code would, or takes it back. */
  setMayCreate: (sub: string, user: string, on: boolean) => operations(sub).adminSetMayCreate<{ sub: string; may_create: boolean }>({ user, on }),
  /** Blocks the account `user` (signed out everywhere, kept out), or lets it back. */
  block: (sub: string, user: string, on: boolean) => operations(sub).adminBlock<{ blocked: boolean }>({ user, on }),
  /** Gives an email the test channel or the standard plan (one left out stays as it was): an account signed in with it at
   *  once (its `sub`), otherwise (`sub` null) the first that signs in with it. */
  setPending: (sub: string, email: string, rights: { beta?: boolean; may_create?: boolean }) =>
    operations(sub).adminSetPending<{ email: string; sub: string | null }>({ email, ...rights }),
  /** Takes back what an email nobody signed in with yet was given. */
  removePending: (sub: string, email: string) => operations(sub).adminRemovePending<{ ok: true }>({ email }),
  deleteWorkspace: (sub: string, workspace: string) => operations(sub).adminDeleteWorkspace<{ ok: true }>({ workspace }),
  /** A workspace for a company: its owners by email (members when they first sign in), and limits of its own. */
  createWorkspace: (sub: string, input: { name: string; owners: string[]; members: number; stations: number }) =>
    operations(sub).adminCreateWorkspace<{ id: string; joined: string[]; added: string[] }>(input),
  setLimits: (sub: string, workspace: string, limits: { members: number; stations: number }) =>
    operations(sub).adminSetLimits<{ members: number; stations: number }>({ workspace, ...limits }),
  /** A station's enrollment for any workspace, the admin not in it. */
  enroll: (sub: string, workspace: string, name: string) =>
    operations(sub).adminEnroll<{ token: string; expires_at: number; install: string; installWindows?: string; command: string }>({ workspace, name }),
  /** Where a bug report stands. */
  feedbackStatus: (sub: string, id: string, status: FeedbackStatus) => operations(sub).adminFeedbackStatus<{ ok: true }>({ id, status }),
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

/** Same action adapter as the station pages; kept as a one-argument facade for existing cloud controls. */
export function useAction<A = void, T = unknown>(write: (arg: A) => Promise<T>, onDone?: (result: T, arg: A) => void): Action<A, T> {
  const action = useOperation(write, onDone);
  return { run: action.run, busy: action.busy, error: action.error, arg: action.args?.[0], result: action.data };
}
