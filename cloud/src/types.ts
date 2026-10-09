// What the account API returns; shared with the web app, so no runtime imports here.
export type Role = "owner" | "admin" | "member";

export interface UserView { sub: string; email: string; name: string; picture: string }
/** The signed-in account, as `/v1/me` has it: `beta` only when the admin let it into the test channel. */
export interface MeView extends UserView { beta?: true }
/** `relays`: the workspace's own relays, used besides still.fail's (absent from a cloud from before them). */
export interface WorkspaceSummary { id: string; name: string; role: Role; created_at: number; stations: number; members: number; relays?: string[] }
/** last_seen: when it last connected to still.fail cloud or left it (whether it is up, each device finds out over the mesh). */
export interface StationView { id: string; name: string; emoji: string | null; icon?: string | null; enrolled_at: number; enrolled_by: string; last_seen: number | null; version: string | null }
export interface MemberView extends UserView { role: Role; added_at: number }
export interface InvitationView { id: string; role: Role; email: string | null; created_by: string; expires_at: number }
/** An invitation waiting for the signed-in account's email. */
export interface PendingInvitation { id: string; workspace: string; name: string; role: Role; inviter: string; expires_at: number }
/** An email added to a workspace whose account has not signed in yet: a member from its first sign-in on. */
export interface AddedView { email: string; role: Role; added_by: string; added_at: number }
export interface WorkspaceView { id: string; name: string; role: Role; created_at: number; members: MemberView[]; stations: StationView[]; invitations: InvitationView[]; added: AddedView[]; relays?: string[] }

/** What `/v1/events` pushes: what changed, for the device to refetch. */
export type AccountEvent =
  | { type: "workspaces" }
  | { type: "workspace"; id: string };

// ── the operator's console (/v1/admin/*, the admin account only) ──────────

/**
 * How someone got in: the admin, a code, the admin's say (`granted`), an invitation, a member from before codes existed,
 * or creating a workspace on the free plan.
 */
export type Admission = "admin" | "code" | "granted" | "invitation" | "early" | "free";
/** Which plan an account, or a workspace (its creator's), is on (directory.ts PLANS). */
export type PlanName = "free" | "standard" | "admin";
export interface AdminUser extends UserView {
  created_at: number;
  /** When they last signed in or opened still.fail (its events socket); null before this was recorded. */
  last_seen: number | null;
  /** null: signed in but not let in yet (no workspace, no code, no invitation). */
  admission: Admission | null;
  workspaces: { id: string; name: string; role: Role }[];
  /** Let into the test channel (app.youdid.wtf). Missing from a cloud from before it. */
  beta?: boolean;
  /** Whether they are on the standard plan (create up to 5 workspaces of 6 people); `creator`: kept it by having made one (before the free plan). Missing from a cloud from before. */
  may_create?: boolean;
  /** may_create as a plan. Missing from a cloud from before; creator is false from the free plan on. */
  plan?: PlanName;
  creator?: boolean;
  /** Blocked by the admin from the console. Missing from a cloud from before. */
  blocked?: boolean;
}
export interface AdminWorkspace {
  id: string;
  name: string;
  created_at: number;
  created_by: UserView | null;
  /** Each with when they last came (missing from a cloud from before). */
  members: (MemberView & { last_seen?: number | null })[];
  stations: StationView[];
  invitations: (InvitationView & { inviter: string })[];
  /** How many people it may hold. Missing from a cloud from before. */
  seats?: number;
  /** Its creator's plan. Missing from a cloud from before. */
  plan?: PlanName;
}
/** What a bug report is about (feedback.ts). */
export type FeedbackArea = "station" | "web" | "android" | "desktop" | "slack" | "cloud" | "unknown";
export type FeedbackStatus = "new" | "triaged" | "fixed" | "wontfix";
/** A bug report about still.fail itself, as the console lists it (/v1/admin/feedback). Times in seconds. */
export interface AdminFeedback {
  id: string;
  /** Counts up from 1: what the reporter was told (FB-<number>). */
  number: number;
  /** The host it came on: app.still.fail (stable) or the test channel's. */
  channel: "stable" | "beta";
  /** The station that sent it (its agent, for the person it works for), with its name and workspace, or null. */
  station: { id: string; name: string } | null;
  workspace: { id: string; name: string } | null;
  /** The signed-in account that sent it, or null. */
  account: { sub: string; email: string; name: string } | null;
  title: string;
  /** What happened, what was expected, how to get there: Markdown, as the agent wrote it and the person agreed to. */
  body: string;
  area: FeedbackArea;
  /** Who it is from, as the agent knew them (a name and where they said it). */
  reporter: string;
  /** What the station added: its version, runtime, the session and thread, trace ids. */
  context: Record<string, unknown> | null;
  logs: string | null;
  status: FeedbackStatus;
  /** The version its fix came in (the changelog's `Fixes: FB-<n>`), and when its station told the reporter; null before. Missing from a cloud from before. */
  fixed_in?: number | null;
  told_at?: number | null;
  created_at: number;
  updated_at: number;
}

export interface InviteCodeView {
  code: string;
  note: string;
  created_at: number;
  expires_at: number;
  revoked_at: number | null;
  used_at: number | null;
  used_by: UserView | null;
  /** The workspace it created (null once that was deleted). */
  workspace: { id: string; name: string } | null;
}
