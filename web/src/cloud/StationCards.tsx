// A workspace's stations, in its settings (cloud/settings.tsx): a card each, made so what may be wrong with one is
// seen at a glance. What is wrong (it is away, a meter running out) is said in words under its name, in colour; the
// rest (its meters as dials, what the machine is) stays grey.
import { useEffect, useState, type ReactNode } from "react";
import { stamp, type StationView } from "../api.ts";
import type { Host, Level } from "../core/shapes.ts";
import { StatusDot, Time, Tip } from "../ui.tsx";
import { Versions } from "../Versions.tsx";
import * as css from "./StationCards.css.ts";

type Meter = Host["meters"][number];

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
  if (s.online && silent) return [{ key: "silent", level: "amber", text: "没有回应：still.fail cloud 说它在线，但一直读不到它的状态，那台机器可能断网或睡眠了" }];
  if (!s.online) {
    return [{ key: "away", level: s.lastSeen ? "red" : "amber", text: s.lastSeen ? "离线：在那台机器上打开 still.fail，它就会重新连上" : "还没连上过：在那台机器上打开 still.fail" }];
  }
  const said: Record<string, (m: Meter) => string> = {
    CPU: (m) => `${m.label} ${m.value}`,
    内存: (m) => `内存快满了：${m.value}`,
    磁盘: (m) => `磁盘快满了：${m.value}`,
  };
  return (s.host?.meters ?? [])
    .filter((m) => m.level !== "ok")
    .sort((a, b) => (a.level === "red" ? 0 : 1) - (b.level === "red" ? 0 : 1))
    .map((m) => ({ key: m.label, level: m.level, text: (said[m.short] ?? ((m) => `${m.label} ${m.percent}%`))(m) }));
}

/** What the machine is, in a line: its chip, system, cores and memory, and how long it has been up. */
function machine(host: Host | undefined): string {
  if (!host) return "";
  return [host.cpuModel, host.line].filter(Boolean).join(" · ");
}

function Dial({ m }: { m: Meter }) {
  const size = 34, r = (size - 4) / 2, c = 2 * Math.PI * r;
  return (
    <Tip label={`${m.label} ${m.value}${m.note ? ` · ${m.note}` : ""}`}><span className={css.dial} data-level={m.level}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden="true">
        <circle className={css.dialTrack} cx={size / 2} cy={size / 2} r={r} />
        <circle className={css.dialFill} cx={size / 2} cy={size / 2} r={r} strokeDasharray={`${(c * m.percent) / 100} ${c}`} transform={`rotate(-90 ${size / 2} ${size / 2})`} />
        <text x="50%" y="50%" dominantBaseline="central" textAnchor="middle">{m.percent}</text>
      </svg>
      <span>{m.short}</span>
    </span></Tip>
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
  const wrong = problems(s, useLong(s.online && !s.host, 15_000));
  return (
    <div className={css.card} data-online={s.online || undefined}>
      <div className={css.cardHead}>
        <StatusDot state={s.online ? "online" : "offline"} label={s.online ? "在线" : "离线"} />
        <span className={css.cardTitle}>
          <span className={css.name}>{s.name}</span>
          <span className={css.state}>{state(s)}</span>
        </span>
        {s.online && s.host && <span className={css.dials}>{s.host.meters.map((m) => <Dial key={m.label} m={m} />)}</span>}
        <span className={css.menu}>{menu}</span>
      </div>
      {wrong.length > 0 && <div className={css.warn}>{wrong.map((p) => <span key={p.key} data-level={p.level}>{p.text}</span>)}</div>}
      <div className={css.cardFoot}>
        {s.online && <span>{machine(s.host) || "正在读取设备信息…"}</span>}
        {/* A station that says its versions says the station's among them; one older, only what the cloud knows. */}
        <span className={css.ident}>{s.version && !s.overview?.updates?.length ? `stillfail-station ${s.version} · ` : ""}<span className={css.mono}>{s.id.slice(0, 12)}</span></span>
      </div>
      {s.online && <div className={css.cardVersions}><Versions station={s.station} updates={s.overview?.updates} manager={manager} /></div>}
    </div>
  );
}
