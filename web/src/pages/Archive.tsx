// The archive: chats archived by hand or by the station once they idled (a
// day by default), of every station online in one list, newest first and
// grouped by the day they were archived; each can be shown again, and one
// archived with its session deleted for good. Anything new said in a chat
// brings it back by itself.
import { useCallback, useEffect, useState } from "react";
import { stationApi, useStations, useStationCall, type ArchivedChat, type StationView } from "../api.ts";
import { useToast } from "../toast.tsx";
import { About, Confirm, MobileBack, Tip } from "../ui.tsx";
import { Retry, Trash } from "../icons.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as css from "./Archive.css.ts";
import * as controlsCss from "../styles/controls.css.ts";

type Api = ReturnType<typeof stationApi>;
/** An archived chat and the station it is on. */
interface Row { chat: ArchivedChat; view: StationView; api: Api }
type Loaded = { rows: Row[] } | { error: string };

export function ArchivePage({ scope, back }: { scope: string; back: string }) {
  const stations = useStations(scope);
  const online = (stations.value ?? []).filter((s) => s.online);
  const [loaded, setLoaded] = useState<Record<string, Loaded>>({});
  const toast = useToast();
  const [deleting, setDeleting] = useState<Row | null>(null);
  const [busy, setBusy] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);
  const onLoad = useCallback((station: string, got: Loaded) => setLoaded((all) => ({ ...all, [station]: got })), []);
  const gone = (row: Row) => setLoaded((all) => {
    const of = all[row.view.station];
    return of && "rows" in of ? { ...all, [row.view.station]: { rows: of.rows.filter((r) => r !== row) } } : all;
  });
  const restore = async (row: Row) => {
    try {
      await row.api.archive(row.chat, false);
      gone(row);
      toast("已恢复到列表");
    } catch (e) {
      toast(`没能恢复：${e instanceof Error ? e.message : String(e)}`);
    }
  };
  const remove = async () => {
    if (!deleting) return;
    setBusy(true);
    setDeleteError(null);
    try {
      await deleting.api.deleteSession(deleting.chat.session);
      gone(deleting);
      setDeleting(null);
      toast("已删除");
    } catch (e) {
      setDeleteError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  };
  const of = online.map((view) => loaded[view.station]);
  const rows = of.flatMap((got) => got && "rows" in got ? got.rows : [])
    .sort((a, b) => archivedAt(b.chat) - archivedAt(a.chat));
  const errors = online.flatMap((view, i) => { const got = of[i]; return got && "error" in got ? [{ view, error: got.error }] : []; });
  const reading = of.some((got) => !got);
  // Which station a chat is on is said only where there is more than one to tell apart.
  const named = scope !== "local" && online.length > 1;
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={back} label="对话" />
      <header className={pagesCss.pageHead}><div><h1>已归档<About>手动归档的对话，和空闲超过一天、已经做完的对话（没在跑、没停在 block、没有未读）。对话里有新消息时会自动回到列表。</About></h1></div></header>
      {online.map((view) => <Fetch key={view.station} view={view} onLoad={onLoad} />)}
      {!stations.value && <p className={shellCss.muted}>正在读取 station…</p>}
      {stations.value && online.length === 0 && <p className={shellCss.muted}>没有在线的 station。</p>}
      {errors.map(({ view, error }) => <p key={view.station} className={controlsCss.fieldError}>{named ? `${view.name}：` : ""}{error}</p>)}
      {rows.length === 0 && online.length > 0 && (reading
        ? <p className={shellCss.muted}>正在读取…</p>
        : errors.length === 0 && <p className={shellCss.muted}>没有归档的对话。</p>)}
      {days(rows).map(([label, items]) => (
        <section key={label} aria-label={label}>
          <div className={css.archiveHeading}>{label}</div>
          {items.map((row) => (
            <div key={`${row.view.station}/${row.chat.thread ?? row.chat.session}`} className={css.archiveRow}>
              <div className={css.archiveHead}>
                <span className={css.archiveTitle}>{row.chat.title}</span>
                <span className={css.archiveWhen} title={row.chat.archived?.by === "auto" ? "空闲后自动归档" : "手动归档"}>
                  {named && <span>{row.view.name}</span>}{clock(archivedAt(row.chat))}
                </span>
                <div className={css.archiveActions}>
                  <Tip label="恢复到列表"><button type="button" className={`${pagesCss.iconBtn} ${css.archiveAction}`} aria-label={`恢复「${row.chat.title}」`} onClick={() => void restore(row)}><Retry size={14} /></button></Tip>
                  {/* A chat archived alone has agents still at work elsewhere: nothing of theirs is deleted from here. */}
                  {!row.chat.archived?.alone && (
                    <Tip label="删除"><button type="button" className={`${pagesCss.iconBtn} ${css.archiveAction} ${css.archiveDelete}`} aria-label={`删除「${row.chat.title}」`} onClick={() => { setDeleteError(null); setDeleting(row); }}><Trash size={14} /></button></Tip>
                  )}
                </div>
              </div>
              <span className={css.archiveMeta}>{row.chat.last?.text ?? ""}</span>
            </div>
          ))}
        </section>
      ))}
      <Confirm open={deleting !== null} title={`删除「${deleting?.chat.title ?? ""}」？`}
        description="它的会话、对话记录和 workspace 目录都会删掉，不能恢复。" action="删除"
        onConfirm={() => void remove()} onClose={() => setDeleting(null)} busy={busy} error={deleteError} />
    </div>
  );
}

/** Reads one station's archive into the page. */
function Fetch({ view, onLoad }: { view: StationView; onLoad: (station: string, got: Loaded) => void }) {
  const api = stationApi(useStationCall(view.station));
  useEffect(() => {
    let live = true;
    api.archivedChats().then(
      (chats) => live && onLoad(view.station, { rows: chats.map((chat) => ({ chat, view, api })) }),
      (e: Error) => live && onLoad(view.station, { error: e.message }));
    return () => { live = false; };
  }, [view.station]);
  return null;
}

const archivedAt = (chat: ArchivedChat) => chat.archived?.at ?? chat.lastActiveAt;
const clock = (at: number) => new Date(at).toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit" });
const WEEKDAY = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"];

/** Rows (newest first) by the day they were archived, as the chat list has its days: 今天, 昨天, 星期三, 9月20日. */
function days(rows: Row[]): [string, Row[]][] {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const out: [string, Row[]][] = [];
  for (const row of rows) {
    const at = new Date(archivedAt(row.chat));
    const day = new Date(at);
    day.setHours(0, 0, 0, 0);
    const ago = Math.round((today.getTime() - day.getTime()) / 86400000);
    const label = ago <= 0 ? "今天" : ago === 1 ? "昨天" : ago < 7 ? WEEKDAY[at.getDay()]!
      : at.getFullYear() === today.getFullYear() ? `${at.getMonth() + 1}月${at.getDate()}日` : `${at.getFullYear()}年${at.getMonth() + 1}月${at.getDate()}日`;
    const last = out[out.length - 1];
    if (last && last[0] === label) last[1].push(row); else out.push([label, [row]]);
  }
  return out;
}
