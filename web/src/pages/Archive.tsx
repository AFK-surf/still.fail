// The archive: chats archived by hand or by the station once they idled (a
// day by default), of every station online in one list, newest first and
// grouped by the day they were archived; each can be shown again, and one
// archived with its session deleted for good. Anything new said in a chat
// brings it back by itself.
import { useState } from "react";
import { stationApi, stationCall, useArchiveView } from "../api.ts";
import { useCall } from "../core/react.ts";
import type { ArchiveItem } from "../core/shapes.ts";
import { failure, useToast } from "../toast.tsx";
import { DoingShown, useDoingState } from "../DoingMark.tsx";
import { About, Confirm, MobileBack, Tip } from "../ui.tsx";
import { Retry, Trash } from "../icons.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as css from "./Archive.css.ts";
import * as controlsCss from "../styles/controls.css.ts";
import { t } from "../i18n.ts";
import { Words } from "../cloud/words.tsx";

/**
 * The archive of a scope's stations online, as both screens show it (the phone's in ../mobile/Archive.tsx), as the
 * core has it (its `archive` topic): its days, what could not be read, what to say in place of rows; and putting one
 * back or deleting it, which the core takes out of it. `restore` says how it went in `toast`; `remove` throws what
 * went wrong.
 */
export function useArchive(scope: string, toast: (text: string) => void) {
  const view = useArchiveView(scope);
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
  const note = view.value ? view.value.note : view.error ? view.error.message : t("web-pages.archive.loading");
  return { days: view.value?.days ?? [], errors: view.value?.errors ?? [], note, restore, remove };
}

/** A row's key in its list. */
export const itemKey = (item: ArchiveItem) => `${item.station}/${item.thread ?? item.session}`;

export function ArchivePage({ scope, back }: { scope: string; back: string }) {
  const toast = useToast();
  const { days, errors, note, restore, remove: removeItem } = useArchive(scope, toast);
  const [deleting, setDeleting] = useState<ArchiveItem | null>(null);
  // Asked, the Confirm closes at once: its row turns until the station has deleted it, a failure said by toast.
  const remove = () => {
    if (!deleting) return;
    setDeleting(null);
    void removeItem(deleting).catch((e: unknown) => toast(t("web-main.chat.deleteFailed", { error: failure(e) })));
  };
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={back} label={t("web-pages.decisions.back")} />
      <header className={pagesCss.pageHead}><div><h1>{t("web-pages.archive.title")}<About>{ABOUT}</About></h1></div></header>
      {errors.map((e) => <p key={e.station} className={controlsCss.fieldError}>{e.text}</p>)}
      {note && <p className={shellCss.muted}>{note}</p>}
      {days.map((day) => (
        <section key={day.label} aria-label={day.label}>
          <div className={css.archiveHeading}>{day.label}</div>
          {day.items.map((item) => (
            <div key={itemKey(item)} className={css.archiveRow}>
              <div className={css.archiveHead}>
                <span className={css.archiveTitle}>{item.title}</span>
                <Tip label={item.how}><span className={css.archiveWhen}>
                  {item.place && <span>{item.place}</span>}{item.clock}
                </span></Tip>
                <div className={css.archiveActions}>
                  <RestoreButton item={item} restore={restore} />
                  {item.deletable && <DeleteButton item={item} ask={() => setDeleting(item)} />}
                </div>
              </div>
              <span className={css.archiveMeta}>{item.last}</span>
            </div>
          ))}
        </section>
      ))}
      <Confirm open={deleting !== null} title={t("web-pages.archive.deleteConfirm", { title: deleting?.title ?? "" })}
        description={DELETE_TEXT} action={t("common.delete")}
        onConfirm={remove} onClose={() => setDeleting(null)} />
    </div>
  );
}

/**
 * Puts a row back in the list: it turns until the station answers (the core's `doing`), and when that failed a red
 * mark stays in its place a few seconds, its tip saying why.
 */
function RestoreButton({ item, restore }: { item: ArchiveItem; restore: (item: ArchiveItem) => Promise<void> }) {
  const state = useDoingState("chat.archive", { station: item.station, session: item.session, archived: false });
  return (
    <Tip label={state.error ?? t("web-pages.archive.restore")}><button type="button" className={`${pagesCss.iconBtn} ${css.archiveAction}`} aria-label={t("web-pages.archive.restoreNamed", { title: item.title })}
      disabled={state.running} aria-busy={state.running || undefined} onClick={() => void restore(item)}>
      <DoingShown state={state} className={controlsCss.iconSpinner} size={14} idle={<Retry size={14} />} bare />
    </button></Tip>
  );
}

/** Deleting a row for good, asked first: it turns while the station deletes it, a red mark a few seconds if that failed. */
function DeleteButton({ item, ask }: { item: ArchiveItem; ask(): void }) {
  const state = useDoingState("session.delete", { station: item.station, key: item.session });
  return (
    <Tip label={state.error ?? t("common.delete")}><button type="button" className={`${pagesCss.iconBtn} ${css.archiveAction} ${css.archiveDelete}`} aria-label={t("web-pages.archive.deleteNamed", { title: item.title })}
      disabled={state.running} aria-busy={state.running || undefined} onClick={ask}>
      <DoingShown state={state} className={controlsCss.iconSpinner} size={14} idle={<Trash size={14} />} bare />
    </button></Tip>
  );
}

/** What the archive is (the wide screen's tip; the phone says it at the top). Elements: their words are read as drawn. */
export const ABOUT = <Words k="web-pages.archive.about" />;
export const DELETE_TEXT = <Words k="web-pages.archive.deleteText" />;
