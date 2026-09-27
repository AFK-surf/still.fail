// The workspace itself on a narrow screen: its name, its people (invited, their roles, moved out), and leaving or
// deleting it. What the desktop's 通用, 成员 and 退出与删除 settings do, on one page in the Android app's manner.
import { useState } from "react";
import { stamp } from "../api.ts";
import { cloud, useWorkspace, type LoginSession, type MemberView, type Role, type WorkspaceView } from "../cloud/api.ts";
import { useTopic } from "../core/react.ts";
import { ROLE_HINT, ROLE_LABEL } from "../cloud/settings.tsx";
import { SheetGrab, SheetHead, useApp, type MobileApp } from "./app.tsx";
import { Avatar, Button, Field, LargeTitle, ListCard, ListRow, Loading, PickRow, SectionHeader, TopBack } from "./parts.tsx";
import { ask, confirm } from "./sheets.tsx";

export function WorkspaceScreen() {
  const app = useApp();
  const view = useWorkspace(app.entry.id).value;
  const me = app.entry.account;
  if (!view) return <div className="m-screen"><TopBack label="会话" onBack={app.pop} /><Loading text="正在读取 workspace…" /></div>;
  const manager = view.role === "owner" || view.role === "admin";
  const leave = () => confirm(app, {
    title: `退出「${view.name}」？`, text: "退出后你就不能再访问里面的 station，需要重新被邀请才能回来。", action: "退出", danger: true,
    run: () => cloud.removeMember(me.sub, view.id, me.sub).then(() => { app.toast("已退出 workspace"); app.replace("/"); }),
  });
  const remove = () => confirm(app, {
    title: `删除「${view.name}」？`, action: "删除 workspace", danger: true,
    text: `所有成员都会失去访问权限，${view.stations.length} 台 station 会断开和 ember cloud 的连接（station 本机上的数据不受影响）。`,
    run: () => cloud.deleteWorkspace(me.sub, view.id).then(() => { app.toast("已删除 workspace"); app.replace("/"); }),
  });
  return (
    <div className="m-screen m-scroll">
      <TopBack label="会话" onBack={app.pop} />
      <LargeTitle small={`你是${ROLE_LABEL[view.role]} · ${me.email}`} big={view.name} />
      {manager && (
        <ListCard>
          <ListRow onClick={() => ask(app, { title: "Workspace 名字", value: view.name, placeholder: "例如：产品团队", action: "保存",
            run: (name) => cloud.renameWorkspace(me.sub, view.id, name).then(() => app.toast("已改名")) })}>
            <span className="m-grow m-row-title">改名</span>
          </ListRow>
        </ListCard>
      )}
      <SectionHeader title={`成员 · ${view.members.length} 人`} start={24} />
      <ListCard>
        {view.members.map((m) => <MemberRow key={m.sub} view={view} m={m} me={me.sub} />)}
        {manager && <ListRow onClick={() => app.sheet({ height: 0.62, content: () => <InviteSheet view={view} /> })}><span className="m-accent m-row-title">＋ 邀请成员</span></ListRow>}
      </ListCard>
      {manager && view.invitations.length > 0 && (
        <>
          <SectionHeader title="未接受的邀请" trailing={`${view.invitations.length} 个`} start={24} />
          <ListCard>
            {view.invitations.map((i) => (
              <ListRow key={i.id}>
                <span className="m-grow m-row-text"><span className="m-row-title">{i.email ?? "任何拿到链接的人"}</span><span className="m-row-note">{ROLE_LABEL[i.role]} · {stamp(i, "expires_at")?.until}过期</span></span>
                <button type="button" className="m-link" onClick={() => void cloud.revokeInvitation(me.sub, view.id, i.id).then(() => app.toast("已撤回邀请"), (e: Error) => app.toast(e.message))}>撤回</button>
              </ListRow>
            ))}
          </ListCard>
        </>
      )}
      <SectionHeader title="离开" start={24} />
      <ListCard>
        <ListRow onClick={leave}><span className="m-grow m-row-title m-red">退出这个 workspace</span></ListRow>
        {view.role === "owner" && <ListRow onClick={remove}><span className="m-grow m-row-title m-red">删除 workspace</span></ListRow>}
      </ListCard>
      <div style={{ height: 30 }} />
    </div>
  );
}

/** A person of the workspace; the owner changes their role, a manager moves them out (an owner only by an owner). */
function MemberRow({ view, m, me }: { view: WorkspaceView; m: MemberView; me: string }) {
  const app = useApp();
  const manager = view.role === "owner" || view.role === "admin";
  const can = m.sub !== me && manager && (m.role !== "owner" || view.role === "owner");
  return (
    <ListRow onClick={can ? () => app.sheet({ height: 0.5, content: () => <MemberSheet view={view} m={m} /> }) : undefined}>
      <Avatar id={m.email} name={m.name || m.email} size={28} picture={m.picture ?? undefined} />
      <span className="m-grow m-row-text">
        <span className="m-row-title">{m.name || m.email}{m.sub === me && <span className="m-you">你</span>}</span>
        <span className="m-row-note">{m.email}</span>
      </span>
      <span className="m-row-note">{ROLE_LABEL[m.role]}</span>
    </ListRow>
  );
}

function MemberSheet({ view, m }: { view: WorkspaceView; m: MemberView }) {
  const app = useApp();
  const me = app.entry.account;
  const setRole = (role: Role) => cloud.setRole(me.sub, view.id, m.sub, role).then(() => { app.toast("已更改角色"); app.sheet(null); }, (e: Error) => app.toast(e.message));
  return (
    <>
      <SheetGrab />
      <SheetHead title={m.name || m.email} />
      <div className="m-sheet-scroll">
        {view.role === "owner" && (["owner", "admin", "member"] as Role[]).map((r) => (
          <PickRow key={r} label={ROLE_LABEL[r]} sub={ROLE_HINT[r]} checked={m.role === r} onClick={() => void setRole(r)} />
        ))}
        <PickRow label="移出 workspace" accent onClick={() => removeMember(app, view, m)} />
      </div>
    </>
  );
}

function removeMember(app: MobileApp, view: WorkspaceView, m: MemberView) {
  confirm(app, {
    title: `把 ${m.email} 移出「${view.name}」？`, text: "对方不能再访问这个 workspace 里的 station，之后可以重新邀请。", action: "移出", danger: true,
    run: () => cloud.removeMember(app.entry.account.sub, view.id, m.sub).then(() => app.toast("已移除成员")),
  });
}

function InviteSheet({ view }: { view: WorkspaceView }) {
  const app = useApp();
  const me = app.entry.account;
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<Role>("member");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);
  const roles: Role[] = view.role === "owner" ? ["member", "admin", "owner"] : ["member", "admin"];
  const valid = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim());
  return (
    <>
      <SheetGrab />
      <SheetHead title="邀请成员" />
      <div className="m-sheet-scroll m-form">
        {done ? (
          <>
            <p>已邀请 {email.trim()}。对方用这个邮箱登录 ember 就能看到邀请并加入。</p>
            <div className="m-form-actions"><Button label="完成" primary onClick={() => app.sheet(null)} /></div>
          </>
        ) : (
          <>
            <p className="m-muted">对方用这个邮箱登录 ember，就会看到加入「{view.name}」的邀请。邀请 7 天内有效。</p>
            <b className="m-form-label">邮箱</b>
            <Field value={email} onChange={setEmail} placeholder="name@example.com" />
            <b className="m-form-label">角色</b>
            {roles.map((r) => <PickRow key={r} label={ROLE_LABEL[r]} sub={ROLE_HINT[r]} checked={role === r} onClick={() => setRole(r)} />)}
            {error && <p className="m-error">{error}</p>}
            <div className="m-form-actions">
              <Button label="取消" primary={false} onClick={() => app.sheet(null)} />
              <Button label="邀请" primary busy={busy} enabled={valid} onClick={() => {
                setBusy(true); setError(null);
                cloud.invite(me.sub, view.id, role, email.trim()).then(() => setDone(true), (e: Error) => setError(e.message)).finally(() => setBusy(false));
              }} />
            </div>
          </>
        )}
      </div>
    </>
  );
}

/** The account's devices: where it is signed in to ember; one not recognised can be signed out from here. */
export function Devices() {
  const app = useApp();
  const me = app.entry.account;
  const devices = useTopic<LoginSession[]>({ topic: "loginSessions", account: me.sub });
  if (!devices.value) return <p className="m-note">{devices.error ? `读不到登录记录：${devices.error.message}` : "正在读取…"}</p>;
  return (
    <ListCard>
      {devices.value.map((s) => (
        <ListRow key={s.id}>
          <span className="m-grow m-row-text">
            <span className="m-row-title">{s.name || "未命名设备"}{s.current && <span className="m-you">这里</span>}</span>
            <span className="m-row-note">{stamp(s, "created_at")?.ago}登录 · {stamp(s, "expires_at")?.until}过期</span>
          </span>
          {!s.current && <button type="button" className="m-link" onClick={() => void cloud.revokeLoginSession(me.sub, s.id).then(() => app.toast("已让那台设备退出"), (e: Error) => app.toast(e.message))}>退出</button>}
        </ListRow>
      ))}
    </ListCard>
  );
}
