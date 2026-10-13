// Station overview: only alerts and available updates. Click its name for the complete device and software details.
import { Fragment, useEffect, useState, type ReactNode } from "react";
import { stamp, type StationView } from "../api.ts";
import type { Level, NetFigure, NetRelay, StationNet } from "../core/shapes.ts";
import { Dialog, StatusDot, Time, Tip } from "../ui.tsx";
import { UpdateSummary, Versions } from "../Versions.tsx";
import { RetryPill } from "../Connection.tsx";
import { MeterChips, MeterDials } from "../components.tsx";
import * as css from "./StationCards.css.ts";
import { MarkPick } from "./MarkPick.tsx";
import { same, type Mark } from "../stationPick.ts";
import { StationMark } from "../StationMark.tsx";
import { stationBase } from "../station.tsx";
import { Link } from "react-router";
import { ChevronRight } from "../icons.tsx";

import { NAME } from "../channel.ts";
import { t } from "../i18n.ts";
import { tx } from "./words.tsx";

/** `manager`: may update a station and its runtimes (a workspace owner or admin); `onMark`: may give it an icon or emoji. */
export function StationList({ stations, menu, manager = false, onMark, markBusy }: {
  stations: StationView[]; menu(s: StationView): ReactNode; manager?: boolean; onMark?: ((s: StationView, mark: Mark) => void) | undefined; markBusy?: ((s: StationView) => boolean) | undefined;
}) {
  return <div className={css.cards}>{stations.map((s) => <StationCard key={s.id} s={s} menu={menu(s)} manager={manager} onMark={onMark} markBusy={markBusy?.(s) ?? false} />)}</div>;
}

/**
 * A station at a glance, in a card that opens over where it is named (a chat's bar): its emoji and name, whether it is
 * up and what its agents do, what the machine is (the line it is named by everywhere), what is left of its CPU, memory
 * and disk, this device's connection to it, and its settings (`settings`, a path; the phone's sheet gives its own way
 * there, `footer`).
 */
export function StationPeek({ s, settings, footer }: { s: StationView; settings?: string; footer?: ReactNode }) {
  return (
    <div className={css.peek}>
      <div className={css.peekHead}>
        <StatusDot state={s.online ? "online" : "offline"} label={s.online ? t("web-pages.stations.online") : t("web-pages.stations.offline")} />
        {(s.emoji || s.icon) && <StationMark emoji={s.emoji} icon={s.icon} size={16} />}
        <span className={css.peekName}>{s.name}</span>
        <span className={css.state}>{state(s)}</span>
      </div>
      {s.host && <div className={css.peekLines}><Parts parts={[s.host.identity]} /></div>}
      {s.online && s.host && <div className={css.peekSection}><MeterChips meters={s.host.meters} /></div>}
      {s.online && s.net && <div className={css.peekSection}><PeekNet net={s.net} /></div>}
      {/* Its drive (docs/drive.md), where it has one: beside its settings, a way there from where it is named. */}
      {settings !== undefined && s.overview?.drive && <Link className={css.peekLink} to={`${stationBase(s.station)}/files`}><span>{t("web-pages.drive.title")}</span><ChevronRight size={14} /></Link>}
      {settings !== undefined && <Link className={css.peekLink} to={settings}><span>{t("web-pages.stations.peekSettings")}</span><ChevronRight size={14} /></Link>}
      {footer}
    </div>
  );
}

/** A line of facts joined by " · " that wraps only between them, never inside one ("up 25 days" stays whole). Its
 * parts split on the core's own " · " too, so a joined `line` breaks the same way. */
function Parts({ parts }: { parts: (string | null | undefined)[] }) {
  const each = parts.flatMap((p) => (p ? p.split(" · ") : []));
  return <span className={css.peekLine}>{each.map((p, i) => <span key={i}>{i > 0 && " · "}<span className={css.peekPart}>{p}</span></span>)}</span>;
}

/** The connection in the peek: how it goes and its round trip in a line, then ↑ and ↓ a line each, totals on the right. */
function PeekNet({ net }: { net: StationNet }) {
  const head = (
    <span className={css.peekNetHead} tabIndex={net.measured?.relays.length ? 0 : undefined}>
      <span>{net.path}{net.rtt && <>{" · "}<Figure f={net.rtt} /></>}</span>
      {net.loss && <Figure f={net.loss} />}
    </span>
  );
  return (
    <div className={css.peekNet}>
      {net.measured?.relays.length ? <Tip label={<Ways relays={net.measured.relays} />}>{head}</Tip> : head}
      <span className={css.peekRates}>
        <span>↑</span><b>{net.up}</b><span>{net.upTotal && t("web-pages.stations.total", { total: net.upTotal })}</span>
        <span>↓</span><b>{net.down}</b><span>{net.downTotal && t("web-pages.stations.total", { total: net.downTotal })}</span>
      </span>
    </div>
  );
}

/** Whether its agents are at work, or when it was last seen. */
function state(s: StationView): ReactNode {
  if (!s.online) return s.lastSeen ? tx("web-pages.stations.lastSeen", { time: <Time stamp={stamp(s, "lastSeen")} /> }) : t("web-pages.stations.neverOnline");
  if (!s.overview) return t("web-pages.stations.connecting");
  const running = s.overview.counts.running;
  return running > 0 ? <span className={css.busy}>{t("web-pages.stations.running", { n: running })}</span> : t("web-pages.stations.idle");
}

/** What may be wrong with it, each in words, worst first. */
function problems(s: StationView, silent: boolean): { key: string; level: Level; text: string }[] {
  if (s.online && silent) return [{ key: "silent", level: "amber", text: t("web-pages.stations.silent", { name: NAME }) }];
  if (!s.online) {
    return [{ key: "away", level: s.lastSeen ? "red" : "amber", text: s.lastSeen ? t("web-pages.stations.away", { name: NAME }) : t("web-pages.stations.neverConnected", { name: NAME }) }];
  }
  return [];
}

/**
 * The machine as its own page shows it, PC's details and the phone's station page alike: what it is (on the phone, its
 * page's title says it), what is left of
 * its CPU, memory and disk large over their cells (as an allowance's on its profile's page), this device's connection
 * to it, then the rest a quiet row each.
 */
export function MachineDetails({ s, phone = false }: { s: StationView; phone?: boolean }) {
  if (!s.host) return <span className={css.machineNote}>{s.online ? t("web-pages.stations.deviceLoading") : t("web-pages.stations.deviceOffline")}</span>;
  return (
    <div className={css.machine}>
      {/* The phone's page says what it is under its title. */}
      {!phone && <span className={css.machineNote}>{s.host.identity}</span>}
      {s.online && <MeterDials meters={s.host.meters} row={phone} />}
      {s.online && s.net && <Net net={s.net} flush />}
      <HostDetails details={s.host.details} phone={phone} />
    </div>
  );
}

/** The rest of a machine, a quiet row each: its hostname, chip, how long it has been up, the process. */
export function HostDetails({ details, phone = false }: { details: { label: string; value: string }[]; phone?: boolean }) {
  return (
    <dl className={css.hostDetails} data-phone={phone || undefined}>
      {details.map((d) => <Fragment key={d.label}><dt>{d.label}</dt><dd>{d.value}</dd></Fragment>)}
    </dl>
  );
}

function Figure({ f }: { f: NetFigure }) {
  return <b data-level={f.level}>{f.text}</b>;
}

/** This device's connection to it: how it goes (and packets lost, when some were) over its round trip; beside them, ↑
 * over ↓, the speed each way and what went that way since it opened, each in a column of its own. Every line stays one
 * line with room kept for its figures: nothing wraps or moves as they change. */
export function Net({ net, stacked = false, flush = false }: { net: StationNet; stacked?: boolean; flush?: boolean }) {
  const part = (
    <span className={css.netPart} tabIndex={net.measured?.relays.length ? 0 : undefined}>
      <span className={css.netLine}>
        <span>{net.path}</span>
        {net.loss && <Figure f={net.loss} />}
      </span>
      {net.rtt && <span>{tx("web-pages.stations.latency", { latency: <Figure f={net.rtt} /> })}</span>}
    </span>
  );
  return (
    <div className={stacked ? `${css.net} ${css.netStacked}` : css.net} data-flush={flush || undefined}>
      {net.measured?.relays.length ? <Tip label={<Ways relays={net.measured.relays} />}>{part}</Tip> : part}
      <span className={css.netRates}>
        <span>↑</span><b>{net.up}</b><span>{net.upTotal && t("web-pages.stations.total", { total: net.upTotal })}</span>
        <span>↓</span><b>{net.down}</b><span>{net.downTotal && t("web-pages.stations.total", { total: net.downTotal })}</span>
      </span>
    </div>
  );
}

/** Each way to the station as last pinged, on hover over how it goes: whether the one in use is the quickest. */
function Ways({ relays }: { relays: NetRelay[] }) {
  return (
    <span className={css.ways}>
      <span className={css.waysTitle}>{t("web-pages.stations.ways")}</span>
      {relays.map((r) => (
        <span key={r.name} className={css.way} data-current={r.current || undefined}>
          <span>{r.name}</span>
          {r.rtt ? <b data-level={r.rtt.level}>{r.rtt.text}</b> : <span>{t("web-pages.stations.wayNone")}</span>}
          <span>{r.current ? t("web-pages.stations.wayCurrent") : ""}</span>
        </span>
      ))}
    </span>
  );
}

/** Whether `waiting` has held for `ms`: a station that says it is online but has not answered for a while. */
function useLong(waiting: boolean, ms: number): boolean {
  const [long, setLong] = useState(false);
  useEffect(() => {
    setLong(false);
    if (!waiting) return;
    const t = setTimeout(() => setLong(true), ms);
    return () => clearTimeout(t);
  }, [waiting, ms]);
  return waiting && long;
}

function StationCard({ s, menu, manager, onMark, markBusy }: { s: StationView; menu: ReactNode; manager: boolean; onMark: ((s: StationView, mark: Mark) => void) | undefined; markBusy: boolean }) {
  const [details, setDetails] = useState(false);
  const silent = useLong(s.online && !s.host, 15_000);
  const wrong = problems(s, silent);
  return (
    <div className={css.card} data-online={s.online || undefined}>
      <div className={css.cardHead}>
        <StatusDot state={s.online ? "online" : "offline"} label={s.online ? t("web-pages.stations.online") : t("web-pages.stations.offline")} />
        <MarkPick emoji={s.emoji} icon={s.icon} name={s.name} editable={onMark !== undefined} busy={markBusy} onPick={(m) => { if (!same(m, s.emoji, s.icon)) onMark?.(s, m); }} />
        <span className={css.cardTitle}>
          <button type="button" className={css.name} onClick={() => setDetails(true)} aria-label={t("web-pages.stations.details", { name: s.name })}>{s.name}</button>
          <span className={css.state}>{state(s)}</span>
        </span>
        {s.online && s.host && <MeterChips meters={s.host.meters} alerts />}
        {/* Away or silent, it is tried again here (not beside the sidebar's line: a station may stay down for long). */}
        {(!s.online || silent) && <RetryPill />}
        <span className={css.menu}>{menu}</span>
      </div>
      {s.host && <div className={css.cardFoot}>{s.host.identity}</div>}
      {wrong.length > 0 && <div className={css.warn}>{wrong.map((p) => <span key={p.key} data-level={p.level}>{p.text}</span>)}</div>}
      {s.online && s.net && <Net net={s.net} />}
      {s.online && <div className={css.cardVersions}><UpdateSummary station={s.station} updates={s.overview?.updates} manager={manager} /></div>}
      <Dialog open={details} title={s.name} onClose={() => setDetails(false)}>
        <div className={css.details}>
          <section className={css.detailSection} aria-label={t("web-pages.stations.device")}>
            <MachineDetails s={s} />
          </section>
          <section className={css.detailSection} aria-label={t("web-pages.stations.software")}>
            <h3 className={css.detailTitle}>{t("web-pages.stations.software")}</h3>
            {s.online ? <Versions station={s.station} updates={s.overview?.updates} manager={manager} beta={s.betaOffered ?? false} rows /> : <span>{t("web-pages.stations.softwareOffline")}</span>}
            {!s.overview?.updates?.length && s.version && <span>Station {s.version}</span>}
          </section>
        </div>
      </Dialog>
    </div>
  );
}
