import { useDoing } from "../doing.ts";
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
import { Avatar, Button, failedIn, Field, LargeTitle, LinkButton, ListCard, ListRow, Loading, NavButton, PickRow, SectionHeader, TopBack } from "./parts.tsx";
import { doingMatches, failed, useDoingList } from "../doing.ts";
import { ask, confirm } from "./sheets.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as css from "./WorkspacePage.css.ts";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as settingsCss from "./styles/settings.css.ts";
import * as homeCss from "./styles/home.css.ts";

import { NAME } from "../channel.ts";
import { t } from "../i18n.ts";
export function WorkspaceScreen() {
  const app = useApp();
  const view = useWorkspace(app.entry.id).value;
  const me = app.entry.account;
  // Before the early return below: the same hooks on every render, read or not yet.
  const doing = useDoingList();
  if (!view) return <div className={pagesCss.mScreen}><TopBack label={t("web-mobile.settings.title")} onBack={app.pop} /><Loading text={t("web-mobile.workspace.reading")} /></div>;
  const manager = view.role === "owner" || view.role === "admin";
  const leave = () => confirm(app, {
    title: t("web-mobile.workspace.leaveAsk", { name: view.name }), text: t("web-mobile.workspace.leaveText"), action: t("web-mobile.workspace.leaveAction"), danger: true, atOnce: "web-mobile.workspace.leaveFailed",
    run: () => { app.replace("/", { left: view.id }); return cloud.removeMember(me.sub, view.id, me.sub).then(() => app.toast(t("web-mobile.workspace.left"))); },
  });
  const remove = () => confirm(app, {
    title: t("web-mobile.archive.deleteAsk", { title: view.name }), action: t("web-mobile.workspace.delete"), danger: true,
    text: t("web-mobile.workspace.deleteText", { n: view.stations.length, name: NAME }), atOnce: "web-main.chat.deleteFailed",
    run: () => { app.replace("/", { left: view.id }); return cloud.deleteWorkspace(me.sub, view.id).then(() => app.toast(t("web-mobile.workspace.deleted"))); },
  });
  const rename = () => ask(app, { title: t("web-mobile.workspace.renameTitle"), value: view.name, placeholder: t("web-mobile.workspaces.namePlaceholder"), action: t("common.save"), atOnce: "web-main.rename.failed",
    run: (name) => cloud.renameWorkspace(me.sub, view.id, name).then(() => app.toast(t("web-mobile.workspace.renamed"))) });
  const add = () => app.sheet({ height: 0.8, draggable: true, content: () => <AddSheet view={view} /> });
  const waiting = manager ? view.added.length + view.invitations.length : 0;
  // A row's link waits, spinning, until still.fail cloud answers; the toast says how it ended (one that failed keeps the
  // failure mark a few seconds).
  const removing = (email: string) => doing.some((d) => !failed(d) && doingMatches(d, "workspace.removeAdded", { account: me.sub, workspace: view.id, email }));
  const revoking = (id: string) => doing.some((d) => !failed(d) && doingMatches(d, "workspace.revokeInvitation", { account: me.sub, workspace: view.id, invitation: id }));
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <TopBack label={t("web-mobile.settings.title")} onBack={app.pop} trailing={manager ? <NavButton icon={UserPlus} iconSize={20} label={t("web-mobile.workspace.add")} onClick={add} /> : undefined} />
      {/* Its name is the title, renamed by a tap on it (by its owner and admins). */}
      <div className={manager ? css.mRename : undefined} role={manager ? "button" : undefined} tabIndex={manager ? 0 : undefined} onClick={manager ? rename : undefined}>
        <LargeTitle small="" big={view.name} />
      </div>
      <p className={css.mLead}>{t(manager ? "web-mobile.workspace.leadManager" : "web-mobile.workspace.lead", { role: ROLE_LABEL[view.role], members: t("web-mobile.settings.members", { n: view.members.length }), stations: t("web-mobile.workspaces.stations", { n: view.stations.length }) })}</p>
      {/* Its people in one list: those in it, then those added who have not signed in yet, then the invitations out; which is which on each row's second line. */}
      <SectionHeader title={t("web-mobile.workspace.members")} trailing={waiting ? t("web-mobile.settings.membersWaiting", { n: view.members.length, waiting }) : t("web-mobile.settings.members", { n: view.members.length })} start={24} />
      <ListCard>
        {view.members.map((m) => <MemberRow key={m.sub} view={view} m={m} me={me.sub} />)}
        {manager && view.added.map((a) => (
          <ListRow key={a.email}>
            <Avatar id={a.email} name={a.email} size={28} />
            <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}><span className={listsCss.mRowTitle}>{a.email}</span><span className={listsCss.mRowNote}>{t("web-mobile.workspace.addedNote", { role: ROLE_LABEL[a.role] })}</span></span>
            <LinkButton label={t("web-mobile.workspace.remove")} busy={removing(a.email)} failed={failedIn(doing, "workspace.removeAdded", { account: me.sub, workspace: view.id, email: a.email })} onClick={() => { cloud.removeAdded(me.sub, view.id, a.email).then(() => app.toast(t("web-mobile.workspace.removed")), (e: Error) => app.toast(t("web-mobile.workspace.removeFailed", { error: e.message }))); }} />
          </ListRow>
        ))}
        {manager && view.invitations.map((i) => (
          <ListRow key={i.id}>
            <Avatar id={i.email ?? i.id} name={i.email ?? "?"} size={28} />
            <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}><span className={listsCss.mRowTitle}>{i.email ?? t("web-mobile.workspace.anyone")}</span><span className={listsCss.mRowNote}>{t("web-mobile.workspace.inviteNote", { role: ROLE_LABEL[i.role], until: stamp(i, "expires_at")?.until ?? "" })}</span></span>
            <LinkButton label={t("web-mobile.workspace.revoke")} busy={revoking(i.id)} failed={failedIn(doing, "workspace.revokeInvitation", { account: me.sub, workspace: view.id, invitation: i.id })} onClick={() => { cloud.revokeInvitation(me.sub, view.id, i.id).then(() => app.toast(t("web-mobile.workspace.revoked")), (e: Error) => app.toast(t("web-mobile.workspace.revokeFailed", { error: e.message }))); }} />
          </ListRow>
        ))}
      </ListCard>
      <Relays view={view} manager={manager} />
      <div className={css.mGap} />
      <ListCard>
        <ListRow onClick={leave}><span className={`${partsCss.mGrow} ${listsCss.mRowTitle} ${partsCss.mRed}`}>{t("web-mobile.workspace.leave")}</span></ListRow>
        {view.role === "owner" && <ListRow onClick={remove}><span className={`${partsCss.mGrow} ${listsCss.mRowTitle} ${partsCss.mRed}`}>{t("web-mobile.workspace.delete")}</span></ListRow>}
      </ListCard>
      <div style={{ height: 30 }} />
    </div>
  );
}

/**
 * The workspace's own relays, used besides still.fail's by its stations and its members' devices: owners and admins add
 * one from the last row (a sheet that says why one is refused) and take one out from its row.
 */
function Relays({ view, manager }: { view: WorkspaceView; manager: boolean }) {
  const app = useApp();
  const me = app.entry.account;
  const relays = view.relays ?? [];
  const doing = useDoingList();
  const busy = doing.some((d) => !failed(d) && doingMatches(d, "workspace.setRelays", { account: me.sub, workspace: view.id }));
  if (!manager && relays.length === 0) return null;
  const add = () => ask(app, { title: t("web-mobile.workspace.relayAdd"), value: "", placeholder: "https://relay.example.com", action: t("web-mobile.workspace.relayAddAction"), hint: t("web-mobile.workspace.relayHint"),
    run: (url) => cloud.setRelays(me.sub, view.id, [...relays, url]).then(() => app.toast(t("web-mobile.workspace.relayAdded"))) });
  const remove = (url: string) => { cloud.setRelays(me.sub, view.id, relays.filter((u) => u !== url)).then(() => app.toast(t("web-mobile.workspace.relayRemoved")), (e: Error) => app.toast(t("web-mobile.workspace.removeFailed", { error: e.message }))); };
  return (
    <>
      <SectionHeader title={t("web-mobile.workspace.relays")} start={24} />
      <ListCard>
        {relays.map((url) => (
          <ListRow key={url}>
            <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}><span className={listsCss.mRowTitle}>{url.replace(/^https?:\/\//, "")}</span></span>
            {manager && <LinkButton label={t("web-mobile.workspace.remove")} enabled={!busy} onClick={() => remove(url)} />}
          </ListRow>
        ))}
        {manager && <ListRow onClick={busy ? undefined : add}><span className={`${partsCss.mGrow} ${listsCss.mRowTitle} ${partsCss.mLink}`}>{busy ? t("web-mobile.workspace.relaySaving") : t("web-mobile.workspace.relayAdd")}</span></ListRow>}
      </ListCard>
      <p className={css.mLead}>{t("web-mobile.workspace.relayLead", { name: NAME })}</p>
    </>
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
        <span className={listsCss.mRowTitle}>{m.name || m.email}{m.sub === me && <span className={css.mYou}>{t("web-mobile.annotate.you")}</span>}</span>
        <span className={listsCss.mRowNote}>{m.email}</span>
      </span>
      <span className={listsCss.mRowNote}>{ROLE_LABEL[m.role]}</span>
    </ListRow>
  );
}

function MemberSheet({ view, m }: { view: WorkspaceView; m: MemberView }) {
  const app = useApp();
  const me = app.entry.account;
  // The sheet goes at once; the role asked shows its spinner on its row (opened again) until still.fail cloud answers.
  const list = useDoingList();
  const doing = list.find((d) => !failed(d) && doingMatches(d, "workspace.setRole", { account: me.sub, workspace: view.id, member: m.sub }));
  const roleFailed = list.findLast((d) => failed(d) && doingMatches(d, "workspace.setRole", { account: me.sub, workspace: view.id, member: m.sub }));
  const setRole = (role: Role) => { app.sheet(null); cloud.setRole(me.sub, view.id, m.sub, role).then(() => app.toast(t("web-mobile.workspace.roleChanged")), (e: Error) => app.toast(t("web-mobile.workspace.roleFailed", { error: e.message }))); };
  return (
    <>
      <SheetGrab />
      <SheetHead title={m.name || m.email} />
      <div className={sheetsCss.mSheetScroll}>
        {view.role === "owner" && (["owner", "admin", "member"] as Role[]).map((r) => (
          <PickRow key={r} label={ROLE_LABEL[r]} sub={ROLE_HINT[r]} checked={m.role === r}
            busy={doing?.params.role === r} failed={!doing && roleFailed?.params.role === r ? (roleFailed.error ?? t("web-mobile.parts.failed")) : undefined} enabled={!doing} onClick={() => setRole(r)} />
        ))}
        <PickRow label={t("web-mobile.workspace.removeMember")} accent enabled={!doing} onClick={() => removeMember(app, view, m)} />
      </div>
    </>
  );
}

function removeMember(app: MobileApp, view: WorkspaceView, m: MemberView) {
  confirm(app, {
    title: t("web-mobile.workspace.removeMemberAsk", { email: m.email, name: view.name }), text: t("web-mobile.workspace.removeMemberText"), action: t("web-mobile.workspace.removeMemberAction"), danger: true, atOnce: "web-mobile.workspace.removeFailed",
    run: () => cloud.removeMember(app.entry.account.sub, view.id, m.sub).then(() => app.toast(t("web-mobile.workspace.memberRemoved"))),
  });
}

function AddSheet({ view }: { view: WorkspaceView }) {
  const app = useApp();
  const me = app.entry.account;
  const [text, setText] = useState("");
  const [role, setRole] = useState<Role>("member");
  const busy = useDoing("workspace.addMembers", { account: me.sub, workspace: view.id });
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
      <SheetHead title={t("web-mobile.workspace.add")} />
      <div className={`${sheetsCss.mSheetScroll} ${sheetsCss.mForm}`}>
        {done ? (
          <>
            <p>{done}</p>
            <div className={sheetsCss.mFormActions}><Button label={t("common.done")} primary onClick={() => app.sheet(null)} /></div>
          </>
        ) : (
          <>
            <p className={partsCss.mMuted}>{t("web-mobile.workspace.addNote", { workspace: view.name, name: NAME })}</p>
            <b className={sheetsCss.mFormLabel}>{t("web-mobile.workspace.email")}</b>
            <Field value={text} onChange={setText} placeholder={t("web-mobile.workspace.emailPlaceholder")} />
            {slack.available && (slack.people === null ? (
              <button type="button" className={`${partsCss.mLink} ${settingsCss.mStepAlt}`} disabled={slack.busy} onClick={() => void slack.load()}>{slack.busy ? t("web-mobile.workspace.slackReading") : t("web-mobile.workspace.slackPick")}</button>
            ) : (
              <>
                <div className={settingsCss.mProfileTools} style={{ padding: 0 }}>
                  <span className={`${partsCss.mGrow} ${partsCss.mSmall} ${partsCss.mMuted}`}>{t("web-mobile.workspace.slackCount", { n: slack.people.length, picked: [...picked].filter((e) => !inside.has(e)).length })}</span>
                  <button type="button" className={partsCss.mLink} onClick={() => setPicked(new Set(slack.people!.filter((p) => !inside.has(p.email)).map((p) => p.email)))}>{t("web-mobile.annotate.selectAll")}</button>
                  <button type="button" className={partsCss.mLink} onClick={() => setPicked(new Set())}>{t("web-mobile.workspace.selectNone")}</button>
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
                        {already ? <span className={listsCss.mRowNote}>{t("web-mobile.workspace.already")}</span> : p.guest && <span className={listsCss.mRowNote}>{t("web-mobile.workspace.guest")}</span>}
                      </button>
                    );
                  })}
                </div>
                {slack.errors.length > 0 && <p className={partsCss.mError}>{slack.errors.join("；")}</p>}
              </>
            ))}
            <b className={sheetsCss.mFormLabel}>{t("web-mobile.workspace.role")}</b>
            {roles.map((r) => <PickRow key={r} label={ROLE_LABEL[r]} sub={ROLE_HINT[r]} checked={role === r} onClick={() => setRole(r)} />)}
            {error && <p className={partsCss.mError}>{error}</p>}
            <div className={sheetsCss.mFormActions}>
              <Button label={t("common.cancel")} primary={false} onClick={() => app.sheet(null)} />
              <Button label={emails.length > 1 ? t("web-mobile.workspace.addMany", { n: emails.length }) : t("web-mobile.workspace.addOne")} primary busy={busy} enabled={emails.length > 0} onClick={() => {
                setError(null);
                cloud.addMembers(me.sub, view.id, role, emails).then((r) => setDone(t("web-mobile.workspace.addedDone", { list: [
                  r.joined.length ? t("web-mobile.workspace.addedJoined", { n: r.joined.length }) : "",
                  r.added.length ? t("web-mobile.workspace.addedLater", { n: r.added.length, name: NAME }) : "",
                  r.already.length ? t("web-mobile.workspace.addedAlready", { n: r.already.length }) : "",
                ].filter(Boolean).join(t("web-mobile.workspace.addedSeparator")) })), (e: Error) => setError(errorText(e)));
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
  const revoking = (id: string) => doing.some((d) => !failed(d) && doingMatches(d, "loginSession.revoke", { account: me.sub, id }));
  if (!devices.value) return <p className={homeCss.mNote}>{devices.error ? t("web-mobile.workspace.devicesFailed", { error: devices.error.message }) : t("web-mobile.reading")}</p>;
  return (
    <ListCard>
      {devices.value.map((s) => (
        <ListRow key={s.id}>
          <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
            <span className={listsCss.mRowTitle}>{s.name || t("web-mobile.workspace.unnamedDevice")}{s.current && <span className={css.mYou}>{t("web-mobile.workspace.here")}</span>}</span>
            <span className={listsCss.mRowNote}>{t("web-mobile.workspace.deviceNote", { ago: stamp(s, "created_at")?.ago ?? "", until: stamp(s, "expires_at")?.until ?? "" })}</span>
          </span>
          {!s.current && <LinkButton label={t("web-mobile.me.signOutOne")} busy={revoking(s.id)} failed={failedIn(doing, "loginSession.revoke", { account: me.sub, id: s.id })} onClick={() => { cloud.revokeLoginSession(me.sub, s.id).then(() => app.toast(t("web-mobile.workspace.deviceOut")), (e: Error) => app.toast(t("web-mobile.workspace.deviceOutFailed", { error: e.message }))); }} />}
        </ListRow>
      ))}
    </ListCard>
  );
}
