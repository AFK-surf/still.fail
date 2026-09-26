import { ArrowLeft, KeyRound, Monitor, Plug, Settings, SquarePen } from "lucide-react";
import { stationBase, useLink, useOnlyMine } from "./station.tsx";
import { lastChat } from "./lastChat.ts";
import { MineFilter, PeopleStack } from "./components.tsx";
import { NavLink, useLocation, useParams } from "react-router";
import { MeContext, useChats, type ChatItem } from "./api.ts";
import { BADGE_LABEL, dayLabel, sessionStatus, sessionTitle, statusBadge } from "./format.ts";
import { ConnectKindIcon, ICON, ResizeHandle, SkeletonRows, Time, Tip } from "./ui.tsx";
import { Lockup, Mark } from "./brand.tsx";

export function Sidebar() {
  const path = useLocation().pathname;
  const settings = path.startsWith("/settings") || path.startsWith("/connects");
  return (
    <nav className="sidebar" aria-label="导航">
      <ResizeHandle variable="--sidebar-w" edge="right" min={180} max={480} label="调整侧边栏宽度" />
      <div className="brand">
        <Lockup />
      </div>
      {settings ? <SettingsNav /> : (
        <>
          <ChatList scope="local" newChat="/new" settings="/settings" />
          <div className="nav-foot">
            <NavLink className="nav-row" to="/settings"><Settings {...ICON} />设置</NavLink>
          </div>
        </>
      )}
    </nav>
  );
}

function SettingsNav() {
  const link = useLink();
  const connectOpen = useLocation().pathname.startsWith("/connects");
  return (
    <div className="nav-scroll">
      <NavLink className="nav-row" to={link(lastChat("local", "/sessions"))}><ArrowLeft {...ICON} />返回会话</NavLink>
      <div className="nav-heading">设置</div>
      <NavLink className="nav-row" to={link("/settings/connects")} aria-current={connectOpen ? "page" : undefined}><Plug {...ICON} />连接</NavLink>
      <NavLink className="nav-row" to={link("/settings/accounts")}><KeyRound {...ICON} />Profile</NavLink>
      <NavLink className="nav-row" to={link("/settings/device")}><Monitor {...ICON} />设备</NavLink>
    </div>
  );
}

/**
 * The chats of a scope (a workspace, or this station), newest first and
 * grouped by day, as the core's `chats` view has them; optionally only the
 * ones the viewer started. `newChat` and `settings` are where its empty states lead.
 */
export function ChatList({ scope, newChat, settings }: { scope: string; newChat: string; settings: string }) {
  const [onlyMine] = useOnlyMine();
  const chats = useChats(scope, onlyMine);
  const view = chats.value;
  const stations = view?.stations ?? [];
  const days = view?.days ?? [];
  // One station of one's own: its name says nothing, and its state is the page's.
  const several = scope !== "local";
  const connecting = several ? stations.filter((s) => s.state === "connecting") : [];
  const failed = several ? stations.filter((s) => s.state === "error") : [];
  const offline = stations.filter((s) => s.state === "offline");
  const loading = !view || view.loading;
  return (
    <MeContext.Provider value={view?.me ?? null}>
      <div className="nav-new"><NavLink className="nav-row" to={newChat}><SquarePen {...ICON} />新建对话</NavLink></div>
      <MineFilter label="会话" mine="我参与的" />
      <div className="nav-scroll">
        {connecting.map((s) => <p key={s.station} className="nav-connecting"><span className="spinner" aria-hidden="true" />正在连接 {s.name}…</p>)}
        {failed.map((s) => <p key={s.station} className="nav-empty nav-error" title={s.message ?? undefined}>连不上「{s.name}」，正在重试…</p>)}
        {chats.error && !view && <p className="nav-empty nav-error">{chats.error.message}</p>}
        {days.length === 0 && loading && !chats.error && <SkeletonRows />}
        {offline.length > 0 && <p className="nav-empty">{offline.map((s) => s.name).join("、")} 离线，它们的会话暂时看不到。</p>}
        {days.length === 0 && view && !loading && !failed.length && !connecting.length && (
          <p className="nav-empty">{onlyMine ? "没有你参与的会话。"
            : stations.length ? <>还没有会话。在 Slack 里 @ {stations.length > 1 ? "它们" : "它"}，或者 <NavLink className="inline-link" to={newChat}>新建对话</NavLink>。</>
            : <>还没有 station，到 <NavLink className="inline-link" to={`${settings}/stations`}>设置 → Station</NavLink> 添加。</>}</p>
        )}
        {days.map((day) => {
          const label = dayLabel(day.at);
          return (
            <section key={day.daysAgo} aria-label={label}>
              <div className="nav-heading">{label}</div>
              {day.items.map((item) => <SessionRow key={`${item.station}/${item.session.key}`} item={item} />)}
            </section>
          );
        })}
      </div>
    </MeContext.Provider>
  );
}

/** A chat in the list. The station is its agent's, not the chat's: it shows with the agent, not here. Unread messages make the title bold and show their count. */
function SessionRow({ item }: { item: ChatItem }) {
  const { session: s, connect } = item;
  const name = connect?.name ?? s.connect;
  const { key } = useParams();
  const badge = statusBadge(sessionStatus(s));
  return (
    <NavLink className="nav-row nav-session" to={`${stationBase(item.station)}/sessions/${encodeURIComponent(s.key)}`} aria-current={key === s.key ? "page" : undefined}
      data-unread={item.unread > 0 || undefined}>
      <span className="nav-session-text">
        <span className="nav-session-title">{sessionTitle(s, name)}</span>
        <span className="nav-session-meta">
          {s.connect === "ember"
            ? <Tip label="ember 对话" side="right"><span className="session-kind"><Mark size={16} className="kind-mark" /></span></Tip>
            : <Tip label={connect ? `来自 ${connect.name}` : "来自连接"} side="right"><span className="session-kind"><ConnectKindIcon kind={connect?.kind ?? "slack"} size={12} /></span></Tip>}
          <PeopleStack people={s.participants} />
          <Time className="nav-time" at={s.lastActiveAt} />
          {item.unread > 0 && <span className="nav-unread" aria-label={`${item.unread} 条未读`}>{item.unread > 99 ? "99+" : item.unread}</span>}
        </span>
      </span>
      {badge && (
        <Tip label={BADGE_LABEL[badge]} side="right">
          <span className="state-dot" data-badge={badge} role="img" aria-label={BADGE_LABEL[badge]} />
        </Tip>
      )}
    </NavLink>
  );
}
