// What the agents spent, on a narrow screen (../Usage.tsx has the view and the wide screen's page): from settings
// (./Settings.tsx), the same totals, chart and lists, on the phone's cards.
import { useState } from "react";
import { useSearchParams } from "react-router";
import { DAYS, DaysChart, Notes, PriceTables, Ranking, SAMPLE_USAGE, Tiles, usageCss as css, useUsage, type UsageDays } from "../Usage.tsx";
import type { UsageView } from "../core/shapes.ts";
import { useApp } from "./app.tsx";
import { LargeTitle, PlaceHead, Seg, TopBack } from "./parts.tsx";
import { Waiting, WaitLine } from "@stillfail/ui/waiting.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as settingsCss from "./styles/settings.css.ts";
import { t } from "../i18n.ts";

export function UsageScreen() {
  const app = useApp();
  const [days, setDays] = useState<UsageDays>("7");
  const [shown, setShown] = useState(0);
  const usage = useUsage(app.entry.id, days);
  const view = usage.value;
  // What it still waits on (the core's `wait`): with nothing to show yet, the cards to come under it; else a line over them.
  const wait = view?.wait;
  const waiting = !!wait && (wait.reading || wait.failing.length > 0);
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <PlaceHead title={t("web-mobile.settings.usage")} back={t("web-mobile.settings.title")} onBack={app.pop}
        trailing={<Seg options={DAYS.map((d) => d.label)} selected={DAYS.findIndex((d) => d.value === days)} onSelect={(i) => setDays(DAYS[i]!.value)} />} />
      {!view || (view.empty && waiting)
        ? <Waiting note={wait} error={usage.error && !view ? t("web-mobile.usage.failed", { error: usage.error.message }) : undefined} sample={<UsageCards view={SAMPLE_USAGE} days={days} shown={0} onShown={() => undefined} />} />
        : <UsageCards view={view} days={days} shown={shown} onShown={setShown} />}
      <div style={{ height: 30 }} />
    </div>
  );
}

/** What was spent (`view`, over `days`) on cards: the totals, the days' chart, the list `shown` of its lists. */
function UsageCards({ view, days, shown, onShown }: { view: UsageView; days: UsageDays; shown: number; onShown(i: number): void }) {
  const app = useApp();
  const list = view.lists[shown] ?? view.lists[0];
  const wait = view.wait;
  return (
    <div className={`${css.usage} ${css.mobile}`}>
      {wait.reading && <WaitLine className={settingsCss.mPageNote} text={wait.text ?? t("common.reading")} />}
      {wait.failing.map((f) => <WaitLine key={f.station} className={settingsCss.mPageNote} text={f.text} error />)}
      <Tiles view={view} pricesPath={`/w/${app.entry.id}/settings/usage/prices?days=${days}`} />
      {/* Nothing spent: what the page counts, said then (the page says it nowhere else). */}
      {view.empty ? <><p className={css.empty}>{t("web-mobile.usage.empty")}</p><p className={css.empty}>{t("web-mobile.usage.note")}</p></> : (
        <>
          <div className={css.card}><DaysChart view={view} /></div>
          {list && (
            <div className={css.card}>
              <div className={css.cardHead}>
                <Seg options={view.lists.map((l) => l.title)} selected={Math.max(0, view.lists.indexOf(list))} onSelect={onShown} fill />
              </div>
              <Ranking key={list.key} list={list} open={(path) => app.push(path)} />
            </div>
          )}
        </>
      )}
      <Notes view={view} basis={!view.empty} />
    </div>
  );
}

export function UsagePricesScreen() {
  const app = useApp();
  const [params] = useSearchParams();
  const usage = useUsage(app.entry.id, params.get("days") === "30" ? "30" : "7");
  return <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
    <TopBack label={t("web-mobile.settings.usage")} onBack={app.pop} />
    <LargeTitle small="" big={t("web-mobile.usage.prices")} />
    <p className={settingsCss.mPageNote}>{t("web-mobile.usage.pricesNote")}</p>
    <div className={`${css.usage} ${css.mobile}`}>
      {usage.value ? <PriceTables view={usage.value} /> : <Waiting error={usage.error ? t("web-mobile.usage.pricesFailed", { error: usage.error.message }) : undefined} sample={<PriceTables view={SAMPLE_USAGE} />} />}
    </div>
  </div>;
}
