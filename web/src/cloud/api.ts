// ember cloud's account API, called as one of the signed-in accounts.
import { accessToken } from "./accounts.ts";
import type { InvitationView, MemberView, PendingInvitation, Role, StationView, UserView, WorkspaceSummary, WorkspaceView } from "../../../cloud/src/types.ts";

export type { InvitationView, MemberView, PendingInvitation, Role, StationView, UserView, WorkspaceSummary, WorkspaceView };

export class CloudError extends Error {
  readonly status: number;
  readonly code: string;
  constructor(status: number, code: string) {
    super(MESSAGES[code] ?? code);
    this.status = status;
    this.code = code;
  }
}

const MESSAGES: Record<string, string> = {
  workspace_not_found: "找不到这个 workspace，或者你已经不在里面了",
  member_not_found: "找不到这个成员",
  station_not_found: "找不到这台 station",
  invitation_not_found: "邀请链接无效或已过期",
  invitation_for_other_email: "这个邀请是发给另一个邮箱的，请换对应的账号接受",
  forbidden: "你在这个 workspace 里没有这个权限",
  invalid_name: "名字不能为空，最长 80 个字",
  invalid_email: "要填对方登录 ember 用的邮箱",
  already_member: "这个邮箱的主人已经在 workspace 里了",
  last_owner: "workspace 至少要保留一个 owner",
  too_many_workspaces: "你创建的 workspace 太多了",
  too_many_invitations: "未处理的邀请太多了，先撤回一些",
  too_many_members: "成员数量到上限了",
  too_many_stations: "station 数量到上限了",
  invalid_session: "登录已失效，请重新登录",
};

async function call<T>(sub: string, method: string, path: string, body?: unknown): Promise<T> {
  const response = await fetch(path, {
    method,
    headers: { authorization: `Bearer ${await accessToken(sub)}`, ...(body === undefined ? {} : { "content-type": "application/json" }) },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const data = await response.json().catch(() => ({})) as { error?: string };
  if (!response.ok) throw new CloudError(response.status, data.error ?? `http_${response.status}`);
  return data as T;
}

export interface Me { user: UserView | null; workspaces: WorkspaceSummary[]; invitations: PendingInvitation[]; relay_url: string }
export interface Grant { grant: string; expires_at: number; station: string; station_name: string; relay_url: string }

const ws = (id: string) => `/v1/workspaces/${encodeURIComponent(id)}`;

export const cloud = {
  me: (sub: string) => call<Me>(sub, "GET", "/v1/me"),
  createWorkspace: (sub: string, name: string) => call<WorkspaceView>(sub, "POST", "/v1/workspaces", { name }),
  workspace: (sub: string, id: string) => call<WorkspaceView>(sub, "GET", ws(id)),
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
  grant: (sub: string, id: string, station: string, device: string) => call<Grant>(sub, "POST", `${ws(id)}/stations/${station}/grant`, { device }),
};
