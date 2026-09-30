// The archive on a narrow screen, as the Android app has it (apps/android/…/screens/Archive.kt), from the list's top bar:
// the wide screen's archive (../pages/Archive.tsx useArchive: every station online, newest first, by the day archived),
// each row put back in the list or deleted for good. With no pointer to point with, a row's actions are always there,
// and what the archive is is said at the top.
import { Retry, Trash } from "../icons.tsx";
import { ABOUT, archivedAt, archivedHow, clock, days, deletable, DELETE_TEXT, useArchive } from "../pages/Archive.tsx";
import { useApp } from "./app.tsx";
import { LargeTitle, SectionHeader, TopBack } from "./parts.tsx";
import { confirm } from "./sheets.tsx";
import * as css from "./Archive.css.ts";
import * as pagesCss from "./styles/pages.css.ts";

export function ArchiveScreen() {
  const app = useApp();
  const { rows, errors, note, named, restore, remove, readers } = useArchive(app.entry.id, app.toast);
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      {readers}
      <TopBack label="会话" onBack={app.pop} />
      <LargeTitle small={app.entry.name} big="已归档" />
      <p className={css.mArchiveAbout}>{ABOUT}</p>
      {errors.map(({ view, error }) => <p key={view.station} className={css.mArchiveNote} data-error>{named ? `${view.name}：` : ""}{error}</p>)}
      {note && <p className={css.mArchiveNote}>{note}</p>}
      {days(rows).map(([label, items]) => (
        <section key={label} aria-label={label}>
          <SectionHeader title={label} />
          {items.map((row) => (
            <div key={`${row.view.station}/${row.chat.thread ?? row.chat.session}`} className={css.mArchiveRow}>
              <div className={css.mArchiveHead}>
                <span className={css.mArchiveTitle}>{row.chat.title}</span>
                <span className={css.mArchiveWhen} aria-label={archivedHow(row.chat)}>
                  {named && <span>{row.view.name}</span>}{clock(archivedAt(row.chat))}
                </span>
                <span className={css.mArchiveActions}>
                  <button type="button" className={css.mArchiveAction} aria-label={`恢复「${row.chat.title}」`} onClick={() => void restore(row)}><Retry size={16} /></button>
                  {deletable(row.chat) && (
                    <button type="button" className={css.mArchiveAction} aria-label={`删除「${row.chat.title}」`}
                      onClick={() => confirm(app, { title: `删除「${row.chat.title}」？`, text: DELETE_TEXT, action: "删除", danger: true, run: () => remove(row) })}>
                      <Trash size={16} />
                    </button>
                  )}
                </span>
              </div>
              <span className={css.mArchiveLast}>{row.chat.last?.text ?? ""}</span>
            </div>
          ))}
        </section>
      ))}
      <div style={{ height: 24 }} />
    </div>
  );
}
