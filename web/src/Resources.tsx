// What of the stations' machines still.fail uses (the core's `resources` view, client/core-ts/src/views/resources.ts),
// as Activity Monitor says it: four totals with the last minutes' line, then one table, grouped by whose (a chat, the
// agents, the desktop app, the station; each opens to its processes) or every process flat with its whose, filtered by
// kind and sorted by a column. A station's page draws it, its 进程 (cloud/StationPage.tsx).
import { Fragment, useState } from "react";
import { Link } from "react-router";
import { ChevronRight } from "@stillfail/ui/icons.tsx";
import { useTopic } from "./core/react.ts";
import type { ResourceGroup, ResourceTile, ResourceUse, ResourcesView } from "./core/shapes.ts";
import { stationBase } from "./station.tsx";
import { Segmented, Waiting } from "./ui.tsx";
import * as css from "./Resources.css.ts";
import { t } from "./i18n.ts";

/** `station`: that one's only; none, every station's of the workspace. */
export function useResources(scope: string, station?: string) {
  return useTopic<ResourcesView>(station === undefined ? { topic: "resources", scope } : { topic: "resources", scope, station });
}

type Column = "cpu" | "memory" | "watts" | "wakeups";
const COLUMNS: { key: Column; text: keyof ResourceUse }[] = [
  { key: "cpu", text: "cpuText" }, { key: "memory", text: "memoryText" }, { key: "watts", text: "wattsText" }, { key: "wakeups", text: "wakeupsText" },
];
const columnLabel = (c: Column) => t(`web-main.resources.column.${c}`);

/** The whole page's body, below its title. */
export function ResourcesBody({ view }: { view: ResourcesView }) {
  const [kind, setKind] = useState("all");
  const [flat, setFlat] = useState<"grouped" | "flat">("grouped");
  const [by, setBy] = useState<Column>("cpu");
  if (view.empty) {
    return (
      <div className={css.page}>
        {view.wait.reading || view.wait.failing.length > 0 ? <Waiting shape="cards" count={2} note={view.wait} /> : <p className={css.empty}>{t("web-main.resources.none")}</p>}
        <Foot view={view} basis={false} />
      </div>
    );
  }
  const groups = view.groups.filter((g) => kind === "all" || g.kind === kind);
  return (
    <div className={css.page}>
      <div className={css.tiles}>{view.tiles.map((tile) => <Tile key={tile.key} tile={tile} />)}</div>
      <div className={css.bar}>
        <Segmented className={css.kinds} label={t("web-main.resources.show")} value={kind} onChange={setKind}
          options={[{ value: "all", label: t("web-main.resources.all") }, ...view.kinds.map((k) => ({ value: k.key, label: k.label }))]} />
        <Segmented<"grouped" | "flat"> className={css.shows} label={t("web-main.resources.show")} value={flat} onChange={setFlat}
          options={[{ value: "grouped", label: t("web-main.resources.grouped") }, { value: "flat", label: t("web-main.resources.flat") }]} />
      </div>
      <div className={css.scroll}>
        {flat === "flat" ? <Flat groups={groups} by={by} setBy={setBy} /> : <Grouped groups={groups} by={by} setBy={setBy} />}
      </div>
      <Foot view={view} />
    </div>
  );
}

/** A total, said, with the last minutes' line under it. */
function Tile({ tile }: { tile: ResourceTile }) {
  return (
    <div className={css.tile}>
      <div className={css.tileHead}><span>{tile.label}</span><span className={css.tileSub}>{tile.sub}</span></div>
      <div className={css.tileValue}>{tile.value}</div>
      <Spark points={tile.points} tone={css.tone[tile.key as Column] ?? ""} />
    </div>
  );
}

function Spark({ points, tone }: { points: number[]; tone: string }) {
  if (points.length < 2) return <svg className={css.spark} aria-hidden="true" />;
  const max = Math.max(...points) || 1;
  const line = points.map((p, i) => `${i === 0 ? "M" : "L"}${((i / (points.length - 1)) * 100).toFixed(2)},${(26 - (p / max) * 24).toFixed(2)}`).join(" ");
  return (
    <svg className={`${css.spark} ${tone}`} viewBox="0 0 100 26" preserveAspectRatio="none" aria-hidden="true">
      <path className={css.sparkArea} d={`${line} L100,26 L0,26 Z`} />
      <path className={css.sparkLine} d={line} />
    </svg>
  );
}

/** The columns' heads: each sorts by itself (the most first). */
function Heads({ first, by, setBy }: { first: string[]; by: Column; setBy(c: Column): void }) {
  return (
    <thead>
      <tr>
        {first.map((h) => <th key={h} className={css.head}>{h}</th>)}
        {COLUMNS.map((c) => (
          <th key={c.key} className={`${css.head} ${css.number}`} aria-sort={c.key === by ? "descending" : "none"}>
            <button type="button" className={`${css.sortable} ${c.key === by ? css.sorted : ""}`} onClick={() => setBy(c.key)} aria-label={t("web-main.resources.by", { column: columnLabel(c.key) })}>
              {columnLabel(c.key)}{c.key === by ? " ↓" : ""}
            </button>
          </th>
        ))}
      </tr>
    </thead>
  );
}

/** A row's figures: the sorted column's bold, with how much of the most it is. */
function Figures({ use, by, max, plain = false }: { use: ResourceUse; by: Column; max: number; plain?: boolean }) {
  return COLUMNS.map((c) => (
    <td key={c.key} className={`${css.cell} ${css.number} ${!plain && c.key === by ? css.strong : ""}`}>
      {!plain && c.key === by && <span className={css.share}><span className={css.shareFill} style={{ width: `${max > 0 ? Math.min(100, (use[by] / max) * 100) : 0}%` }} /></span>}
      {use[c.text]}
    </td>
  ));
}

function chatPath(group: ResourceGroup): string | null {
  const chat = group.chat;
  if (!chat) return null;
  const id = chat.thread != null ? String(chat.thread) : chat.session;
  return id ? `${stationBase(chat.station)}/chats/${encodeURIComponent(id)}` : null;
}

/** Whose uses what, each opening to its processes. */
function Grouped({ groups, by, setBy }: { groups: ResourceGroup[]; by: Column; setBy(c: Column): void }) {
  const [open, setOpen] = useState<Set<string>>(() => new Set(groups[0] ? [groups[0].key] : []));
  const sorted = [...groups].sort((a, b) => b.use[by] - a.use[by]);
  const max = Math.max(0, ...sorted.map((g) => g.use[by]));
  const flip = (key: string) => setOpen((was) => { const now = new Set(was); if (now.has(key)) now.delete(key); else now.add(key); return now; });
  return (
    <table className={css.table}>
      <Heads first={[t("web-main.resources.column.name")]} by={by} setBy={setBy} />
      <tbody>
        {sorted.map((g) => {
          const on = open.has(g.key);
          const to = chatPath(g);
          return (
            <Fragment key={g.key}>
              <tr className={css.group} onClick={() => flip(g.key)} aria-expanded={on}>
                <td className={css.cell}>
                  <span className={css.name}>
                    <span className={`${css.toggle} ${on ? css.open : ""}`}><ChevronRight size={14} /></span>
                    <span className={css.nameText}>{to ? <Link className={css.chatLink} to={to} onClick={(e) => e.stopPropagation()}>{g.title}</Link> : g.title}</span>
                    <span className={css.meta}>{[g.kindText, String(g.processes.length)].filter(Boolean).join(" · ")}</span>
                  </span>
                </td>
                <Figures use={g.use} by={by} max={max} />
              </tr>
              {on && [...g.processes].sort((a, b) => b.use[by] - a.use[by]).map((p) => (
                <tr key={p.key} className={css.process}>
                  <td className={`${css.cell} ${css.processName}`}>{p.name} <span className={css.meta}>{p.pid}</span></td>
                  <Figures use={p.use} by={by} max={max} plain />
                </tr>
              ))}
            </Fragment>
          );
        })}
      </tbody>
    </table>
  );
}

/** Every process, with whose it is. */
function Flat({ groups, by, setBy }: { groups: ResourceGroup[]; by: Column; setBy(c: Column): void }) {
  const rows = groups.flatMap((g) => g.processes.map((p) => ({ ...p, group: g }))).sort((a, b) => b.use[by] - a.use[by]);
  const max = Math.max(0, ...rows.map((r) => r.use[by]));
  return (
    <table className={css.table}>
      <Heads first={[t("web-main.resources.column.process"), t("web-main.resources.column.whose")]} by={by} setBy={setBy} />
      <tbody>
        {rows.map((r) => {
          const to = chatPath(r.group);
          return (
            <tr key={r.key}>
              <td className={css.cell}>{r.name} <span className={css.meta}>{r.pid}</span></td>
              <td className={`${css.cell} ${css.whose}`}>{to ? <Link className={css.chatLink} to={to}>{r.group.title}</Link> : r.group.title}</td>
              <Figures use={r.use} by={by} max={max} />
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}

/** How often it is read, what is missing, how it is counted. */
function Foot({ view, basis = true }: { view: ResourcesView; basis?: boolean }) {
  return (
    <ul className={css.foot}>
      {view.everyMs > 0 && <li>{t("web-main.resources.every", { n: Math.round(view.everyMs / 1000) })}</li>}
      {view.notes.map((n) => <li key={n}>{n}</li>)}
      {basis && <li>{view.basis}</li>}
    </ul>
  );
}
