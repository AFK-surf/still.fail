// What changed in still.fail (../changelog.ts) on a narrow screen, as the Android app has it (apps/android/…/screens/
// Changelog.kt): the settings' 更新日志 page, a tab a part (this app's first), by day on cards, each change with where
// it is and whether this app has it; and at the top of the list, what the last update brought, until the page is
// opened or it is put away. The wide screen's are ../pages/Changelog.tsx.
import { useEffect, useState } from "react";
import { useChangelog, useChangelogSeen } from "../changelog.ts";
import { Close, Sparks } from "../icons.tsx";
import { useApp } from "./app.tsx";
import { LargeTitle, ListCard, SectionHeader, Seg, Spinner, TopBack } from "./parts.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as css from "./Changelog.css.ts";
import { t } from "../i18n.ts";

export function ChangelogScreen() {
  const app = useApp();
  const view = useChangelog().value;
  const seen = useChangelogSeen();
  const [part, setPart] = useState<string | null>(null);
  const tabs = view?.tabs ?? [];
  const at = Math.max(0, tabs.findIndex((x) => x.part === part));
  const tab = tabs[at];
  const news = !!view?.news;
  useEffect(() => {
    if (news) seen();
  }, [news, seen]);
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <TopBack label={t("web-mobile.settings.title")} onBack={app.pop} />
      <LargeTitle small={view?.build != null ? t("web-mobile.changelog.build", { version: `0.1.${view.build}` }) : ""} big={t("web-mobile.settings.changelog")} />
      {tab && <div className={css.mTabs}><Seg options={tabs.map((x) => x.label)} selected={at} onSelect={(i) => setPart(tabs[i]!.part)} height={34} fill /></div>}
      {!view || view.loading ? <p className={css.mNote}><Spinner size={13} />{t("web-mobile.reading")}</p>
        : view.error ? <p className={css.mNote} data-error>{view.error}</p>
        : !tab || tab.days.length === 0 ? <p className={css.mNote}>{t("web-mobile.changelog.empty")}</p>
        : tab.days.map((day) => (
          <section key={day.label}>
            <SectionHeader title={day.label} start={24} />
            <ListCard>
              {day.entries.map((item) => (
                <div key={item.version} className={css.mChange}>
                  {item.text.map((line, i) => <span key={i} className={css.mLine}>{line}</span>)}
                  <span className={css.mMeta}>
                    {item.place && <span>{item.place}</span>}
                    <span data-has={item.has == null ? undefined : String(item.has)}>{item.note}</span>
                  </span>
                </div>
              ))}
            </ListCard>
          </section>
        ))}
      <div style={{ height: 30 }} />
    </div>
  );
}

/** At the top of the list after an update: the build it is now and what it brought; opens the changelog. */
export function ChangelogNews() {
  const app = useApp();
  const news = useChangelog().value?.news;
  const seen = useChangelogSeen();
  if (!news) return null;
  const lines = news.entries.flatMap((e) => e.text);
  return (
    <div className={css.mNews}>
      <button type="button" className={css.mNewsBody} onClick={() => app.push(app.at("/settings/changelog"))}>
        <span className={css.mNewsHead}><Sparks size={16} />{news.build ? t("web-mobile.changelog.updatedTo", { build: news.build }) : t("web-mobile.changelog.updated")}</span>
        {lines.slice(0, 3).map((line, i) => <span key={i} className={css.mNewsLine}>{line}</span>)}
        {lines.length > 3 && <span className={css.mNewsLine}>{t("web-mobile.changelog.more", { n: lines.length - 3 })}</span>}
      </button>
      <button type="button" className={css.mNewsClose} aria-label={t("web-mobile.changelog.dismiss")} onClick={seen}><Close size={16} /></button>
    </div>
  );
}
