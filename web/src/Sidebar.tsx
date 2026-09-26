import { ArrowLeft, KeyRound, Monitor, Plug, Settings, SquarePen } from "lucide-react";
import { stationBase, useLink, useOnlyMine, usePerson } from "./station.tsx";
import { lastChat } from "./lastChat.ts";
import { MineFilter, PeopleStack } from "./components.tsx";
import { NavLink, useLocation } from "react-router";
import { MeContext, useChats, useIsMine, type ChatItem } from "./api.ts";
import { BADGE_LABEL, chatBadge, cleanText, dayLabel } from "./format.ts";
import { Avatar, ConnectKindIcon, ICON, ModelLogo, ResizeHandle, SkeletonRows, Time, Tip } from "./ui.tsx";
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
              {day.items.map((item) => <ChatRow key={`${item.station}/${item.thread.id}`} item={item} />)}
            </section>
          );
        })}
      </div>
    </MeContext.Provider>
  );
}

/**
 * A chat in the list: its title (bold while something in it is unread), the
 * last thing said in it, where it came from, its people and when it was last
 * written in. The dot on the right is its agents' state (block before work
 * before failure).
 */
function ChatRow({ item }: { item: ChatItem }) {
  const { thread, connect } = item;
  const badge = chatBadge(item.agents);
  return (
    <NavLink className="nav-row nav-session" to={`${stationBase(item.station)}/chats/${thread.id}`} data-unread={item.unread || undefined}>
      <span className="nav-session-text">
        {/* Where the chat happens sits at the title's end, top right. */}
        <span className="nav-session-head">
          <span className="nav-session-title">{item.title}</span>
          {thread.surface === "ember"
            ? <Tip label="ember 对话" side="right"><span className="session-kind"><Mark size={16} className="kind-mark" /></span></Tip>
            : <Tip label={connect ? `来自 ${connect.name}` : "来自 Slack"} side="right"><span className="session-kind"><ConnectKindIcon kind={connect?.kind ?? "slack"} size={12} /></span></Tip>}
        </span>
        {item.last && <LastMessage item={item} />}
        <span className="nav-session-meta">
          <PeopleStack people={item.people} />
          <Time className="nav-time" at={item.lastActiveAt} />
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

/** The last thing said in a chat, on one line: a small picture of who said it (name on hover), then what. */
function LastMessage({ item }: { item: ChatItem }) {
  const person = usePerson();
  const isMine = useIsMine();
  const last = item.last!;
  const agent = last.authorKind === "agent" ? item.agents.find((a) => a.key === last.author) : undefined;
  const mine = last.authorKind === "person" && isMine({ id: last.author, email: last.author });
  const name = last.authorKind === "ember" ? "ember"
    : last.authorKind === "agent" ? agent?.model || last.authorName || "agent"
    : mine ? "你" : person(last.author)?.name || last.authorName || last.author;
  const picture = last.authorKind === "person" ? person(last.author)?.picture : undefined;
  const who = last.authorKind === "ember" ? <Mark size={12} />
    : last.authorKind === "agent" ? <ModelLogo model={agent?.model ?? null} runtime={agent?.runtime ?? "claude"} size={12} />
    : picture ? <img className="person-pic" src={picture} alt="" width={12} height={12} referrerPolicy="no-referrer" />
    : <Avatar id={last.author} name={name} size={12} />;
  const text = last.deletedAt !== null ? "（已删除）" : cleanText(last.text) || "（文件）";
  return <span className="nav-session-last"><span className="nav-session-who" title={name} aria-label={`${name}：`}>{who}</span>{text}</span>;
}
