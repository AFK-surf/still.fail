import { Archive, Edit, Compose, Pin, Unplug } from "./icons.tsx";
import { stationBase, useChatFilter, type ChatFilter } from "./station.tsx";
import { MineFilter } from "./components.tsx";
import { NavLink, useLocation, useNavigate } from "react-router";
import { stationApi, useChats, useStationCall, useStatus, type ChatItem } from "./api.ts";
import { prime } from "./core/react.ts";
import { RowAside } from "./RowPicture.tsx";
import { Retry, Waiting, WaitingItems } from "./Status.tsx";
import { failure, useToast } from "./toast.tsx";
import { Confirm, ConnectKindIcon, ICON, SkeletonRows, Time, Tip } from "./ui.tsx";
import { chatClicked } from "./telemetry.ts";
import { useComposerMove } from "./dock.tsx";
import { goToNeighbour } from "./Chat.tsx";
import { useShortcut } from "./keymap.ts";
import { ChatMark, jumpFromLine, stateLine, WaitingText } from "./ChatMark.tsx";
import { useCallback, useEffect, useRef, useState, useSyncExternalStore } from "react";
import { ContextMenu } from "radix-ui";
import { TitleInput, useRename, useRenaming } from "./Rename.tsx";
import { useDoing } from "./doing.ts";
import { DoingShown, useDoingState } from "./DoingMark.tsx";
import * as controlsCss from "./styles/controls.css.ts";
import { StationGlyph, glyphCounts } from "./StationGlyph.tsx";
import { useHeldOrder, useListMotion, usePointerOver } from "./listMotion.ts";
import { useWorkspaceMarks } from "./lastChat.ts";
import * as nav from "./Sidebar.css.ts";
import * as decisionsCss from "./Decisions.css.ts";
import * as chatCss from "./styles/chat.css.ts";
import * as pagesCss from "./styles/pages.css.ts";

/**
 * The chats of a workspace, newest first and
 * grouped by day, as the core's `chats` view has them; optionally only the
 * ones the viewer started, with `newChat` above them and the way to the `archive` in the filter's menu beside it. With no station its empty
 * state leads to `stationsPage` (the page itself, where stations are added: nothing is appended to it).
 */
export function ChatList({ scope, newChat, stationsPage, archive }: { scope: string; newChat: string; stationsPage: string; archive: string }) {
  const [filter] = useChatFilter();
  const move = useComposerMove();
  useShortcut("chat.prev", () => goToNeighbour(-1));
  useShortcut("chat.next", () => goToNeighbour(1));
  // The lists are followed at once, side by side: switching slides from one to another with nothing to wait for.
  const all = useChats(scope, false);
  const mine = useChats(scope, true);
  const watching = useChats(scope, false, true);
  // The page it was going to is there (or another took its place).
  const path = useLocation().pathname;
  useEffect(() => setGoing(null), [path]);
  return (
    <>
      <div className={nav.navNew}>
        <NavLink className={nav.navRow} to={newChat} onClick={(e) => move(e, newChat, "new")}><Compose {...ICON} />新建对话</NavLink>
        {/* The filter, and the archive under it: nothing to narrow or look back on with no station at all. */}
        {!(all.value && !all.value.loading && all.value.stations.length === 0) && <MineFilter label="会话" mine="我参与的" compact archive={archive} watching />}
      </div>
      <div className={nav.navSlider}>
        <div className={nav.navTrack} data-filter={filter}>
          <ChatPane chats={all} scope={scope} filter="all" stationsPage={stationsPage} hidden={filter !== "all"} />
          <ChatPane chats={mine} scope={scope} filter="mine" stationsPage={stationsPage} hidden={filter !== "mine"} />
          <ChatPane chats={watching} scope={scope} filter="watching" stationsPage={stationsPage} hidden={filter !== "watching"} />
        </div>
      </div>
    </>
  );
}

/**
 * The stations at the top of the sidebar's foot, always: their glyph (./StationGlyph.tsx) and a line beside it, how many
 * and who works while all is well, or what is wrong (the core's `trouble`: which, or how many; red while one fails). It
 * leads to the stations. Short of a station down, the line says what the core has been waiting on for a while, or ember
 * cloud not reached (the core's `status`: what, how long, how fast; each thing on hover); that last puts the glyph to
 * sleep. Cloud not reached, it offers to try again at once; a station down does not.
 */
export function StationTrouble({ scope, to }: { scope: string; to: string }) {
  const view = useChats(scope, false).value;
  const status = useStatus(scope);
  if (!view || view.stations.length === 0) return status?.state ? <Waiting status={status} /> : null;
  const counts = glyphCounts(view, status?.state === "trouble");
  const trouble = view.trouble;
  const waiting = !trouble && status?.state ? status : undefined;
  const text = trouble?.text ?? waiting?.text ?? view.glyph?.summary ?? "";
  // A station down offers no retry here (it may stay down for long; the stations' page is where to): only still.fail cloud not reached.
  const retry = waiting?.state === "trouble";
  const row = (
    <NavLink className={`${nav.navRow} ${nav.stationTrouble}`} to={to} data-state={trouble?.state ?? waiting?.state} data-retry={retry || undefined} aria-label={`Station：${trouble?.text ?? waiting?.text ?? view.glyph?.label ?? ""}`}>
      <span className={nav.stationTroubleMark}><StationGlyph counts={counts} size={18} /></span>
      <span className={nav.stationTroubleText}>{text}</span>
    </NavLink>
  );
  return (
    <div className={nav.stationRow}>
      {waiting?.items.length ? <Tip label={<WaitingItems status={waiting} />} side="top">{row}</Tip> : row}
      {retry && <Retry />}
    </div>
  );
}

/**
 * 奏 N in the sidebar's foot, by the stations: the decisions waiting for the viewer in the workspace (the core's
 * `decisions` count), leading to their page. Nothing while there are none (or from a core before them).
 */
export function DecisionsEntry({ scope, to }: { scope: string; to: string }) {
  const n = useWorkspaceMarks(scope)?.workspaces[scope]?.decisions ?? 0;
  if (n <= 0) return null;
  return (
    <NavLink className={`${nav.navRow} ${decisionsCss.sideEntry}`} to={to} aria-label={`奏：${n} 件等你决定`}>
      <span className={decisionsCss.sideEntryLead}>奏</span>
      <span className={decisionsCss.sideEntryCount}>{n} 件等你决定</span>
    </NavLink>
  );
}

/** One of the lists, all, the viewer's or the watching ones: its states (connecting, failing, empty) and its days; an offline station's chats say so row by row. */
function ChatPane({ chats, scope, filter, stationsPage, hidden }: { chats: ReturnType<typeof useChats>; scope: string; filter: ChatFilter; stationsPage: string; hidden: boolean }) {
  const view = chats.value;
  const stations = view?.stations ?? [];
  const [over, pointer] = usePointerOver();
  const days = useHeldOrder(view?.days ?? [], rowKey, over, pinMoved);
  // What the list says with no rows, the core's.
  const note = view?.note ?? { reading: !view || view.loading, failing: [], empty: false };
  const scroller = useScrolling();
  const list = useRef<HTMLDivElement | null>(null);
  const ref = useCallback((el: HTMLDivElement | null) => { list.current = el; return scroller(el); }, [scroller]);
  useListMotion(list);
  // Whose pictures lead, as the core puts the setting and the scope together (a core from before it: the agents).
  const lead = view?.leading ?? "agents";
  // A station's link coming back is said on its rows (the core's `reconnecting`); only with no rows at all to show does
  // the list say it, in place of the rows.
  return (
    <div ref={ref} className={nav.navScroll} aria-hidden={hidden || undefined} inert={hidden || undefined} {...pointer}>
      {chats.error && !view && <p className={`${nav.navEmpty} ${nav.navError}`}>{chats.error.message}</p>}
      {days.length === 0 && note.failing.map((s) => <Tip key={s.station} label={s.message ?? undefined}><p className={`${nav.navEmpty} ${nav.navError}`}>{s.text}</p></Tip>)}
      {days.length === 0 && note.reading && !chats.error && <SkeletonRows />}
      {days.length === 0 && view && note.empty && (
        <p className={nav.navEmpty}>{filter === "mine" ? "没有你参与的会话。"
          : filter === "watching" ? "没有在监控的会话。"
          : stations.length ? "还没有会话。"
          : <>还没有 station，到 <NavLink className={chatCss.inlineLink} to={stationsPage}>设置 → Station</NavLink> 添加。</>}</p>
      )}
      {days.map((day) => (
        <section key={day.daysAgo} aria-label={day.label}>
          <div className={nav.navHeading} data-flip={`day:${day.daysAgo}`}>{day.label}</div>
          {day.items.map((item) => <ChatRow key={rowKey(item)} item={item} lead={lead} />)}
        </section>
      ))}
    </div>
  );
}

/** A row pinned or let go moves at once, even while the list is held still under the pointer. */
const pinMoved = (was: ChatItem, now: ChatItem): boolean => Boolean(was.pinned) !== Boolean(now.pinned);

/**
 * A row's key in the list, kept as it changes: a chat asked for here goes by the key given here (its `clientKey`) before
 * and after its station makes it.
 */
const rowKey = (item: ChatItem): string => `${item.station}/${item.clientKey ?? item.id}`;

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
 * dot before its title (ChatMark.tsx), who is in it small at the second line's end. While a piece of work in it waits,
 * the second line says on whom and what; with all its work over, the row is faded.
 */
function ChatRow({ item, lead }: { item: ChatItem; lead: "agents" | "people" }) {
  const { connect } = item;
  const to = `${stationBase(item.station)}/chats/${encodeURIComponent(item.id)}`;
  const move = useComposerMove();
  const archive = useArchive(item, to);
  // A chat keeping watch is archived only once asked: its watch runs on in the archive (the core's words).
  const [asking, setAsking] = useState(false);
  const archiveAsked = () => { if (item.watch) setAsking(true); else void archive(); };
  const pin = usePin(item);
  const rename = useRename(item.station);
  const [editing, setEditing] = useState(false);
  // Pinned, renamed (its new name shown meanwhile) or brought back from the archive, until the station answers.
  const renamingTo = useRenaming(item.station, item.session);
  // Failed: a red mark in the spinner's place a few seconds more, why on hover (the menu that asked has closed).
  const saving = useDoingState(["chat.pin", "chat.rename", "chat.archive"], { station: item.station, session: item.session });
  const goingTo = useGoing();
  const here = decodeURIComponent(useLocation().pathname) === decodeURIComponent(to);
  // A new chat its station has not made yet, or one on a station offline, is neither renamed nor archived.
  const menu = !item.offline && !item.pending;
  const row = (
    <NavLink className={`${nav.navRow} ${nav.navSession}`} to={to} data-unread={item.unread || undefined} data-offline={item.offline ? true : undefined} data-settled={item.settled || undefined} onClick={(e) => {
        if (editing) { e.preventDefault(); return; }
        chatClicked();
        if (e.button === 0 && !e.metaKey && !e.ctrlKey && !e.shiftKey && !e.altKey) jumpFromLine(item, e.target);
        move(e, to, "chat");
        if (!here && e.button === 0 && !e.metaKey && !e.ctrlKey && !e.shiftKey && !e.altKey) setGoing(to);
      }}
      data-going={goingTo === null ? undefined : goingTo === to ? "here" : "away"}
      // Pressing a chat does not take the focus from the composer: it stays there, focused, into the next chat.
      onMouseDown={(e) => e.preventDefault()}
      // Pointed at or pressed: its chat is read meanwhile, there when the page opens.
      onPointerEnter={() => primeChat(item)} onPointerDown={() => primeChat(item)} onFocus={() => primeChat(item)}>
      <span className={nav.navSessionText}>
        {/* Where the chat happens sits at the title's end, top right. */}
        <span className={nav.navSessionHead}>
          <ChatMark item={item} inline />
          {editing
            ? <TitleInput value={item.title} onDone={(title) => { setEditing(false); rename(item, title); }} />
            : <span className={nav.navSessionTitle}>{renamingTo ?? item.title}</span>}
          {(saving.running || saving.error !== undefined) && !editing && <span className={nav.sessionKind}><DoingShown state={saving} className={nav.rowSpinner} label="正在保存" side="right" /></span>}
          {/* Only an agent that came from elsewhere (Slack) says so; one made on ember needs no mark. */}
          {/* Slack is the only kind of connect there is. */}
          {/* Its station offline, or its link coming back: marked unplugged there (the core says which, row by row). A
              spinner on a row is only ever something its person did, under way. */}
          {item.offline || item.reconnecting
            ? <Tip label={item.offline ?? item.reconnecting} side="right"><span className={nav.sessionKind} aria-label={item.offline ?? item.reconnecting}><Unplug size={12} /></span></Tip>
            : connect && <Tip label={item.originText ?? "Slack"} side="right"><span className={nav.sessionKind}><ConnectKindIcon kind="slack" size={12} /></span></Tip>}
        </span>
        {/* The last thing said, who is in the chat, and when (in their place while pointed at). */}
        <span className={nav.navSessionMeta}>
          {/* Where it stands, when the core has words for it (奏 · …, 要你帮忙：…, 做完了), instead. */}
          {stateLine(item) ? <WaitingText text={stateLine(item)!} className={nav.navSessionLast} />
            : item.last ? <LastMessage item={item} /> : <span className={nav.navSessionLast} />}
          <RowAside item={item} lead={lead} size={16} className={nav.rowAside} />
          <Time className={nav.navTime} stamp={item.time?.lastActiveAt} fixed />
        </span>
      </span>
    </NavLink>
  );
  return (
    <div className={nav.navSessionWrap} data-editing={editing || undefined} data-flip={rowKey(item)} data-archivable={(menu && !editing && item.archivable) || undefined}>
    {menu ? (
      // Right-clicking a row: what can be done to the chat.
      <ContextMenu.Root modal={false}>
        <ContextMenu.Trigger asChild disabled={editing}>{row}</ContextMenu.Trigger>
        <ContextMenu.Portal>
          <ContextMenu.Content className={`${controlsCss.popover} ${controlsCss.menuList}`} collisionPadding={8} onCloseAutoFocus={(e) => e.preventDefault()}>
            {/* A station from before pins says nothing of them: its chats are not pinned from here. */}
            {item.pinned != null && <ContextMenu.Item className={controlsCss.menuItem} onSelect={() => void pin()}><Pin size={14} />{item.pinned ? "取消固定" : "固定"}</ContextMenu.Item>}
            <ContextMenu.Item className={controlsCss.menuItem} onSelect={() => setEditing(true)}><Edit size={14} />重命名</ContextMenu.Item>
            <ContextMenu.Item className={controlsCss.menuItem} onSelect={archiveAsked}><Archive size={14} />归档</ContextMenu.Item>
          </ContextMenu.Content>
        </ContextMenu.Portal>
      </ContextMenu.Root>
    ) : row}
    {menu && !editing && (item.archivable ? <ArchiveChip item={item} archive={archiveAsked} /> : <ArchiveButton item={item} archive={archiveAsked} />)}
    {item.watch && <Confirm open={asking} title={`归档「${item.title}」？`} description={item.watch.ask} action="归档"
      onConfirm={() => { setAsking(false); void archive(); }} onClose={() => setAsking(false)} />}
    </div>
  );
}

/**
 * Puts a chat's row in the archive (its session with it when it is that session's own), leaving its page if open. The
 * core takes the row out of the lists at once, and puts it back if the station could not.
 */
function useArchive(item: ChatItem, to: string) {
  const api = stationApi(useStationCall(item.station));
  const path = useLocation().pathname;
  const navigate = useNavigate();
  const toast = useToast();
  return async () => {
    // Move away now, to the chat beside it in the list (the list page if none); a slow response must not navigate over
    // a chat opened meanwhile.
    if (decodeURIComponent(path) === decodeURIComponent(to) && !goToNeighbour(1) && !goToNeighbour(-1)) navigate(`${stationBase(item.station)}/chats`);
    try {
      await api.archive(item, true);
      toast("已归档");
    } catch (error) {
      toast(`没能归档：${error instanceof Error ? error.message : String(error)}`);
    }
  };
}

/**
 * The chat a row's click is going to, while its page is on the way (the page before stays until the chat is read,
 * core/react.ts useReady): its row is the one shown selected meanwhile, so the click answers at once.
 */
let going: string | null = null;
const goingHeard = new Set<() => void>();
function setGoing(to: string | null): void {
  if (going === to) return;
  going = to;
  for (const heard of goingHeard) heard();
}
function useGoing(): string | null {
  return useSyncExternalStore((heard) => { goingHeard.add(heard); return () => goingHeard.delete(heard); }, () => going, () => going);
}

function primeChat(item: ChatItem): void {
  if (!item.offline) prime({ topic: "chat", station: item.station, session: item.id });
}

/** Pins a chat to the top of the list, or lets it go; its station moves the row. */
function usePin(item: ChatItem) {
  const api = stationApi(useStationCall(item.station));
  const toast = useToast();
  const pinning = useDoing("chat.pin", { station: item.station, session: item.session });
  return async () => {
    if (pinning) return;
    try {
      await api.pin(item, !item.pinned);
    } catch (error) {
      toast(`没能${item.pinned ? "取消固定" : "固定"}：${failure(error)}`);
    }
  };
}

/** Beside a chat's row while pointed at: puts it in the archive. */
function ArchiveButton({ item, archive }: { item: ChatItem; archive: () => void }) {
  return (
    <Tip label="归档" side="right">
      <button type="button" className={`${pagesCss.iconBtn} ${nav.rowArchive}`} aria-label={`归档「${item.title}」`} onMouseDown={(e) => e.preventDefault()} onClick={archive}>
        <Archive size={16} />
      </button>
    </Tip>
  );
}

/** Nothing left in its chat (the core's `archivable`): 归档 in words at the row's end while it is pointed at. */
function ArchiveChip({ item, archive }: { item: ChatItem; archive: () => void }) {
  return (
    <button type="button" className={nav.rowArchiveChip} aria-label={`归档「${item.title}」`} onMouseDown={(e) => e.preventDefault()} onClick={archive}>
      归档
    </button>
  );
}

/** The last thing said in a chat, on one line (the row's picture says who is in it). */
function LastMessage({ item }: { item: ChatItem }) {
  return <span className={nav.navSessionLast}>{item.last!.preview}</span>;
}
