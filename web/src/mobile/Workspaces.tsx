// The workspace switcher, on Home's bar (apps/android/…/screens/Workspaces.kt the same): the workspace's name, swiped
// sideways to the next or the one before, tapped to a panel under it with every workspace (and the invitations
// waiting, a new one, another account); a new workspace in a sheet of its own. The workspace's settings are in 设置
// (./Settings.tsx).
import { useLayoutEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from "react";
import { signIn, useAccounts, useSignIn } from "../cloud/accounts.ts";
import { cloud, errorText, needsInviteCode, useAction, useWorkspaces, type AccountWorkspaces, type PendingInvitation, type WorkspaceSummary } from "../cloud/api.ts";
import type { Account } from "../cloud/accounts.ts";
import type { WorkspaceMarksView } from "../core/shapes.ts";
import { SheetGrab, SheetHead, useApp, type MobileApp } from "./app.tsx";
import { useWorkspaceMarks } from "../lastChat.ts";
import { MarkCounts } from "../ChatMark.tsx";
import * as chatMarkCss from "../ChatMark.css.ts";
import { Button, Field, PickRow } from "./parts.tsx";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as css from "./Workspaces.css.ts";
import * as homeCss from "./Home.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import { leave, SWITCH_EASE, SWITCH_MS, type Arrival } from "./switch.ts";

import { Check, ChevronDown, LogIn, Plus } from "../icons.tsx";
import { NAME } from "../channel.ts";
import { t } from "../i18n.ts";

interface Place { account: Account; workspace: WorkspaceSummary }

/** Every workspace in the order they are swiped through: each account's in turn, as the accounts are (once each). */
function order(byAccount: AccountWorkspaces[]): Place[] {
  const seen = new Set<string>();
  return byAccount.flatMap((a) => a.workspaces.map((workspace) => ({ account: a.account, workspace })))
    .filter((p) => !seen.has(p.workspace.id) && seen.add(p.workspace.id));
}

/** To `to`, from the workspace in view: what is on screen (Home's lists, `lists`) slides away to the side it is on. */
function switchTo(app: MobileApp, places: Place[], to: string, lists: HTMLElement | null, from = 0) {
  const here = places.findIndex((p) => p.workspace.id === app.entry.id);
  const there = places.findIndex((p) => p.workspace.id === to);
  leave(lists, app.entry.name, there < here ? -1 : 1, from);
  app.replace(`/w/${to}`, undefined, true);
}

/** Past this (px), or flung, a swiped name goes to the next workspace; short of it, it comes back. */
const SWIPE_AT = 64;

/**
 * The workspace's name on Home's bar, its way to the others: swiped sideways the next (or the one before) comes in
 * after the finger and is gone to; tapped, the panel of them all opens under it. Dots under it with more than one:
 * where it is among them, and those with something waiting in their mark's colour (in place of the mark by the name).
 * `come`: the one left, its name going out as this one's comes in (`started`: from then).
 */
export function WorkspaceTitle({ come, started }: { come: Arrival | null; started: boolean }) {
  const app = useApp();
  const byAccount = useWorkspaces().value ?? [];
  const places = order(byAccount);
  const at = places.findIndex((p) => p.workspace.id === app.entry.id);
  const invited = byAccount.some((a) => a.invitations.length > 0);
  const marks = useWorkspaceMarks(app.entry.id);
  const dots = places.length > 1 && at >= 0;
  const strip = useRef<HTMLSpanElement>(null);
  const button = useRef<HTMLButtonElement>(null);
  const drag = useRef<{ x: number; y: number; t: number; dx: number; on: boolean } | null>(null);
  const moved = useRef(false);
  const before = at > 0 ? places[at - 1] : undefined;
  const after = at >= 0 ? places[at + 1] : undefined;
  const lists = () => button.current?.closest(`.${homeCss.mHome}`)?.querySelector<HTMLElement>(`.${homeCss.mHomePanes}`) ?? null;
  // The pages of the strip (the one before, this, the next; the one left while it goes) where `dx` puts them.
  const settled = useRef(0);
  const put = (dx: number, animate = false) => {
    const el = strip.current;
    if (!el) return;
    clearTimeout(settled.current);
    el.style.setProperty("--dx", `${dx}px`);
    el.toggleAttribute("data-settling", animate);
    el.toggleAttribute("data-peek", true);
    if (animate) settled.current = window.setTimeout(() => { el.removeAttribute("data-peek"); el.removeAttribute("data-settling"); }, 240);
  };
  // Come from another: the name left where the finger left it (or in place) and this one a gap beside it, on the side
  // it came from; once the lists start (`started`), both go along together to where this one is in place.
  const ends = useRef<{ left: HTMLElement | null; here: HTMLElement | null; from: number; off: number; gone: number } | null>(null);
  useLayoutEffect(() => {
    const el = strip.current;
    if (!come || !el) return;
    const left = el.querySelector<HTMLElement>("[data-page=left]"), here = el.querySelector<HTMLElement>("[data-page=here]");
    const off = come.way > 0 ? (left?.offsetWidth ?? 0) + 24 : -((here?.offsetWidth ?? 0) + 24);
    // The one left goes out of the strip: to the left by as far as this one comes, or to the right past its end.
    const gone = come.way > 0 ? -off : el.clientWidth;
    ends.current = { left, here, from: come.from, off, gone };
    if (left) Object.assign(left.style, { visibility: "visible", transform: `translateX(${come.from}px)` });
    if (here) here.style.transform = `translateX(${come.from + off}px)`;
  }, [come]);
  useLayoutEffect(() => {
    const e = ends.current;
    if (!started || !e) return;
    const timing = { duration: SWITCH_MS, easing: SWITCH_EASE };
    if (e.left) {
      e.left.style.transform = `translateX(${e.gone}px)`;
      e.left.animate([{ transform: `translateX(${e.from}px)` }, { transform: `translateX(${e.gone}px)` }], timing);
    }
    // In place: its own place again (the strip's, a swipe's from there).
    if (e.here) {
      e.here.style.transform = "";
      e.here.animate([{ transform: `translateX(${e.from + e.off}px)` }, { transform: "translateX(0)" }], timing);
    }
  }, [started]);
  const down = (e: ReactPointerEvent<HTMLButtonElement>) => {
    if (!e.isPrimary || (e.pointerType === "mouse" && e.button !== 0)) return;
    drag.current = { x: e.clientX, y: e.clientY, t: e.timeStamp, dx: 0, on: false };
    moved.current = false;
  };
  const move = (e: ReactPointerEvent<HTMLButtonElement>) => {
    const d = drag.current;
    if (!d) return;
    const dx = e.clientX - d.x;
    if (!d.on) {
      // Across first it is the swipe; up or down first, nothing.
      if (Math.abs(e.clientY - d.y) > 10 && Math.abs(e.clientY - d.y) > Math.abs(dx)) { drag.current = null; return; }
      if (Math.abs(dx) < 8) return;
      d.on = true;
      moved.current = true;
      const here = strip.current?.querySelector<HTMLElement>("[data-page=here]");
      if (here) strip.current!.style.setProperty("--here", `${here.offsetWidth}px`);
      e.currentTarget.setPointerCapture(e.pointerId);
    }
    // No workspace that way: it gives a little, as at the end of a list.
    d.dx = (dx < 0 ? after : before) ? dx : dx * 0.3;
    d.t = e.timeStamp;
    put(d.dx);
  };
  const up = (e: ReactPointerEvent<HTMLButtonElement>) => {
    const d = drag.current;
    drag.current = null;
    if (!d?.on) return;
    const quick = Math.abs(d.dx) > 24 && e.timeStamp - d.t < 60;
    const to = d.dx < 0 ? after : before;
    if (to && (Math.abs(d.dx) > SWIPE_AT || quick)) switchTo(app, places, to.workspace.id, lists(), d.dx);
    else put(0, true);
  };
  const cancel = () => { if (drag.current?.on) put(0, true); drag.current = null; };
  const open = () => {
    if (moved.current) { moved.current = false; return; }
    const r = button.current!.getBoundingClientRect();
    const width = Math.min(320, window.innerWidth - 32);
    app.menu({ anchor: new DOMRect(r.left - 8, r.top, 0, r.height + 8), items: [], width, content: (close) => <WorkspacePanel close={close} lists={lists()} /> });
  };
  const name = (text: string, mark: boolean) => (
    <>
      <b>{text}</b>
      {mark && (marks?.others && !dots
        ? <span className={chatMarkCss.chatMarkInline} data-tone={marks.others} role="img" aria-label={marks.othersLabel ?? ""} />
        : invited && <span className={homeCss.mDot} aria-label={t("web-mobile.home.invited")} />)}
      <ChevronDown size={16} />
    </>
  );
  return (
    <button ref={button} type="button" className={`${homeCss.mHomeWorkspace} ${css.mTitle}`} onClick={open}
      onPointerDown={down} onPointerMove={move} onPointerUp={up} onPointerCancel={cancel}>
      <span ref={strip} className={css.mStrip}>
        {before && <span className={css.mPage} data-page="before" aria-hidden="true">{name(before.workspace.name, false)}</span>}
        <span className={css.mPage} data-page="here">{name(app.entry.name, true)}</span>
        {after && <span className={css.mPage} data-page="after" aria-hidden="true">{name(after.workspace.name, false)}</span>}
        {come && <span className={css.mPage} data-page="left" aria-hidden="true">{name(come.name, false)}</span>}
      </span>
      {dots && (
        <span className={css.mDots} aria-hidden="true">
          {places.map((p, i) => <span key={p.workspace.id} className={css.mPageDot} data-here={i === at || undefined} data-tone={i === at ? undefined : marks?.workspaces[p.workspace.id]?.tone} />)}
        </span>
      )}
    </button>
  );
}

/**
 * Under the name, every workspace to go to: the invitations waiting first (joined or declined here), then each
 * account's workspaces (under its address when more than one is signed in), the one in view checked, the others with
 * what they have waiting; a new workspace and another account at its foot.
 */
function WorkspacePanel({ close, lists }: { close: () => void; lists: HTMLElement | null }) {
  const app = useApp();
  const login = useSignIn();
  const byAccount: AccountWorkspaces[] = useWorkspaces().value ?? [];
  const places = order(byAccount);
  const pending = byAccount.flatMap((a) => a.invitations.map((invite) => ({ account: a.account, invite })));
  const accounts = byAccount.filter((a) => a.workspaces.length > 0);
  const marks: WorkspaceMarksView | undefined = useWorkspaceMarks(app.entry.id);
  const respond = useAction(async ({ account, invite, join }: { account: Account; invite: PendingInvitation; join: boolean }) => {
    if (join) {
      const w = await cloud.acceptInvitationById(account.sub, invite.id);
      app.toast(t("web-mobile.workspaces.joined", { name: invite.name }));
      close();
      app.replace(`/w/${w.id}`);
    } else {
      await cloud.declineInvitation(account.sub, invite.id);
      app.toast(t("web-mobile.workspaces.declined"));
    }
  });
  const shown = new Set<string>();
  return (
    <div className={css.mPanel}>
      {pending.map(({ account, invite }) => (
        <div key={invite.id} className={css.mInvite}>
          <span className={css.mInviteText}>
            <span>{invite.inviter ? t("web-mobile.workspaces.invitedBy", { inviter: invite.inviter, name: invite.name }) : t("web-mobile.workspaces.invited", { name: invite.name })}</span>
            <small>{account.email}</small>
          </span>
          <Button label={t("web-mobile.workspaces.join")} primary busy={respond.busy && respond.arg?.invite.id === invite.id && respond.arg.join} onClick={() => respond.run({ account, invite, join: true })} />
          <Button label={t("web-mobile.workspaces.decline")} primary={false} busy={respond.busy && respond.arg?.invite.id === invite.id && !respond.arg.join} onClick={() => respond.run({ account, invite, join: false })} />
        </div>
      ))}
      {respond.error && <p className={`${partsCss.mError} ${css.mPanelNote}`}>{errorText(respond.error)}</p>}
      {accounts.map(({ account, workspaces }) => (
        <div key={account.sub} className={css.mGroup}>
          {accounts.length > 1 && <div className={css.mGroupLabel}>{account.email}</div>}
          {workspaces.filter((w) => !shown.has(w.id) && shown.add(w.id)).map((w) => {
            const here = w.id === app.entry.id;
            return (
              <button key={w.id} type="button" className={css.mRow} data-here={here || undefined} aria-current={here || undefined}
                onClick={() => { close(); if (!here) switchTo(app, places, w.id, lists); }}>
                <span className={css.mTile} aria-hidden="true">{initial(w.name)}</span>
                <span className={css.mRowName}>{w.name}</span>
                {here ? <Check size={18} /> : <MarkCounts mark={marks?.workspaces[w.id]} />}
              </button>
            );
          })}
        </div>
      ))}
      <div className={css.mActions}>
        <button type="button" className={css.mAction} onClick={() => { close(); app.sheet({ height: 0.8, content: () => <NewWorkspaceSheet /> }); }}>
          <Plus size={18} />{t("web-mobile.workspaces.new")}
        </button>
        <button type="button" className={css.mAction} disabled={login.busy} aria-busy={login.busy || undefined} onClick={() => { void login.signIn(); }}>
          <LogIn size={18} />{t("web-mobile.workspaces.addAccount")}
        </button>
      </div>
    </div>
  );
}

/** A workspace's mark in the panel: the first letter of its name (a character, not half of one), capitalised. */
function initial(name: string): string {
  const first = [...new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(name.trim())][0]?.segment ?? "";
  return first.toUpperCase();
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
