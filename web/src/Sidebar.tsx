import { ArrowLeft, KeyRound, Monitor, Plug, Settings, SquarePen } from "lucide-react";
import { stationBase, useLink, useOnlyMine } from "./station.tsx";
import { lastChat } from "./lastChat.ts";
import { MineFilter } from "./components.tsx";
import { NavLink, useLocation } from "react-router";
import { MeContext, useChats, type ChatItem } from "./api.ts";
import { BADGE_LABEL, cleanText, dayLabel } from "./format.ts";
import { Avatar, ConnectKindIcon, ICON, ModelLogo, ResizeHandle, SkeletonRows, Time, Tip } from "./ui.tsx";
import { SidebarBrand, Mark } from "./brand.tsx";
import { chatClicked } from "./telemetry.ts";

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
      <NavLink className="nav-row" to={link(lastChat("local", "/chats"))}><ArrowLeft {...ICON} />返回会话</NavLink>
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
  // Both lists are followed at once, side by side: switching slides from one to the other with nothing to wait for.
  const all = useChats(scope, false);
  const mine = useChats(scope, true);
  return (
    <MeContext.Provider value={all.value?.me ?? mine.value?.me ?? null}>
      <div className="nav-new">
        <NavLink className="nav-row" to={newChat}><SquarePen {...ICON} />新建对话</NavLink>
        <MineFilter label="会话" mine="我参与的" compact />
      </div>
      <div className="nav-slider">
        <div className="nav-track" data-mine={onlyMine || undefined}>
          <ChatPane chats={all} scope={scope} onlyMine={false} newChat={newChat} settings={settings} hidden={onlyMine} />
          <ChatPane chats={mine} scope={scope} onlyMine newChat={newChat} settings={settings} hidden={!onlyMine} />
        </div>
      </div>
    </MeContext.Provider>
  );
}

/** One of the two lists, all or the viewer's: its states (connecting, offline, empty) and its days. */
function ChatPane({ chats, scope, onlyMine, newChat, settings, hidden }: { chats: ReturnType<typeof useChats>; scope: string; onlyMine: boolean; newChat: string; settings: string; hidden: boolean }) {
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
    <div className="nav-scroll" aria-hidden={hidden || undefined} inert={hidden || undefined}>
      {connecting.map((s) => <p key={s.station} className="nav-connecting"><span className="spinner" aria-hidden="true" />正在连接 {s.name}…</p>)}
      {failed.map((s) => <p key={s.station} className="nav-empty nav-error" title={s.message ?? undefined}>连不上「{s.name}」，正在重试…</p>)}
      {chats.error && !view && <p className="nav-empty nav-error">{chats.error.message}</p>}
      {days.length === 0 && loading && !chats.error && <SkeletonRows />}
      {offline.length > 0 && <p className="nav-empty">{offline.map((s) => s.name).join("、")} 离线：列出的是之前读到的会话，暂时不能发消息。</p>}
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
            {day.items.map((item) => <ChatRow key={`${item.station}/${item.id}`} item={item} />)}
          </section>
        );
      })}
    </div>
  );
}

/**
 * A chat in the list: its title (bold while something in it is unread) and
 * where it came from, then the last thing said in it, when, and its agents'
 * state as a dot (block before work before failure).
 */
function ChatRow({ item }: { item: ChatItem }) {
  const { connect } = item;
  return (
    <NavLink className="nav-row nav-session" to={`${stationBase(item.station)}/chats/${encodeURIComponent(item.id)}`} data-unread={item.unread || undefined} onClick={chatClicked}
      // Pressing a chat does not take the focus from the composer: it stays there, focused, into the next chat.
      onMouseDown={(e) => e.preventDefault()}>
      {item.unread && <span className="unread-dot" role="img" aria-label="有未读消息" />}
      <span className="nav-session-text">
        {/* Where the chat happens sits at the title's end, top right. */}
        <span className="nav-session-head">
          <span className="nav-session-title">{item.title}</span>
          {/* Only an agent that came from elsewhere (Slack) says so; one made on ember needs no mark. */}
          {/* Slack is the only kind of connect there is. */}
          {connect && <Tip label={originLabel(item)} side="right"><span className="session-kind"><ConnectKindIcon kind="slack" size={12} /></span></Tip>}
        </span>
        {/* People are in the chat itself; here only the last thing said and when. */}
        <span className="nav-session-meta">
          {item.last ? <LastMessage item={item} /> : <span className="nav-session-last" />}
          <Time className="nav-time" at={item.lastActiveAt} fixed />
        </span>
      </span>
    </NavLink>
  );
}

/** Where a chat's agent came from, for the connect icon's tip: the Slack workspace, then the thread's channel. */
function originLabel(item: ChatItem): string {
  const o = item.origin;
  const where = !o ? null : o.channelName ? `#${o.channelName}` : o.channel.startsWith("D") ? "私信" : null;
  return ["Slack", o?.teamName, where].filter(Boolean).join(" · ");
}

/**
 * The last thing said in a chat, on one line: a small picture of who said it (name on hover), then what. Who it is
 * and the agent's state on its picture are the core's (present.rs); the state shows only there.
 */
function LastMessage({ item }: { item: ChatItem }) {
  const last = item.last!;
  const by = last.by;
  const name = by?.name ?? last.authorName ?? last.author;
  const who = !by || by.kind === "person"
    ? by?.picture ? <img className="person-pic" src={by.picture} alt="" width={12} height={12} referrerPolicy="no-referrer" /> : <Avatar id={last.author} name={name} size={12} />
    : by.kind === "ember" ? <Mark size={12} />
    : <span className="who-agent" data-badge={by.state ?? undefined}><ModelLogo model={by.model ?? null} runtime={by.runtime ?? "claude"} size={12} /></span>;
  const label = by?.kind === "agent" && by.state ? `${name}（${BADGE_LABEL[by.state]}）` : name;
  const text = cleanText(last.text) || "（文件）";
  return <span className="nav-session-last"><span className="nav-session-who" title={label} aria-label={`${label}：`}>{who}</span>{text}</span>;
}
