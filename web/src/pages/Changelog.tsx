// What changed in still.fail (../changelog.ts), on a wide screen: the settings' 更新日志 page, a tab a part (this
// app's first), by day, each change with where it is and whether this app has it; and, at the sidebar's foot, what
// the last update brought, until the page is opened or it is put away. The phone's are ../mobile/Changelog.tsx.
import { useEffect, useState } from "react";
import { Link } from "react-router";
import { useChangelog, useChangelogSeen } from "../changelog.ts";
import type { ChangelogItem } from "../core/shapes.ts";
import { Close, Sparks } from "../icons.tsx";
import { Loading, MobileBack, Segmented, Tip } from "../ui.tsx";
import { t } from "../i18n.ts";
import * as pagesCss from "../styles/pages.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as controlsCss from "../styles/controls.css.ts";
import * as css from "./Changelog.css.ts";

export function ChangelogPage({ back }: { back: string }) {
  const view = useChangelog().value;
  const seen = useChangelogSeen();
  const [part, setPart] = useState<string | null>(null);
  const tab = view?.tabs.find((x) => x.part === part) ?? view?.tabs[0];
  // Opened: what the update brought is read.
  const news = !!view?.news;
  useEffect(() => {
    if (news) seen();
  }, [news, seen]);
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={back} label={t("web-pages.settings.title")} />
      <header className={pagesCss.pageHead}>
        <div>
          <h1>{t("web-pages.settings.nav.changelog")}</h1>
          {view?.build != null && <p className={shellCss.muted}>{t("web-pages.changelog.build", { build: view.build })}</p>}
        </div>
      </header>
      {tab && <div className={css.tabsRow}><Segmented className={css.tabs} label={t("web-pages.settings.nav.changelog")} value={tab.part}
        onChange={setPart} options={view!.tabs.map((x) => ({ value: x.part, label: x.label }))} /></div>}
      {!view || view.loading ? <Loading label={t("web-pages.settings.reading")} fill={false} />
        : view.error ? <p className={controlsCss.fieldError}>{view.error}</p>
        : !tab || tab.days.length === 0 ? <p className={shellCss.muted}>{t("web-pages.changelog.empty")}</p>
        : tab.days.map((day) => (
          <section key={day.label} aria-label={day.label}>
            <div className={css.heading}>{day.label}</div>
            {day.entries.map((item) => <Change key={item.version} item={item} />)}
          </section>
        ))}
    </div>
  );
}

/** One change: each line with its kind before it, the version at the end of the first; under them, what is not out yet. */
function Change({ item }: { item: ChangelogItem }) {
  return (
    <div className={css.change}>
      {item.lines.map((line, i) => (
        <div key={i} className={css.row}>
          <span className={css.kind} data-kind={line.kind ?? undefined}>{line.label}</span>
          <p className={css.line}>{line.text}</p>
          {i === 0 && <span className={css.version}>{item.versionName}</span>}
        </div>
      ))}
      {item.note && <p className={css.note} data-has={item.has == null ? undefined : String(item.has)}>{item.note}</p>}
    </div>
  );
}

/** At the sidebar's foot after an update: the build it is now and what it brought; opens the changelog. */
export function ChangelogNews({ to }: { to: string }) {
  const news = useChangelog().value?.news;
  const seen = useChangelogSeen();
  if (!news) return null;
  const lines = news.entries.flatMap((e) => e.text);
  return (
    <div className={css.news}>
      <Link className={css.newsLink} to={to}>
        <span className={css.newsHead}><Sparks size={15} strokeWidth={1.8} />{news.build ? t("web-pages.changelog.updatedTo", { build: news.build }) : t("web-pages.changelog.updated")}</span>
        {lines.slice(0, 3).map((line, i) => <span key={i} className={css.newsLine}>{line}</span>)}
        {lines.length > 3 && <span className={css.newsMore}>{t("web-pages.changelog.more", { n: lines.length - 3 })}</span>}
      </Link>
      <Tip label={t("web-pages.changelog.dismiss")} side="top">
        <button type="button" className={css.newsClose} aria-label={t("web-pages.changelog.dismiss")} onClick={seen}><Close size={14} strokeWidth={1.8} /></button>
      </Tip>
    </div>
  );
}
