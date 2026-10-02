// 奏 with none left (both screens): it stays, for the next to come, and says how the day went (how many answered, how
// long they waited for the viewer, how many agents are at work), where the next may come from (the viewer's chats with
// an agent at work or waiting) and what was answered today (core decisions.rs `today`). Each opens its chat.
import type { DecisionsView } from "./core/shapes.ts";
import { stationBase } from "./station.tsx";
import { IdleFace } from "./brand.tsx";
import * as css from "./DecisionsIdle.css.ts";
import { t } from "./i18n.ts";

const chatPath = (station: string, session: string) => `${stationBase(station)}/chats/${encodeURIComponent(session)}`;

export function DecisionsIdle({ view, onOpen }: { view: DecisionsView; onOpen: (path: string) => void }) {
  const today = view.today;
  const working = view.working ?? [];
  const answered = view.answered ?? [];
  return (
    <div className={css.idle}>
      <div className={css.column}>
        <div className={css.head}>
          <IdleFace size={72} />
          <h2 className={css.title}>{t("web-main.decisions.idle.title")}</h2>
          <p className={css.note}>{t("web-main.decisions.idle.note")}</p>
          {today && (
            <div className={css.stats}>
              <div className={css.stat}><span className={css.figure}>{today.count}</span><span className={css.figureWords}>{t("web-main.decisions.idle.answered")}</span></div>
              {today.waited && <div className={css.stat}><span className={css.figure}>{today.waited}</span><span className={css.figureWords}>{t("web-main.decisions.idle.waited")}</span></div>}
              <div className={css.stat}><span className={css.figure}>{today.working}</span><span className={css.figureWords}>{t("web-main.decisions.idle.working")}</span></div>
            </div>
          )}
        </div>
        {working.length > 0 && (
          <section className={css.section}>
            <h3 className={css.sectionTitle}>{t("web-main.decisions.idle.workingTitle")}</h3>
            {working.map((w) => (
              <button key={`${w.station}/${w.session}`} type="button" className={css.row} onClick={() => onOpen(chatPath(w.station, w.session))}>
                <span className={css.busy} aria-hidden="true" />
                <span className={css.words}>
                  <span className={css.main}>{w.title}</span>
                  <span className={css.meta}>{w.line}</span>
                </span>
                <span className={css.when}>{w.time?.lastActiveAt?.ago}</span>
              </button>
            ))}
          </section>
        )}
        {answered.length > 0 && (
          <section className={css.section}>
            <h3 className={css.sectionTitle}>{t("web-main.decisions.idle.answeredTitle")}</h3>
            {answered.map((a) => (
              <button key={`${a.station}/${a.thread}/${a.seq}`} type="button" className={css.row} onClick={() => onOpen(chatPath(a.station, a.session))}>
                <span className={css.done} aria-hidden="true" />
                <span className={css.words}>
                  <span className={css.main}>{a.text}</span>
                  <span className={css.meta}>{a.title} · <span className={css.answer}>{a.answer}</span></span>
                </span>
                <span className={css.when}>{a.clock}</span>
              </button>
            ))}
          </section>
        )}
      </div>
    </div>
  );
}
