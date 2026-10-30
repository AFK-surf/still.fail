// Station overview: only alerts and available updates. Its name opens its own page (StationPage.tsx), where the rest is.
import { Fragment, type ReactNode } from "react";
import type { StationView } from "../api.ts";
import type { NetFigure, NetRelay, ResourceStation, ResourceUse, StationNet } from "../core/shapes.ts";
import { StatusDot, Tip } from "../ui.tsx";
import { useTopic } from "../core/react.ts";
import { UpdateSummary } from "../Versions.tsx";
import { RetryPill } from "../Connection.tsx";
import { MeterChips, MeterDials } from "../components.tsx";
import * as css from "./StationCards.css.ts";
import { MarkPick } from "./MarkPick.tsx";
import { same, type Mark } from "../stationPick.ts";
import { StationMark } from "../StationMark.tsx";
import { StationDot, useStationLink } from "../StationLink.tsx";
import { stationBase } from "../station.tsx";
import { Link } from "react-router";
import { ChevronRight } from "@stillfail/ui/icons.tsx";

import { NAME } from "../channel.ts";
import { t } from "../i18n.ts";
import { tx } from "./words.tsx";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";

/** `manager`: may update a station and its runtimes (a workspace owner or admin); `onMark`: may give it an icon or emoji. */
/** `page`: where its own page is, opened by its name. `resources`: what still.fail uses of each machine (by its station),
 * a line on its card opening its 进程 (`resourcesPage`). */
export function StationList({ stations, menu, page, manager = false, onMark, markBusy, resources, resourcesPage }: {
  stations: StationView[]; menu(s: StationView): ReactNode; page(s: StationView): string; manager?: boolean; onMark?: ((s: StationView, mark: Mark) => void) | undefined; markBusy?: ((s: StationView) => boolean) | undefined;
  resources?: ReadonlyMap<string, ResourceStation> | undefined; resourcesPage?: ((s: StationView) => string) | undefined;
}) {
  return <div className={css.cards}>{stations.map((s) => <StationCard key={s.id} s={s} menu={menu(s)} page={page(s)} manager={manager} onMark={onMark} markBusy={markBusy?.(s) ?? false}
    uses={s.online ? resources?.get(s.station) : undefined} usesPage={resourcesPage?.(s)} />)}</div>;
}

/** What still.fail uses of the machine now, in a line opening its 进程. `flush`: at its section's edge (its
 * own page), not in by a card's dot. */
export function Uses({ use, net, to, flush = false }: { use: ResourceUse; net: boolean; to: string; flush?: boolean }) {
  return (
    <Link className={css.uses} to={to} data-flush={flush || undefined}>
      <span>{t("web-pages.stations.uses", { name: NAME })}</span>
      <span className={css.usesFigures}>
        <span>CPU <b>{use.cpuText}</b></span>
        <span>{t("web-main.resources.column.memory")} <b>{use.memoryText}</b></span>
        {net && <span>{t("web-main.resources.column.net")} <b>{use.netText}</b></span>}
      </span>
      <ChevronRight size={14} />
    </Link>
  );
}

/**
 * A station at a glance, in a card that opens over where it is named (a chat's bar): its emoji and name, whether it is
 * up and what its agents do, what the machine is (the line it is named by everywhere), what is left of its CPU, memory
 * and disk, this device's connection to it, and its settings (`settings`, a path; the phone's sheet gives its own way
 * there, `footer`).
 */
export function StationPeek({ s, settings, footer, panel = false }: { s: StationView; settings?: string; footer?: ReactNode; panel?: boolean }) {
  const net = useStationNet(s.online ? s.station : null);
  const link = useStationLink(s.station);
  // In a small panel (a hover card): the card's whole room, its words in by a row's padding, its rows at the card's
  // padding (docs/ui-panels.md).
  return (
    <div className={panel ? `${css.peek} ${controlsCss.panelCard} ${controlsCss.panelEdge}` : css.peek}>
      <div className={css.peekHead}>
        {/* The same dot as on its tile in the chat's bar: how this device reaches it, not only whether it is up. */}
        {link ? <StationDot link={link} /> : <StatusDot state={s.online ? "online" : "offline"} label={s.online ? t("web-pages.stations.online") : t("web-pages.stations.offline")} />}
        {(s.emoji || s.icon) && <StationMark emoji={s.emoji} icon={s.icon} size={16} />}
        <span className={css.peekName}>{s.name}</span>
        <span className={css.state}>{state(s)}</span>
      </div>
      {s.host && <div className={css.peekLines}><Parts parts={[s.host.identity]} /></div>}
      {s.online && s.host && <div className={css.peekSection}><MeterChips meters={s.host.meters} /></div>}
      {net && <div className={css.peekSection}><PeekNet net={net} /></div>}
      {/* Its drive (docs/drive.md), where it has one: beside its settings, a way there from where it is named. */}
      {settings !== undefined && s.overview?.drive && <Link className={`${css.peekLink} ${controlsCss.panelEdge}`} to={`${stationBase(s.station)}/files`}><span>{t("web-pages.drive.title")}</span><ChevronRight size={14} /></Link>}
      {settings !== undefined && <Link className={`${css.peekLink} ${controlsCss.panelEdge}`} to={settings}><span>{t("web-pages.stations.peekSettings")}</span><ChevronRight size={14} /></Link>}
      {footer}
    </div>
  );
}

/** This device's connection to a station with its figures (the `stationNet` view), for where they are drawn: sampled
 * while something shows them. Null for none (`station` null: one away), or before a connection of its own is open. */
export function useStationNet(station: string | null): StationNet | null {
  return useTopic<StationNet | null>(station === null ? null : { topic: "stationNet", station }).value ?? null;
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

/** Where a station the workspace joined is from (its home workspace, which manages the machine: docs/multi-workspace.md),
 * in words; null for one whose home is here. */
export function joinedText(s: StationView): string | null {
  if (!s.joined) return null;
  return s.home ? t("web-pages.stations.joinedFrom", { name: s.home }) : t("web-pages.stations.joinedElsewhere");
}

/** How it is in a few words (the core's `stateText`): its agents at work in the accent. */
export function state(s: StationView): ReactNode {
  return s.stateBusy ? <span className={css.busy}>{s.stateText}</span> : s.stateText;
}

/** Whether it is silent though up: no host reading for a while (the core's `problems`). */
export function silentOf(s: StationView): boolean {
  return s.problems.some((p) => p.key === "silent");
}

/**
 * The machine as its own page shows it, PC's details and the phone's station page alike: what it is (on the phone, its
 * page's title says it), what is left of
 * its CPU, memory and disk large over their cells (as an allowance's on its profile's page), this device's connection
 * to it, then the rest a quiet row each.
 */
export function MachineDetails({ s, phone = false }: { s: StationView; phone?: boolean }) {
  const net = useStationNet(s.online && s.host ? s.station : null);
  if (!s.host) return <span className={css.machineNote}>{s.online ? t("web-pages.stations.deviceLoading") : t("web-pages.stations.deviceOffline")}</span>;
  return (
    <div className={css.machine}>
      {/* The phone's page says what it is under its title. */}
      {!phone && <span className={css.machineNote}>{s.host.identity}</span>}
      {s.online && <MeterDials meters={s.host.meters} row={phone} />}
      {net && <Net net={net} flush />}
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

function StationCard({ s, menu, page, manager, onMark, markBusy, uses, usesPage }: {
  s: StationView; menu: ReactNode; page: string; manager: boolean; onMark: ((s: StationView, mark: Mark) => void) | undefined; markBusy: boolean; uses: ResourceStation | undefined; usesPage: string | undefined;
}) {
  const silent = silentOf(s);
  const wrong = s.problems;
  const foot = [s.host?.identity, joinedText(s)].filter(Boolean).join(" · ");
  const net = useStationNet(s.online ? s.station : null);
  return (
    <div className={css.card} data-online={s.online || undefined}>
      <div className={css.cardHead}>
        <StatusDot state={s.online ? "online" : "offline"} label={s.online ? t("web-pages.stations.online") : t("web-pages.stations.offline")} />
        <MarkPick emoji={s.emoji} icon={s.icon} name={s.name} editable={onMark !== undefined} busy={markBusy} onPick={(m) => { if (!same(m, s.emoji, s.icon)) onMark?.(s, m); }} />
        <span className={css.cardTitle}>
          <Link className={css.name} to={page} aria-label={t("web-pages.stations.details", { name: s.name })}>{s.name}</Link>
          <span className={css.state}>{state(s)}</span>
        </span>
        {s.online && s.host && <MeterChips meters={s.host.meters} alerts />}
        {/* Away or silent, it is tried again here (not beside the sidebar's line: a station may stay down for long). */}
        {(!s.online || silent) && <RetryPill trying={s.link.retrying === true} />}
        <span className={css.menu}>{menu}</span>
      </div>
      {foot && <div className={css.cardFoot}>{foot}</div>}
      {wrong.length > 0 && <div className={css.warn}>{wrong.map((p) => <span key={p.key} data-level={p.level}>{p.text}</span>)}</div>}
      {net && <Net net={net} />}
      {uses && usesPage && <Uses use={uses.use} net={uses.net} to={usesPage} />}
      {s.online && <div className={css.cardVersions}><UpdateSummary station={s.station} updates={s.overview?.updates} manager={manager} /></div>}
    </div>
  );
}
