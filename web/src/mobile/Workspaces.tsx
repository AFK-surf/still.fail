// The workspace sheet, opened from its name on Home: the one in use (its settings open from it), the invitations
// waiting, the others to switch to and a new one; a new workspace in a sheet of its own.
import { useState } from "react";
import { signIn, useAccounts } from "../cloud/accounts.ts";
import { cloud, errorText, needsInviteCode, useAction, useWorkspaces, type AccountWorkspaces, type PendingInvitation } from "../cloud/api.ts";
import type { Account } from "../cloud/accounts.ts";
import { ROLE_LABEL } from "../cloud/settings.tsx";
import { ChevronRight } from "../icons.tsx";
import { SheetGrab, SheetHead, useApp, type MobileApp } from "./app.tsx";
import { Button, Field, PickRow } from "./parts.tsx";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as css from "./Workspaces.css.ts";
import * as partsCss from "./styles/parts.css.ts";

export function openWorkspaces(app: MobileApp) {
  app.sheet({ height: 0.7, draggable: true, content: () => <WorkspacesSheet /> });
}

function WorkspacesSheet() {
  const app = useApp();
  const byAccount: AccountWorkspaces[] = useWorkspaces().value ?? [];
  const pending = byAccount.flatMap((a) => a.invitations.map((invite) => ({ account: a.account, invite })));
  const currentOf = byAccount.find((a) => a.workspaces.some((w) => w.id === app.entry.id));
  const current = currentOf?.workspaces.find((w) => w.id === app.entry.id);
  const others = byAccount
    .map((a) => ({ account: a.account, workspaces: a.workspaces.filter((w) => w.id !== app.entry.id) }))
    .filter((a) => a.workspaces.length > 0);
  const respond = useAction(async ({ account, invite, join }: { account: Account; invite: PendingInvitation; join: boolean }) => {
    if (join) {
      const w = await cloud.acceptInvitationById(account.sub, invite.id);
      app.toast(`已加入「${invite.name}」`);
      app.replace(`/w/${w.id}`);
    } else {
      await cloud.declineInvitation(account.sub, invite.id);
      app.toast("已忽略邀请");
    }
  });
  return (
    <>
      <SheetGrab />
      <SheetHead title="Workspace" />
      <div className={sheetsCss.mSheetScroll}>
        {/* The workspace in use first, as what the sheet is about: its settings open from it, not from a row among the others. */}
        {current && (
          <button type="button" className={css.mCurrent} onClick={() => { app.sheet(null); app.push(app.at("/settings/general")); }}>
            <span className={partsCss.mGrow}>
              <b>{current.name}</b>
              <small>你是{ROLE_LABEL[current.role]} · {current.stations} 台 station · {current.members} 人</small>
              {byAccount.length > 1 && <small>{currentOf!.account.email}</small>}
            </span>
            <span className={css.mCurrentGo}>设置<ChevronRight size={14} /></span>
          </button>
        )}
        {pending.length > 0 && (
          <>
            <div className={css.mSheetLabel}>邀请</div>
            {pending.map(({ account, invite }) => (
              <div key={invite.id} className={css.mInvite}>
                <span className={partsCss.mGrow}><span>{invite.inviter || "有人"}邀请你加入「{invite.name}」</span><small>{account.email}</small></span>
                <Button label="加入" primary busy={respond.busy && respond.arg?.invite.id === invite.id && respond.arg.join} onClick={() => respond.run({ account, invite, join: true })} />
                <Button label="忽略" primary={false} busy={respond.busy && respond.arg?.invite.id === invite.id && !respond.arg.join} onClick={() => respond.run({ account, invite, join: false })} />
              </div>
            ))}
            {respond.error && <p className={`${partsCss.mError} ${partsCss.mPad}`}>{errorText(respond.error)}</p>}
          </>
        )}
        {others.length > 0 && <div className={css.mSheetLabel}>切换到</div>}
        {/* With more than one account signed in, each workspace says whose it is under its name (a heading per account read as something to tap); what it holds goes at the row's end. */}
        {others.flatMap(({ account, workspaces }) => workspaces.map((w) => (
          <PickRow key={w.id} label={w.name} sub={byAccount.length > 1 ? account.email : undefined}
            aside={[`${w.stations} 台 station`, `${w.members} 人`]}
            onClick={() => { app.sheet(null); app.replace(`/w/${w.id}`); }} />
        )))}
        <PickRow label="＋ 新建 workspace" accent onClick={() => app.sheet({ height: 0.8, content: () => <NewWorkspaceSheet /> })} />
      </div>
    </>
  );
}

function NewWorkspaceSheet() {
  const app = useApp();
  const accounts = useAccounts() ?? [];
  const [name, setName] = useState("");
  const [owner, setOwner] = useState<string | null>(null);
  // Sent every time: ember cloud looks at it only for an account not let in yet, and then asks for it when it is missing or wrong.
  const [code, setCode] = useState("");
  const sub = accounts.find((a) => a.sub === owner)?.sub ?? accounts[0]?.sub;
  const create = useAction(async () => {
    const w = await cloud.createWorkspace(sub!, name.trim(), code.trim() || undefined);
    app.replace(`/w/${w.id}`);
  });
  const asked = needsInviteCode(create.error);
  return (
    <>
      <SheetGrab />
      <SheetHead title="新建 workspace" />
      <div className={`${sheetsCss.mSheetScroll} ${sheetsCss.mForm}`}>
        <p className={partsCss.mMuted}>workspace 是一组人和他们共用的 station。你会成为它的 owner。</p>
        <b className={sheetsCss.mFormLabel}>名字</b>
        <Field value={name} onChange={setName} placeholder="例如：产品团队" />
        {accounts.length > 1 && (
          <>
            <b className={sheetsCss.mFormLabel}>属于哪个账号</b>
            {accounts.map((a) => <PickRow key={a.sub} label={a.email} checked={a.sub === sub} onClick={() => setOwner(a.sub)} />)}
          </>
        )}
        {asked && (
          <>
            <b className={sheetsCss.mFormLabel}>邀请码</b>
            <Field value={code} onChange={setCode} placeholder="XXXX-XXXX-XXXX" mono />
            {create.error && code.trim()
              ? <p className={partsCss.mError}>{errorText(create.error)}</p>
              : <p className={`${partsCss.mSmall} ${partsCss.mMuted}`}>still.fail 目前只对受邀的人开放：这个账号还没被邀请进任何 workspace，新建需要一个邀请码。</p>}
          </>
        )}
        {create.error && !asked && <p className={partsCss.mError}>{errorText(create.error)}</p>}
        <div className={sheetsCss.mFormActions}>
          <Button label="取消" primary={false} onClick={() => app.sheet(null)} />
          <Button label="新建" primary busy={create.busy} enabled={!!name.trim() && !!sub} onClick={() => create.run()} />
        </div>
        {accounts.length === 0 && <Button label="登录" primary={false} onClick={() => void signIn()} />}
      </div>
    </>
  );
}
