// Station overview: only alerts and available updates. Click its name for the complete device and software details.
import { useEffect, useState, type ReactNode } from "react";
import { stamp, type StationView } from "../api.ts";
import type { Host, Level, NetFigure, StationNet } from "../core/shapes.ts";
import { Dialog, StatusDot, Time } from "../ui.tsx";
import { UpdateSummary, Versions } from "../Versions.tsx";
import { RetryPill } from "../Connection.tsx";
import { MeterChips } from "../components.tsx";
import * as css from "./StationCards.css.ts";

import { NAME } from "../channel.ts";

/** `manager`: may update a station and its runtimes (a workspace owner or admin). */
export function StationList({ stations, menu, manager = false }: { stations: StationView[]; menu(s: StationView): ReactNode; manager?: boolean }) {
  return <div className={css.cards}>{stations.map((s) => <StationCard key={s.id} s={s} menu={menu(s)} manager={manager} />)}</div>;
}

/** Whether its agents are at work, or when it was last seen. */
function state(s: StationView): ReactNode {
  if (!s.online) return s.lastSeen ? <><Time stamp={stamp(s, "lastSeen")} />在线</> : "还没上线";
  if (!s.overview) return "正在连接…";
  const running = s.overview.counts.running;
  return running > 0 ? <span className={css.busy}>{running} 个 agent 在跑</span> : "空闲";
}

/** What may be wrong with it, each in words, worst first. */
function problems(s: StationView, silent: boolean): { key: string; level: Level; text: string }[] {
  if (s.online && silent) return [{ key: "silent", level: "amber", text: `没有回应：${NAME} cloud 说它在线，但一直读不到它的状态，那台机器可能断网或睡眠了` }];
  if (!s.online) {
    return [{ key: "away", level: s.lastSeen ? "red" : "amber", text: s.lastSeen ? `离线：在那台机器上打开 ${NAME}，它就会重新连上` : `还没连上过：在那台机器上打开 ${NAME}` }];
  }
  return [];
}

/** What the machine is, in a line: its chip, system, cores and memory, and how long it has been up. */
function machine(host: Host | undefined): string {
  if (!host) return "";
  return [host.cpuModel, host.line].filter(Boolean).join(" · ");
}

function Figure({ f }: { f: NetFigure }) {
  return <b data-level={f.level}>{f.text}</b>;
}

/** This device's connection to it: how it goes (and packets lost, when some were) over its round trip; beside them, ↑
 * over ↓, the speed each way and what went that way since it opened, each in a column of its own. Every line stays one
 * line with room kept for its figures: nothing wraps or moves as they change. */
export function Net({ net, stacked = false }: { net: StationNet; stacked?: boolean }) {
  return (
    <div className={stacked ? `${css.net} ${css.netStacked}` : css.net}>
      <span className={css.netPart}>
        <span className={css.netLine}>
          <span>{net.path}</span>
          {net.loss && <Figure f={net.loss} />}
        </span>
        {net.rtt && <span>当前延时 <Figure f={net.rtt} /></span>}
      </span>
      <span className={css.netRates}>
        <span>↑</span><b>{net.up}</b><span>{net.upTotal && `共 ${net.upTotal}`}</span>
        <span>↓</span><b>{net.down}</b><span>{net.downTotal && `共 ${net.downTotal}`}</span>
      </span>
    </div>
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

function StationCard({ s, menu, manager }: { s: StationView; menu: ReactNode; manager: boolean }) {
  const [details, setDetails] = useState(false);
  const silent = useLong(s.online && !s.host, 15_000);
  const wrong = problems(s, silent);
  return (
    <div className={css.card} data-online={s.online || undefined}>
      <div className={css.cardHead}>
        <StatusDot state={s.online ? "online" : "offline"} label={s.online ? "在线" : "离线"} />
        <span className={css.cardTitle}>
          <button type="button" className={css.name} onClick={() => setDetails(true)} aria-label={`查看 ${s.name} 详情`}>{s.name}</button>
          <span className={css.state}>{state(s)}</span>
        </span>
        {s.online && s.host && <MeterChips meters={s.host.meters} alerts />}
        {/* Away or silent, it is tried again here (not beside the sidebar's line: a station may stay down for long). */}
        {(!s.online || silent) && <RetryPill />}
        <span className={css.menu}>{menu}</span>
      </div>
      {wrong.length > 0 && <div className={css.warn}>{wrong.map((p) => <span key={p.key} data-level={p.level}>{p.text}</span>)}</div>}
      {s.online && s.net && <Net net={s.net} />}
      {s.online && <div className={css.cardVersions}><UpdateSummary station={s.station} updates={s.overview?.updates} manager={manager} /></div>}
      <Dialog open={details} title={s.name} onClose={() => setDetails(false)}>
        <div className={css.details}>
          <section className={css.detailSection} aria-label="设备信息">
            <h3 className={css.detailTitle}>设备信息</h3>
            {s.host ? <>
              <span>{machine(s.host)}</span>
              <span>{s.host.hostname} · {s.host.arch} · {s.host.emberText}</span>
              <MeterChips meters={s.host.meters} />
              {s.host.meters.map((m) => <span key={m.label}>{m.label} · {m.value}{m.note ? ` · ${m.note}` : ""}</span>)}
            </> : <span>{s.online ? "正在读取设备信息…" : "离线，暂无设备信息"}</span>}
            <span className={css.mono}>{s.id}</span>
          </section>
          <section className={css.detailSection} aria-label="软件与更新">
            <h3 className={css.detailTitle}>软件与更新</h3>
            {s.online ? <Versions station={s.station} updates={s.overview?.updates} manager={manager} beta={s.betaOffered ?? false} rows /> : <span>station 离线，连接后可查看更新</span>}
            {!s.overview?.updates?.length && s.version && <span>still.fail station {s.version}</span>}
          </section>
        </div>
      </Dialog>
    </div>
  );
}
