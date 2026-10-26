// What the agents spent (the core's `usage` view, client/core-ts/src/views/usage.ts): a few totals, each day's cost split by
// who it was for, and who, which chats, which accounts and which models spent the most. The settings page draws it on
// the wide screen (cloud/settings.tsx UsageSettings), the phone's its own page around the same chart
// (mobile/Usage.tsx). Everything shown is the core's: the page only picks 7 or 30 days and which list to show.
import { useState } from "react";
import { Link } from "react-router";
import { useTopic } from "./core/react.ts";
import type { UsageDay, UsageItem, UsageList, UsageSeries, UsageView } from "./core/shapes.ts";
import { stationBase } from "./station.tsx";
import { Avatar, Segmented, Waiting } from "./ui.tsx";
import { sampleUsage } from "./samples.ts";
import * as css from "./Usage.css.ts";
import * as conversationCss from "./styles/conversation.css.ts";
import * as proseCss from "./Prose.css.ts";
import { t } from "./i18n.ts";

export type UsageDays = "7" | "30";
export const DAYS: { value: UsageDays; label: string }[] = [
  { value: "7", get label() { return t("web-main.usage.days", { n: 7 }); } },
  { value: "30", get label() { return t("web-main.usage.days", { n: 30 }); } },
];

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

export function Tiles({ view, pricesPath }: { view: UsageView; pricesPath?: string | undefined }) {
  return (
    <div className={css.tiles}>
      {view.tiles.map((tile, i) => {
        const content = <><span className={css.tileLabel}>{tile.label}</span><span className={css.tileValue}>{tile.value}</span><span className={css.tileSub}>{i === 0 && pricesPath ? t("web-main.usage.seePrices") : tile.sub}</span></>;
        return i === 0 && pricesPath ? <Link key={tile.label} className={`${css.tile} ${css.tileLink}`} to={pricesPath} aria-label={t("web-main.usage.costPrices")}>{content}</Link>
          : <div key={tile.label} className={css.tile}>{content}</div>;
      })}
    </div>
  );
}

/**
 * Each day's cost as a bar on the scale's lines, split by who it was for: the day picked (today at first) says its
 * numbers over them, and with several people what each of them spent that day under them. A day pointed at says its
 * numbers while it is (the wide screen); a click or a tap picks it.
 */
export function DaysChart({ view }: { view: UsageView }) {
  const many = view.many ?? false;
  const several = view.series.length > 1;
  const [picked, setPicked] = useState<string | null>(null);
  const [pointed, setPointed] = useState<string | null>(null);
  const day = view.daily.find((d) => d.day === pointed) ?? view.daily.find((d) => d.day === picked) ?? view.daily[view.daily.length - 1];
  return (
    <div>
      {day && (
        <div className={css.dayHead}>
          <span className={css.dayName}>{day.name}</span>
          <span className={css.dayFigures}><span className={css.dayCost}>{day.costText}</span><span className={css.dayCalls}>{day.callsText}</span></span>
        </div>
      )}
      <div className={css.plot}>
        {view.top > 0 && view.ticks.map((tick) => (
          <span key={tick.value} className={css.tick} style={{ bottom: `${(tick.value / view.top) * 100}%` }}><span className={css.tickLabel}>{tick.label}</span></span>
        ))}
        <div className={css.days} data-many={many || undefined} onPointerLeave={() => setPointed(null)}>
          {view.daily.map((d) => (
            <button key={d.day} type="button" className={css.day} aria-label={`${d.label} ${d.costText}`} aria-pressed={d.day === day?.day}
              onClick={() => setPicked(d.day)} onPointerEnter={(e) => e.pointerType === "mouse" && setPointed(d.day)}>
              <Bar day={d} view={view} many={many} />
            </button>
          ))}
        </div>
      </div>
      <div className={css.labels} data-many={many || undefined}>
        {view.daily.map((d) => (
          <span key={d.day} className={css.label} data-on={d.day === day?.day || undefined}>
            {d.tick}
          </span>
        ))}
      </div>
      {several && day && (
        <div className={css.dayRows}>
          {view.series.map((s, i) => {
            const share = day.shares?.[i] ?? 0;
            return (
              <div key={s.key} className={css.dayRow}>
                <span className={`${css.dayDot} ${seriesClass(view.series, i)}`} />
                <span className={css.dayWho}>{s.name}</span>
                <span className={css.dayPart}>{day.partsText[i] ?? ""}</span>
                <span className={css.dayShare}><span className={seriesClass(view.series, i)} style={{ width: `${share * 100}%` }} /></span>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

/** A day's bar, as high as its share of the scale's top: its people's parts one over another, the first at the foot, 1 apart, each round at its ends but the foot's. */
function Bar({ day, view, many }: { day: UsageDay; view: UsageView; many: boolean }) {
  if (view.top <= 0 || day.cost <= 0) return null;
  return (
    <span className={css.bar} data-many={many || undefined} style={{ height: `${Math.min(1, day.cost / view.top) * 100}%` }}>
      {day.parts.map((p, i) => p > 0 && <span key={i} className={`${css.part} ${seriesClass(view.series, i)}`} style={{ flexGrow: p }} />)}
    </span>
  );
}

/** One of the lists: the most spent first, the first few until asked for all. */
export function Ranking({ list, first = 8, open }: { list: UsageList; first?: number; open?: (path: string) => void }) {
  const [all, setAll] = useState(false);
  const shown = all ? list.items : list.items.slice(0, first);
  return (
    <div className={css.rows}>
      {shown.map((item, i) => <Row key={item.key} item={item} rank={i + 1} kind={list.key} open={open} />)}
      {list.items.length > first && <button type="button" className={css.more} onClick={() => setAll(!all)}>{all ? t("web-main.fold") : t("web-main.usage.showAll", { n: list.items.length })}</button>}
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
        <Segmented className={css.pickLists} label={t("web-main.usage.rankBy")} value={list.key} onChange={setShown} options={view.lists.map((l) => ({ value: l.key, label: l.title }))} />
      </div>
      <Ranking key={list.key} list={list} />
    </div>
  );
}

/** `basis`: how it is counted, said last (not where an empty place has said it already). */
export function Notes({ view, basis = true }: { view: UsageView; basis?: boolean }) {
  return (
    <ul className={css.notes}>
      {view.notes.map((n) => <li key={n}>{n}</li>)}
      {basis && <li>{view.basis}</li>}
    </ul>
  );
}

/** The whole page's body, below its title: the totals, the days, the lists, what is missing. */
export function UsageBody({ view, pricesPath }: { view: UsageView; pricesPath?: string | undefined }) {
  return (
    <div className={css.usage}>
      <Tiles view={view} pricesPath={pricesPath} />
      {view.empty ? (view.wait.reading || view.wait.failing.length > 0 ? <Waiting note={view.wait} sample={<><DaysChart view={SAMPLE_USAGE} /><Rankings view={SAMPLE_USAGE} /></>} /> : <p className={css.empty}>{t("web-main.usage.none")}</p>) : (
        <>
          <DaysChart view={view} />
          <Rankings view={view} />
        </>
      )}
      <Notes view={view} />
    </div>
  );
}

/** What the agents spent made up, for what the pages show while it is read (in their bones). */
export const SAMPLE_USAGE = sampleUsage();

/** Prices come from each station, through the core; no independent table in a UI. */
export function PriceTables({ view }: { view: UsageView }) {
  const tables = view.prices ?? [];
  return <div className={css.usage}>
    {tables.length === 0 && <p className={css.empty}>{t("web-main.usage.noPrices")}</p>}
    {tables.map((table, i) => <section className={css.card} key={i}>
      <h2 className={css.priceStation}>{table.station}</h2>
      <p className={css.priceNote}>{table.note}</p>
      {table.rows.length === 0 ? <p className={css.priceNote}>{t("web-main.usage.noModelUsage")}</p> : <div className={conversationCss.markdown} style={{ paddingTop: 8 }}><div className={proseCss.tableScroll} style={{ width: "100%" }}><div className={proseCss.tableFrame} style={{ minWidth: "100%" }}>
        <table style={{ width: "100%" }}>
          <thead><tr><th scope="col">{t("web-main.model.models")}</th>{table.rows[0]?.rates.map((r) => <th scope="col" key={r.label}>{r.label}</th>)}</tr></thead>
          <tbody>{table.rows.map((row) => <tr key={row.model}><td>{row.model}</td>{row.rates.map((rate) => <td key={rate.label}>{rate.value}</td>)}</tr>)}</tbody>
        </table>
      </div></div></div>}
    </section>)}
  </div>;
}

export { css as usageCss };
