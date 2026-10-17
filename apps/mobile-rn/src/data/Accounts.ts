// The `accounts` and `workspaces` topics: who is signed in, and which workspaces each account reaches
// (data/Accounts.kt; web/src/cloud/accounts.ts, web/src/cloud/api.ts). still.fail cloud's topics are not shaped yet
// (not in shapes.ts): their shapes are here. A field the Kotlin gives a default may be absent (`?`): read it with that
// default (`name ?? ""`, `role ?? "member"`, a list `?? []`).
import type { Stamp } from "../../../../web/src/core/shapes.ts";
import { t } from "../i18n";

export interface Account { sub: string; email: string; name?: string; picture?: string }

/** `emoji` and `icon` are its mark, as a station's (StationMark): none when none. */
export interface WorkspaceSummary { id: string; name: string; role?: string; stations?: number; members?: number; emoji?: string | null; icon?: string | null }

export interface AccountWorkspaces {
  account: Account;
  workspaces?: WorkspaceSummary[];
  /** Invitations waiting for this account's email. */
  invitations?: PendingInvitation[];
  /** The account's `/v1/me` has answered; until then (or after a failure) an empty list says nothing. */
  loaded?: boolean;
  /** still.fail cloud lets this account use the beta apps (its `/v1/me` says `user.beta`). */
  beta?: boolean;
  /** In the beta app, an account still.fail cloud has not let into the beta: what to say (the core's), with a way out. */
  blocked?: string | null;
  /** Set when this account could not be read. */
  error?: unknown;
}

export interface PendingInvitation { id: string; workspace?: string; name?: string; role?: string; inviter?: string }

export const ROLE_LABEL: Record<string, string> = {
  owner: "Owner",
  get admin() { return t("android-misc.role.admin"); },
  get member() { return t("android-misc.role.member"); },
};

/** A workspace with the account it is reached through. */
export interface WorkspaceEntry { workspace: WorkspaceSummary; account: Account }

/** Every account's workspaces, each once (the first account that reaches it). */
export function entries(list: AccountWorkspaces[]): WorkspaceEntry[] {
  const seen = new Set<string>();
  const out: WorkspaceEntry[] = [];
  for (const a of list) {
    for (const w of a.workspaces ?? []) {
      if (seen.has(w.id)) continue;
      seen.add(w.id);
      out.push({ workspace: w, account: a.account });
    }
  }
  return out;
}

export const ROLE_HINT: Record<string, string> = {
  get owner() { return t("android-misc.role.owner.hint"); },
  get admin() { return t("android-misc.role.admin.hint"); },
  get member() { return t("android-misc.role.member.hint"); },
};

export interface Member { email: string; name?: string; sub?: string; picture?: string | null; role?: string }

export interface WorkspaceStation { id: string; name?: string }

/** An invitation not accepted yet; `time` has its expiry in words (the core's). */
export interface Invitation { id: string; role?: string; email?: string | null; time?: Record<string, Stamp> | null }

/** An email added to a workspace whose account has not signed in yet: a member from its first sign-in on (cloud/src/types.ts → AddedView). */
export interface Added { email: string; role?: string; added_by?: string }

/**
 * The `workspace` topic: the viewer's role in it, its members (to name people by their email, and to manage them), its
 * stations' names, the emails added but not signed in yet, the invitations not accepted yet, and its own relays (used
 * besides still.fail's; none from a cloud from before them). Its mark (`emoji`, `icon`) is as a station's.
 */
export interface WorkspaceView {
  id: string; name?: string; emoji?: string | null; icon?: string | null; role?: string; members?: Member[];
  stations?: WorkspaceStation[]; invitations?: Invitation[];
  added?: Added[]; relays?: string[];
}

/** The viewer may manage it (WorkspaceView.manager): an owner or an admin. */
export function manager(view: WorkspaceView): boolean {
  return view.role === "owner" || view.role === "admin";
}

/** Where an account is signed in to still.fail (the `loginSessions` topic); `time` has when, in words. */
export interface LoginSession { id: string; name?: string; current?: boolean; time?: Record<string, Stamp> | null }

/** What adding people by email came to: who joined at once, who joins at their first sign-in, who was in already. */
export class AddedMembers {
  constructor(readonly joined: string[], readonly added: string[], readonly already: string[]) {}
}

/** A person of a Slack workspace a station's connects are in, by their email there (GET /slack/people). */
export interface SlackPerson { email: string; name?: string; image?: string | null; guest?: boolean; team?: string | null }
