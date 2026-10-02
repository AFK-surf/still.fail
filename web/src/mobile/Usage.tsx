// What the agents spent, on a narrow screen (../Usage.tsx has the view and the wide screen's page): from settings
// (./Settings.tsx), the same totals, chart and lists, on the phone's cards.
import { useState } from "react";
import { useSearchParams } from "react-router";
import { DAYS, DaysChart, Notes, PriceTables, Ranking, Tiles, usageCss as css, useUsage, type UsageDays } from "../Usage.tsx";
import { useApp } from "./app.tsx";
import { LargeTitle, Loading, Seg, TopBack } from "./parts.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as settingsCss from "./styles/settings.css.ts";
import { t } from "../i18n.ts";

export function UsageScreen() {
  const app = useApp();
  const [days, setDays] = useState<UsageDays>("7");
  const [shown, setShown] = useState(0);
  const usage = useUsage(app.entry.id, days);
  const view = usage.value;
  const list = view?.lists[shown] ?? view?.lists[0];
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <TopBack label={t("web-mobile.settings.title")} onBack={app.pop} trailing={<Seg options={DAYS.map((d) => d.label)} selected={DAYS.findIndex((d) => d.value === days)} onSelect={(i) => setDays(DAYS[i]!.value)} />} />
      <LargeTitle small="" big={t("web-mobile.settings.usage")} />
      <p className={settingsCss.mPageNote}>{t("web-mobile.usage.note")}</p>
      {!view ? <Loading text={usage.error ? t("web-mobile.usage.failed", { error: usage.error.message }) : t("web-mobile.reading")} /> : (
        <div className={`${css.usage} ${css.mobile}`}>
          <Tiles view={view} pricesPath={`/w/${app.entry.id}/settings/usage/prices?days=${days}`} />
          {view.empty ? <p className={css.empty}>{view.loading ? t("web-mobile.reading") : t("web-mobile.usage.empty")}</p> : (
            <>
              <div className={css.card}><DaysChart view={view} /></div>
              {list && (
                <div className={css.card}>
                  <div className={css.cardHead}>
                    <Seg options={view.lists.map((l) => l.title)} selected={Math.max(0, view.lists.indexOf(list))} onSelect={setShown} fill />
                  </div>
                  <Ranking key={list.key} list={list} open={(path) => app.push(path)} />
                </div>
              )}
            </>
          )}
          <Notes view={view} />
        </div>
      )}
      <div style={{ height: 30 }} />
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
      {usage.value ? <PriceTables view={usage.value} /> : <Loading text={usage.error ? t("web-mobile.usage.pricesFailed", { error: usage.error.message }) : t("web-mobile.reading")} />}
    </div>
  </div>;
}
