import { ArrowLeft, KeyRound, Plus, Settings } from "lucide-react";
import { useMemo, useState } from "react";
import { NavLink, useLocation, useParams } from "react-router";
import { useOverview, useSessions, type SessionSummary } from "./api.ts";
import { cleanText, connectionText, dayLabel, presence, relativeTime, sessionStatus } from "./format.ts";
import { NewConnectDialog } from "./pages/Connect.tsx";
import { Avatar, ICON, IconButton, StatusDot, Tip } from "./ui.tsx";

export function Sidebar() {
  const settings = useLocation().pathname.startsWith("/settings");
  return (
    <nav className="sidebar" aria-label="导航">
      <div className="brand">
        <img src="/admin/ember.svg" alt="" width={22} height={22} />
        <span className="brand-word">ember</span>
      </div>
      {settings ? <SettingsNav /> : <MainNav />}
    </nav>
  );
}

function SettingsNav() {
  return (
    <div className="nav-scroll">
      <NavLink className="nav-row" to="/sessions"><ArrowLeft {...ICON} />返回会话</NavLink>
      <div className="nav-heading">设置</div>
      <NavLink className="nav-row" to="/settings/accounts"><KeyRound {...ICON} />运行时账号</NavLink>
    </div>
  );
}

function MainNav() {
  const overview = useOverview();
  const sessions = useSessions();
  const [adding, setAdding] = useState(false);
  const connects = overview.data?.connects ?? [];
  const byId = useMemo(() => new Map(connects.map((c) => [c.id, c])), [connects]);
  const groups = useMemo(() => {
    const list = [...(sessions.data ?? [])].sort((a, b) => b.lastActiveAt - a.lastActiveAt);
    const out: { label: string; items: SessionSummary[] }[] = [];
    for (const s of list) {
      const label = dayLabel(s.lastActiveAt);
      if (out.at(-1)?.label !== label) out.push({ label, items: [] });
      out.at(-1)!.items.push(s);
    }
    return out;
  }, [sessions.data]);

  return (
    <>
      <div className="nav-scroll">
        {groups.length === 0 && !sessions.isPending && (
          <p className="nav-empty">{connects.length ? "在 Slack 里 @ 它，会话就会出现在这里。" : "先添加一个连接。"}</p>
        )}
        {groups.map((group) => (
          <section key={group.label} aria-label={group.label}>
            <div className="nav-heading">{group.label}</div>
            {group.items.map((s) => <SessionRow key={s.key} session={s} connect={byId.get(s.connect)} />)}
          </section>
        ))}
        <div className="nav-heading nav-heading-action">
          连接
          <IconButton label="添加连接" icon={Plus} onClick={() => setAdding(true)} />
        </div>
        {connects.map((c) => (
          <NavLink key={c.id} className="nav-row" to={`/connects/${c.id}`}>
            <Avatar id={c.id} name={c.name} />
            <span className="nav-text">{c.name}</span>
            {c.connection.state !== "connected" && <span className="nav-note">{connectionText(c.connection)}</span>}
            <StatusDot state={presence(c.connection)} label={connectionText(c.connection)} />
          </NavLink>
        ))}
      </div>
      <div className="nav-foot">
        <NavLink className="nav-row" to="/settings"><Settings {...ICON} />设置</NavLink>
      </div>
      <NewConnectDialog open={adding} onClose={() => setAdding(false)} />
    </>
  );
}

function SessionRow({ session: s, connect }: { session: SessionSummary; connect: { id: string; name: string } | undefined }) {
  const name = connect?.name ?? s.connect;
  const { key } = useParams();
  const status = sessionStatus(s);
  const marker = status === "running" || status === "queued" ? "running"
    : status === "block" ? "attention" : status === "failed" || status === "unexpected" ? "problem" : null;
  return (
    <NavLink className="nav-row nav-session" to={`/sessions/${encodeURIComponent(s.key)}`} aria-current={key === s.key ? "page" : undefined}>
      <span className="nav-session-text">
        <span className="nav-session-title">{s.scope === "all" ? `${name} 的会话` : cleanText(s.firstText) || "（没有消息）"}</span>
        <span className="nav-session-meta">
          <Avatar id={s.connect} name={name} size={14} />
          <span className="nav-text">{s.scope === "all" ? "所有 thread" : name}</span>
          <span className="nav-time">{relativeTime(s.lastActiveAt)}</span>
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
