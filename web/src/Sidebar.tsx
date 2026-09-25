import { ArrowLeft, KeyRound, Plug, Settings } from "lucide-react";
import { useIsMine, useLink } from "./station.tsx";
import { useMemo } from "react";
import { MineFilter, PeopleStack, useOnlyMine } from "./components.tsx";
import { NavLink, useLocation, useParams } from "react-router";
import { useOverview, useSessions, type SessionSummary } from "./api.ts";
import { dayLabel, relativeTime, sessionStatus, sessionTitle } from "./format.ts";
import { ConnectKindIcon, ICON, Tip } from "./ui.tsx";

export function Sidebar() {
  const path = useLocation().pathname;
  const settings = path.startsWith("/settings") || path.startsWith("/connects");
  return (
    <nav className="sidebar" aria-label="导航">
      <div className="brand">
        <img src={`${import.meta.env.BASE_URL}ember.svg`} alt="" width={22} height={22} />
        <span className="brand-word">ember</span>
      </div>
      {settings ? <SettingsNav /> : <MainNav />}
    </nav>
  );
}

function SettingsNav() {
  const link = useLink();
  const connectOpen = useLocation().pathname.startsWith("/connects");
  return (
    <div className="nav-scroll">
      <NavLink className="nav-row" to={link("/sessions")}><ArrowLeft {...ICON} />返回会话</NavLink>
      <div className="nav-heading">设置</div>
      <NavLink className="nav-row" to={link("/settings/connects")} aria-current={connectOpen ? "page" : undefined}><Plug {...ICON} />连接</NavLink>
      <NavLink className="nav-row" to={link("/settings/accounts")}><KeyRound {...ICON} />Profile</NavLink>
    </div>
  );
}

/** Sessions, newest first, grouped by day; optionally only the ones the viewer started. */
export function useSessionGroups<T extends { session: SessionSummary }>(rows: T[]): { label: string; items: T[] }[] {
  const [onlyMine] = useOnlyMine();
  const isMine = useIsMine();
  return useMemo(() => {
    const list = rows.filter((r) => !onlyMine || isMine(r.session.creator)).sort((a, b) => b.session.lastActiveAt - a.session.lastActiveAt);
    const out: { label: string; items: T[] }[] = [];
    for (const r of list) {
      const label = dayLabel(r.session.lastActiveAt);
      if (out.at(-1)?.label !== label) out.push({ label, items: [] });
      out.at(-1)!.items.push(r);
    }
    return out;
    // isMine is stable for a given viewer
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rows, onlyMine]);
}

function MainNav() {
  const link = useLink();
  const overview = useOverview();
  const sessions = useSessions();
  const [onlyMine] = useOnlyMine();
  const connects = overview.data?.connects ?? [];
  const byId = useMemo(() => new Map(connects.map((c) => [c.id, c])), [connects]);
  const rows = useMemo(() => (sessions.data ?? []).map((session) => ({ session })), [sessions.data]);
  const groups = useSessionGroups(rows);

  return (
    <>
      <MineFilter label="会话" />
      <div className="nav-scroll">
        {groups.length === 0 && !sessions.isPending && (
          <p className="nav-empty">{onlyMine ? "没有你发起的会话。" : connects.length ? "在 Slack 里 @ 它，会话就会出现在这里。" : "先到「设置 → 连接」添加一个连接。"}</p>
        )}
        {groups.map((group) => (
          <section key={group.label} aria-label={group.label}>
            <div className="nav-heading">{group.label}</div>
            {group.items.map(({ session: s }) => <SessionRow key={s.key} session={s} connect={byId.get(s.connect)} />)}
          </section>
        ))}
      </div>
      <div className="nav-foot">
        <NavLink className="nav-row" to={link("/settings")}><Settings {...ICON} />设置</NavLink>
      </div>
    </>
  );
}

/** A session in a list. `station` names the station it runs on, where several share one list. */
export function SessionRow({ session: s, connect, station }: { session: SessionSummary; connect: { id: string; name: string; kind?: string } | undefined; station?: string }) {
  const link = useLink();
  const name = connect?.name ?? s.connect;
  const { key } = useParams();
  const status = sessionStatus(s);
  const marker = status === "running" || status === "queued" ? "running"
    : status === "block" ? "attention" : status === "failed" || status === "unexpected" ? "problem" : null;
  return (
    <NavLink className="nav-row nav-session" to={link(`/sessions/${encodeURIComponent(s.key)}`)} aria-current={key === s.key ? "page" : undefined}>
      <span className="nav-session-text">
        <span className="nav-session-title">{sessionTitle(s, name)}</span>
        <span className="nav-session-meta">
          <Tip label={connect ? `来自 ${connect.name}` : "来自连接"} side="right"><span className="session-kind"><ConnectKindIcon kind={connect?.kind ?? "slack"} size={12} /></span></Tip>
          {station && <span className="station-tag small">{station}</span>}
          <span className="nav-time">{relativeTime(s.lastActiveAt)}</span>
          <span className="nav-text" />
          <PeopleStack people={s.participants} />
        </span>
      </span>
      {marker && (
        <Tip label={marker === "running" ? "进行中" : marker === "attention" ? "等人回复" : "需要处理"} side="right">
          <span className="nav-marker" data-kind={marker} role="img" aria-label={marker === "running" ? "进行中" : marker === "attention" ? "等人回复" : "需要处理"} />
        </Tip>
      )}
    </NavLink>
  );
}
