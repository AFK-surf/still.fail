// The workspace's security mode on a narrow screen (as the Android app has it, screens/Security.kt): its page from
// the settings, turning it on, a device to confirm in a bottom sheet, and what a device waiting itself shows. The
// core's (`lock`, `lockDraft`, `lockPrompts`; client/core-ts/src/views/lock.ts): this only draws.
import { useEffect, useState } from "react";
import { useCall, useTopic } from "../core/react.ts";
import { useDoing } from "../doing.ts";
import { stamp } from "../api.ts";
import { ShieldCheck } from "@stillfail/ui/icons.tsx";
import { t } from "../i18n.ts";
import { StationInWords, StationNamedAt } from "../StationNamed.tsx";
import { CodeEntry, spacedCode, useLock, useLockPrompts, type LockDraft, type LockPairing, type LockRequest, type LockView } from "../cloud/Security.tsx";
import { WorkspaceBadge } from "../WorkspaceMark.tsx";
import { useApp } from "./app.tsx";
import { Button, LargeTitle, LinkButton, ListCard, ListRow, PickRow, SectionHeader, TopBack } from "./parts.tsx";
import { confirm } from "./sheets.tsx";
import { Spinner, Waiting } from "@stillfail/ui/waiting.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as css from "./Security.css.ts";
import { sampleLock, sampleLockDraft } from "../samples.ts";

/** What a call answers, said by toast when it fails (and `done` when it worked). */
function useRun() {
  const app = useApp();
  const call = useCall();
  return (name: string, params: unknown, what: string, done?: string) => call(name, params).then(
    () => { if (done) app.toast(done); },
    (e: unknown) => app.toast(t("web-main.act.failed", { what, error: e instanceof Error ? e.message : String((e as { message?: unknown })?.message ?? e) })),
  );
}

export function SecurityScreen() {
  const app = useApp();
  const lock = useLock(app.entry.id);
  const turnOn = lock?.available && !lock.locked && lock.owner && lock.canSign;
  return (
    <div className={pagesCss.mScreen}>
      <div className={pagesCss.mScroll}>
        <TopBack label={t("web-mobile.settings.title")} onBack={app.pop} />
        <LargeTitle small="" big={t("web-pages.security.title")} />
        {!lock ? <Waiting sample={<Off lock={SAMPLE_LOCK} />} /> : !lock.available
          ? <ListCard><div className={css.mBody}><span className={partsCss.mSubtle}>{t("web-pages.security.unavailable")}</span></div></ListCard>
          : lock.locked ? <On lock={lock} /> : <Off lock={lock} />}
        <div style={{ height: 30 }} />
      </div>
      {turnOn && <div className={css.mFoot}><Button primary label={t("web-pages.security.turnOn")} onClick={() => app.push(app.at("/settings/security/open"))} /></div>}
    </div>
  );
}

/** Security mode made up, and turning it on, for what the screens show while they are read (in their bones). */
const SAMPLE_LOCK = sampleLock();
const SAMPLE_DRAFT = sampleLockDraft();

function Off({ lock }: { lock: LockView }) {
  return (
    <>
      <ListCard><div className={css.mBody}>
        <div className={css.mState}><span className={css.mDot} />{t("web-pages.security.off")}</div>
        <div>{t("web-pages.security.now")}<span className={css.mSub}>{t("web-pages.security.nowRisk")}</span></div>
        <div>{t("web-pages.security.then")}</div>
        <div>{t("web-pages.security.newDevices")}<span className={css.mSub}>{t("web-pages.security.newDevicesHow")}</span></div>
        {!lock.owner ? <span className={css.mNote}>{t("web-pages.security.ownerOnly")}</span>
          : !lock.canSign && <span className={css.mNote}>{t("web-pages.security.webCannotSign")}</span>}
      </div></ListCard>
      <SectionHeader title={t("web-pages.security.signing")} start={24} />
      <ListCard><div className={css.mBody}><span className={partsCss.mSubtle}>{t("web-pages.security.signingWho")}</span></div></ListCard>
    </>
  );
}

function On({ lock }: { lock: LockView }) {
  const app = useApp();
  const run = useRun();
  const ws = app.entry.id;
  const check = (r: LockRequest) => app.sheet({ height: 0.5, content: () => <ConfirmSheet r={r} workspace={app.entry.id} /> });
  return (
    <>
      <ListCard><div className={css.mBody}>
        <div className={css.mState}><span className={css.mDot} data-on="true" />{t("web-pages.security.on")}</div>
        <span className={partsCss.mSubtle}>{t("web-pages.security.onMeta", { signers: lock.signers, stations: lock.protected })}</span>
        {!lock.signs && !lock.me?.waiting && !lock.me?.unsigned && <span className={css.mNote}>{lock.canSign ? t("web-pages.security.notSignerApp") : t("web-pages.security.notSignerWeb")}</span>}
      </div></ListCard>
      {/* Not confirmed yet: asked for here too, not only on the waiting screen (settings skip it); in the lock without
          signing, made a trusted device the same way. */}
      {(lock.me?.waiting || lock.me?.unsigned) && <>
        <SectionHeader title={t(lock.me.unsigned ? "web-pages.security.upgradeTitle" : "web-pages.security.waitingTitle")} start={24} />
        <ListCard><div className={css.mBody}><PairSteps lock={lock} /></div></ListCard>
      </>}
      {lock.requests.length > 0 && <>
        <SectionHeader title={`${t("web-pages.security.waiting")} · ${lock.requests.length}`} start={24} />
        <ListCard>
          {lock.requests.map((r) => (
            <ListRow key={r.device} onClick={lock.signs ? () => check(r) : undefined}>
              <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
                <span className={listsCss.mRowTitle}>{t("web-pages.security.newDeviceOf", { name: r.whoText })}</span>
                <span className={listsCss.mRowNote}>{r.deviceText} · {stamp(r, "created_at")?.ago ?? ""}</span>
              </span>
              <span className={css.mCode}>{r.code}</span>
            </ListRow>
          ))}
        </ListCard>
      </>}
      <SectionHeader title={t("web-pages.security.people")} start={24} />
      <ListCard>
        {lock.members.map((m) => (
          <div key={m.sub}>
            <ListRow><span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{m.nameText}</span><span className={partsCss.mSubtle}>{m.roleText}</span></ListRow>
            {m.groups.map((g) => (
              <div key={g.appText}>
                <div className={css.mDeviceApp}>{g.appText}</div>
                {g.devices.map((d) => (
                  <DeviceRow key={d.id} d={d} renew={lock.signs ? () => void run("lock.renew", { workspace: ws, device: d.id }, t("web-pages.security.renew"), t("web-pages.security.renewed")) : undefined} />
                ))}
              </div>
            ))}
          </div>
        ))}
      </ListCard>
      <SectionHeader title="Station" start={24} />
      <ListCard>
        {lock.stations.length === 0 && <div className={css.mBody}><span className={partsCss.mSubtle}>{t("web-pages.security.noStations")}</span></div>}
        {lock.stations.map((s) => {
          const join = !s.protected && lock.owner && lock.signs;
          return (
            <ListRow key={s.id} onClick={join ? () => app.sheet({ height: 0.4, content: () => <JoinSheet s={s} /> }) : undefined}>
              <span className={css.mDot} data-on={s.protected} data-tone={s.protected ? undefined : "amber"} />
              <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
                <span className={listsCss.mRowTitle}><StationNamedAt station={`${app.entry.id}/${s.id}`} name={s.name} /></span>
                {!s.protected && <span className={listsCss.mRowNote}>{t("web-pages.security.unprotectedWhy")}</span>}
              </span>
              {s.protected ? <span className={partsCss.mSubtle}>{t("web-pages.security.protected")}</span>
                : join ? <JoinMark id={s.id} /> : <span className={css.mWarn}>{t("web-pages.security.unprotected")}</span>}
            </ListRow>
          );
        })}
      </ListCard>
      <SectionHeader title={t("web-pages.security.webTitle")} start={24} />
      <ListCard><div className={css.mBody}><span className={partsCss.mSubtle}>{t("web-pages.security.webRisk")}</span></div></ListCard>
    </>
  );
}

/** A device in the lock: which machine it is (its group says the app), when it was last used; 续期 a web page's, 移除
 *  (asked first in a sheet) where this one may, in a line of their own under its words: its name, of no length known,
 *  never squeezed by them. */
function DeviceRow({ d, renew }: { d: LockView["members"][number]["groups"][number]["devices"][number]; renew?: (() => void) | undefined }) {
  const app = useApp();
  const call = useCall();
  const ws = app.entry.id;
  const renewing = useDoing("lock.renew", { workspace: ws, device: d.id });
  const removing = useDoing("lock.removeDevice", { workspace: ws, device: d.id });
  const remove = () => confirm(app, {
    title: t("web-pages.security.removeTitle", { name: d.fullText }), text: t("web-pages.security.removeBody"),
    action: t("web-pages.security.remove"), danger: true,
    run: () => call("lock.removeDevice", { workspace: ws, device: d.id }).then(() => app.toast(t("web-pages.security.removed"))),
  });
  return (
    <ListRow>
      <span className={`${partsCss.mGrow} ${listsCss.mRowText} ${css.mDevice}`}>
        <span>{d.nameText}</span>
        <span className={d.renewSoon ? css.mWarn : listsCss.mRowNote}>{d.metaText}</span>
        {((d.daysLeft != null && renew) || d.removable) && <span className={css.mDeviceActs}>
          {d.daysLeft != null && renew && <LinkButton label={t("web-pages.security.renew")} busy={renewing} onClick={renew} />}
          {d.removable && <LinkButton label={t("web-pages.security.remove")} busy={removing} onClick={remove} />}
        </span>}
      </span>
    </ListRow>
  );
}

function JoinMark({ id }: { id: string }) {
  const app = useApp();
  return useDoing("lock.joinStation", { workspace: app.entry.id, station: id }) ? <Spinner inline /> : <span className={partsCss.mAccent}>{t("web-pages.security.join")}</span>;
}

/** A station of the workspace not in the lock, taken in once its owner says it is theirs. */
function JoinSheet({ s }: { s: LockView["stations"][number] }) {
  const app = useApp();
  const run = useRun();
  return (
    <div className={css.mSheet}>
      <b className={css.mSheetTitle}>{<StationInWords station={`${app.entry.id}/${s.id}`} text={t("web-pages.security.joinTitle", { name: s.name })} />}</b>
      <span className={partsCss.mSubtle}>{t("web-pages.security.joinBody")}</span>
      <div className={css.mPair}>
        <Button primary={false} label={t("common.cancel")} onClick={() => app.sheet(null)} />
        <Button primary label={t("web-pages.security.join")} onClick={() => { app.sheet(null); void run("lock.joinStation", { workspace: app.entry.id, station: s.id }, t("web-pages.security.join"), t("web-pages.security.joined", { name: s.name })); }} />
      </div>
    </div>
  );
}

/** A new device met face to face, showing a code of this one's to type there (the core's `lockPrompts`): put up wherever
 * the person is and kept up as pages change. Nothing here approves it, only the code typed on the new device; turned
 * away (`lockPrompt.deny`), the code is worth nothing; closed (`lockPrompt.hide`), it is no longer shown and the code
 * still holds. */
export function SecurityPrompt() {
  const app = useApp();
  const call = useCall();
  const r = useLockPrompts()?.pairing[0] ?? null;
  useEffect(() => {
    if (!r) return;
    app.sheet({ height: 0.55, keep: true, onClose: () => void call("lockPrompt.hide", { device: r.device }), content: () => <PairSheet r={r} /> });
  }, [r?.device]); // eslint-disable-line react-hooks/exhaustive-deps
  return null;
}

/** The code a new device asks for, and where it asks to be let in; gone once it is done there or turned away. */
function PairSheet({ r }: { r: LockPairing }) {
  const app = useApp();
  const call = useCall();
  const prompts = useLockPrompts();
  const gone = prompts !== undefined && !prompts.pairing.some((x) => x.device === r.device);
  useEffect(() => { if (gone) app.sheet(null); }, [gone]); // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <div className={css.mSheet}>
      <b className={css.mSheetTitle}>{t("web-pages.security.pairTitle", { name: r.name || r.email })}</b>
      <span className={partsCss.mSubtle}>{t("web-pages.security.pairBody", { device: r.deviceText })}</span>
      <div className={css.mPlaces}>
        <span className={partsCss.mSubtle}>{t("web-pages.security.promptFor")}</span>
        {r.workspaces.map((w) => <span key={w.id} className={css.mPlace}><WorkspaceBadge w={w} size={16} />{w.name}</span>)}
      </div>
      <div className={css.mBigCode}>{spacedCode(r.code)}</div>
      {r.untilText && <span className={css.mNote}>{r.untilText}</span>}
      <span className={css.mNote}>{t("web-pages.security.pairNote")}</span>
      <div className={`${css.mPair} ${css.mStack}`}>
        <Button primary={false} label={t("web-pages.security.pairDeny")} onClick={() => { app.sheet(null); void call("lockPrompt.deny", { device: r.device }); }} />
      </div>
    </div>
  );
}

/** A waiting device from a workspace's 设置 › 安全 (a client from before asking through the cloud): confirmed once its
 * code is the one on its screen. */
function ConfirmSheet({ r, workspace }: { r: LockRequest; workspace: string }) {
  const app = useApp();
  const run = useRun();
  const close = (then: () => void) => () => { app.sheet(null); then(); };
  // Answered on another device: gone here too.
  const lock = useTopic<LockView>({ topic: "lock", workspace }).value;
  const gone = lock !== undefined && !lock.requests.some((x) => x.device === r.device);
  useEffect(() => { if (gone) app.sheet(null); }, [gone]); // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <div className={css.mSheet}>
      <b className={css.mSheetTitle}>{t("web-pages.security.confirmTitle", { name: r.whoText })}</b>
      <span className={partsCss.mSubtle}>{t("web-pages.security.confirmBody", { device: r.deviceText, name: r.whoText })}</span>
      <div className={css.mBigCode}>{r.code}</div>
      <span className={css.mNote}>{r.kind === "web" ? t("web-pages.security.confirmWeb") : t("web-pages.security.confirmApp")}</span>
      <div className={`${css.mPair} ${css.mStack}`}>
        <Button primary label={t("web-pages.security.confirm")} onClick={close(() => void run("lock.confirm", { workspace, device: r.device, code: r.code }, t("web-pages.security.confirmDevice"), t("web-pages.security.confirmed")))} />
        <Button primary={false} label={t("web-pages.security.deny")} onClick={close(() => void run("lock.deny", { workspace, device: r.device }, t("web-pages.security.denyDevice")))} />
      </div>
    </div>
  );
}

/** 开启安全模式, on a phone. */
export function SecurityOpenScreen() {
  const app = useApp();
  const call = useCall();
  const run = useRun();
  const draft = useTopic<LockDraft>({ topic: "lockDraft", workspace: app.entry.id }).value;
  const opening = useDoing("lock.open", { workspace: app.entry.id });
  const toggle = (id: string) => void call("lock.toggle", { workspace: app.entry.id, id });
  return (
    <div className={pagesCss.mScreen}>
      <div className={pagesCss.mScroll}>
      <TopBack label={t("web-pages.security.title")} onBack={app.pop} />
      <LargeTitle small="" big={t("web-pages.security.openTitle")} />
      {!draft || draft.loading ? <Waiting sample={<OpenDraft draft={SAMPLE_DRAFT} onToggle={() => undefined} />} /> : <OpenDraft draft={draft} onToggle={toggle} />}
      </div>
      {draft && !draft.loading && (
        <div className={css.mFoot}>
          <div className={css.mFootNote}>{draft.canSign ? t("web-pages.security.webExpiry") : t("web-pages.security.webCannotSign")}</div>
          <Button primary busy={opening} enabled={draft.ready && draft.owner && draft.canSign} label={t("web-pages.security.signAndTurnOn")}
            onClick={() => void run("lock.open", { workspace: app.entry.id }, t("web-pages.security.turnOn"), t("web-pages.security.turnedOn")).then(() => app.pop())} />
        </div>
      )}
    </div>
  );
}

/** Turning security mode on as `draft` has it: who it covers, which of their devices and stations (each `onToggle`d). */
function OpenDraft({ draft, onToggle }: { draft: LockDraft; onToggle(id: string): void }) {
  return <>
    <p className={css.mLead}>{t("web-pages.security.openLead")}</p>
    <SectionHeader title={t("web-pages.security.members")} trailing={t("web-pages.security.peopleCount", { n: draft.members.length })} start={24} />
    <ListCard>{draft.members.map((m) => <ListRow key={m.sub}><span className={`${partsCss.mGrow} ${listsCss.mRowText}`}><span className={listsCss.mRowTitle}>{m.nameText}</span><span className={listsCss.mRowNote}>{m.email}</span></span><span className={partsCss.mSubtle}>{m.roleText}</span></ListRow>)}</ListCard>
    <SectionHeader title={t("web-pages.security.devices")} trailing={t("web-pages.security.devicesWhich")} start={24} />
    <ListCard>{draft.devices.map((d) => (
      <PickRow key={d.id} label={d.nameText} sub={d.howText}
        checked={d.on} enabled={!d.fixed} onClick={() => onToggle(d.id)} />
    ))}</ListCard>
    <SectionHeader title="Station" start={24} />
    <ListCard>{draft.stations.map((s) => (
      <PickRow key={s.id} label={s.name} sub={s.state === "ok" ? (s.version ?? undefined) : s.state === "asking" ? t("web-pages.security.asking") : s.state === "old" ? t("web-pages.security.tooOld") : t("web-pages.security.offline")}
        checked={s.on} enabled={!s.fixed} onClick={() => onToggle(s.id)} />
    ))}</ListCard>
    <p className={css.mLead}>{t("web-pages.security.unprotectedNote")}</p>
    <div style={{ height: 24 }} />
  </>;
}

/** What a device waiting to be confirmed shows instead of the workspace: asking by hand, its person's trusted devices
 * reached, the code one of them shows typed here (`me.pair`; views/pair.ts). */
export function SecurityWaitingScreen({ lock }: { lock: LockView }) {
  const app = useApp();
  return (
    <div className={css.mWaiting}>
      <ShieldCheck size={44} strokeWidth={1.4} />
      <b className={css.mWaitingTitle}>{t("web-pages.security.waitingTitle")}</b>
      <span className={partsCss.mSubtle}>{t("web-pages.security.waitingLead", { name: app.entry.name })}</span>
      <PairSteps lock={lock} />
    </div>
  );
}

/** Asking to be confirmed, and the code typed: on the waiting screen, and on 设置 › 安全 (where the vault's page sends a
 * device not yet confirmed). */
function PairSteps({ lock }: { lock: LockView }) {
  const app = useApp();
  const run = useRun();
  const call = useCall();
  const ws = app.entry.id;
  const asking = useDoing("lock.pair", { workspace: ws });
  const checking = useDoing("lock.pairCode", { workspace: ws });
  const [code, setCode] = useState("");
  const pair = lock.me?.pair ?? null;
  const typing = pair !== null && (pair.state === "code" || pair.state === "wrong" || pair.state === "checking");
  // Typed wrong: the boxes empty again for the next try, the page says how many are left.
  const prove = (typed: string) => void call("lock.pairCode", { workspace: ws, code: typed }).catch(() => setCode(""));
  return typing ? <>
    <span className={css.mNote}>{t("web-pages.security.pairEnter")}</span>
    <CodeEntry value={code} onChange={setCode} onDone={prove} wrong={pair.state === "wrong" && code === ""} disabled={checking || pair.state === "checking"} label={t("web-pages.security.pairEnter")} />
    {checking || pair.state === "checking" ? <span className={css.mNote}><Spinner inline />{t("web-pages.security.pairChecking")}</span>
      : <>
        {pair.state === "wrong" && <span className={css.mFailed}>{t("web-pages.security.pairWrong", { n: pair.left ?? 0 })}</span>}
        {/* how long the code holds, and a new one asked for at any time (2026-10-30) */}
        {pair.untilText && <span className={css.mNote}>{pair.untilText}</span>}
        <Button primary={false} label={t("web-pages.security.pairAgain")} onClick={() => { setCode(""); void run("lock.pair", { workspace: ws }, t("web-pages.security.pairAgain")); }} />
      </>}
  </> : pair?.state === "finding" || asking ? <span className={css.mNote}><Spinner inline />{t("web-pages.security.pairFinding")}</span>
    : <>
      <span className={pair?.state === "failed" || lock.me?.failed ? css.mFailed : css.mNote}>
        {pair?.state === "none" ? t("web-pages.security.pairNone") : pair?.state === "failed" ? (pair.error ?? "") : lock.me?.failed ? t("web-pages.security.requestFailed", { error: lock.me.failed }) : t(lock.me?.unsigned ? "web-pages.security.upgradeNotAsked" : "web-pages.security.notAsked")}
      </span>
      <Button primary label={t("web-pages.security.request")} onClick={() => void run("lock.pair", { workspace: ws }, t("web-pages.security.request"))} />
    </>;
}
