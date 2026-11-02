// The workspace's security mode (its lock, docs/workspace-lock.md) in the settings: whether it is on, turning it on,
// the devices waiting to be confirmed, and what a device waiting itself shows. All of it is the core's (`lock`,
// `lockDraft` topics, `lock.*` calls, client/core-ts/src/views/lock.ts): this only draws.
import { useRef, useState } from "react";
import { Link, useNavigate } from "react-router";
import { Close, Devices, Key, Monitor, Server, ShieldCheck, Web } from "@stillfail/ui/icons.tsx";
import { useCall, useTopic } from "../core/react.ts";
import { stamp } from "../api.ts";
import { useDoing } from "../doing.ts";
import { failure, useAct, useToast } from "@stillfail/ui/toast.tsx";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import { Button, Confirm, Dialog, Field, IconButton, MobileBack, Section, Time, Spinner, Waiting } from "../ui.tsx";import { t } from "../i18n.ts";
import { StationInWords, StationNamedAt } from "../StationNamed.tsx";
import type { WorkspaceEntry } from "./workspace.tsx";
import { WorkspaceBadge } from "../WorkspaceMark.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as css from "./Security.css.ts";

export type { LockDevice, LockPairing, LockView, LockDraftView as LockDraft } from "../core/shapes.ts";
import type { LockDevice, LockPairing, LockPromptsView, LockStation, LockView, LockDraftView as LockDraft } from "../core/shapes.ts";
import { sampleLock, sampleLockDraft } from "../samples.ts";

// A function, not a table made as the module loads: words are the page's language when shown (and the site's
// prerender loads this module before any language is set).
export function useLock(workspace: string): LockView | undefined {
  return useTopic<LockView>({ topic: "lock", workspace }).value;
}

/** The devices waiting on this one, in every workspace of the person's (the core's `lockPrompts`). */
export function useLockPrompts(): LockPromptsView | undefined {
  return useTopic<LockPromptsView>({ topic: "lockPrompts" }).value;
}

/** A device's name as people know it: its label, or what kind of client it is. */
function DeviceIcon({ d }: { d: { kind: string } }) {
  const Icon = d.kind === "web" ? Web : Monitor;
  return <Icon size={16} strokeWidth={1.6} className={css.deviceIcon} />;
}

/** 设置 › 安全. */
export function SecuritySettings({ entry }: { entry: WorkspaceEntry }) {
  const lock = useLock(entry.id);
  const back = `/w/${entry.id}/settings`;
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={back} label={t("web-pages.settings.title")} />
      <header className={pagesCss.pageHead}><div><h1>{t("web-pages.security.title")}</h1><p className={css.sub}>{t("web-pages.security.lead")}</p></div></header>
      {!lock ? <Waiting sample={<Off entry={entry} lock={SAMPLE_LOCK} />} /> : !lock.available ? <div className={pagesCss.card}><p className={css.sub}>{t("web-pages.security.unavailable")}</p></div>
        : lock.locked ? <On entry={entry} lock={lock} /> : <Off entry={entry} lock={lock} />}
    </div>
  );
}

/** Security mode and turning it on made up, for what their pages show while they are read (in their bones). */
const SAMPLE_LOCK = sampleLock();
const SAMPLE_DRAFT = sampleLockDraft();

function Off({ entry, lock }: { entry: WorkspaceEntry; lock: LockView }) {
  const navigate = useNavigate();
  return (
    <>
      <div className={`${pagesCss.card} ${css.lead}`}>
        <div className={css.state}>{t("web-pages.security.off")}</div>
        <div className={css.points}>
          <div className={css.point}><Server size={18} strokeWidth={1.6} className={css.pointIcon} /><span>{t("web-pages.security.now")}<span className={css.sub}>{t("web-pages.security.nowRisk")}</span></span></div>
          <div className={css.point}><Key size={18} strokeWidth={1.6} className={css.pointIcon} /><span>{t("web-pages.security.then")}<span className={css.sub}>{t("web-pages.security.thenSafe")}</span></span></div>
          <div className={css.point}><Devices size={18} strokeWidth={1.6} className={css.pointIcon} /><span>{t("web-pages.security.newDevices")}<span className={css.sub}>{t("web-pages.security.newDevicesHow")}</span></span></div>
        </div>
        {!lock.owner ? <p className={css.note}>{t("web-pages.security.ownerOnly")}</p>
          : lock.canSign ? (
            <div className={css.actions}>
              <Button variant="primary" onClick={() => navigate(`/w/${entry.id}/settings/security/open`)}>{t("web-pages.security.turnOn")}</Button>
              <span className={css.note}>{t("web-pages.security.signsHere")}</span>
            </div>
          ) : <p className={css.note}>{t("web-pages.security.webCannotSign")}</p>}
      </div>
      <Section title={t("web-pages.security.signing")}>
        <div className={pagesCss.card}><p className={css.sub}>{t("web-pages.security.signingWho")}</p></div>
      </Section>
    </>
  );
}

function On({ entry, lock }: { entry: WorkspaceEntry; lock: LockView }) {
  const call = useCall();
  const act = useAct();
  const [off, setOff] = useState(false);
  const [joining, setJoining] = useState<LockStation | null>(null);
  const [removing, setRemoving] = useState<LockDevice | null>(null);
  const turningOff = useDoing("lock.disable", { workspace: entry.id });
  return (
    <>
      <div className={`${pagesCss.card} ${css.lead}`}>
        <div className={css.state}>{t("web-pages.security.on")}
          <span className={css.stateMeta}>· {t("web-pages.security.onMeta", { signers: lock.signers, stations: lock.protected })}</span></div>
        <p className={css.sub}>{t("web-pages.security.onLead")}</p>
        {!lock.signs && !lock.me?.waiting && !lock.me?.unsigned && <p className={css.note}>{lock.canSign ? t("web-pages.security.notSignerApp") : t("web-pages.security.notSignerWeb")}</p>}
      </div>
      {/* Not confirmed yet: asked for here too, not only on the workspace's waiting page (settings skip it). */}
      {/* In the lock without signing (let in before it kept a key): made a trusted device the same way. */}
      {(lock.me?.waiting || lock.me?.unsigned) && (
        <div className={`${pagesCss.card} ${css.lead}`}>
          <div className={css.state}>{t(lock.me.unsigned ? "web-pages.security.upgradeTitle" : "web-pages.security.waitingTitle")}</div>
          <PairSteps entry={entry} lock={lock} />
        </div>
      )}
      <Section title={t("web-pages.security.people")}>
        <div className={pagesCss.card}><div className={css.rows}>
          {lock.members.map((m) => (
            <div key={m.sub} className={css.rows}>
              <div className={css.row}><div className={css.rowText}><span className={css.rowName}>{m.nameText}</span><span className={css.rowMeta}>{m.roleText}</span></div></div>
              {m.groups.length > 0 && <div className={css.devices}>
                {m.groups.map((g) => (
                  <div key={g.appText} className={css.deviceGroup}>
                    <span className={css.deviceApp}>{g.appText}</span>
                    {g.devices.map((d) => <DeviceRow key={d.id} entry={entry} d={d} canRenew={lock.signs} onRemove={() => setRemoving(d)} />)}
                  </div>
                ))}
              </div>}
            </div>
          ))}
        </div></div>
      </Section>
      <Section title="Station">
        <div className={pagesCss.card}>{lock.stations.length === 0 ? <p className={css.sub}>{t("web-pages.security.noStations")}</p> : <div className={css.rows}>
          {lock.stations.map((s) => <StationRow key={s.id} entry={entry} s={s} canJoin={lock.owner && lock.signs} onJoin={() => setJoining(s)} />)}
        </div>}</div>
      </Section>
      <Section title={t("web-pages.security.webTitle")}>
        <div className={pagesCss.card}><p className={css.sub}>{t("web-pages.security.webRisk")}</p></div>
      </Section>
      {lock.owner && lock.signs && <div><Button variant="danger" busy={turningOff} onClick={() => setOff(true)}>{t("web-pages.security.turnOff")}</Button></div>}
      <Dialog open={joining !== null} onClose={() => setJoining(null)} title={joining ? <StationInWords station={`${entry.id}/${joining.id}`} text={t("web-pages.security.joinTitle", { name: joining.name })} /> : ""} description={t("web-pages.security.joinBody")}
        footer={joining && <><Button variant="ghost" onClick={() => setJoining(null)}>{t("common.cancel")}</Button><Button variant="primary" onClick={() => { const s = joining; setJoining(null); act(call("lock.joinStation", { workspace: entry.id, station: s.id }), t("web-pages.security.join"), t("web-pages.security.joined", { name: s.name })); }}>{t("web-pages.security.join")}</Button></>}>
        <span />
      </Dialog>
      <Confirm open={removing !== null} onClose={() => setRemoving(null)} title={removing ? t("web-pages.security.removeTitle", { name: removing.fullText }) : ""}
        description={t("web-pages.security.removeBody")} action={t("web-pages.security.remove")}
        onConfirm={() => { const d = removing; setRemoving(null); if (d) act(call("lock.removeDevice", { workspace: entry.id, device: d.id }), t("web-pages.security.remove"), t("web-pages.security.removed")); }} />
      {off && <TurnOff entry={entry} onClose={() => setOff(false)} />}
    </>
  );
}

/**
 * 关闭安全模式？: what turning it off gives up, a line each, and the workspace's name typed before it can go. The core
 * then has the system ask the person (Touch ID, the phone's screen lock) before it signs; their no says nothing.
 */
function TurnOff({ entry, onClose }: { entry: WorkspaceEntry; onClose(): void }) {
  const call = useCall();
  const toast = useToast();
  const [typed, setTyped] = useState("");
  const named = typed.trim() === entry.name.trim();
  const go = () => {
    if (!named) return;
    onClose();
    call("lock.disable", { workspace: entry.id }).catch((e: unknown) => {
      if ((e as { code?: unknown } | null)?.code !== "user_cancelled") toast(t("web-main.act.failed", { what: t("web-pages.security.turnOff"), error: failure(e) }));
    });
  };
  return (
    <Dialog open onClose={onClose} title={t("web-pages.security.turnOffTitle")} description={t("web-pages.security.turnOffBody")}
      footer={<><Button variant="ghost" onClick={onClose}>{t("common.cancel")}</Button><Button variant="danger-solid" disabled={!named} onClick={go}>{t("web-pages.security.turnOff")}</Button></>}>
      <div className={css.points}>
        <div className={css.point}><Server size={18} strokeWidth={1.6} className={css.pointIcon} /><span>{t("web-pages.security.nowRisk")}</span></div>
        <div className={css.point}><Devices size={18} strokeWidth={1.6} className={css.pointIcon} /><span>{t("web-pages.security.turnOffApproval")}</span></div>
        <div className={css.point}><Key size={18} strokeWidth={1.6} className={css.pointIcon} /><span>{t("web-pages.security.turnOffVault")}</span></div>
      </div>
      <Field label={t("web-pages.security.turnOffType", { name: entry.name })} htmlFor="lock-off-name">
        <input id="lock-off-name" className={controlsCss.input} value={typed} autoFocus autoComplete="off" spellCheck={false} onChange={(e) => setTyped(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing) go(); }} />
      </Field>
    </Dialog>
  );
}

/** A station and whether the lock protects it; one it does not, the owner's signing device can take in. */
function StationRow({ entry, s, canJoin, onJoin }: { entry: WorkspaceEntry; s: LockStation; canJoin: boolean; onJoin(): void }) {
  const joiningNow = useDoing("lock.joinStation", { workspace: entry.id, station: s.id });
  return (
    <div className={css.row}>
      <span className={css.dot} data-on={s.protected} data-tone={s.protected ? undefined : "amber"} />
      <div className={css.rowText}><span className={css.rowName}><StationNamedAt station={`${entry.id}/${s.id}`} name={s.name} /></span>{!s.protected && <span className={css.rowMeta}>{t("web-pages.security.unprotectedWhy")}</span>}</div>
      {s.protected ? <span className={css.rowMeta}>{t("web-pages.security.protected")}</span>
        : canJoin ? <Button variant="ghost" busy={joiningNow} onClick={onJoin}>{t("web-pages.security.join")}</Button>
        : <span className={css.warn}>{t("web-pages.security.unprotected")}</span>}
    </div>
  );
}

/** A device in the lock: which machine it is (its group says the app), when it was last used; 续期 a web page's, 移除
 *  (asked first) where this one may. */
function DeviceRow({ entry, d, canRenew, onRemove }: { entry: WorkspaceEntry; d: LockDevice; canRenew: boolean; onRemove(): void }) {
  const call = useCall();
  const act = useAct();
  const renewing = useDoing("lock.renew", { workspace: entry.id, device: d.id });
  const removing = useDoing("lock.removeDevice", { workspace: entry.id, device: d.id });
  return (
    <div className={css.row}>
      <DeviceIcon d={d} />
      <div className={css.rowText}><span>{d.nameText}</span><span className={d.renewSoon ? css.warn : css.rowMeta}>{d.metaText}</span></div>
      {d.daysLeft != null && canRenew && <Button variant="ghost" busy={renewing} onClick={() => act(call("lock.renew", { workspace: entry.id, device: d.id }), t("web-pages.security.renew"), t("web-pages.security.renewed"))}>{t("web-pages.security.renew")}</Button>}
      {d.removable && <Button variant="ghost" busy={removing} onClick={onRemove}>{t("web-pages.security.remove")}</Button>}
    </div>
  );
}

/** A new device met face to face, showing a code of this one's to type there (the core's `lockPrompts`): put up wherever
 * the person is, the workspaces it asks to be let into named first. Nothing here approves it: only the code typed on
 * the new device does. Turned away (`lockPrompt.deny`), the code is worth nothing; closed (`lockPrompt.hide`), it is
 * no longer shown and the code still holds, read by then; done there, it goes. */
export function SecurityPrompt() {
  const call = useCall();
  const r = useLockPrompts()?.pairing[0] ?? null;
  const deny = () => { if (r) void call("lockPrompt.deny", { device: r.device }); };
  const hide = () => { if (r) void call("lockPrompt.hide", { device: r.device }); };
  return (
    <Dialog open={r !== null} onClose={hide} title={r ? t("web-pages.security.pairTitle", { name: r.name || r.email }) : ""}
      description={r ? t("web-pages.security.pairBody", { device: r.deviceText }) : ""}
      footer={r && <Button variant="ghost" onClick={deny}>{t("web-pages.security.pairDeny")}</Button>}>
      {r && <>
        <PromptPlaces r={r} />
        <div className={css.bigCode}>{spacedCode(r.code)}</div>
        {r.untilText && <p className={css.note} style={{ textAlign: "center" }}>{r.untilText}</p>}
        <p className={css.note} style={{ textAlign: "center" }}>{t("web-pages.security.pairNote")}</p>
      </>}
    </Dialog>
  );
}

/** A face-to-face code as shown: its six digits three and three. */
export const spacedCode = (code: string) => (code.length === 6 ? `${code.slice(0, 3)} ${code.slice(3)}` : code);

/** Six digits typed into six boxes (three and three): the one to type next marked, a code pasted whole taken, the last
 * one typed handing it on (`onDone`) at once. The phone's keypad comes up for it. One field under the boxes takes the
 * typing, so pasting, deleting and the system's own code fill all work as in any field. */
export function CodeEntry({ value, onChange, onDone, wrong = false, disabled = false, label }: {
  value: string; onChange(v: string): void; onDone(v: string): void; wrong?: boolean; disabled?: boolean; label: string;
}) {
  const field = useRef<HTMLInputElement>(null);
  const [focused, setFocused] = useState(false);
  const digits = value.replace(/[^0-9]/g, "").slice(0, 6);
  const box = (i: number) => (
    <span key={i} className={css.codeBox} data-next={(focused && !disabled && i === Math.min(digits.length, 5)) || undefined} data-filled={i < digits.length || undefined}>{digits[i] ?? ""}</span>
  );
  return (
    <div className={css.codeBoxes} data-wrong={wrong || undefined} data-disabled={disabled || undefined} onClick={() => field.current?.focus()}>
      <input ref={field} className={css.codeField} value={digits} inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]*" maxLength={6} autoFocus disabled={disabled}
        aria-label={label} spellCheck={false} onFocus={() => setFocused(true)} onBlur={() => setFocused(false)}
        onChange={(e) => {
          const next = e.target.value.replace(/[^0-9]/g, "").slice(0, 6);
          onChange(next);
          if (next.length === 6) onDone(next);
        }} />
      {[0, 1, 2].map(box)}<span className={css.codeGap} />{[3, 4, 5].map(box)}
    </div>
  );
}

/** The workspaces a new device asks to be let into, by name and mark. */
export function PromptPlaces({ r }: { r: LockPairing }) {
  return (
    <div className={css.places}>
      <span className={css.placesLabel}>{t("web-pages.security.promptFor")}</span>
      {r.workspaces.map((w) => <span key={w.id} className={css.place}><WorkspaceBadge w={w} size={16} />{w.name}</span>)}
    </div>
  );
}

/** 开启安全模式: what it will sign, everything ticked but what is left out. */
export function SecurityOpen({ entry }: { entry: WorkspaceEntry }) {
  const draft = useTopic<LockDraft>({ topic: "lockDraft", workspace: entry.id }).value;
  const back = `/w/${entry.id}/settings/security`;
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={back} label={t("web-pages.security.title")} />
      <header className={pagesCss.pageHead}><div><h1>{t("web-pages.security.openTitle")}</h1><p className={css.sub}>{t("web-pages.security.openLead")}</p></div></header>
      {!draft || draft.loading ? <Waiting sample={<OpenDraft entry={entry} draft={SAMPLE_DRAFT} />} /> : <OpenDraft entry={entry} draft={draft} />}
    </div>
  );
}

/** Turning security mode on, under its page's head: who and what `draft` takes in, and signing it. */
function OpenDraft({ entry, draft }: { entry: WorkspaceEntry; draft: LockDraft }) {
  const call = useCall();
  const act = useAct();
  const navigate = useNavigate();
  const opening = useDoing("lock.open", { workspace: entry.id });
  const back = `/w/${entry.id}/settings/security`;
  const toggle = (id: string) => void call("lock.toggle", { workspace: entry.id, id });
  const open = () => {
    const doing = call("lock.open", { workspace: entry.id });
    act(doing, t("web-pages.security.turnOn"), t("web-pages.security.turnedOn"));
    void doing.then(() => navigate(back), () => {});
  };
  return (
    <>
      <Section title={t("web-pages.security.members")} actions={<span className={css.rowMeta}>{t("web-pages.security.peopleCount", { n: draft.members.length })}</span>}>
        <div className={pagesCss.card}><div className={css.rows}>
          {draft.members.map((m) => <div key={m.sub} className={css.row}><div className={css.rowText}><span className={css.rowName}>{m.nameText}</span><span className={css.rowMeta}>{m.email}</span></div><span className={css.rowMeta}>{m.roleText}</span></div>)}
        </div></div>
      </Section>
      <Section title={t("web-pages.security.devices")} actions={<span className={css.rowMeta}>{t("web-pages.security.devicesWhich")}</span>}>
        <div className={pagesCss.card}><div className={css.rows}>
          {draft.devices.map((d) => (
            <label key={d.id} className={css.row}>
              <input type="checkbox" className={css.check} checked={d.on} disabled={d.fixed} onChange={() => toggle(d.id)} />
              <div className={css.rowText}><span className={css.rowName}>{d.nameText}</span>
                <span className={css.rowMeta}>{d.howText}</span></div>
              <span className={css.rowMeta}><Time stamp={stamp(d, "last_seen")} /></span>
            </label>
          ))}
        </div></div>
      </Section>
      <Section title="Station">
        <div className={pagesCss.card}><div className={css.rows}>
          {draft.stations.map((s) => (
            <label key={s.id} className={css.row}>
              <input type="checkbox" className={css.check} checked={s.on} disabled={s.fixed} onChange={() => toggle(s.id)} />
              <div className={css.rowText}><span className={css.rowName}><StationNamedAt station={`${entry.id}/${s.id}`} name={s.name} /></span>
                {s.stateText && <span className={css.rowMeta}>{s.stateText}</span>}</div>
              {s.version && <span className={s.state === "old" ? css.warn : css.rowMeta}>{s.version}</span>}
            </label>
          ))}
          <p className={css.note}>{t("web-pages.security.unprotectedNote")}</p>
        </div></div>
      </Section>
      <div className={css.foot}>
        <span className={css.footNote}>{draft.canSign ? t("web-pages.security.webExpiry") : t("web-pages.security.webCannotSign")}</span>
        <Link to={back}><Button variant="ghost">{t("common.cancel")}</Button></Link>
        <Button variant="primary" busy={opening} disabled={!draft.ready || !draft.owner || !draft.canSign} onClick={open}>{t("web-pages.security.signAndTurnOn")}</Button>
      </div>
    </>
  );
}

/** The one-line notice on the settings pages while the lock is off: the owner's, closed for good. */
export function SecurityNotice({ entry }: { entry: WorkspaceEntry }) {
  const lock = useLock(entry.id);
  const call = useCall();
  if (!lock?.available || !lock.notice) return null;
  return (
    <div className={css.banner}>
      <ShieldCheck size={16} strokeWidth={1.6} className={css.pointIcon} />
      <span>{t("web-pages.security.notice")} · <Link className={css.bannerLink} to={`/w/${entry.id}/settings/security`}>{t("web-pages.security.learn")}</Link></span>
      <span className={css.bannerClose}><IconButton label={t("common.close")} icon={Close} onClick={() => void call("lock.dismiss", { workspace: entry.id })} /></span>
    </div>
  );
}

/** What a device waiting to be confirmed shows instead of the workspace's pages: asking by hand, its person's trusted
 * devices reached, the code one of them shows typed here (`me.pair`; views/pair.ts). */
export function SecurityWaiting({ entry, lock }: { entry: WorkspaceEntry; lock: LockView }) {
  return (
    <div className={css.waiting}>
      <ShieldCheck size={40} strokeWidth={1.4} />
      <h1 className={css.waitingTitle}>{t("web-pages.security.waitingTitle")}</h1>
      <p className={css.waitingLead}>{t("web-pages.security.waitingLead", { name: entry.name })}</p>
      <PairSteps entry={entry} lock={lock} />
    </div>
  );
}

/** Asking to be confirmed, and the code typed: on the waiting page, and on 设置 › 安全 (where the vault's page sends a
 * device not yet confirmed). */
function PairSteps({ entry, lock }: { entry: WorkspaceEntry; lock: LockView }) {
  const call = useCall();
  const act = useAct();
  const asking = useDoing("lock.pair", { workspace: entry.id });
  const checking = useDoing("lock.pairCode", { workspace: entry.id });
  const [code, setCode] = useState("");
  const pair = lock.me?.pair ?? null;
  const ask = (words = t("web-pages.security.request")) => act(call("lock.pair", { workspace: entry.id }), words);
  // Typed wrong: the boxes empty again for the next try, the page says how many are left.
  const prove = (typed: string) => void call("lock.pairCode", { workspace: entry.id, code: typed }).catch(() => setCode(""));
  const typing = pair !== null && (pair.state === "code" || pair.state === "wrong" || pair.state === "checking");
  return typing ? <>
    <div className={css.waitingNote}>{t("web-pages.security.pairEnter")}</div>
    <CodeEntry value={code} onChange={setCode} onDone={prove} wrong={pair.state === "wrong" && code === ""} disabled={checking || pair.state === "checking"} label={t("web-pages.security.pairEnter")} />
    {checking || pair.state === "checking" ? <div className={css.waitingNote}><Spinner inline />{t("web-pages.security.pairChecking")}</div>
      : <>
        {pair.state === "wrong" && <div className={css.waitingFailed}>{t("web-pages.security.pairWrong", { n: pair.left ?? 0 })}</div>}
        {/* how long the code holds, and a new one asked for at any time (2026-10-30) */}
        {pair.untilText && <div className={css.waitingNote}>{pair.untilText}</div>}
        <div className={css.actions}><Button variant="ghost" onClick={() => { setCode(""); ask(t("web-pages.security.pairAgain")); }}>{t("web-pages.security.pairAgain")}</Button></div>
      </>}
  </> : pair?.state === "finding" || asking ? <div className={css.waitingNote}><Spinner inline />{t("web-pages.security.pairFinding")}</div>
    : <>
      <div className={pair?.state === "failed" ? css.waitingFailed : css.waitingNote}>
        {pair?.state === "none" ? t("web-pages.security.pairNone") : pair?.state === "failed" ? (pair.error ?? "") : t(lock.me?.unsigned ? "web-pages.security.upgradeNotAsked" : "web-pages.security.notAsked")}
      </div>
      <div className={css.actions}><Button variant="primary" onClick={() => ask()}>{t("web-pages.security.request")}</Button></div>
    </>;
}
