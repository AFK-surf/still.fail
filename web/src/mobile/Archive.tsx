// The archive on a narrow screen, as the Android app has it (apps/android/…/screens/Archive.kt), from the list's top bar:
// the wide screen's archive (../pages/Archive.tsx useArchive: every station online, newest first, by the day archived),
// each row put back in the list or deleted for good. With no pointer to point with, a row's actions are always there,
// and what the archive is is said at the top.
import { Retry, Trash } from "../icons.tsx";
import type { ArchiveItem } from "../core/shapes.ts";
import { useDoing, useDoingFailed } from "../doing.ts";
import { ABOUT, DELETE_TEXT, itemKey, useArchive } from "../pages/Archive.tsx";
import { useApp } from "./app.tsx";
import { FailedMark, LargeTitle, SectionHeader, Spinner, TopBack } from "./parts.tsx";
import { confirm } from "./sheets.tsx";
import * as css from "./Archive.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import { t } from "../i18n.ts";

export function ArchiveScreen() {
  const app = useApp();
  const { days, errors, note, restore, remove } = useArchive(app.entry.id, app.toast);
  return (
    <div className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <TopBack label={t("web-mobile.nav.chats")} onBack={app.pop} />
      <LargeTitle small={app.entry.name} big={t("web-mobile.archive.title")} />
      <p className={css.mArchiveAbout}>{ABOUT}</p>
      {errors.map((e) => <p key={e.station} className={css.mArchiveNote} data-error>{e.text}</p>)}
      {note && <p className={css.mArchiveNote}>{note}</p>}
      {days.map((day) => (
        <section key={day.label} aria-label={day.label}>
          <SectionHeader title={day.label} />
          {day.items.map((item) => <Row key={itemKey(item)} item={item} restore={restore} remove={remove} />)}
        </section>
      ))}
      <div style={{ height: 24 }} />
    </div>
  );
}

/** A row, with its actions; while one is under way its spinner stands for both (it says how it ended in the toast), and
 *  one that failed leaves the failure mark before them a few seconds. */
function Row({ item, restore, remove }: { item: ArchiveItem; restore: (item: ArchiveItem) => Promise<void>; remove: (item: ArchiveItem) => Promise<void> }) {
  const app = useApp();
  const restoring = useDoing("chat.archive", { station: item.station, session: item.session, thread: item.thread ?? undefined, archived: false });
  const deleting = useDoing("session.delete", { station: item.station, key: item.session });
  const busy = restoring || deleting;
  const failed = useDoingFailed("chat.archive", { station: item.station, session: item.session, thread: item.thread ?? undefined, archived: false })
    ?? useDoingFailed("session.delete", { station: item.station, key: item.session });
  return (
    <div className={css.mArchiveRow}>
      <div className={css.mArchiveHead}>
        <span className={css.mArchiveTitle}>{item.title}</span>
        <span className={css.mArchiveWhen} aria-label={item.how}>
          {item.place && <span>{item.place}</span>}{item.clock}
        </span>
        <span className={css.mArchiveActions}>
          {!busy && failed !== undefined && <FailedMark error={failed} />}
          {/* restore says how it went itself (../pages/Archive.tsx useArchive) */}
          <button type="button" className={css.mArchiveAction} aria-label={t("web-mobile.archive.restore", { title: item.title })} disabled={busy} aria-busy={restoring || undefined} onClick={() => void restore(item)}>
            {restoring ? <Spinner size={16} /> : <Retry size={16} />}
          </button>
          {item.deletable && (
            <button type="button" className={css.mArchiveAction} aria-label={t("web-mobile.archive.delete", { title: item.title })} disabled={busy} aria-busy={deleting || undefined}
              onClick={() => confirm(app, { title: t("web-mobile.archive.deleteAsk", { title: item.title }), text: DELETE_TEXT, action: t("common.delete"), danger: true, atOnce: "web-main.chat.deleteFailed", run: () => remove(item) })}>
              {deleting ? <Spinner size={16} /> : <Trash size={16} />}
            </button>
          )}
        </span>
      </div>
      <span className={css.mArchiveLast}>{item.last}</span>
    </div>
  );
}
