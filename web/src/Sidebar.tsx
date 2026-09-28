import { ArrowLeft, Brain, ChevronRight, Compose, Key, Monitor, Plug, Settings, Unplug } from "./icons.tsx";
import { stationBase, useLink, useOnlyMine } from "./station.tsx";
import { lastChat } from "./lastChat.ts";
import { MineFilter } from "./components.tsx";
import { NavLink, useLocation } from "react-router";
import { useChats, type ChatItem } from "./api.ts";
import { ConnectKindIcon, ICON, ModelLogo, ResizeHandle, SkeletonRows, StatusDot, Time, Tip } from "./ui.tsx";
import { SidebarBrand, Mark } from "./brand.tsx";
import { chatClicked } from "./telemetry.ts";
import { useCallback } from "react";

export function Sidebar() {
  const path = useLocation().pathname;
  const settings = path.startsWith("/settings") || path.startsWith("/connects");
  return (
    <nav className="sidebar" aria-label="导航">
      <ResizeHandle variable="--sidebar-w" edge="right" min={180} max={480} label="调整侧边栏宽度" />
      <div className="brand">
        <SidebarBrand />
      </div>
      {settings ? <SettingsNav /> : (
        <>
          <ChatList scope="local" newChat="/new" stationsPage="/settings" />
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
      <NavLink className="nav-row" to={link(lastChat("local", "/chats"))}><ArrowLeft {...ICON} />返回会话</NavLink>
      <div className="nav-heading">设置</div>
      <NavLink className="nav-row" to={link("/settings/connects")} aria-current={connectOpen ? "page" : undefined}><Plug {...ICON} />连接</NavLink>
      <NavLink className="nav-row" to={link("/settings/accounts")}><Key {...ICON} />Profile</NavLink>
      <NavLink className="nav-row" to={link("/settings/memory")}><Brain {...ICON} />记忆</NavLink>
      <NavLink className="nav-row" to={link("/settings/device")}><Monitor {...ICON} />设备</NavLink>
    </div>
  );
}

/**
 * The chats of a scope (a workspace, or this station), newest first and
 * grouped by day, as the core's `chats` view has them; optionally only the
 * ones the viewer started, with `newChat` above them. With no station its empty state leads to `stationsPage` (the page
 * itself, where stations are added: nothing is appended to it).
 */
export function ChatList({ scope, newChat, stationsPage }: { scope: string; newChat: string; stationsPage: string }) {
  const [onlyMine] = useOnlyMine();
  // Both lists are followed at once, side by side: switching slides from one to the other with nothing to wait for.
  const all = useChats(scope, false);
  const mine = useChats(scope, true);
  return (
    <>
      <div className="nav-new">
        <NavLink className="nav-row" to={newChat}><Compose {...ICON} />新建对话</NavLink>
        {/* Nothing to narrow while there is no chat at all. */}
        {!(all.value && !all.value.loading && all.value.days.length === 0) && <MineFilter label="会话" mine="我参与的" compact />}
      </div>
      <div className="nav-slider">
        <div className="nav-track" data-mine={onlyMine || undefined}>
          <ChatPane chats={all} scope={scope} onlyMine={false} stationsPage={stationsPage} hidden={onlyMine} />
          <ChatPane chats={mine} scope={scope} onlyMine stationsPage={stationsPage} hidden={!onlyMine} />
        </div>
      </div>
    </>
  );
}

/**
 * The workspace's stations not working as they should (the core's `trouble`): a row at the top of the sidebar's foot,
 * over the account — which, or how many, and the worst state's dot (a spinner while one reconnects). It leads to the
 * stations. Nothing while all work.
 */
export function StationTrouble({ scope, to }: { scope: string; to: string }) {
  const trouble = useChats(scope, false).value?.trouble;
  if (!trouble) return null;
  return (
    <NavLink className="nav-row station-trouble" to={to} data-state={trouble.state}>
      <span className="station-trouble-mark">
        {trouble.state === "reconnecting" ? <span className="spinner row-spinner" aria-hidden="true" /> : <StatusDot state={trouble.state === "error" ? "error" : "offline"} />}
      </span>
      <span className="station-trouble-text">{trouble.text}</span>
      <ChevronRight size={14} className="station-trouble-go" aria-hidden="true" />
    </NavLink>
  );
}

/** One of the two lists, all or the viewer's: its states (connecting, failing, empty) and its days; an offline station's chats say so row by row. */
function ChatPane({ chats, scope, onlyMine, stationsPage, hidden }: { chats: ReturnType<typeof useChats>; scope: string; onlyMine: boolean; stationsPage: string; hidden: boolean }) {
  const view = chats.value;
  const stations = view?.stations ?? [];
  const days = view?.days ?? [];
  // One station of one's own: its name says nothing, and its state is the page's.
  const several = scope !== "local";
  const connecting = several ? stations.filter((s) => s.state === "connecting") : [];
  const failed = several ? stations.filter((s) => s.state === "error") : [];
  const loading = !view || view.loading;
  const scroller = useScrolling();
  // A station's link coming back is said on its rows (the core's `reconnecting`); only with no rows at all to show does
  // the list say it, in place of the rows.
  return (
    <div ref={scroller} className="nav-scroll" aria-hidden={hidden || undefined} inert={hidden || undefined}>
      {chats.error && !view && <p className="nav-empty nav-error">{chats.error.message}</p>}
      {days.length === 0 && !loading && failed.map((s) => <p key={s.station} className="nav-empty nav-error" title={s.message ?? undefined}>连不上「{s.name}」，正在重试…</p>)}
      {days.length === 0 && (loading || connecting.length > 0) && !chats.error && <SkeletonRows />}
      {days.length === 0 && view && !loading && !failed.length && !connecting.length && (
        <p className="nav-empty">{onlyMine ? "没有你参与的会话。"
          : stations.length ? "还没有会话。"
          : <>还没有 station，到 <NavLink className="inline-link" to={stationsPage}>设置 → Station</NavLink> 添加。</>}</p>
      )}
      {days.map((day) => (
        <section key={day.daysAgo} aria-label={day.label}>
          <div className="nav-heading">{day.label}</div>
          {day.items.map((item) => <ChatRow key={`${item.station}/${item.id}`} item={item} />)}
        </section>
      ))}
    </div>
  );
}

/** Marks a scroller `data-scrolling` while it scrolls and a moment after (its rows ignore the pointer meanwhile). */
function useScrolling() {
  return useCallback((el: HTMLElement | null) => {
    if (!el) return;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const onScroll = () => {
      el.dataset.scrolling = "";
      clearTimeout(timer);
      timer = setTimeout(() => delete el.dataset.scrolling, 150);
    };
    el.addEventListener("scroll", onScroll, { passive: true });
    return () => { el.removeEventListener("scroll", onScroll); clearTimeout(timer); };
  }, []);
}

/**
 * A chat in the list: its title (bold while something in it is unread) and
 * where it came from, then the last thing said in it, when, and its agents'
 * state as a dot (block before work before failure).
 */
function ChatRow({ item }: { item: ChatItem }) {
  const { connect } = item;
  return (
    <NavLink className="nav-row nav-session" to={`${stationBase(item.station)}/chats/${encodeURIComponent(item.id)}`} data-unread={item.unread || undefined} data-offline={item.offline ? true : undefined} onClick={chatClicked}
      // Pressing a chat does not take the focus from the composer: it stays there, focused, into the next chat.
      onMouseDown={(e) => e.preventDefault()}>
      {item.unread && <span className="unread-dot" role="img" aria-label="有未读消息" />}
      <AgentsPicture item={item} />
      <span className="nav-session-text">
        {/* Where the chat happens sits at the title's end, top right. */}
        <span className="nav-session-head">
          <span className="nav-session-title">{item.title}</span>
          {/* Only an agent that came from elsewhere (Slack) says so; one made on ember needs no mark. */}
          {/* Slack is the only kind of connect there is. */}
          {/* Its station offline: greyed, and marked there instead (the core says so, row by row). */}
          {item.offline
            ? <Tip label={item.offline} side="right"><span className="session-kind" aria-label={item.offline}><Unplug size={12} /></span></Tip>
            : item.reconnecting
            ? <Tip label={item.reconnecting} side="right"><span className="session-kind" aria-label={item.reconnecting}><span className="spinner row-spinner" aria-hidden="true" /></span></Tip>
            : connect && <Tip label={item.originText ?? "Slack"} side="right"><span className="session-kind"><ConnectKindIcon kind="slack" size={12} /></span></Tip>}
        </span>
        {/* People are in the chat itself; here only the last thing said and when. */}
        <span className="nav-session-meta">
          {item.last ? <LastMessage item={item} /> : <span className="nav-session-last" />}
          <Time className="nav-time" stamp={item.time?.lastActiveAt} fixed />
        </span>
      </span>
    </NavLink>
  );
}

/**
 * Who is in a chat, as its row's picture: its agent's mark, or two of its agents' overlapping (more are in the chat
 * itself), with its state (block, run, failed: the core's) at the corner. A chat with no agent yet shows ember's.
 */
function AgentsPicture({ item }: { item: ChatItem }) {
  const agents = item.agents.slice(0, 2);
  return (
    <span className="row-picture" data-count={agents.length || 1} data-badge={item.state ?? undefined} title={item.agents.map((a) => a.agentText).join("、") || undefined} aria-hidden="true">
      {agents.length === 0
        ? <span className="row-agent"><Mark size={20} /></span>
        : agents.map((a) => <span key={a.key} className="row-agent"><ModelLogo maker={a.maker} runtime={a.runtime} size={agents.length > 1 ? 14 : 22} /></span>)}
    </span>
  );
}

/** The last thing said in a chat, on one line (the row's picture says who is in it). */
function LastMessage({ item }: { item: ChatItem }) {
  return <span className="nav-session-last">{item.last!.preview}</span>;
}
