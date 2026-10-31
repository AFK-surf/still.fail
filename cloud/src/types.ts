// What the account API returns; shared with the web app, so no runtime imports here.
export type Role = "owner" | "admin" | "member";

export interface UserView { sub: string; email: string; name: string; picture: string }
/** The signed-in account, as `/v1/me` has it: `beta` only when the admin let it into the test channel. */
export interface MeView extends UserView { beta?: true }
/** `relays`: the workspace's own relays, used besides still.fail's (absent from a cloud from before them). `ways_off`: the
 * ways its devices do not go to its stations (relay URLs, `lan`, `tailnet`, `direct`), only when some are turned off. */
export interface WorkspaceSummary { id: string; name: string; emoji?: string; icon?: string; role: Role; created_at: number; stations: number; members: number; relays?: string[]; ways_off?: string[] }
/** One way a workspace's devices reach its stations, on or turned off: a relay (still.fail's, `name` as still.fail calls
 * it; or the workspace's own, `own`), or a kind of way that is no relay (`id` the kind). */
export interface WayView { id: string; kind: "relay" | "lan" | "tailnet" | "direct"; name?: string; own?: true; on: boolean }
/**
 * last_seen: when it last connected to still.fail cloud or left it (whether it is up, each device finds out over the mesh).
 * name, emoji, icon, enrolled_*: in this workspace. joined: the station is in another workspace too, which it joined
 * first (its home, whose owners and admins manage the machine: docs/multi-workspace.md); absent where this is its home.
 */
export interface StationView { id: string; name: string; emoji: string | null; icon?: string | null; enrolled_at: number; enrolled_by: string; last_seen: number | null; version: string | null; joined?: true }
export interface MemberView extends UserView { role: Role; added_at: number }
export interface InvitationView { id: string; role: Role; email: string | null; created_by: string; expires_at: number }
/** An invitation waiting for the signed-in account's email. */
export interface PendingInvitation { id: string; workspace: string; name: string; role: Role; inviter: string; expires_at: number }
/** An email added to a workspace whose account has not signed in yet: a member from its first sign-in on. */
export interface AddedView { email: string; role: Role; added_by: string; added_at: number }
export interface WorkspaceView { id: string; name: string; emoji?: string; icon?: string; role: Role; created_at: number; members: MemberView[]; stations: StationView[]; invitations: InvitationView[]; added: AddedView[]; relays?: string[]; ways_off?: string[]; /** Every way, on or off (setWay). */ ways?: WayView[]; lock?: LockHead | null; /** In security mode now: a lock not turned off. */ locked?: true; lock_requests?: number }

/** How far the workspace's lock goes as the cloud keeps it (docs/workspace-lock.md): null, none. */
export interface LockHead { seq: number; hash: string; genesis: string }
/** A device that asked for a member credential in a workspace: its endpoint, and (a newer client) its base key, which
 * proved it holds the endpoint. What turning the lock on lists for its owner to check. */
export interface DeviceView { sub: string; email: string; device: string; base: string | null; kind: string | null; label: string | null; first_seen: number; last_seen: number }
/** A device waiting to be confirmed into a locked workspace. */
export interface LockRequestView { base: string; sub: string; email: string; kind: string; label: string; sign_key: string | null; endpoints: string[]; code: string; created_at: number }

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
/** Rights the admin gave an email nobody has signed in with yet: the account it signs in with first has them. */
export interface AdminPending {
  email: string;
  beta: boolean;
  may_create: boolean;
  added_at: number;
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
  /** How many stations it may hold. Missing from older clouds. */
  station_seats?: number;
  /** Older clouds said this when the free plan had no station limit. */
  stations_unlimited?: true;
  /** Its creator's plan, or `enterprise`: limits of its own, the admin made it for a company. Missing from a cloud from before. */
  plan?: PlanName | "enterprise";
  /** Emails added that have not signed in yet (a company's owners, at first). Missing from a cloud from before. */
  added?: AddedView[];
  /** Whether the admin may put a station in it: made for a company, none of its owners signed in yet. */
  enrollable?: boolean;
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
  /** Whoever redeems it is let into the test channel too. Missing from a cloud from before. */
  beta?: boolean;
  created_at: number;
  expires_at: number;
  revoked_at: number | null;
  used_at: number | null;
  used_by: UserView | null;
  /** The workspace it created (null once that was deleted). */
  workspace: { id: string; name: string } | null;
}
