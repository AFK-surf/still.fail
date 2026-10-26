// What of the stations' machines still.fail uses (the core's `resources` view, client/core-ts/src/views/resources.ts),
// as Activity Monitor says it: its totals (CPU, memory, network) with the last minutes' line, then one table, grouped by whose (a chat, the
// agents, the desktop app, the station; each opens to its processes) or every process flat with its whose, filtered by
// kind and sorted by a column; a chat's process (not its agent's own) ended from its row, asked first. A station's page
// draws it, its 进程 (cloud/StationPage.tsx).
import { Fragment, useState } from "react";
import { Link } from "react-router";
import { ChevronRight, Stop } from "@stillfail/ui/icons.tsx";
import { failure, useToast } from "@stillfail/ui/toast.tsx";
import { useCall, useTopic } from "./core/react.ts";
import type { ResourceGroup, ResourceProcess, ResourceTile, ResourceUse, ResourcesView } from "./core/shapes.ts";
import { stationBase } from "./station.tsx";
import { Confirm, IconButton, Segmented, Waiting } from "./ui.tsx";
import * as css from "./Resources.css.ts";
import { t } from "./i18n.ts";
import { sampleResources } from "./samples.ts";

/** `station`: that one's only; none, every station's of the workspace. */
export function useResources(scope: string, station?: string) {
  return useTopic<ResourcesView>(station === undefined ? { topic: "resources", scope } : { topic: "resources", scope, station });
}

type Column = "cpu" | "memory" | "net" | "disk";
const ALL: { key: Column; text: keyof ResourceUse }[] = [
  { key: "cpu", text: "cpuText" }, { key: "memory", text: "memoryText" }, { key: "net", text: "netText" }, { key: "disk", text: "diskText" },
];
/// The network's and the disk's columns only where some station reads them.
const columnsOf = (net: boolean, disk: boolean) => ALL.filter((c) => (c.key !== "net" || net) && (c.key !== "disk" || disk));
/// A process to end, with its chat's.
type Ending = { process: ResourceProcess; group: ResourceGroup };
type Columns = typeof ALL;
const columnLabel = (c: Column) => t(`web-main.resources.column.${c}`);

/** The whole page's body, below its title. */
export function ResourcesBody({ view }: { view: ResourcesView }) {
  const [kind, setKind] = useState("all");
  const [flat, setFlat] = useState<"grouped" | "flat">("grouped");
  const [by, setBy] = useState<Column>("cpu");
  const [ending, setEnding] = useState<Ending | null>(null);
  const call = useCall();
  const toast = useToast();
  const end = (e: Ending) => {
    setEnding(null);
    if (!e.group.session) return;
    void (call("process.end", { station: e.group.station, pid: e.process.pid, session: e.group.session }) as Promise<unknown>)
      .then(() => toast(t("web-main.resources.ended", { name: e.process.name })))
      .catch((err: unknown) => toast(t("web-main.resources.endFailed", { name: e.process.name, error: failure(err) })));
  };
  // (nothing read yet: what will come, made up, in its bones)
  if (view.empty && (view.wait.reading || view.wait.failing.length > 0)) return <Waiting note={view.wait} sample={<ResourcesBody view={SAMPLE_RESOURCES} />} />;
  if (view.empty) {
    return (
      <div className={css.page}>
        <p className={css.empty}>{t("web-main.resources.none")}</p>
        <Foot view={view} basis={false} />
      </div>
    );
  }
  const groups = view.groups.filter((g) => kind === "all" || g.kind === kind);
  const columns = columnsOf(view.net, view.disk);
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
        {flat === "flat" ? <Flat groups={groups} columns={columns} by={by} setBy={setBy} onEnd={setEnding} /> : <Grouped groups={groups} columns={columns} by={by} setBy={setBy} onEnd={setEnding} />}
      </div>
      <Foot view={view} />
      <Confirm open={ending !== null} onClose={() => setEnding(null)} onConfirm={() => { if (ending) end(ending); }}
        title={t("web-main.resources.endTitle", { name: ending?.process.name ?? "", pid: ending?.process.pid ?? 0 })}
        description={t("web-main.resources.endBody", { chat: ending?.group.title ?? "" })} action={t("web-main.resources.end")} />
    </div>
  );
}

/** What a machine's still.fail uses made up, for what the pages show while it is read (in their bones). */
export const SAMPLE_RESOURCES = sampleResources();

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
function Heads({ first, columns, by, setBy }: { first: string[]; columns: Columns; by: Column; setBy(c: Column): void }) {
  // The last column: the way to end a row's process.
  return (
    <thead>
      <tr>
        {first.map((h) => <th key={h} className={css.head}>{h}</th>)}
        {columns.map((c) => (
          <th key={c.key} className={`${css.head} ${css.number}`} aria-sort={c.key === by ? "descending" : "none"}>
            <button type="button" className={`${css.sortable} ${c.key === by ? css.sorted : ""}`} onClick={() => setBy(c.key)} aria-label={t("web-main.resources.by", { column: columnLabel(c.key) })}>
              {columnLabel(c.key)}{c.key === by ? " ↓" : ""}
            </button>
          </th>
        ))}
        <th className={css.head} aria-hidden="true" />
      </tr>
    </thead>
  );
}

/** A row's figures: the sorted column's bold, with how much of the most it is. */
function Figures({ use, columns, by, max, plain = false }: { use: ResourceUse; columns: Columns; by: Column; max: number; plain?: boolean }) {
  return columns.map((c) => (
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
function Grouped({ groups, columns, by, setBy, onEnd }: { groups: ResourceGroup[]; columns: Columns; by: Column; setBy(c: Column): void; onEnd(e: Ending): void }) {
  const [open, setOpen] = useState<Set<string>>(() => new Set(groups[0] ? [groups[0].key] : []));
  const sorted = [...groups].sort((a, b) => b.use[by] - a.use[by]);
  const max = Math.max(0, ...sorted.map((g) => g.use[by]));
  const flip = (key: string) => setOpen((was) => { const now = new Set(was); if (now.has(key)) now.delete(key); else now.add(key); return now; });
  return (
    <table className={css.table}>
      <Heads first={[t("web-main.resources.column.name")]} columns={columns} by={by} setBy={setBy} />
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
                <Figures columns={columns} use={g.use} by={by} max={max} />
                <td className={css.cell} />
              </tr>
              {on && [...g.processes].sort((a, b) => b.use[by] - a.use[by]).map((p) => (
                <tr key={p.key} className={`${css.process} ${css.row}`}>
                  <td className={`${css.cell} ${css.processName}`}>{p.name} <span className={css.meta}>{p.pid}</span></td>
                  <Figures columns={columns} use={p.use} by={by} max={max} plain />
                  <EndCell process={p} onEnd={() => onEnd({ process: p, group: g })} />
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
function Flat({ groups, columns, by, setBy, onEnd }: { groups: ResourceGroup[]; columns: Columns; by: Column; setBy(c: Column): void; onEnd(e: Ending): void }) {
  const rows = groups.flatMap((g) => g.processes.map((p) => ({ ...p, group: g }))).sort((a, b) => b.use[by] - a.use[by]);
  const max = Math.max(0, ...rows.map((r) => r.use[by]));
  return (
    <table className={css.table}>
      <Heads first={[t("web-main.resources.column.process"), t("web-main.resources.column.whose")]} columns={columns} by={by} setBy={setBy} />
      <tbody>
        {rows.map((r) => {
          const to = chatPath(r.group);
          return (
            <tr key={r.key} className={css.row}>
              <td className={css.cell}>{r.name} <span className={css.meta}>{r.pid}</span></td>
              <td className={`${css.cell} ${css.whose}`}>{to ? <Link className={css.chatLink} to={to}>{r.group.title}</Link> : r.group.title}</td>
              <Figures columns={columns} use={r.use} by={by} max={max} />
              <EndCell process={r} onEnd={() => onEnd({ process: r, group: r.group })} />
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}

/** Its row's end: a way to end the process, where it may be ended (a chat's, not its agent's own), seen as the row is
 * pointed at. */
function EndCell({ process: p, onEnd }: { process: ResourceProcess; onEnd(): void }) {
  return (
    <td className={`${css.cell} ${css.endCell}`}>
      {p.endable && <IconButton className={css.end} icon={Stop} label={t("web-main.resources.endLabel", { name: p.name })} onClick={onEnd} />}
    </td>
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
