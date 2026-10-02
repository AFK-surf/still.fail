// The workspace sheet, opened from its name on Home: the invitations waiting, the one in use and the others to switch
// to, and a new one; a new workspace in a sheet of its own. The workspace's settings are in 设置 (./Settings.tsx).
import { useState } from "react";
import { signIn, useAccounts, useSignIn } from "../cloud/accounts.ts";
import { cloud, errorText, needsInviteCode, useAction, useWorkspaces, type AccountWorkspaces, type PendingInvitation } from "../cloud/api.ts";
import type { Account } from "../cloud/accounts.ts";
import { SheetGrab, SheetHead, useApp, type MobileApp } from "./app.tsx";
import { useWorkspaceMarks } from "../lastChat.ts";
import { MarkCounts } from "../ChatMark.tsx";
import { Button, Field, PickRow } from "./parts.tsx";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as css from "./Workspaces.css.ts";
import * as partsCss from "./styles/parts.css.ts";

import { LogIn, Plus } from "../icons.tsx";
import { NAME } from "../channel.ts";
import { t } from "../i18n.ts";
export function openWorkspaces(app: MobileApp) {
  app.sheet({ height: 0.7, draggable: true, content: () => <WorkspacesSheet /> });
}

function WorkspacesSheet() {
  const app = useApp();
  const login = useSignIn();
  const byAccount: AccountWorkspaces[] = useWorkspaces().value ?? [];
  const pending = byAccount.flatMap((a) => a.invitations.map((invite) => ({ account: a.account, invite })));
  const currentOf = byAccount.find((a) => a.workspaces.some((w) => w.id === app.entry.id));
  const current = currentOf?.workspaces.find((w) => w.id === app.entry.id);
  const others = byAccount
    .map((a) => ({ account: a.account, workspaces: a.workspaces.filter((w) => w.id !== app.entry.id) }))
    .filter((a) => a.workspaces.length > 0);
  // What each of the others has waiting, as the core counts it.
  const marks = useWorkspaceMarks(app.entry.id);
  const respond = useAction(async ({ account, invite, join }: { account: Account; invite: PendingInvitation; join: boolean }) => {
    if (join) {
      const w = await cloud.acceptInvitationById(account.sub, invite.id);
      app.toast(t("web-mobile.workspaces.joined", { name: invite.name }));
      app.replace(`/w/${w.id}`);
    } else {
      await cloud.declineInvitation(account.sub, invite.id);
      app.toast(t("web-mobile.workspaces.declined"));
    }
  });
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-mobile.workspaces.title")} />
      <div className={sheetsCss.mSheetScroll}>
        {current && <>
          <div className={css.mSheetLabel}>{t("web-mobile.workspaces.current")}</div>
          <div className={css.mCurrent}>
            <PickRow label={current.name} sub={currentOf!.account.email} checked onClick={() => app.sheet(null)} />
          </div>
        </>}
        {pending.length > 0 && (
          <>
            <div className={css.mSheetLabel}>{t("web-mobile.workspaces.invitations")}</div>
            {pending.map(({ account, invite }) => (
              <div key={invite.id} className={css.mInvite}>
                <span className={partsCss.mGrow}><span>{invite.inviter ? t("web-mobile.workspaces.invitedBy", { inviter: invite.inviter, name: invite.name }) : t("web-mobile.workspaces.invited", { name: invite.name })}</span><small>{account.email}</small></span>
                <Button label={t("web-mobile.workspaces.join")} primary busy={respond.busy && respond.arg?.invite.id === invite.id && respond.arg.join} onClick={() => respond.run({ account, invite, join: true })} />
                <Button label={t("web-mobile.workspaces.decline")} primary={false} busy={respond.busy && respond.arg?.invite.id === invite.id && !respond.arg.join} onClick={() => respond.run({ account, invite, join: false })} />
              </div>
            ))}
            {respond.error && <p className={`${partsCss.mError} ${partsCss.mPad}`}>{errorText(respond.error)}</p>}
          </>
        )}
        {others.length > 0 && <div className={css.mSheetLabel}>{t("web-mobile.workspaces.others")}</div>}
        {others.flatMap(({ account, workspaces }) => workspaces.map((w) => (
          <PickRow key={w.id} label={w.name} sub={account.email}
            mark={marks?.workspaces[w.id]?.tone && <MarkCounts mark={marks.workspaces[w.id]} />}
            onClick={() => { app.sheet(null); app.replace(`/w/${w.id}`); }} />
        )))}
      </div>
      <div className={css.mActions}>
        <PickRow label={t("web-mobile.workspaces.addAccount")} sub={t("web-mobile.workspaces.addAccountNote")} leading={<LogIn size={20} />} busy={login.busy} onClick={() => { void login.signIn(); }} />
        <PickRow label={t("web-mobile.workspaces.new")} leading={<Plus size={20} />} onClick={() => app.sheet({ height: 0.8, content: () => <NewWorkspaceSheet /> })} />
      </div>
    </>
  );
}

function NewWorkspaceSheet() {
  const app = useApp();
  const accounts = useAccounts() ?? [];
  const [name, setName] = useState("");
  const [owner, setOwner] = useState<string | null>(null);
  // Sent every time: still.fail cloud looks at it only for an account not let in yet, and then asks for it when it is missing or wrong.
  const [code, setCode] = useState("");
  const sub = accounts.find((a) => a.sub === owner)?.sub ?? accounts[0]?.sub;
  const create = useAction(async () => {
    const w = await cloud.createWorkspace(sub!, name.trim(), code.trim() || undefined);
    app.replace(`/w/${w.id}`);
  });
  const asked = needsInviteCode(create.error);
  // Signing in leaves for Google's page once still.fail says where: under way till then; if it cannot, why, here.
  const [signingIn, setSigningIn] = useState(false);
  const [signInError, setSignInError] = useState<string | null>(null);
  const signInHere = () => {
    setSigningIn(true); setSignInError(null);
    signIn().catch((e: unknown) => { setSigningIn(false); setSignInError(t("web-mobile.me.signInFailed", { error: e instanceof Error ? e.message : String(e) })); });
  };
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-mobile.workspaces.new")} />
      <div className={`${sheetsCss.mSheetScroll} ${sheetsCss.mForm}`}>
        <p className={partsCss.mMuted}>{t("web-mobile.workspaces.newNote")}</p>
        <b className={sheetsCss.mFormLabel}>{t("web-mobile.workspaces.name")}</b>
        <Field value={name} onChange={setName} placeholder={t("web-mobile.workspaces.namePlaceholder")} />
        {accounts.length > 1 && (
          <>
            <b className={sheetsCss.mFormLabel}>{t("web-mobile.workspaces.account")}</b>
            {accounts.map((a) => <PickRow key={a.sub} label={a.email} checked={a.sub === sub} onClick={() => setOwner(a.sub)} />)}
          </>
        )}
        {asked && (
          <>
            <b className={sheetsCss.mFormLabel}>{t("web-mobile.workspaces.code")}</b>
            <Field value={code} onChange={setCode} placeholder="XXXX-XXXX-XXXX" mono />
            {create.error && code.trim()
              ? <p className={partsCss.mError}>{errorText(create.error)}</p>
              : <p className={`${partsCss.mSmall} ${partsCss.mMuted}`}>{t("web-mobile.workspaces.codeNote", { name: NAME })}</p>}
          </>
        )}
        {create.error && !asked && <p className={partsCss.mError}>{errorText(create.error)}</p>}
        <div className={sheetsCss.mFormActions}>
          <Button label={t("common.cancel")} primary={false} onClick={() => app.sheet(null)} />
          <Button label={t("web-mobile.workspaces.create")} primary busy={create.busy} enabled={!!name.trim() && !!sub} onClick={() => create.run()} />
        </div>
        {accounts.length === 0 && <Button label={t("web-mobile.workspaces.signIn")} primary={false} busy={signingIn} onClick={signInHere} />}
        {signInError && <p className={partsCss.mError}>{signInError}</p>}
      </div>
    </>
  );
}
