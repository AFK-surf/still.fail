// The workspace's security mode (its lock, docs/workspace-lock.md) in the settings: whether it is on, turning it on,
// the devices waiting to be confirmed, and what a device waiting itself shows. All of it is the core's (`lock`,
// `lockDraft` topics, `lock.*` calls, client/core-ts/src/views/lock.ts): this only draws.
import { useState } from "react";
import { Link, useNavigate } from "react-router";
import { Close, Devices, Key, Monitor, Server, ShieldCheck, Web } from "../icons.tsx";
import { useCall, useTopic } from "../core/react.ts";
import { stamp } from "../api.ts";
import { useDoing } from "../doing.ts";
import { useAct } from "../toast.tsx";
import { Button, Dialog, IconButton, Loading, MobileBack, Section, Time } from "../ui.tsx";
import { t } from "../i18n.ts";
import type { WorkspaceEntry } from "./workspace.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as waitingCss from "../styles/waiting.css.ts";
import * as css from "./Security.css.ts";

export type { LockDevice, LockRequest, LockView, LockDraftView as LockDraft } from "../core/shapes.ts";
import type { LockDevice, LockRequest, LockStation, LockView, LockDraftView as LockDraft } from "../core/shapes.ts";

const ROLE: Record<string, string> = { owner: "Owner", admin: "Admin", member: t("web-pages.roles.member"), viewer: t("web-pages.security.viewer") };

export function useLock(workspace: string): LockView | undefined {
  return useTopic<LockView>({ topic: "lock", workspace }).value;
}

/** A device's name as people know it: its label, or what kind of client it is. */
export function deviceName(d: { kind: string; label: string; older?: boolean }): string {
  if (d.older) return d.label || t("web-pages.security.olderClient");
  return d.label || (d.kind === "web" ? t("web-pages.security.webDevice") : t("web-pages.security.appDevice"));
}

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
      {!lock ? <Loading label={t("web-pages.settings.reading")} /> : !lock.available ? <div className={pagesCss.card}><p className={css.sub}>{t("web-pages.security.unavailable")}</p></div>
        : lock.locked ? <On entry={entry} lock={lock} /> : <Off entry={entry} lock={lock} />}
    </div>
  );
}

function Off({ entry, lock }: { entry: WorkspaceEntry; lock: LockView }) {
  const navigate = useNavigate();
  return (
    <>
      <div className={`${pagesCss.card} ${css.lead}`}>
        <div className={css.state}><span className={css.dot} />{t("web-pages.security.off")}</div>
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
  const [checking, setChecking] = useState<LockRequest | null>(null);
  const [off, setOff] = useState(false);
  const [joining, setJoining] = useState<LockStation | null>(null);
  const turningOff = useDoing("lock.disable", { workspace: entry.id });
  return (
    <>
      <div className={`${pagesCss.card} ${css.lead}`}>
        <div className={css.state}><span className={css.dot} data-on="true" />{t("web-pages.security.on")}
          <span className={css.stateMeta}>· {t("web-pages.security.onMeta", { signers: lock.signers, stations: lock.protected })}</span></div>
        <p className={css.sub}>{t("web-pages.security.onLead")}</p>
        {!lock.signs && <p className={css.note}>{lock.canSign ? t("web-pages.security.notSignerApp") : t("web-pages.security.notSignerWeb")}</p>}
      </div>
      {lock.requests.length > 0 && (
        <Section title={<>{t("web-pages.security.waiting")} <span className={css.count}>{lock.requests.length}</span></>}>
          <div className={pagesCss.card}><div className={css.rows}>
            {lock.requests.map((r) => (
              <div key={r.device} className={css.row}>
                <div className={css.rowText}>
                  <span className={css.rowName}>{t("web-pages.security.newDeviceOf", { name: r.name || r.email })}</span>
                  <span className={css.rowMeta}>{r.label || (r.kind === "web" ? t("web-pages.security.webDevice") : t("web-pages.security.appDevice"))} · <Time stamp={stamp(r, "created_at")} /></span>
                </div>
                <span className={css.code}>{r.code}</span>
                {lock.signs && <Button variant="primary" onClick={() => setChecking(r)}>{t("web-pages.security.check")}</Button>}
              </div>
            ))}
          </div></div>
        </Section>
      )}
      <Section title={t("web-pages.security.people")}>
        <div className={pagesCss.card}><div className={css.rows}>
          {lock.members.map((m) => (
            <div key={m.sub} className={css.rows}>
              <div className={css.row}><div className={css.rowText}><span className={css.rowName}>{m.name || m.email}</span><span className={css.rowMeta}>{ROLE[m.role] ?? m.role}</span></div></div>
              {m.devices.length > 0 && <div className={css.devices}>
                {m.devices.map((d) => <DeviceRow key={d.id} entry={entry} d={d} canRenew={lock.signs} />)}
              </div>}
            </div>
          ))}
        </div></div>
      </Section>
      <Section title="Station">
        <div className={pagesCss.card}><div className={css.rows}>
          {lock.stations.map((s) => <StationRow key={s.id} entry={entry} s={s} canJoin={lock.owner && lock.signs} onJoin={() => setJoining(s)} />)}
        </div></div>
      </Section>
      <Section title={t("web-pages.security.webTitle")}>
        <div className={pagesCss.card}><p className={css.sub}>{t("web-pages.security.webRisk")}</p></div>
      </Section>
      {lock.owner && lock.signs && <div><Button variant="danger" busy={turningOff} onClick={() => setOff(true)}>{t("web-pages.security.turnOff")}</Button></div>}
      <Dialog open={joining !== null} onClose={() => setJoining(null)} title={joining ? t("web-pages.security.joinTitle", { name: joining.name }) : ""} description={t("web-pages.security.joinBody")}
        footer={joining && <><Button variant="ghost" onClick={() => setJoining(null)}>{t("common.cancel")}</Button><Button variant="primary" onClick={() => { const s = joining; setJoining(null); act(call("lock.joinStation", { workspace: entry.id, station: s.id }), t("web-pages.security.join"), t("web-pages.security.joined", { name: s.name })); }}>{t("web-pages.security.join")}</Button></>}>
        <span />
      </Dialog>
      <ConfirmDevice entry={entry} request={checking} onClose={() => setChecking(null)} />
      <Dialog open={off} onClose={() => setOff(false)} title={t("web-pages.security.turnOffTitle")} description={t("web-pages.security.turnOffBody")}
        footer={<><Button variant="ghost" onClick={() => setOff(false)}>{t("common.cancel")}</Button><Button variant="danger" onClick={() => { setOff(false); act(call("lock.disable", { workspace: entry.id }), t("web-pages.security.turnOff")); }}>{t("web-pages.security.turnOff")}</Button></>}>
        <span />
      </Dialog>
    </>
  );
}

/** A station and whether the lock protects it; one it does not, the owner's signing device can take in. */
function StationRow({ entry, s, canJoin, onJoin }: { entry: WorkspaceEntry; s: LockStation; canJoin: boolean; onJoin(): void }) {
  const joiningNow = useDoing("lock.joinStation", { workspace: entry.id, station: s.id });
  return (
    <div className={css.row}>
      <span className={css.dot} data-on={s.protected} data-tone={s.protected ? undefined : "amber"} />
      <div className={css.rowText}><span className={css.rowName}>{s.name}</span>{!s.protected && <span className={css.rowMeta}>{t("web-pages.security.unprotectedWhy")}</span>}</div>
      {s.protected ? <span className={css.rowMeta}>{t("web-pages.security.protected")}</span>
        : canJoin ? <Button variant="ghost" busy={joiningNow} onClick={onJoin}>{t("web-pages.security.join")}</Button>
        : <span className={css.warn}>{t("web-pages.security.unprotected")}</span>}
    </div>
  );
}

function DeviceRow({ entry, d, canRenew }: { entry: WorkspaceEntry; d: LockDevice; canRenew: boolean }) {
  const call = useCall();
  const act = useAct();
  const renewing = useDoing("lock.renew", { workspace: entry.id, device: d.id });
  const meta = [
    d.kind === "web" ? t("web-pages.security.web") : t("web-pages.security.app"),
    d.signs ? t("web-pages.security.signs") : null,
    d.mine ? t("web-pages.security.thisDevice") : null,
    d.daysLeft != null ? t("web-pages.security.daysLeft", { n: d.daysLeft }) : null,
    d.recent ? t("web-pages.security.recent") : null,
  ].filter(Boolean).join(" · ");
  return (
    <div className={css.row}>
      <DeviceIcon d={d} />
      <div className={css.rowText}><span>{deviceName(d)}</span><span className={d.renewSoon ? css.warn : css.rowMeta}>{meta}</span></div>
      {d.daysLeft != null && canRenew && <Button variant="ghost" busy={renewing} onClick={() => act(call("lock.renew", { workspace: entry.id, device: d.id }), t("web-pages.security.renew"), t("web-pages.security.renewed"))}>{t("web-pages.security.renew")}</Button>}
    </div>
  );
}

/** A waiting device, confirmed once its code is the one on its screen. */
function ConfirmDevice({ entry, request, onClose }: { entry: WorkspaceEntry; request: LockRequest | null; onClose(): void }) {
  const call = useCall();
  const act = useAct();
  const r = request;
  return (
    <Dialog open={r !== null} onClose={onClose} title={r ? t("web-pages.security.confirmTitle", { name: r.name || r.email }) : ""}
      description={r ? t("web-pages.security.confirmBody", { device: deviceName(r), name: r.name || r.email }) : ""}
      footer={r && <>
        <Button variant="ghost" onClick={() => { onClose(); act(call("lock.deny", { workspace: entry.id, device: r.device }), t("web-pages.security.deny")); }}>{t("web-pages.security.deny")}</Button>
        <Button variant="primary" onClick={() => { onClose(); act(call("lock.confirm", { workspace: entry.id, device: r.device, code: r.code }), t("web-pages.security.confirm"), t("web-pages.security.confirmed")); }}>{t("web-pages.security.confirm")}</Button>
      </>}>
      {r && <>
        <div className={css.bigCode}>{r.code}</div>
        <p className={css.note} style={{ textAlign: "center" }}>{r.kind === "web" ? t("web-pages.security.confirmWeb") : t("web-pages.security.confirmApp")}</p>
      </>}
    </Dialog>
  );
}

/** 开启安全模式: what it will sign, everything ticked but what is left out. */
export function SecurityOpen({ entry }: { entry: WorkspaceEntry }) {
  const draft = useTopic<LockDraft>({ topic: "lockDraft", workspace: entry.id }).value;
  const call = useCall();
  const act = useAct();
  const navigate = useNavigate();
  const opening = useDoing("lock.open", { workspace: entry.id });
  const back = `/w/${entry.id}/settings/security`;
  const toggle = (id: string) => void call("lock.toggle", { workspace: entry.id, id });
  if (!draft || draft.loading) return <Loading label={t("web-pages.settings.reading")} />;
  const open = () => {
    const doing = call("lock.open", { workspace: entry.id });
    act(doing, t("web-pages.security.turnOn"), t("web-pages.security.turnedOn"));
    void doing.then(() => navigate(back), () => {});
  };
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={back} label={t("web-pages.security.title")} />
      <header className={pagesCss.pageHead}><div><h1>{t("web-pages.security.openTitle")}</h1><p className={css.sub}>{t("web-pages.security.openLead")}</p></div></header>
      <Section title={t("web-pages.security.members")} actions={<span className={css.rowMeta}>{t("web-pages.security.peopleCount", { n: draft.members.length })}</span>}>
        <div className={pagesCss.card}><div className={css.rows}>
          {draft.members.map((m) => <div key={m.sub} className={css.row}><div className={css.rowText}><span className={css.rowName}>{m.name || m.email}</span><span className={css.rowMeta}>{m.email}</span></div><span className={css.rowMeta}>{ROLE[m.role] ?? m.role}</span></div>)}
        </div></div>
      </Section>
      <Section title={t("web-pages.security.devices")} actions={<span className={css.rowMeta}>{t("web-pages.security.devicesWhich")}</span>}>
        <div className={pagesCss.card}><div className={css.rows}>
          {draft.devices.map((d) => (
            <label key={d.id} className={css.row}>
              <input type="checkbox" className={css.check} checked={d.on} disabled={d.fixed} onChange={() => toggle(d.id)} />
              <div className={css.rowText}><span className={css.rowName}>{d.person} · {d.current ? t("web-pages.security.thisDevice") : deviceName(d)}</span>
                <span className={css.rowMeta}>{d.older ? t("web-pages.security.olderHow") : d.kind === "web" ? t("web-pages.security.web") : t("web-pages.security.app")}{d.current && d.kind === "app" ? ` · ${t("web-pages.security.signs")}` : ""}</span></div>
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
              <div className={css.rowText}><span className={css.rowName}>{s.name}</span>
                {s.state !== "ok" && <span className={css.rowMeta}>{s.state === "asking" ? t("web-pages.security.asking") : s.state === "old" ? t("web-pages.security.tooOld") : t("web-pages.security.offline")}</span>}</div>
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
    </div>
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

/** What a device waiting to be confirmed shows instead of the workspace's pages. */
export function SecurityWaiting({ entry, lock }: { entry: WorkspaceEntry; lock: LockView }) {
  return (
    <div className={css.waiting}>
      <ShieldCheck size={40} strokeWidth={1.4} />
      <h1 className={css.waitingTitle}>{t("web-pages.security.waitingTitle")}</h1>
      <p className={css.waitingLead}>{t("web-pages.security.waitingLead", { name: entry.name })}</p>
      <div className={css.bigCode}>{lock.me?.code}</div>
      <div className={css.waitingNote}><span className={waitingCss.spinner} aria-hidden="true" />{t("web-pages.security.waitingNote")}</div>
    </div>
  );
}
