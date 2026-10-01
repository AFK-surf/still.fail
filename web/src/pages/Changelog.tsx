// What changed in still.fail (../changelog.ts), on a wide screen: the settings' 更新日志 page, by day, each change
// with where it is and whether this app has it; and, at the sidebar's foot, what the last update brought, until the
// page is opened or it is put away. The phone's are ../mobile/Changelog.tsx.
import { useEffect } from "react";
import { Link } from "react-router";
import { useChangelog, useChangelogSeen } from "../changelog.ts";
import type { ChangelogItem } from "../core/shapes.ts";
import { Close, Sparks } from "../icons.tsx";
import { Loading, MobileBack, Tip } from "../ui.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as controlsCss from "../styles/controls.css.ts";
import * as css from "./Changelog.css.ts";

export function ChangelogPage({ back }: { back: string }) {
  const view = useChangelog().value;
  const seen = useChangelogSeen();
  // Opened: what the update brought is read.
  const news = !!view?.news;
  useEffect(() => {
    if (news) seen();
  }, [news, seen]);
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={back} label="设置" />
      <header className={pagesCss.pageHead}>
        <div>
          <h1>更新日志</h1>
          {view?.build != null && <p className={shellCss.muted}>这个 app 是 0.1.{view.build}</p>}
        </div>
      </header>
      {!view || view.loading ? <Loading label="正在读取…" fill={false} />
        : view.error ? <p className={controlsCss.fieldError}>{view.error}</p>
        : view.days.length === 0 ? <p className={shellCss.muted}>还没有更新记录</p>
        : view.days.map((day) => (
          <section key={day.label} aria-label={day.label}>
            <div className={css.heading}>{day.label}</div>
            {day.entries.map((item) => <Change key={item.version} item={item} />)}
          </section>
        ))}
    </div>
  );
}

function Change({ item }: { item: ChangelogItem }) {
  return (
    <div className={css.change}>
      {item.text.map((line, i) => <p key={i} className={css.line}>{line}</p>)}
      <p className={css.meta}>
        {item.place && <span>{item.place}</span>}
        <span className={css.note} data-has={item.has == null ? undefined : String(item.has)}>{item.note}</span>
      </p>
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
        <span className={css.newsHead}><Sparks size={15} strokeWidth={1.8} />已更新{news.build ? `到 ${news.build}` : ""}</span>
        {lines.slice(0, 3).map((line, i) => <span key={i} className={css.newsLine}>{line}</span>)}
        {lines.length > 3 && <span className={css.newsMore}>还有 {lines.length - 3} 项</span>}
      </Link>
      <Tip label="知道了" side="top">
        <button type="button" className={css.newsClose} aria-label="知道了" onClick={seen}><Close size={14} strokeWidth={1.8} /></button>
      </Tip>
    </div>
  );
}
