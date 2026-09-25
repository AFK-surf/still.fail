// What the account API returns; shared with the web app, so no runtime imports here.
export type Role = "owner" | "admin" | "member";

export interface UserView { sub: string; email: string; name: string; picture: string }
export interface WorkspaceSummary { id: string; name: string; role: Role; created_at: number; stations: number; members: number }
export interface StationView { id: string; name: string; enrolled_at: number; enrolled_by: string; last_seen: number | null; version: string | null }
export interface MemberView extends UserView { role: Role; added_at: number }
export interface InvitationView { id: string; role: Role; email: string | null; created_by: string; expires_at: number }
/** An invitation waiting for the signed-in account's email. */
export interface PendingInvitation { id: string; workspace: string; name: string; role: Role; inviter: string; expires_at: number }
export interface WorkspaceView { id: string; name: string; role: Role; created_at: number; members: MemberView[]; stations: StationView[]; invitations: InvitationView[] }

