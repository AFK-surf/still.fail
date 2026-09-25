import { ArrowLeft, KeyRound, Plus, Settings } from "lucide-react";
import { useMemo, useState } from "react";
import { NavLink, useLocation, useParams } from "react-router";
import { useOverview, useSessions, type SessionSummary } from "./api.ts";
import { cleanText, connectionText, dayLabel, presence, relativeTime, sessionStatus } from "./format.ts";
import { NewBotDialog } from "./pages/NewBot.tsx";
import { Avatar, ICON, IconButton, StatusDot } from "./ui.tsx";

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
  const bots = overview.data?.bots ?? [];
  const byId = useMemo(() => new Map(bots.map((b) => [b.id, b])), [bots]);
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
          <p className="nav-empty">{bots.length ? "在 Slack 里 @ 一个 bot，会话就会出现在这里。" : "先添加一个 bot。"}</p>
        )}
        {groups.map((group) => (
          <section key={group.label} aria-label={group.label}>
            <div className="nav-heading">{group.label}</div>
            {group.items.map((s) => <SessionRow key={s.key} session={s} bot={byId.get(s.bot)} />)}
          </section>
        ))}
        <div className="nav-heading nav-heading-action">
          Bot
          <IconButton label="添加 Bot" icon={Plus} onClick={() => setAdding(true)} />
        </div>
        {bots.map((b) => (
          <NavLink key={b.id} className="nav-row" to={`/bots/${b.id}`}>
            <Avatar id={b.id} name={b.name} />
            <span className="nav-text">{b.name}</span>
            <StatusDot state={presence(b.connection)} label={connectionText(b.connection)} />
            {b.connection.state !== "connected" && <span className="nav-note">{connectionText(b.connection)}</span>}
          </NavLink>
        ))}
      </div>
      <div className="nav-foot">
        <NavLink className="nav-row" to="/settings"><Settings {...ICON} />设置</NavLink>
      </div>
      <NewBotDialog open={adding} onClose={() => setAdding(false)} />
    </>
  );
}

function SessionRow({ session: s, bot }: { session: SessionSummary; bot: { id: string; name: string } | undefined }) {
  const { key } = useParams();
  const status = sessionStatus(s);
  const marker = status === "running" || status === "queued" ? "running"
    : status === "block" ? "attention" : status === "failed" || status === "unexpected" ? "problem" : null;
  return (
    <NavLink className="nav-row nav-session" to={`/sessions/${encodeURIComponent(s.key)}`} aria-current={key === s.key ? "page" : undefined}>
      <span className="nav-session-text">
        <span className="nav-session-title">{cleanText(s.firstText) || "（没有消息）"}</span>
        <span className="nav-session-meta">
          <Avatar id={s.bot} name={bot?.name ?? s.bot} size={14} />
          {bot?.name ?? s.bot} · {relativeTime(s.lastActiveAt)}
        </span>
      </span>
      {marker && <span className="nav-marker" data-kind={marker} aria-label={marker === "running" ? "进行中" : marker === "attention" ? "等你回复" : "需要处理"} />}
    </NavLink>
  );
}
