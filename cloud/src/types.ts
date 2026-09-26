// What the account API returns; shared with the web app, so no runtime imports here.
export type Role = "owner" | "admin" | "member";

export interface UserView { sub: string; email: string; name: string; picture: string }
export interface WorkspaceSummary { id: string; name: string; role: Role; created_at: number; stations: number; members: number }
/** online: connected to ember cloud now; last_seen: when it last connected or disconnected. */
export interface StationView { id: string; name: string; enrolled_at: number; enrolled_by: string; online: boolean; last_seen: number | null; version: string | null }
export interface MemberView extends UserView { role: Role; added_at: number }
export interface InvitationView { id: string; role: Role; email: string | null; created_by: string; expires_at: number }
/** An invitation waiting for the signed-in account's email. */
export interface PendingInvitation { id: string; workspace: string; name: string; role: Role; inviter: string; expires_at: number }
export interface WorkspaceView { id: string; name: string; role: Role; created_at: number; members: MemberView[]; stations: StationView[]; invitations: InvitationView[] }

/** What `/v1/events` pushes: what changed, for the device to refetch. */
export type AccountEvent =
  | { type: "workspaces" }
  | { type: "workspace"; id: string }
  | { type: "station"; workspace: string; id: string; online: boolean };

// ── the operator's console (/v1/admin/*, the admin account only) ──────────

/** How someone got in: the admin, a code, an invitation, or a member from before codes existed. */
export type Admission = "admin" | "code" | "invitation" | "early";
export interface AdminUser extends UserView {
  created_at: number;
  /** When they last signed in or opened ember (its events socket); null before this was recorded. */
  last_seen: number | null;
  /** null: signed in but not let in yet (no workspace, no code, no invitation). */
  admission: Admission | null;
  workspaces: { id: string; name: string; role: Role }[];
}
export interface AdminWorkspace {
  id: string;
  name: string;
  created_at: number;
  created_by: UserView | null;
  members: MemberView[];
  stations: StationView[];
  invitations: (InvitationView & { inviter: string })[];
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
