// The archive: chats archived by hand or by the station once they idled (a day by default), of every station online in
// one list, newest first and grouped by the day they were archived; each can be read, shown again, and one archived with
// its session deleted for good. Anything new said in a chat the station archived brings it back by itself; one archived
// by hand takes no messages until shown again.
//
// On the wide screen it is one of the sidebar's lists (ArchiveRows), its chat open beside it as any chat's
// is (its page says it is archived, ArchiveNotice.tsx); its own page opens the newest of them. The phone's is
// ../mobile/Archive.tsx.
import { memo, useCallback, useEffect, useRef, useState } from "react";
import { Navigate, NavLink } from "react-router";
import { stationApi, stationCall, useArchiveView } from "../api.ts";
import { prime, useCall } from "../core/react.ts";
import type { ArchiveItem, ArchiveView } from "../core/shapes.ts";
import { failure, useToast } from "@stillfail/ui/toast.tsx";
import { DoingShown, useDoingState } from "../DoingMark.tsx";
import { Confirm, Empty, Tip, Waiting } from "../ui.tsx";
import { Retry, Search, Trash } from "@stillfail/ui/icons.tsx";
import { StationMark } from "../StationMark.tsx";
import { NavSection } from "../SidebarList.tsx";
import { useListMotion } from "../listMotion.ts";
import { useGo, useHere } from "../go.ts";
import { stationBase } from "../station.tsx";
import * as nav from "../Sidebar.css.ts";
import * as css from "./Archive.css.ts";
import { t } from "../i18n.ts";
import { Words } from "../cloud/words.tsx";
import * as pageCss from "@stillfail/ui/styles/page.css.ts";
import { sampleArchive, sampleWords } from "../samples.ts";

/**
 * The archive of a scope's stations online, as both screens show it (the phone's in ../mobile/Archive.tsx), as the
 * core has it (its `archive` topic): its days, what could not be read, what to say in place of rows; and putting one
 * back or deleting it, which the core takes out of it. `restore` says how it went in `toast`; `remove` throws what
 * went wrong.
 */
export function useArchive(scope: string, toast: (text: string) => void, q = "", limit = 0) {
  const view = useArchiveView(scope, q, limit);
  // Asked for more (or other words), what was shown stays until it comes: no rows taken away meanwhile.
  const last = useRef<ArchiveView | undefined>(undefined);
  if (view.value) last.current = view.value;
  const value = view.value ?? last.current;
  const call = useCall();
  const api = (item: ArchiveItem) => stationApi(stationCall(call, item.station));
  const restore = async (item: ArchiveItem) => {
    try {
      await api(item).archive(item, false);
      toast(t("web-pages.archive.restored"));
    } catch (e) {
      toast(t("web-pages.archive.restoreFailed", { error: e instanceof Error ? e.message : String(e) }));
    }
  };
  const remove = async (item: ArchiveItem) => {
    await api(item).deleteSession(item.session);
    toast(t("web-pages.archive.deleted"));
  };
  // Not there yet: being read; refused (a core from before the archive): why.
  const note = value ? value.note : view.error ? view.error.message : t("common.readingStations");
  // `wait`: what the list still waits on (undefined: none of it read yet); `failed`: the topic refused.
  return { days: value?.days ?? [], errors: value?.errors ?? [], note, read: value !== undefined, wait: value?.wait, failed: view.error?.message, more: value?.more === true, restore, remove };
}

/** A row's key in its list. */
export const itemKey = (item: ArchiveItem) => `${item.station}/${item.thread ?? item.session}`;

/** An archived chat's page, as any chat's. */
const chatPath = (item: ArchiveItem) => `${stationBase(item.station)}/chats/${encodeURIComponent(item.id)}`;

/**
 * The archive's own page. On the wide screen, the newest archived chat open (the archive itself is in the sidebar);
 * with none, what the archive is. On a narrow one the sidebar's list is the page (cloud/workspace.tsx).
 */
export function ArchivePage({ scope, wide }: { scope: string; wide: boolean }) {
  const { days, note, read } = useArchive(scope, useToast(), "", 1);
  const newest = days[0]?.items[0];
  if (wide && newest) return <Navigate to={chatPath(newest)} replace />;
  if (!read) return null;
  return (
    <Empty>
      <h2>{t("web-pages.archive.title")}</h2>
      {note && <p>{note}</p>}
      <p>{ABOUT}</p>
    </Empty>
  );
}

/** How many rows the archive's list shows at first, and how many more each time it is scrolled near its end (both screens'). */
export const ARCHIVE_PAGE = 60;
const PAGE = ARCHIVE_PAGE;

/**
 * The archive as one of the sidebar's lists (Sidebar.tsx ChatList), in place of the chats: a field to look for one by
 * its title or last line, then its days, each archived chat a row as a chat's is, leading to its page. It can be very
 * long: only its newest rows are made, more as it is scrolled near its end. Pointed at, a row puts it back or deletes
 * it for good (asked first).
 */
export const ArchiveRows = memo(function ArchiveRows({ scope, hidden }: { scope: string; hidden: boolean }) {
  const toast = useToast();
  const [q, setQ] = useState("");
  const [limit, setLimit] = useState(PAGE);
  const { days, errors, note, read, wait, failed, more, restore, remove: removeItem } = useArchive(scope, toast, q, limit);
  // No rows yet: their shapes while they are read, what could not be in red over them.
  const waiting = days.length === 0 && (!wait || wait.reading || wait.failing.length > 0);
  // Near the list's end (a screen or so before it), the next rows.
  const end = useRef<HTMLDivElement | null>(null);
  useEffect(() => {
    const el = end.current;
    if (!el || !more || hidden) return;
    const seen = new IntersectionObserver((e) => { if (e.some((x) => x.isIntersecting)) setLimit((n) => n + PAGE); }, { root: list.current, rootMargin: "0px 0px 600px 0px" });
    seen.observe(el);
    return () => seen.disconnect();
  }, [more, hidden, days]);
  const [deleting, setDeleting] = useState<ArchiveItem | null>(null);
  const here = useHere();
  const go = useGo();
  const list = useRef<HTMLDivElement | null>(null);
  useListMotion(list);
  // Asked, the Confirm closes at once: its row turns until the station has deleted it, a failure said by toast. Its
  // page open, the archive's next one opens in its place.
  const remove = () => {
    const item = deleting;
    if (!item) return;
    setDeleting(null);
    if (decodeURIComponent(here()) === decodeURIComponent(chatPath(item))) go(`/w/${scope}/archive`);
    void removeItem(item).catch((e: unknown) => toast(t("web-main.chat.deleteFailed", { error: failure(e) })));
  };
  return (
    <div ref={list} className={nav.navScroll} aria-hidden={hidden || undefined} inert={hidden || undefined}>
      <label className={css.search}>
        <Search size={14} />
        <input type="search" value={q} spellCheck={false} placeholder={t("web-pages.archive.search")} aria-label={t("web-pages.archive.search")}
          onChange={(e) => { setQ(e.target.value); setLimit(PAGE); }} />
      </label>
      {!waiting && errors.map((e) => <p key={e.station} className={`${nav.navEmpty} ${nav.navError}`}>{e.text}</p>)}
      {waiting && <Waiting note={wait} error={failed} sample={<NavSection title={sampleWords(2)}>{SAMPLE_ARCHIVE.map((item) => <ArchiveRow key={itemKey(item)} item={item} restore={() => Promise.resolve()} ask={() => undefined} />)}</NavSection>} />}
      {read && !waiting && note && <p className={nav.navEmpty}>{note}</p>}
      {days.map((day) => (
        <NavSection key={day.label} title={day.label} flip={`archive:${day.label}`}>
          {day.items.map((item) => <ArchiveRow key={itemKey(item)} item={item} restore={restore} ask={setDeleting} />)}
        </NavSection>
      ))}
      {more && <div ref={end} className={css.end} />}
      <Confirm open={deleting !== null} title={t("web-pages.archive.deleteConfirm", { title: deleting?.title ?? "" })}
        description={DELETE_TEXT} action={t("common.delete")}
        onConfirm={remove} onClose={() => setDeleting(null)} />
    </div>
  );
});

/** Archived chats made up, for what the list shows while it is read (in their bones). */
const SAMPLE_ARCHIVE = sampleArchive();

/**
 * An archived chat: its title (its station's mark at the end, with several), the last thing said in it under it, when
 * it was archived there while pointed at (how, on hover); and over the title's end then, putting it back and deleting it.
 */
function ArchiveRow({ item, restore, ask }: { item: ArchiveItem; restore: (item: ArchiveItem) => Promise<void>; ask: (item: ArchiveItem) => void }) {
  const restoring = useDoingState("chat.archive", { station: item.station, session: item.session, archived: false });
  const deleting = useDoingState("session.delete", { station: item.station, key: item.session });
  const busy = restoring.running || deleting.running;
  const read = useCallback(() => prime({ topic: "chat", station: item.station, session: item.id }), [item.station, item.id]);
  return (
    <div className={nav.navSessionWrap} data-flip={itemKey(item)} data-busy={busy || undefined}>
      <NavLink className={`${nav.navRow} ${nav.navSession}`} to={chatPath(item)}
        // Pressing a row does not take the focus from the composer; pointed at, its chat is read meanwhile.
        onMouseDown={(e) => e.preventDefault()} onPointerEnter={read} onPointerDown={read} onFocus={read}>
        <span className={nav.navSessionText}>
          <span className={`${nav.navSessionHead} ${css.head}`}>
            <span className={nav.navSessionTitle}>{item.title}</span>
            {(item.stationEmoji || item.stationIcon) && <Tip label={item.place}><span className={nav.sessionKind} aria-label={item.place ?? undefined}><StationMark emoji={item.stationEmoji} icon={item.stationIcon} size={12} /></span></Tip>}
          </span>
          <span className={nav.navSessionMeta}>
            <span className={nav.navSessionLast}>{item.last}</span>
            <Tip label={item.how}><span className={nav.navTime}>{item.clock}</span></Tip>
          </span>
        </span>
      </NavLink>
      <div className={css.actions}>
        <Tip label={restoring.error ?? t("web-pages.archive.restore")}>
          <button type="button" className={`${pageCss.iconBtn} ${css.action}`} aria-label={t("web-pages.archive.restoreNamed", { title: item.title })}
            disabled={busy} aria-busy={restoring.running || undefined} onMouseDown={(e) => e.preventDefault()} onClick={() => void restore(item)}>
            <DoingShown state={restoring} idle={<Retry size={14} />} bare />
          </button>
        </Tip>
        {item.deletable && (
          <Tip label={deleting.error ?? t("common.delete")}>
            <button type="button" className={`${pageCss.iconBtn} ${css.action} ${css.remove}`} aria-label={t("web-pages.archive.deleteNamed", { title: item.title })}
              disabled={busy} aria-busy={deleting.running || undefined} onMouseDown={(e) => e.preventDefault()} onClick={() => ask(item)}>
              <DoingShown state={deleting} idle={<Trash size={14} />} bare />
            </button>
          </Tip>
        )}
      </div>
    </div>
  );
}

/** What the archive is (the wide screen's empty page; the phone says it at the top). Elements: their words are read as drawn. */
export const ABOUT = <Words k="web-pages.archive.about" />;
export const DELETE_TEXT = <Words k="web-pages.archive.deleteText" />;
