import { ArrowLeft, KeyRound, Plus, Settings } from "lucide-react";
import { useLink } from "./station.tsx";
import { useMemo, useState } from "react";
import { NavLink, useLocation, useParams } from "react-router";
import { useOverview, useSessions, type SessionSummary } from "./api.ts";
import { connectionText, dayLabel, modeShort, presence, relativeTime, sessionStatus, sessionTitle } from "./format.ts";
import { NewConnectDialog } from "./pages/Connect.tsx";
import { ConnectKindIcon, ICON, IconButton, StatusDot, Tip } from "./ui.tsx";

export function Sidebar() {
  const settings = useLocation().pathname.startsWith("/settings");
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
  return (
    <div className="nav-scroll">
      <NavLink className="nav-row" to={link("/sessions")}><ArrowLeft {...ICON} />返回会话</NavLink>
      <div className="nav-heading">设置</div>
      <NavLink className="nav-row" to={link("/settings/accounts")}><KeyRound {...ICON} />运行时账号</NavLink>
    </div>
  );
}

function MainNav() {
  const link = useLink();
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
          <p className="nav-empty">{connects.length ? "在 Slack 里 @ 它，会话就会出现在这里。" : "先在下面添加一个连接。"}</p>
        )}
        {groups.map((group) => (
          <section key={group.label} aria-label={group.label}>
            <div className="nav-heading">{group.label}</div>
            {group.items.map((s) => <SessionRow key={s.key} session={s} connect={byId.get(s.connect)} />)}
          </section>
        ))}
      </div>
      <section className="nav-connects" aria-label="连接">
        <div className="nav-heading nav-heading-action">
          <span>连接</span>
          <IconButton label="添加连接" icon={Plus} onClick={() => setAdding(true)} />
        </div>
        {connects.length === 0 && <p className="nav-empty">还没有连接。</p>}
        {connects.map((c) => (
          <NavLink key={c.id} className="nav-row" to={link(`/connects/${c.id}`)}>
            <ConnectKindIcon kind={c.kind} />
            <span className="nav-text">{c.name}</span>
            <span className="nav-note">{c.connection.state === "connected" ? modeShort(c.mode) : connectionText(c.connection)}</span>
            <StatusDot state={presence(c.connection)} label={connectionText(c.connection)} />
          </NavLink>
        ))}
      </section>
      <div className="nav-foot">
        <NavLink className="nav-row" to={link("/settings")}><Settings {...ICON} />设置</NavLink>
      </div>
      <NewConnectDialog open={adding} onClose={() => setAdding(false)} />
    </>
  );
}

/** A session in a list. `station` names the station it runs on, where several share one list. */
export function SessionRow({ session: s, connect, station }: { session: SessionSummary; connect: { id: string; name: string } | undefined; station?: string }) {
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
          <span className="nav-text">{station ? `${station} · ` : ""}{s.scope === "all" ? `${name} · 单会话` : name}</span>
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
