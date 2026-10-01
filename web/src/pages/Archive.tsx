// The archive: chats archived by hand or by the station once they idled (a
// day by default), of every station online in one list, newest first and
// grouped by the day they were archived; each can be shown again, and one
// archived with its session deleted for good. Anything new said in a chat
// brings it back by itself.
import { useState } from "react";
import { stationApi, stationCall, useArchiveView } from "../api.ts";
import { useCall } from "../core/react.ts";
import type { ArchiveItem } from "../core/shapes.ts";
import { useToast } from "../toast.tsx";
import { doingMatches, useDoingList } from "../doing.ts";
import * as waitingCss from "../styles/waiting.css.ts";
import { About, Confirm, MobileBack, Tip } from "../ui.tsx";
import { Retry, Trash } from "../icons.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as css from "./Archive.css.ts";
import * as controlsCss from "../styles/controls.css.ts";

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
      toast("已恢复到列表");
    } catch (e) {
      toast(`没能恢复：${e instanceof Error ? e.message : String(e)}`);
    }
  };
  const remove = async (item: ArchiveItem) => {
    await api(item).deleteSession(item.session);
    toast("已删除");
  };
  // Not there yet: being read; refused (a core from before the archive): why.
  const note = view.value ? view.value.note : view.error ? view.error.message : "正在读取 station…";
  return { days: view.value?.days ?? [], errors: view.value?.errors ?? [], note, restore, remove };
}

/** A row's key in its list. */
export const itemKey = (item: ArchiveItem) => `${item.station}/${item.thread ?? item.session}`;

export function ArchivePage({ scope, back }: { scope: string; back: string }) {
  const toast = useToast();
  const { days, errors, note, restore, remove: removeItem } = useArchive(scope, toast);
  const [deleting, setDeleting] = useState<ArchiveItem | null>(null);
  const [busy, setBusy] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);
  // Being put back in the list: its button turns until the station answers.
  const doing = useDoingList();
  const restoring = (item: ArchiveItem) => doing.some((d) => doingMatches(d, "chat.archive", { station: item.station, session: item.session, archived: false }));
  const remove = async () => {
    if (!deleting) return;
    setBusy(true);
    setDeleteError(null);
    try {
      await removeItem(deleting);
      setDeleting(null);
    } catch (e) {
      setDeleteError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  };
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={back} label="对话" />
      <header className={pagesCss.pageHead}><div><h1>已归档<About>{ABOUT}</About></h1></div></header>
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
                  <Tip label="恢复到列表"><button type="button" className={`${pagesCss.iconBtn} ${css.archiveAction}`} aria-label={`恢复「${item.title}」`}
                    disabled={restoring(item)} aria-busy={restoring(item) || undefined} onClick={() => void restore(item)}>
                    {restoring(item) ? <span className={`${waitingCss.spinner} ${controlsCss.iconSpinner}`} aria-hidden="true" /> : <Retry size={14} />}
                  </button></Tip>
                  {item.deletable && (
                    <Tip label="删除"><button type="button" className={`${pagesCss.iconBtn} ${css.archiveAction} ${css.archiveDelete}`} aria-label={`删除「${item.title}」`} onClick={() => { setDeleteError(null); setDeleting(item); }}><Trash size={14} /></button></Tip>
                  )}
                </div>
              </div>
              <span className={css.archiveMeta}>{item.last}</span>
            </div>
          ))}
        </section>
      ))}
      <Confirm open={deleting !== null} title={`删除「${deleting?.title ?? ""}」？`}
        description={DELETE_TEXT} action="删除"
        onConfirm={() => void remove()} onClose={() => setDeleting(null)} busy={busy} error={deleteError} />
    </div>
  );
}

/** What the archive is (the wide screen's tip; the phone says it at the top). */
export const ABOUT = "手动归档的对话，和空闲超过一天、已经做完的对话（没在跑、没停在 block、没有未读）。对话里有新消息时会自动回到列表。";
export const DELETE_TEXT = "它的会话、对话记录和 workspace 目录都会删掉，不能恢复。";
