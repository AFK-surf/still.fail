// What the agents spent (the core's `usage` view, client/core/src/views/usage.rs): a few totals, each day's cost split by
// who it was for, and who, which chats, which accounts and which models spent the most. The settings page draws it on
// the wide screen (cloud/settings.tsx UsageSettings), the phone's its own page around the same chart
// (mobile/Usage.tsx). Everything shown is the core's: the page only picks 7 or 30 days and which list to show.
import { useState } from "react";
import { Link } from "react-router";
import { useTopic } from "./core/react.ts";
import type { UsageDay, UsageItem, UsageList, UsageSeries, UsageView } from "./core/shapes.ts";
import { stationBase } from "./station.tsx";
import { Avatar, Segmented, Tip } from "./ui.tsx";
import * as css from "./Usage.css.ts";

export type UsageDays = "7" | "30";
export const DAYS: { value: UsageDays; label: string }[] = [{ value: "7", label: "7 天" }, { value: "30", label: "30 天" }];

export function useUsage(scope: string, days: UsageDays) {
  return useTopic<UsageView>({ topic: "usage", scope, days: Number(days) });
}

/** A series' colour: the first four people's own, the rest grey. */
export function seriesClass(series: UsageSeries[], i: number): string {
  return series[i]?.key === "" ? css.series.rest : css.series[(i % 4) as 0 | 1 | 2 | 3];
}

/** A chat in the lists: its page, by its thread or its agent. */
export function chatPath(item: UsageItem): string | null {
  const chat = item.chat;
  if (!chat) return null;
  const id = chat.thread != null ? String(chat.thread) : chat.session;
  return id ? `${stationBase(chat.station)}/chats/${encodeURIComponent(id)}` : null;
}

export function Tiles({ view }: { view: UsageView }) {
  return (
    <div className={css.tiles}>
      {view.tiles.map((t) => (
        <div key={t.label} className={css.tile}>
          <span className={css.tileLabel}>{t.label}</span>
          <span className={css.tileValue}>{t.value}</span>
          <span className={css.tileSub}>{t.sub}</span>
        </div>
      ))}
    </div>
  );
}

/** Each day's cost as a bar, split by who it was for; the day's numbers on hover. */
export function DaysChart({ view }: { view: UsageView }) {
  const many = view.daily.length > 10;
  const several = view.series.length > 1;
  return (
    <div>
      <div className={css.chartHead}>
        {several && (
          <div className={css.legend}>
            {view.series.map((s, i) => <span key={s.key} className={css.legendItem}><span className={`${css.swatch} ${seriesClass(view.series, i)}`} />{s.name}</span>)}
          </div>
        )}
        {view.max > 0 && <span className={css.top}>最多一天 {view.daily.find((d) => d.cost === view.max)?.costText}</span>}
      </div>
      <div className={css.plot} data-many={many || undefined}>
        {view.max > 0 && <span className={css.ceiling} />}
        {view.daily.map((d) => <Day key={d.day} day={d} view={view} />)}
      </div>
      <div className={css.labels} data-many={many || undefined}>
        {view.daily.map((d, i) => (
          <span key={d.day} className={css.label} data-today={d.today || undefined}>
            {!many || d.today || (view.daily.length - 1 - i) % 7 === 0 ? (d.today ? "今天" : d.label) : ""}
          </span>
        ))}
      </div>
    </div>
  );
}

function Day({ day, view }: { day: UsageDay; view: UsageView }) {
  const height = view.max > 0 ? (day.cost / view.max) * 100 : 0;
  const tip = (
    <span>
      <span className={css.tipHead}>{day.today ? "今天" : day.label} · {day.costText}</span>
      <span>{day.callsText}</span>
      {view.series.length > 1 && day.cost > 0 && view.series.map((s, i) => (day.parts[i] ?? 0) > 0 && (
        <span key={s.key} className={css.tipRow}><span className={`${css.swatch} ${seriesClass(view.series, i)}`} />{s.name}<span className={css.tipValue}>{day.partsText[i]}</span></span>
      ))}
    </span>
  );
  return (
    <Tip label={tip} side="top">
      <button type="button" className={css.day} aria-label={`${day.label} ${day.costText}`}>
        <span className={css.bar} style={{ height: `${height}%` }}>
          {day.parts.map((p, i) => p > 0 && <span key={i} className={`${css.part} ${seriesClass(view.series, i)}`} style={{ height: `${(p / day.cost) * 100}%` }} />)}
        </span>
      </button>
    </Tip>
  );
}

/** One of the lists: the most spent first, the first few until asked for all. */
export function Ranking({ list, first = 8, open }: { list: UsageList; first?: number; open?: (path: string) => void }) {
  const [all, setAll] = useState(false);
  const shown = all ? list.items : list.items.slice(0, first);
  return (
    <div className={css.rows}>
      {shown.map((item, i) => <Row key={item.key} item={item} rank={i + 1} kind={list.key} open={open} />)}
      {list.items.length > first && <button type="button" className={css.more} onClick={() => setAll(!all)}>{all ? "收起" : `显示全部 ${list.items.length} 个`}</button>}
    </div>
  );
}

/** `open`: how a chat's page is gone to (the phone's own way); else a link. */
function Row({ item, rank, kind, open }: { item: UsageItem; rank: number; kind: string; open?: ((path: string) => void) | undefined }) {
  const lead = kind === "people" && item.person
    ? <span className={css.face}>{item.person.shown?.picture
      ? <img src={item.person.shown.picture} alt="" width={20} height={20} referrerPolicy="no-referrer" />
      : <Avatar id={item.person.email ?? item.person.id} name={item.person.shown?.name ?? item.title} size={20} />}</span>
    : <span className={css.rank}>{rank}</span>;
  const body = (
    <>
      {lead}
      <span className={css.rowText}>
        <span className={css.rowTitle}>{item.title}</span>
        <span className={css.rowSub}>{[item.sub, item.detail].filter(Boolean).join(" · ")}</span>
      </span>
      <span className={css.rowCost}><b>{item.costText}</b><span className={css.rowShare}>{item.shareText}</span></span>
      <span className={css.share}><span className={css.shareFill} style={{ width: `${Math.max(item.share * 100, item.share > 0 ? 1 : 0)}%` }} /></span>
    </>
  );
  const to = kind === "chats" ? chatPath(item) : null;
  if (to && open) return <button type="button" className={css.row} onClick={() => open(to)}>{body}</button>;
  return to ? <Link className={css.row} to={to}>{body}</Link> : <div className={css.row}>{body}</div>;
}

/** The lists, one at a time. */
export function Rankings({ view }: { view: UsageView }) {
  const [shown, setShown] = useState("people");
  const list = view.lists.find((l) => l.key === shown) ?? view.lists[0];
  if (!list) return null;
  return (
    <div>
      <div className={css.listHead}>
        <Segmented className={css.pickLists} label="按什么排" value={list.key} onChange={setShown} options={view.lists.map((l) => ({ value: l.key, label: l.title }))} />
      </div>
      <Ranking key={list.key} list={list} />
    </div>
  );
}

export function Notes({ view }: { view: UsageView }) {
  return (
    <ul className={css.notes}>
      {view.notes.map((n) => <li key={n}>{n}</li>)}
      <li>{view.basis}</li>
    </ul>
  );
}

/** The whole page's body, below its title: the totals, the days, the lists, what is missing. */
export function UsageBody({ view }: { view: UsageView }) {
  return (
    <div className={css.usage}>
      <Tiles view={view} />
      {view.empty ? <p className={css.empty}>{view.loading ? "正在读取…" : "这段时间没有用量"}</p> : (
        <>
          <DaysChart view={view} />
          <Rankings view={view} />
        </>
      )}
      <Notes view={view} />
    </div>
  );
}

export { css as usageCss };
