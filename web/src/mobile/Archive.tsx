// The archive on a narrow screen, as the Android app has it (apps/android/…/screens/Archive.kt), from the list's top bar:
// the wide screen's archive (../pages/Archive.tsx useArchive: every station online, newest first, by the day archived),
// each row opening its chat (to read: it is archived), put back in the list or deleted for good. With no pointer to point
// with, a row's actions are always there, and what the archive is is said at the top. It can be very long: a field over
// it looks for one by its title or last line, and only its newest rows are made, more as it is scrolled near its end.
import { useEffect, useRef, useState } from "react";
import { useReady } from "../core/react.ts";
import { stationBase } from "../station.tsx";
import { LOCAL_MS } from "@stillfail/ui/motion.ts";
import { Retry, Search, Trash } from "@stillfail/ui/icons.tsx";
import type { ArchiveItem } from "../core/shapes.ts";
import { useDoing, useDoingFailed } from "../doing.ts";
import { ABOUT, ARCHIVE_PAGE, DELETE_TEXT, itemKey, useArchive } from "../pages/Archive.tsx";
import { useApp } from "./app.tsx";
import { FailedMark, PlaceHead, PlaceNote, SectionHeader, Spinner } from "./parts.tsx";
import { confirm } from "./sheets.tsx";
import * as css from "./Archive.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as homeCss from "./Home.css.ts";
import { t } from "../i18n.ts";

export function ArchiveScreen() {
  const app = useApp();
  // Slides in once what it shows is read from the device (LOCAL_MS at most, as Chat.tsx): not its loading look first.
  useReady({ topic: "archive", scope: app.entry.id }, LOCAL_MS);
  const [q, setQ] = useState("");
  const [limit, setLimit] = useState(ARCHIVE_PAGE);
  const { days, errors, note, more, restore, remove } = useArchive(app.entry.id, app.toast, q, limit);
  // Near the list's end (a screen or so before it), the next rows.
  const page = useRef<HTMLDivElement | null>(null);
  const end = useRef<HTMLDivElement | null>(null);
  useEffect(() => {
    if (!end.current || !more) return;
    const seen = new IntersectionObserver((e) => { if (e.some((x) => x.isIntersecting)) setLimit((n) => n + ARCHIVE_PAGE); }, { root: page.current, rootMargin: "0px 0px 800px 0px" });
    seen.observe(end.current);
    return () => seen.disconnect();
  }, [more, days]);
  return (
    <div ref={page} className={`${pagesCss.mScreen} ${pagesCss.mScroll}`}>
      <PlaceHead title={t("web-mobile.archive.title")} back={t("web-mobile.nav.chats")} onBack={app.pop} />
      <div className={css.mArchiveSearch}>
        <label className={homeCss.mSearchInput}>
          <Search size={17} />
          <input type="search" enterKeyHint="search" value={q} spellCheck={false} placeholder={t("web-pages.archive.search")} aria-label={t("web-pages.archive.search")}
            onChange={(e) => { setQ(e.target.value); setLimit(ARCHIVE_PAGE); }} />
        </label>
      </div>
      {errors.map((e) => <p key={e.station} className={css.mArchiveNote} data-error>{e.text}</p>)}
      {note && <p className={css.mArchiveNote}>{note}</p>}
      {days.map((day) => (
        <section key={day.label} aria-label={day.label}>
          <SectionHeader title={day.label} />
          {day.items.map((item) => <Row key={itemKey(item)} item={item} restore={restore} remove={remove} />)}
        </section>
      ))}
      {/* Nothing archived: what the archive is, said then (the page says it nowhere else). */}
      {days.length === 0 && !q && <PlaceNote>{ABOUT}</PlaceNote>}
      {more && <div ref={end} style={{ height: 1 }} />}
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
    // Tapped, its chat (archived: read, and restored from its composer); its buttons are its own.
    <div className={css.mArchiveRow} role="link" tabIndex={0} onClick={() => app.push(`${stationBase(item.station)}/chats/${encodeURIComponent(item.id)}`)}>
      <div className={css.mArchiveHead}>
        <span className={css.mArchiveTitle}>{item.title}</span>
        <span className={css.mArchiveWhen} aria-label={item.how}>
          {item.place && <span>{item.place}</span>}{item.clock}
        </span>
        <span className={css.mArchiveActions} onClick={(e) => e.stopPropagation()}>
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
