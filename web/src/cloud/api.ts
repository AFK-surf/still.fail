import { bindCloudOperations } from "../core/operations.ts";
// still.fail cloud's account API: what the pages have done there, by name, done by the core as one of the signed-in
// accounts. Reads are the core's `workspaces` and `workspace` topics; after a
// write the core refetches them, so nothing here keeps a cache.
import { useAction as useOperation } from "../action.ts";
import type { ErrorBody } from "../core/client.ts";
import { core, useTopic, type TopicState } from "../core/react.ts";
import { prefs, setPrefs } from "../prefs.ts";
import { t } from "../i18n.ts";
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

/** Has the core do `name` (client/core-ts/src/ops.ts) on still.fail cloud as the account `sub`, with `params`. */
const operations = (account: string) => bindCloudOperations((name, params) => core().call(name, { ...params, account }));

export interface LoginSession { id: string; name: string; created_at: number; expires_at: number; current: boolean }

export const cloud = {
  /** `code`: an invite code, for an account not let in yet (still.fail is invite-only). */
  createWorkspace: (sub: string, name: string, code?: string) => operations(sub).workspaceCreate<WorkspaceView>(code ? { name, invite_code: code } : { name }),
  renameWorkspace: (sub: string, id: string, name: string) => operations(sub).workspaceRename<WorkspaceView>({ workspace: id, name }),
  /** The workspace's own relays, the whole list (cloud directory.ts setRelays). */
  setRelays: (sub: string, id: string, relays: string[]) => operations(sub).workspaceSetRelays<WorkspaceView>({ workspace: id, relays }),
  deleteWorkspace: (sub: string, id: string) => operations(sub).workspaceDelete<{ ok: true }>({ workspace: id }),
  invite: (sub: string, id: string, role: Role, email: string) =>
    operations(sub).workspaceInvite<{ token: string; url: string; expires_at: number }>({ workspace: id, role, email }),
  /** Adds people by email: members at once, or from their first sign-in; no invitation to accept. */
  addMembers: (sub: string, id: string, role: Role, emails: string[]) =>
    operations(sub).workspaceAddMembers<{ joined: string[]; added: string[]; already: string[]; view: WorkspaceView }>({ workspace: id, role, emails }),
  removeAdded: (sub: string, id: string, email: string) => operations(sub).workspaceRemoveAdded<WorkspaceView>({ workspace: id, email }),
  revokeInvitation: (sub: string, id: string, invitation: string) => operations(sub).workspaceRevokeInvitation<{ ok: true }>({ workspace: id, invitation }),
  previewInvitation: (sub: string, token: string) =>
    operations(sub).invitationPreview<{ workspace: string; name: string; role: Role; inviter: string; email: string | null }>({ token }),
  acceptInvitationById: (sub: string, id: string) => operations(sub).invitationAccept<WorkspaceView>({ id }),
  declineInvitation: (sub: string, id: string) => operations(sub).invitationDecline<{ ok: true }>({ id }),
  acceptInvitation: (sub: string, token: string) => operations(sub).invitationAccept<WorkspaceView>({ token }),
  setRole: (sub: string, id: string, member: string, role: Role) => operations(sub).workspaceSetRole<WorkspaceView>({ workspace: id, member, role }),
  removeMember: (sub: string, id: string, member: string) => operations(sub).workspaceRemoveMember<{ ok: true }>({ workspace: id, member }),
  enroll: (sub: string, id: string, name: string) => operations(sub).workspaceEnroll<{ token: string; expires_at: number; install: string; command: string }>({ workspace: id, name }),
  renameStation: (sub: string, id: string, station: string, name: string) => operations(sub).workspaceRenameStation<WorkspaceView>({ workspace: id, station, name }),
  /** Its icon and emoji together (../stationPick.ts); "" takes either away. */
  setStationMark: (sub: string, id: string, station: string, mark: { emoji: string; icon: string }) => operations(sub).workspaceRenameStation<WorkspaceView>({ workspace: id, station, emoji: mark.emoji, icon: mark.icon }),
  removeStation: (sub: string, id: string, station: string) => operations(sub).workspaceRemoveStation<{ ok: true }>({ workspace: id, station }),
  revokeLoginSession: (sub: string, id: string) => operations(sub).loginSessionRevoke<{ ok: true }>({ id }),
};

/** The admin's console (on its own host, src/admin/); every call is a 404 for other accounts. */
export const admin = {
  me: (sub: string) => operations(sub).adminMe<{ email: string }>(),
  /** Each with its sign-up link on the web app. */
  createCode: (sub: string, note: string, days: number) => operations(sub).adminCreateCode<InviteCodeView & { url: string }>({ note, days }),
  revokeCode: (sub: string, code: string) => operations(sub).adminRevokeCode<{ ok: true }>({ code }),
  /** Lets the account `user` into the test channel (app.youdid.wtf), or out of it. */
  setBeta: (sub: string, user: string, on: boolean) => operations(sub).adminSetBeta<{ sub: string; beta: boolean }>({ user, on }),
  /** Gives the account `user` the right to create workspaces, as an invite code would, or takes it back. */
  setMayCreate: (sub: string, user: string, on: boolean) => operations(sub).adminSetMayCreate<{ sub: string; may_create: boolean }>({ user, on }),
  /** Blocks the account `user` (signed out everywhere, kept out), or lets it back. */
  block: (sub: string, user: string, on: boolean) => operations(sub).adminBlock<{ blocked: boolean }>({ user, on }),
  deleteWorkspace: (sub: string, workspace: string) => operations(sub).adminDeleteWorkspace<{ ok: true }>({ workspace }),
  /** Where a bug report stands. */
  feedbackStatus: (sub: string, id: string, status: FeedbackStatus) => operations(sub).adminFeedbackStatus<{ ok: true }>({ id, status }),
};

// still.fail cloud's invite-code errors in words; the core passes their codes through (see CoreError).
const INVITE_ERRORS = (): Record<string, string> => ({
  invite_code_required: t("web-pages.errors.inviteCodeRequired"),
  invite_code_invalid: t("web-pages.errors.inviteCodeInvalid"),
  invite_code_used: t("web-pages.errors.inviteCodeUsed"),
  invite_code_expired: t("web-pages.errors.inviteCodeExpired"),
});

const codeOf = (error: Error | null) => (error as { code?: string } | null)?.code ?? "";

/** Whether creating a workspace failed for want of a (good) invite code. */
export const needsInviteCode = (error: Error | null): boolean => codeOf(error) in INVITE_ERRORS();

// Its limits: what an account may create, and how many a workspace holds.
const LIMIT_ERRORS = (): Record<string, string> => ({
  too_many_workspaces: t("web-pages.errors.tooManyWorkspaces"),
  too_many_members: t("web-pages.errors.tooManyMembers"),
});

export const errorText = (error: Error): string => INVITE_ERRORS()[codeOf(error)] ?? LIMIT_ERRORS()[codeOf(error)] ?? error.message;

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

/** Same action adapter as the station pages; kept as a one-argument facade for existing cloud controls. */
export function useAction<A = void, T = unknown>(write: (arg: A) => Promise<T>, onDone?: (result: T, arg: A) => void): Action<A, T> {
  const action = useOperation(write, onDone);
  return { run: action.run, busy: action.busy, error: action.error, arg: action.args?.[0], result: action.data };
}
