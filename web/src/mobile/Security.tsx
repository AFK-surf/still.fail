// The workspace's security mode on a narrow screen (as the Android app has it, screens/Security.kt): its page from
// the settings, turning it on, a device to confirm in a bottom sheet, and what a device waiting itself shows. The
// core's (`lock`, `lockDraft`, `lockPrompts`; client/core-ts/src/views/lock.ts): this only draws.
import { useEffect } from "react";
import { useCall, useTopic } from "../core/react.ts";
import { useDoing } from "../doing.ts";
import { stamp } from "../api.ts";
import { ShieldCheck } from "@stillfail/ui/icons.tsx";
import { t } from "../i18n.ts";
import { deviceName, useLock, useLockPrompts, type LockDraft, type LockPrompt, type LockRequest, type LockView } from "../cloud/Security.tsx";
import { marked, WorkspaceMark } from "../WorkspaceMark.tsx";
import { ROLE_LABEL } from "../cloud/settings.tsx";
import { useApp } from "./app.tsx";
import { Button, LargeTitle, ListCard, ListRow, PickRow, SectionHeader, TopBack } from "./parts.tsx";
import { Spinner, Waiting } from "@stillfail/ui/waiting.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as css from "./Security.css.ts";

const role = (r: string) => ROLE_LABEL[r as keyof typeof ROLE_LABEL] ?? r;

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
        {!lock ? <Waiting shape="cards" count={2} /> : !lock.available
          ? <ListCard><div className={css.mBody}><span className={partsCss.mSubtle}>{t("web-pages.security.unavailable")}</span></div></ListCard>
          : lock.locked ? <On lock={lock} /> : <Off lock={lock} />}
        <div style={{ height: 30 }} />
      </div>
      {turnOn && <div className={css.mFoot}><Button primary label={t("web-pages.security.turnOn")} onClick={() => app.push(app.at("/settings/security/open"))} /></div>}
    </div>
  );
}

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
        {!lock.signs && <span className={css.mNote}>{lock.canSign ? t("web-pages.security.notSignerApp") : t("web-pages.security.notSignerWeb")}</span>}
      </div></ListCard>
      {lock.requests.length > 0 && <>
        <SectionHeader title={`${t("web-pages.security.waiting")} · ${lock.requests.length}`} start={24} />
        <ListCard>
          {lock.requests.map((r) => (
            <ListRow key={r.device} onClick={lock.signs ? () => check(r) : undefined}>
              <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
                <span className={listsCss.mRowTitle}>{t("web-pages.security.newDeviceOf", { name: r.name || r.email })}</span>
                <span className={listsCss.mRowNote}>{deviceName(r)} · {stamp(r, "created_at")?.ago ?? ""}</span>
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
            <ListRow><span className={`${partsCss.mGrow} ${listsCss.mRowTitle}`}>{m.name || m.email}</span><span className={partsCss.mSubtle}>{role(m.role)}</span></ListRow>
            {m.devices.map((d) => (
              <DeviceRow key={d.id} d={d} renew={lock.signs ? () => void run("lock.renew", { workspace: ws, device: d.id }, t("web-pages.security.renew"), t("web-pages.security.renewed")) : undefined} />
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
                <span className={listsCss.mRowTitle}>{s.name}</span>
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

function DeviceRow({ d, renew }: { d: LockView["members"][number]["devices"][number]; renew?: (() => void) | undefined }) {
  const app = useApp();
  const renewing = useDoing("lock.renew", { workspace: app.entry.id, device: d.id });
  const meta = [
    d.kind === "web" ? t("web-pages.security.web") : t("web-pages.security.app"),
    d.signs ? t("web-pages.security.signs") : null,
    d.mine ? t("web-pages.security.thisDevice") : null,
    d.daysLeft != null ? t("web-pages.security.daysLeft", { n: d.daysLeft }) : null,
    d.recent ? t("web-pages.security.recent") : null,
  ].filter(Boolean).join(" · ");
  return (
    <ListRow onClick={d.daysLeft != null && renew && !renewing ? renew : undefined}>
      <span className={`${partsCss.mGrow} ${listsCss.mRowText} ${css.mDevice}`}>
        <span>{deviceName(d)}</span>
        <span className={d.renewSoon ? css.mWarn : listsCss.mRowNote}>{meta}</span>
      </span>
      {renewing ? <Spinner inline /> : d.daysLeft != null && renew && <span className={partsCss.mAccent}>{t("web-pages.security.renew")}</span>}
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
      <b className={css.mSheetTitle}>{t("web-pages.security.joinTitle", { name: s.name })}</b>
      <span className={partsCss.mSubtle}>{t("web-pages.security.joinBody")}</span>
      <div className={css.mPair}>
        <Button primary={false} label={t("common.cancel")} onClick={() => app.sheet(null)} />
        <Button primary label={t("web-pages.security.join")} onClick={() => { app.sheet(null); void run("lock.joinStation", { workspace: app.entry.id, station: s.id }, t("web-pages.security.join"), t("web-pages.security.joined", { name: s.name })); }} />
      </div>
    </div>
  );
}

/** A device waiting on this one, in any workspace of the person's, put up wherever they are (the core's
 * `lockPrompts`) and kept up as pages change, until it is answered or closed by hand (`lockPrompt.shown`: then it stays
 * in each workspace's 设置 › 安全). */
export function SecurityPrompt() {
  const app = useApp();
  const call = useCall();
  const r = useLockPrompts()?.prompt ?? null;
  useEffect(() => {
    if (!r) return;
    app.sheet({ height: 0.55, keep: true, onClose: () => void call("lockPrompt.shown", { device: r.device }), content: () => <ConfirmSheet r={r} /> });
  }, [r?.device]); // eslint-disable-line react-hooks/exhaustive-deps
  return null;
}

/** A waiting device: confirmed once its code is the one on its screen. Put up on its own (`lockPrompts`), the
 * workspaces it asks to be let into are named first, and it is approved in all of them at once; from a workspace's
 * 设置 › 安全 (`workspace`), in that one. */
function ConfirmSheet({ r, workspace }: { r: LockPrompt | LockRequest; workspace?: string }) {
  const app = useApp();
  const run = useRun();
  const close = (then: () => void) => () => { app.sheet(null); then(); };
  // Answered on another device: gone here too; asked in one more workspace meanwhile, named too.
  const prompts = useLockPrompts();
  const lock = useTopic<LockView>(workspace ? { topic: "lock", workspace } : null).value;
  const now = prompts?.waiting.find((x) => x.device === r.device);
  const gone = workspace ? lock !== undefined && !lock.requests.some((x) => x.device === r.device) : prompts !== undefined && now === undefined;
  useEffect(() => { if (gone) app.sheet(null); }, [gone]); // eslint-disable-line react-hooks/exhaustive-deps
  const places = workspace ? [] : (now ?? (r as LockPrompt)).workspaces ?? [];
  const many = places.length > 1;
  const deny = () => workspace ? run("lock.deny", { workspace, device: r.device }, t("web-pages.security.denyDevice")) : run("lockPrompt.deny", { device: r.device }, t("web-pages.security.denyDevice"));
  const confirm = () => workspace
    ? run("lock.confirm", { workspace, device: r.device, code: r.code }, t("web-pages.security.confirmDevice"), t("web-pages.security.confirmed"))
    : run("lockPrompt.confirm", { device: r.device, code: r.code }, t("web-pages.security.confirmDevice"), t("web-pages.security.confirmed"));
  return (
    <div className={css.mSheet}>
      <b className={css.mSheetTitle}>{t("web-pages.security.confirmTitle", { name: r.name || r.email })}</b>
      <span className={partsCss.mSubtle}>{t("web-pages.security.confirmBody", { device: deviceName(r), name: r.name || r.email })}</span>
      {places.length > 0 && <div className={css.mPlaces}>
        <span className={partsCss.mSubtle}>{t("web-pages.security.promptFor")}</span>
        {places.map((w) => <span key={w.id} className={css.mPlace}>{marked(w) && <WorkspaceMark w={w} size={16} />}{w.name}</span>)}
      </div>}
      <div className={css.mBigCode}>{r.code}</div>
      <span className={css.mNote}>{r.kind === "web" ? t("web-pages.security.confirmWeb") : t("web-pages.security.confirmApp")}</span>
      <div className={`${css.mPair} ${css.mStack}`}>
        <Button primary label={many ? t("web-pages.security.confirmAll") : t("web-pages.security.confirm")} onClick={close(() => void confirm())} />
        <Button primary={false} label={many ? t("web-pages.security.denyAll") : t("web-pages.security.deny")} onClick={close(() => void deny())} />
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
      {!draft || draft.loading ? <Waiting shape="cards" count={3} /> : <>
        <p className={css.mLead}>{t("web-pages.security.openLead")}</p>
        <SectionHeader title={t("web-pages.security.members")} trailing={t("web-pages.security.peopleCount", { n: draft.members.length })} start={24} />
        <ListCard>{draft.members.map((m) => <ListRow key={m.sub}><span className={`${partsCss.mGrow} ${listsCss.mRowText}`}><span className={listsCss.mRowTitle}>{m.name || m.email}</span><span className={listsCss.mRowNote}>{m.email}</span></span><span className={partsCss.mSubtle}>{role(m.role)}</span></ListRow>)}</ListCard>
        <SectionHeader title={t("web-pages.security.devices")} trailing={t("web-pages.security.devicesWhich")} start={24} />
        <ListCard>{draft.devices.map((d) => (
          <PickRow key={d.id} label={`${d.person} · ${d.current ? t("web-pages.security.thisDevice") : deviceName(d)}`} sub={d.older ? t("web-pages.security.olderHow") : d.kind === "web" ? t("web-pages.security.web") : t("web-pages.security.app")}
            checked={d.on} enabled={!d.fixed} onClick={() => toggle(d.id)} />
        ))}</ListCard>
        <SectionHeader title="Station" start={24} />
        <ListCard>{draft.stations.map((s) => (
          <PickRow key={s.id} label={s.name} sub={s.state === "ok" ? (s.version ?? undefined) : s.state === "asking" ? t("web-pages.security.asking") : s.state === "old" ? t("web-pages.security.tooOld") : t("web-pages.security.offline")}
            checked={s.on} enabled={!s.fixed} onClick={() => toggle(s.id)} />
        ))}</ListCard>
        <p className={css.mLead}>{t("web-pages.security.unprotectedNote")}</p>
        <div style={{ height: 24 }} />
      </>}
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

/** What a device waiting to be confirmed shows instead of the workspace. */
export function SecurityWaitingScreen({ lock }: { lock: LockView }) {
  const app = useApp();
  const run = useRun();
  const asking = useDoing("lock.request", { workspace: app.entry.id });
  const failed = lock.me?.failed;
  return (
    <div className={css.mWaiting}>
      <ShieldCheck size={44} strokeWidth={1.4} />
      <b className={css.mWaitingTitle}>{t("web-pages.security.waitingTitle")}</b>
      <span className={partsCss.mSubtle}>{t("web-pages.security.waitingLead", { name: app.entry.name })}</span>
      <div className={css.mBigCode}>{lock.me?.code}</div>
      {(failed || lock.me?.asked === false) && !asking
        ? <><span className={failed ? css.mFailed : css.mNote}>{failed ? t("web-pages.security.requestFailed", { error: failed }) : t("web-pages.security.notAsked")}</span>
          <Button primary label={t("web-pages.security.request")} onClick={() => void run("lock.request", { workspace: app.entry.id }, t("web-pages.security.request"))} /></>
        : <span className={css.mNote}><Spinner inline />{t("web-pages.security.waitingNote")}</span>}
    </div>
  );
}
