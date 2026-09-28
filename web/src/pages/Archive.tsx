// The archive: chats archived by hand or by the station once they idled (a
// day by default), newest first; each can be shown again, and one archived
// with its session deleted for good. Anything new said in a chat brings it
// back by itself.
import { useEffect, useState } from "react";
import { stationApi, useStations, useStationCall, type StationView } from "../api.ts";
import type { ChatRow } from "../../../src/admin/types.ts";
import { useToast } from "../toast.tsx";
import { About, Button, Confirm, MobileBack } from "../ui.tsx";

export function ArchivePage({ scope, back }: { scope: string; back: string }) {
  const stations = useStations(scope);
  const online = (stations.value ?? []).filter((s) => s.online);
  return (
    <div className="page page-narrow">
      <MobileBack to={back} label="对话" />
      <header className="page-head"><div><h1>已归档<About>手动归档的对话，和空闲超过一天、已经做完的对话（没在跑、没停在 block、没有未读）。对话里有新消息时会自动回到列表。</About></h1></div></header>
      {!stations.value && <p className="muted">正在读取 station…</p>}
      {stations.value && online.length === 0 && <p className="muted">没有在线的 station。</p>}
      {online.map((view) => <ArchivedOn key={view.station} view={view} named={scope !== "local" && online.length > 1} />)}
    </div>
  );
}

const when = (at: number) => new Date(at).toLocaleString("zh-CN", { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" });

function ArchivedOn({ view, named }: { view: StationView; named: boolean }) {
  const api = stationApi(useStationCall(view.station));
  const toast = useToast();
  const [rows, setRows] = useState<ChatRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [deleting, setDeleting] = useState<ChatRow | null>(null);
  const [busy, setBusy] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);
  useEffect(() => {
    let live = true;
    api.archivedChats().then((r) => live && setRows(r), (e: Error) => live && setError(e.message));
    return () => { live = false; };
  }, [view.station]);
  const gone = (row: ChatRow) => setRows((all) => all?.filter((r) => r !== row) ?? null);
  const restore = async (row: ChatRow) => {
    try {
      await api.archive(row, false);
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
      await api.deleteSession(deleting.session);
      gone(deleting);
      setDeleting(null);
      toast("已删除");
    } catch (e) {
      setDeleteError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  };
  const sorted = [...(rows ?? [])].sort((a, b) => (b.archived?.at ?? 0) - (a.archived?.at ?? 0));
  return (
    <section className="archive-station" aria-label={view.name}>
      {named && <div className="nav-heading">{view.name}</div>}
      {error && <p className="field-error">{error}</p>}
      {!rows && !error && <p className="muted">正在读取…</p>}
      {rows && sorted.length === 0 && <p className="muted">没有归档的对话。</p>}
      <div className="archive-list">
        {sorted.map((row) => (
          <div key={`${row.thread ?? row.session}`} className="archive-row">
            <div className="archive-text">
              <span className="archive-title">{row.title}</span>
              <span className="archive-meta">
                {row.archived?.by === "auto" ? "空闲后自动归档" : "手动归档"} · {when(row.archived?.at ?? row.lastActiveAt)}
                {row.last?.text ? ` · ${row.last.text}` : ""}
              </span>
            </div>
            <div className="archive-actions">
              <Button variant="ghost" onClick={() => void restore(row)}>恢复</Button>
              {/* A chat archived alone has agents still at work elsewhere: nothing of theirs is deleted from here. */}
              {!row.archived?.alone && <Button variant="ghost" onClick={() => { setDeleteError(null); setDeleting(row); }}>删除</Button>}
            </div>
          </div>
        ))}
      </div>
      <Confirm open={deleting !== null} title={`删除「${deleting?.title ?? ""}」？`}
        description="它的会话、对话记录和 workspace 目录都会删掉，不能恢复。" action="删除"
        onConfirm={() => void remove()} onClose={() => setDeleting(null)} busy={busy} error={deleteError} />
    </section>
  );
}
