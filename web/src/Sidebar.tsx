import { Archive, ArrowLeft, Brain, ChevronRight, Command, Compose, Key, Monitor, Plug, Settings, Sliders, Unplug } from "./icons.tsx";
import { stationBase, useLink, useOnlyMine } from "./station.tsx";
import { lastChat } from "./lastChat.ts";
import { MineFilter } from "./components.tsx";
import { NavLink, useLocation, useNavigate } from "react-router";
import { stationApi, useChats, useStationCall, type ChatItem } from "./api.ts";
import { useToast } from "./toast.tsx";
import { ConnectKindIcon, ICON, ModelLogo, ResizeHandle, SkeletonRows, StatusDot, Time, Tip } from "./ui.tsx";
import { SidebarBrand, Mark } from "./brand.tsx";
import { chatClicked } from "./telemetry.ts";
import { useComposerMove } from "./dock.tsx";
import { goToNeighbour } from "./Chat.tsx";
import { CHANGEABLE, useShortcut } from "./keymap.ts";
import { ChatMark } from "./ChatMark.tsx";
import { createContext, useCallback, useContext, useEffect, useState, useSyncExternalStore } from "react";
import { archiveKey, PendingArchives } from "./pendingArchives.ts";
import * as nav from "./Sidebar.css.ts";
import * as waitingCss from "./styles/waiting.css.ts";
import * as chatCss from "./styles/chat.css.ts";
import * as pagesCss from "./styles/pages.css.ts";

export function Sidebar() {
  const path = useLocation().pathname;
  const settings = path.startsWith("/settings") || path.startsWith("/connects");
  return (
    <nav className={nav.sidebar} aria-label="导航">
      <ResizeHandle variable="--sidebar-w" edge="right" min={180} max={480} label="调整侧边栏宽度" />
      <div className={nav.brand}>
        <SidebarBrand />
      </div>
      {settings ? <SettingsNav /> : (
        <>
          <ChatList scope="local" newChat="/new" stationsPage="/settings" archive="/archive" />
          <div className={nav.navFoot}>
            <NavLink className={nav.navRow} to="/settings"><Settings {...ICON} />设置</NavLink>
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
    <div className={nav.navScroll}>
      <NavLink className={nav.navRow} to={link(lastChat("local", "/chats"))}><ArrowLeft {...ICON} />返回会话</NavLink>
      <div className={nav.navHeading}>客户端</div>
      <NavLink className={nav.navRow} to={link("/settings/appearance")}><Sliders {...ICON} />外观</NavLink>
      {CHANGEABLE && <NavLink className={nav.navRow} to={link("/settings/shortcuts")}><Command {...ICON} />快捷键</NavLink>}
      <div className={nav.navHeading}>Station</div>
      <NavLink className={nav.navRow} to={link("/settings/connects")} aria-current={connectOpen ? "page" : undefined}><Plug {...ICON} />连接</NavLink>
      <NavLink className={nav.navRow} to={link("/settings/accounts")}><Key {...ICON} />Profile</NavLink>
      <NavLink className={nav.navRow} to={link("/settings/memory")}><Brain {...ICON} />记忆</NavLink>
      <NavLink className={nav.navRow} to={link("/settings/device")}><Monitor {...ICON} />设备</NavLink>
    </div>
  );
}

/**
 * The chats of a scope (a workspace, or this station), newest first and
 * grouped by day, as the core's `chats` view has them; optionally only the
 * ones the viewer started, with `newChat` above them and the way to the `archive` in the filter's menu beside it. With no station its empty
 * state leads to `stationsPage` (the page itself, where stations are added: nothing is appended to it).
 */
const ArchivesContext = createContext<PendingArchives | null>(null);

export function ChatList({ scope, newChat, stationsPage, archive }: { scope: string; newChat: string; stationsPage: string; archive: string }) {
  const [onlyMine] = useOnlyMine();
  const [pending] = useState(() => new PendingArchives());
  const move = useComposerMove();
  useShortcut("chat.prev", () => goToNeighbour(-1));
  useShortcut("chat.next", () => goToNeighbour(1));
  // Both lists are followed at once, side by side: switching slides from one to the other with nothing to wait for.
  const all = useChats(scope, false);
  const mine = useChats(scope, true);
  useEffect(() => {
    if (all.value && mine.value) {
      pending.reconcile(new Set([...all.value.days, ...mine.value.days].flatMap((day) => day.items.map(archiveKey))));
    }
  }, [pending, all.value, mine.value]);
  return (
    <ArchivesContext.Provider value={pending}>
      <div className={nav.navNew}>
        <NavLink className={nav.navRow} to={newChat} onClick={(e) => move(e, newChat, "new")}><Compose {...ICON} />新建对话</NavLink>
        {/* The filter, and the archive under it: nothing to narrow or look back on with no station at all. */}
        {!(all.value && !all.value.loading && all.value.stations.length === 0) && <MineFilter label="会话" mine="我参与的" compact archive={archive} />}
      </div>
      <div className={nav.navSlider}>
        <div className={nav.navTrack} data-mine={onlyMine || undefined}>
          <ChatPane chats={all} scope={scope} onlyMine={false} stationsPage={stationsPage} hidden={onlyMine} />
          <ChatPane chats={mine} scope={scope} onlyMine stationsPage={stationsPage} hidden={!onlyMine} />
        </div>
      </div>
    </ArchivesContext.Provider>
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
    <NavLink className={`${nav.navRow} ${nav.stationTrouble}`} to={to} data-state={trouble.state}>
      <span className={nav.stationTroubleMark}>
        {trouble.state === "reconnecting" ? <span className={`${waitingCss.spinner} ${nav.rowSpinner}`} aria-hidden="true" /> : <StatusDot state={trouble.state === "error" ? "error" : "offline"} />}
      </span>
      <span className={nav.stationTroubleText}>{trouble.text}</span>
      <ChevronRight size={14} className={nav.stationTroubleGo} aria-hidden="true" />
    </NavLink>
  );
}

/** One of the two lists, all or the viewer's: its states (connecting, failing, empty) and its days; an offline station's chats say so row by row. */
function ChatPane({ chats, scope, onlyMine, stationsPage, hidden }: { chats: ReturnType<typeof useChats>; scope: string; onlyMine: boolean; stationsPage: string; hidden: boolean }) {
  const pending = useContext(ArchivesContext)!;
  const archived = useSyncExternalStore(pending.subscribe, pending.getSnapshot);
  const view = chats.value;
  const stations = view?.stations ?? [];
  const days = (view?.days ?? []).map((day) => ({ ...day, items: day.items.filter((item) => !archived.has(archiveKey(item))) })).filter((day) => day.items.length > 0);
  // One station of one's own: its name says nothing, and its state is the page's.
  const several = scope !== "local";
  const connecting = several ? stations.filter((s) => s.state === "connecting") : [];
  const failed = several ? stations.filter((s) => s.state === "error") : [];
  const loading = !view || view.loading;
  const scroller = useScrolling();
  // A station's link coming back is said on its rows (the core's `reconnecting`); only with no rows at all to show does
  // the list say it, in place of the rows.
  return (
    <div ref={scroller} className={nav.navScroll} aria-hidden={hidden || undefined} inert={hidden || undefined}>
      {chats.error && !view && <p className={`${nav.navEmpty} ${nav.navError}`}>{chats.error.message}</p>}
      {days.length === 0 && !loading && failed.map((s) => <p key={s.station} className={`${nav.navEmpty} ${nav.navError}`} title={s.message ?? undefined}>连不上「{s.name}」，正在重试…</p>)}
      {days.length === 0 && (loading || connecting.length > 0) && !chats.error && <SkeletonRows />}
      {days.length === 0 && view && !loading && !failed.length && !connecting.length && (
        <p className={nav.navEmpty}>{onlyMine ? "没有你参与的会话。"
          : stations.length ? "还没有会话。"
          : <>还没有 station，到 <NavLink className={chatCss.inlineLink} to={stationsPage}>设置 → Station</NavLink> 添加。</>}</p>
      )}
      {days.map((day) => (
        <section key={day.daysAgo} aria-label={day.label}>
          <div className={nav.navHeading}>{day.label}</div>
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
 * where it came from, then the last thing said in it and when; its state as a
 * mark on its picture (ChatMark.tsx).
 */
function ChatRow({ item }: { item: ChatItem }) {
  const { connect } = item;
  const to = `${stationBase(item.station)}/chats/${encodeURIComponent(item.id)}`;
  const move = useComposerMove();
  return (
    <div className={nav.navSessionWrap}>
    <NavLink className={`${nav.navRow} ${nav.navSession}`} to={to} data-unread={item.unread || undefined} data-offline={item.offline ? true : undefined} onClick={(e) => { chatClicked(); move(e, to, "chat"); }}
      // Pressing a chat does not take the focus from the composer: it stays there, focused, into the next chat.
      onMouseDown={(e) => e.preventDefault()}>
      <AgentsPicture item={item} />
      <span className={nav.navSessionText}>
        {/* Where the chat happens sits at the title's end, top right. */}
        <span className={nav.navSessionHead}>
          <span className={nav.navSessionTitle}>{item.title}</span>
          {/* Only an agent that came from elsewhere (Slack) says so; one made on ember needs no mark. */}
          {/* Slack is the only kind of connect there is. */}
          {/* Its station offline: greyed, and marked there instead (the core says so, row by row). */}
          {item.offline
            ? <Tip label={item.offline} side="right"><span className={nav.sessionKind} aria-label={item.offline}><Unplug size={12} /></span></Tip>
            : item.reconnecting
            ? <Tip label={item.reconnecting} side="right"><span className={nav.sessionKind} aria-label={item.reconnecting}><span className={`${waitingCss.spinner} ${nav.rowSpinner}`} aria-hidden="true" /></span></Tip>
            : connect && <Tip label={item.originText ?? "Slack"} side="right"><span className={nav.sessionKind}><ConnectKindIcon kind="slack" size={12} /></span></Tip>}
        </span>
        {/* People are in the chat itself; here only the last thing said and when. */}
        <span className={nav.navSessionMeta}>
          {item.last ? <LastMessage item={item} /> : <span className={nav.navSessionLast} />}
          <Time className={nav.navTime} stamp={item.time?.lastActiveAt} fixed />
        </span>
      </span>
    </NavLink>
    {!item.offline && <ArchiveButton item={item} to={to} />}
    </div>
  );
}

/** Beside a chat's row while pointed at: puts it in the archive (its session with it when it is that session's own). */
function ArchiveButton({ item, to }: { item: ChatItem; to: string }) {
  const pending = useContext(ArchivesContext)!;
  const api = stationApi(useStationCall(item.station));
  const path = useLocation().pathname;
  const navigate = useNavigate();
  const toast = useToast();
  const archive = async () => {
    const key = archiveKey(item);
    if (!pending.begin(key)) return;
    // Move away now; a slow response must not navigate over a chat opened meanwhile.
    if (decodeURIComponent(path) === decodeURIComponent(to)) navigate(`${stationBase(item.station)}/chats`);
    try {
      await api.archive(item, true);
      pending.finish(key);
      toast("已归档");
    } catch (error) {
      pending.fail(key);
      toast(`没能归档：${error instanceof Error ? error.message : String(error)}`);
    }
  };
  return (
    <Tip label="归档" side="right">
      <button type="button" className={`${pagesCss.iconBtn} ${nav.rowArchive}`} aria-label={`归档「${item.title}」`} onMouseDown={(e) => e.preventDefault()} onClick={() => void archive()}>
        <Archive size={16} />
      </button>
    </Tip>
  );
}

/**
 * Who is in a chat, as its row's picture: its agent's mark, or two of its agents' overlapping (more are in the chat
 * itself), with the chat's state at the corner. A chat with no agent yet shows ember's.
 */
function AgentsPicture({ item }: { item: ChatItem }) {
  const agents = item.agents.slice(0, 2);
  return (
    <span className={nav.rowPicture} data-count={agents.length || 1} title={item.agents.map((a) => a.agentText).join("、") || undefined}>
      {agents.length === 0
        ? <span className={nav.rowAgent} aria-hidden="true"><Mark size={20} /></span>
        : agents.map((a) => <span key={a.key} className={nav.rowAgent} aria-hidden="true"><ModelLogo maker={a.maker} runtime={a.runtime} size={agents.length > 1 ? 14 : 26} /></span>)}
      <ChatMark item={item} />
    </span>
  );
}

/** The last thing said in a chat, on one line (the row's picture says who is in it). */
function LastMessage({ item }: { item: ChatItem }) {
  return <span className={nav.navSessionLast}>{item.last!.preview}</span>;
}
