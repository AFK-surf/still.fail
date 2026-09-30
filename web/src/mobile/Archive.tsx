// The archive on a narrow screen, as the Android app has it (apps/android/…/screens/Archive.kt), from the list's top bar:
// the wide screen's archive (../pages/Archive.tsx useArchive: every station online, newest first, by the day archived),
// each row put back in the list or deleted for good. With no pointer to point with, a row's actions are always there,
// and what the archive is is said at the top.
import { Retry, Trash } from "../icons.tsx";
import { ABOUT, DELETE_TEXT, itemKey, useArchive } from "../pages/Archive.tsx";
import { useApp } from "./app.tsx";
import { LargeTitle, SectionHeader, TopBack } from "./parts.tsx";
import { confirm } from "./sheets.tsx";
import * as css from "./Archive.css.ts";
import * as pagesCss from "./styles/pages.css.ts";

export function ArchiveScreen() {
  const app = useApp();
  const { days, errors, note, restore, remove } = useArchive(app.entry.id, app.toast);
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <TopBack label="会话" onBack={app.pop} />
      <LargeTitle small={app.entry.name} big="已归档" />
      <p className={css.mArchiveAbout}>{ABOUT}</p>
      {errors.map((e) => <p key={e.station} className={css.mArchiveNote} data-error>{e.text}</p>)}
      {note && <p className={css.mArchiveNote}>{note}</p>}
      {days.map((day) => (
        <section key={day.label} aria-label={day.label}>
          <SectionHeader title={day.label} />
          {day.items.map((item) => (
            <div key={itemKey(item)} className={css.mArchiveRow}>
              <div className={css.mArchiveHead}>
                <span className={css.mArchiveTitle}>{item.title}</span>
                <span className={css.mArchiveWhen} aria-label={item.how}>
                  {item.place && <span>{item.place}</span>}{item.clock}
                </span>
                <span className={css.mArchiveActions}>
                  <button type="button" className={css.mArchiveAction} aria-label={`恢复「${item.title}」`} onClick={() => void restore(item)}><Retry size={16} /></button>
                  {item.deletable && (
                    <button type="button" className={css.mArchiveAction} aria-label={`删除「${item.title}」`}
                      onClick={() => confirm(app, { title: `删除「${item.title}」？`, text: DELETE_TEXT, action: "删除", danger: true, run: () => remove(item) })}>
                      <Trash size={16} />
                    </button>
                  )}
                </span>
              </div>
              <span className={css.mArchiveLast}>{item.last}</span>
            </div>
          ))}
        </section>
      ))}
      <div style={{ height: 24 }} />
    </div>
  );
}
