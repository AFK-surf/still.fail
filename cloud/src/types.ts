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
