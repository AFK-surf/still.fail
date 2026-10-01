// The workspace itself on a narrow screen, from settings (./Settings.tsx): its name as the title (a tap renames it), its
// people in one list (those in it, those added who have not signed in, the invitations out), adding them from the ＋
// at the top, and leaving or deleting it at the bottom. What the desktop's workspace settings do, in the Android app's manner.
import { parseEmails, useSlackPeople } from "../cloud/adding.ts";
import { useEffect, useState } from "react";
import { stamp } from "../api.ts";
import { cloud, errorText, useWorkspace, type LoginSession, type MemberView, type Role, type WorkspaceView } from "../cloud/api.ts";
import { useTopic } from "../core/react.ts";
import { ROLE_HINT, ROLE_LABEL } from "../cloud/settings.tsx";
import { SheetGrab, SheetHead, useApp, type MobileApp } from "./app.tsx";
import { Check, UserPlus } from "../icons.tsx";
import { Avatar, Button, Field, LargeTitle, LinkButton, ListCard, ListRow, Loading, NavButton, PickRow, SectionHeader, TopBack } from "./parts.tsx";
import { doingMatches, useDoingList } from "../doing.ts";
import { ask, confirm } from "./sheets.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as css from "./WorkspacePage.css.ts";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as settingsCss from "./styles/settings.css.ts";
import * as homeCss from "./styles/home.css.ts";

import { NAME } from "../channel.ts";
export function WorkspaceScreen() {
  const app = useApp();
  const view = useWorkspace(app.entry.id).value;
  const me = app.entry.account;
  if (!view) return <div className={pagesCss.mScreen}><TopBack label="设置" onBack={app.pop} /><Loading text="正在读取 workspace…" /></div>;
  const manager = view.role === "owner" || view.role === "admin";
  const leave = () => confirm(app, {
    title: `退出「${view.name}」？`, text: "退出后你就不能再访问里面的 station，需要重新被邀请才能回来。", action: "退出", danger: true,
    run: () => cloud.removeMember(me.sub, view.id, me.sub).then(() => { app.toast("已退出 workspace"); app.replace("/"); }),
  });
  const remove = () => confirm(app, {
    title: `删除「${view.name}」？`, action: "删除 workspace", danger: true,
    text: `所有成员都会失去访问权限，${view.stations.length} 台 station 会断开和 ${NAME} cloud 的连接（station 本机上的数据不受影响）。`,
    run: () => cloud.deleteWorkspace(me.sub, view.id).then(() => { app.toast("已删除 workspace"); app.replace("/"); }),
  });
  const rename = () => ask(app, { title: "Workspace 名字", value: view.name, placeholder: "例如：产品团队", action: "保存",
    run: (name) => cloud.renameWorkspace(me.sub, view.id, name).then(() => app.toast("已改名")) });
  const add = () => app.sheet({ height: 0.8, draggable: true, content: () => <AddSheet view={view} /> });
  const waiting = manager ? view.added.length + view.invitations.length : 0;
  // A row's link waits, spinning, until still.fail cloud answers; the toast says how it ended.
  const doing = useDoingList();
  const removing = (email: string) => doing.some((d) => doingMatches(d, "workspace.removeAdded", { account: me.sub, workspace: view.id, email }));
  const revoking = (id: string) => doing.some((d) => doingMatches(d, "workspace.revokeInvitation", { account: me.sub, workspace: view.id, invitation: id }));
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <TopBack label="设置" onBack={app.pop} trailing={manager ? <NavButton icon={UserPlus} iconSize={20} label="添加成员" onClick={add} /> : undefined} />
      {/* Its name is the title, renamed by a tap on it (by its owner and admins). */}
      <div className={manager ? css.mRename : undefined} role={manager ? "button" : undefined} tabIndex={manager ? 0 : undefined} onClick={manager ? rename : undefined}>
        <LargeTitle small="" big={view.name} />
      </div>
      <p className={css.mLead}>你是{ROLE_LABEL[view.role]} · {view.members.length} 人 · {view.stations.length} 台 station{manager ? " · 点名字改名" : ""}</p>
      {/* Its people in one list: those in it, then those added who have not signed in yet, then the invitations out; which is which on each row's second line. */}
      <SectionHeader title="成员" trailing={`${view.members.length} 人${waiting ? ` · ${waiting} 人待加入` : ""}`} start={24} />
      <ListCard>
        {view.members.map((m) => <MemberRow key={m.sub} view={view} m={m} me={me.sub} />)}
        {manager && view.added.map((a) => (
          <ListRow key={a.email}>
            <Avatar id={a.email} name={a.email} size={28} />
            <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}><span className={listsCss.mRowTitle}>{a.email}</span><span className={listsCss.mRowNote}>{ROLE_LABEL[a.role]} · 还没登录过，第一次登录时自动加入</span></span>
            <LinkButton label="移除" busy={removing(a.email)} onClick={() => { cloud.removeAdded(me.sub, view.id, a.email).then(() => app.toast("已移除"), (e: Error) => app.toast(`没能移除：${e.message}`)); }} />
          </ListRow>
        ))}
        {manager && view.invitations.map((i) => (
          <ListRow key={i.id}>
            <Avatar id={i.email ?? i.id} name={i.email ?? "?"} size={28} />
            <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}><span className={listsCss.mRowTitle}>{i.email ?? "任何拿到链接的人"}</span><span className={listsCss.mRowNote}>{ROLE_LABEL[i.role]} · 邀请 · {stamp(i, "expires_at")?.until}过期</span></span>
            <LinkButton label="撤回" busy={revoking(i.id)} onClick={() => { cloud.revokeInvitation(me.sub, view.id, i.id).then(() => app.toast("已撤回邀请"), (e: Error) => app.toast(`没能撤回邀请：${e.message}`)); }} />
          </ListRow>
        ))}
      </ListCard>
      <div className={css.mGap} />
      <ListCard>
        <ListRow onClick={leave}><span className={`${partsCss.mGrow} ${listsCss.mRowTitle} ${partsCss.mRed}`}>退出这个 workspace</span></ListRow>
        {view.role === "owner" && <ListRow onClick={remove}><span className={`${partsCss.mGrow} ${listsCss.mRowTitle} ${partsCss.mRed}`}>删除 workspace</span></ListRow>}
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
      <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
        <span className={listsCss.mRowTitle}>{m.name || m.email}{m.sub === me && <span className={css.mYou}>你</span>}</span>
        <span className={listsCss.mRowNote}>{m.email}</span>
      </span>
      <span className={listsCss.mRowNote}>{ROLE_LABEL[m.role]}</span>
    </ListRow>
  );
}

function MemberSheet({ view, m }: { view: WorkspaceView; m: MemberView }) {
  const app = useApp();
  const me = app.entry.account;
  // The role asked shows its spinner on its row until still.fail cloud answers; the sheet stays open if it fails.
  const doing = useDoingList().find((d) => doingMatches(d, "workspace.setRole", { account: me.sub, workspace: view.id, member: m.sub }));
  const setRole = (role: Role) => { cloud.setRole(me.sub, view.id, m.sub, role).then(() => { app.toast("已更改角色"); app.sheet(null); }, (e: Error) => app.toast(`没能更改角色：${e.message}`)); };
  return (
    <>
      <SheetGrab />
      <SheetHead title={m.name || m.email} />
      <div className={sheetsCss.mSheetScroll}>
        {view.role === "owner" && (["owner", "admin", "member"] as Role[]).map((r) => (
          <PickRow key={r} label={ROLE_LABEL[r]} sub={ROLE_HINT[r]} checked={m.role === r}
            busy={doing?.params.role === r} enabled={!doing} onClick={() => setRole(r)} />
        ))}
        <PickRow label="移出 workspace" accent enabled={!doing} onClick={() => removeMember(app, view, m)} />
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

function AddSheet({ view }: { view: WorkspaceView }) {
  const app = useApp();
  const me = app.entry.account;
  const [text, setText] = useState("");
  const [role, setRole] = useState<Role>("member");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const roles: Role[] = view.role === "owner" ? ["member", "admin", "owner"] : ["member", "admin"];
  // The people of the Slack workspaces the stations are in, read when asked for; the workspace's own picked, guests left to choose.
  const slack = useSlackPeople(view.id);
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const inside = new Set([...view.members.map((m) => m.email.toLowerCase()), ...view.added.map((a) => a.email)]);
  useEffect(() => {
    if (slack.people) setPicked(new Set(slack.people.filter((p) => !p.guest && !inside.has(p.email)).map((p) => p.email)));
  }, [slack.people]); // eslint-disable-line react-hooks/exhaustive-deps
  const toggle = (email: string) => setPicked((now) => {
    const next = new Set(now);
    if (next.has(email)) next.delete(email); else next.add(email);
    return next;
  });
  const emails = [...new Set([...parseEmails(text), ...picked])].filter((e) => !inside.has(e));
  return (
    <>
      <SheetGrab />
      <SheetHead title="添加成员" />
      <div className={`${sheetsCss.mSheetScroll} ${sheetsCss.mForm}`}>
        {done ? (
          <>
            <p>{done}</p>
            <div className={sheetsCss.mFormActions}><Button label="完成" primary onClick={() => app.sheet(null)} /></div>
          </>
        ) : (
          <>
            <p className={partsCss.mMuted}>直接加进「{view.name}」，不用对方接受：登录过 {NAME} 的人马上加入，其他人第一次用这个邮箱登录时自动加入。</p>
            <b className={sheetsCss.mFormLabel}>邮箱</b>
            <Field value={text} onChange={setText} placeholder="name@example.com，可以粘贴多个" />
            {slack.available && (slack.people === null ? (
              <button type="button" className={`${partsCss.mLink} ${settingsCss.mStepAlt}`} disabled={slack.busy} onClick={() => void slack.load()}>{slack.busy ? "正在读取 Slack 里的人…" : "从 Slack 里选人"}</button>
            ) : (
              <>
                <div className={settingsCss.mProfileTools} style={{ padding: 0 }}>
                  <span className={`${partsCss.mGrow} ${partsCss.mSmall} ${partsCss.mMuted}`}>Slack 里 {slack.people.length} 人，选中 {[...picked].filter((e) => !inside.has(e)).length} 人</span>
                  <button type="button" className={partsCss.mLink} onClick={() => setPicked(new Set(slack.people!.filter((p) => !inside.has(p.email)).map((p) => p.email)))}>全选</button>
                  <button type="button" className={partsCss.mLink} onClick={() => setPicked(new Set())}>全不选</button>
                </div>
                <div>
                  {slack.people.map((p) => {
                    const already = inside.has(p.email);
                    const on = already || picked.has(p.email);
                    return (
                      <button key={p.email} type="button" className={settingsCss.mModelRow} style={{ padding: "9px 0" }} disabled={already} onClick={() => toggle(p.email)}>
                        <span className={settingsCss.mCheck} data-on={on || undefined}>{on && <Check size={14} />}</span>
                        <Avatar id={p.email} name={p.name || p.email} size={26} picture={p.image ?? undefined} />
                        <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}><span className={listsCss.mRowTitle}>{p.name}</span><span className={listsCss.mRowNote}>{p.email}</span></span>
                        {already ? <span className={listsCss.mRowNote}>已在</span> : p.guest && <span className={listsCss.mRowNote}>访客</span>}
                      </button>
                    );
                  })}
                </div>
                {slack.errors.length > 0 && <p className={partsCss.mError}>{slack.errors.join("；")}</p>}
              </>
            ))}
            <b className={sheetsCss.mFormLabel}>角色</b>
            {roles.map((r) => <PickRow key={r} label={ROLE_LABEL[r]} sub={ROLE_HINT[r]} checked={role === r} onClick={() => setRole(r)} />)}
            {error && <p className={partsCss.mError}>{error}</p>}
            <div className={sheetsCss.mFormActions}>
              <Button label="取消" primary={false} onClick={() => app.sheet(null)} />
              <Button label={emails.length > 1 ? `添加 ${emails.length} 人` : "添加"} primary busy={busy} enabled={emails.length > 0} onClick={() => {
                setBusy(true); setError(null);
                cloud.addMembers(me.sub, view.id, role, emails).then((r) => setDone([
                  r.joined.length ? `${r.joined.length} 人已经加入` : "",
                  r.added.length ? `${r.added.length} 人第一次登录 ${NAME} 时自动加入` : "",
                  r.already.length ? `${r.already.length} 人本来就在` : "",
                ].filter(Boolean).join("，") + "。"), (e: Error) => setError(errorText(e))).finally(() => setBusy(false));
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
  const doing = useDoingList();
  const revoking = (id: string) => doing.some((d) => doingMatches(d, "loginSession.revoke", { account: me.sub, id }));
  if (!devices.value) return <p className={homeCss.mNote}>{devices.error ? `读不到登录记录：${devices.error.message}` : "正在读取…"}</p>;
  return (
    <ListCard>
      {devices.value.map((s) => (
        <ListRow key={s.id}>
          <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
            <span className={listsCss.mRowTitle}>{s.name || "未命名设备"}{s.current && <span className={css.mYou}>这里</span>}</span>
            <span className={listsCss.mRowNote}>{stamp(s, "created_at")?.ago}登录 · {stamp(s, "expires_at")?.until}过期</span>
          </span>
          {!s.current && <LinkButton label="退出" busy={revoking(s.id)} onClick={() => { cloud.revokeLoginSession(me.sub, s.id).then(() => app.toast("已让那台设备退出"), (e: Error) => app.toast(`没能让那台设备退出：${e.message}`)); }} />}
        </ListRow>
      ))}
    </ListCard>
  );
}
