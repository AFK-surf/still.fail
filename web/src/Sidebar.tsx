import { Archive, ArrowUpRight, Copy, Edit, File, Pin, ShieldCheck, Unplug } from "@stillfail/ui/icons.tsx";
import { openRelay } from "./Relay.tsx";
import { StationMark } from "./StationMark.tsx";
import { StationInWords } from "./StationNamed.tsx";
import { useCopyChatLink, useCopyTranscripts } from "./ChatRef.tsx";
import { stationBase, useSidebarMode, type ChatFilter } from "./station.tsx";
import { SidebarActions } from "./SidebarActions.tsx";
import { NavSection, NavTop } from "./SidebarList.tsx";
import { NavLink, useLocation } from "react-router";
import { useGo, useHere } from "./go.ts";
import { archiveSaid, stationApi, useStationCall, useStatus, type ChatItem, type ChatsView } from "./api.ts";
import { prime, useTopic, useTopicSelect } from "./core/react.ts";
import type { Topic } from "./core/client.ts";
import { RowAside } from "./RowPicture.tsx";
import { sampleChats, sampleWords } from "./samples.ts";
import { Retry, Waiting as StatusWaiting, WaitingItems } from "./Status.tsx";
import { failure, useAct, useToast } from "@stillfail/ui/toast.tsx";
import { Confirm, ConnectKindIcon, ICON, Time, Tip, Waiting } from "./ui.tsx";
import { chatClicked } from "./telemetry.ts";
import { useComposerMove } from "./dock.tsx";
import { goToNeighbour } from "./Chat.tsx";
import { useShortcut } from "./keymap.ts";
import { ChatMark, jumpFromLine, rowLead, stateLine, WaitingText } from "./ChatMark.tsx";
import { memo, useCallback, useEffect, useRef, useState, useSyncExternalStore, type ReactNode } from "react";
import { ContextMenu } from "radix-ui";
import { TitleInput, useRename, useRenaming } from "./Rename.tsx";
import { useDoing } from "./doing.ts";
import { DoingShown, useDoingState } from "./DoingMark.tsx";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import { StationGlyph, glyphCounts } from "./StationGlyph.tsx";
import { useHeldOrder, useListMotion, usePointerOver } from "./listMotion.ts";
import { useWorkspaceMarks } from "./lastChat.ts";
import * as nav from "./Sidebar.css.ts";
import { ArchiveRows } from "./pages/Archive.tsx";
import * as chatCss from "./styles/chat.css.ts";
import { t } from "./i18n.ts";
import * as pageCss from "@stillfail/ui/styles/page.css.ts";

/**
 * The chats of a workspace, newest first and
 * grouped by day, as the core's `chats` view has them; optionally only the
 * ones the viewer started or the watching ones, or in their place the archived chats (ArchiveRows, its page
 * `archive`), with
 * `newChat` above them and the filter's menu beside it. With no station its empty state leads to `stationsPage` (the page itself, where stations are
 * added: nothing is appended to it).
 */
export function ChatList({ scope, newChat, stationsPage, archive, top, below }: { scope: string; newChat: string; stationsPage: string; archive: string; top?: ReactNode; below?: ReactNode }) {
  const [mode] = useSidebarMode();
  useShortcut("chat.prev", () => goToNeighbour(-1));
  useShortcut("chat.next", () => goToNeighbour(1));
  // No station at all: nothing to filter (the lists themselves follow their own topics, ChatPane).
  const none = useTopicSelect<ChatsView, boolean>(chatsTopic(scope, "all"), (s) => !!s.value && !s.value.loading && s.value.stations.length === 0);
  // Catching up on what changed while away (its mark beside the filter): drawn again only as it changes.
  const syncing = useTopicSelect<ChatsView, string | null>(chatsTopic(scope, "all"), (s) => s.value?.syncing ?? null);
  const archiveSeen = useRef(false);
  if (mode === "archive") archiveSeen.current = true;
  return (
    <>
      <GoingArrived />
      <NavTop top={top} below={below}
        action={<SidebarActions newChat={newChat} archive={archive} workspace={`/w/${scope}`} syncing={syncing} showFilter={!none} />} />
      <div className={nav.navSlider}>
        <div className={nav.navTrack} data-filter={mode} ref={sliding}>
          {/* Followed at once, side by side: switching slides from one to another with nothing to wait for. */}
          <ChatPane scope={scope} filter="all" stationsPage={stationsPage} hidden={mode !== "all"} />
          <ChatPane scope={scope} filter="mine" stationsPage={stationsPage} hidden={mode !== "mine"} />
          <ChatPane scope={scope} filter="watching" stationsPage={stationsPage} hidden={mode !== "watching"} />
          {/* Made once first shown (it can be long, and is rarely looked at), kept then for sliding back to it. */}
          {archiveSeen.current ? <ArchiveRows scope={scope} hidden={mode !== "archive"} /> : <div className={nav.navScroll} />}
        </div>
      </div>
    </>
  );
}

/** Marks the track while it slides (`data-sliding`): the panes it passes are drawn then (Sidebar.css.ts navTrack). */
function sliding(track: HTMLElement | null): (() => void) | undefined {
  if (!track) return undefined;
  const slid = (e: TransitionEvent) => {
    if (e.target !== track || e.propertyName !== "transform") return;
    if (e.type === "transitionrun") track.dataset.sliding = "";
    else delete track.dataset.sliding;
  };
  const types = ["transitionrun", "transitionend", "transitioncancel"] as const;
  for (const type of types) track.addEventListener(type, slid);
  return () => { for (const type of types) track.removeEventListener(type, slid); };
}

/**
 * For the sidebar (its ref): the heights of its frosted top and foot, which its lists scroll under, as `--nav-top` and
 * `--nav-foot`, for the lists to start and end clear of them.
 */
export function useGlassBands(): (el: HTMLElement | null) => (() => void) | void {
  return useCallback((el: HTMLElement | null) => {
    if (!el) return;
    const measure = () => {
      for (const [name, cls] of [["--nav-top", nav.navTop], ["--nav-foot", nav.navFoot]] as const) {
        const band = el.querySelector(`:scope > .${cls}`);
        el.style.setProperty(name, `${band ? band.getBoundingClientRect().height : 0}px`);
      }
    };
    const sizes = new ResizeObserver(measure);
    const watch = () => {
      sizes.disconnect();
      for (const band of el.querySelectorAll(`:scope > :is(.${nav.navTop}, .${nav.navFoot})`)) sizes.observe(band);
      measure();
    };
    // The bands come and go with the page (the settings' list has no top band).
    const children = new MutationObserver(watch);
    children.observe(el, { childList: true });
    watch();
    return () => { sizes.disconnect(); children.disconnect(); };
  }, []);
}

/**
 * The stations at the top of the sidebar's foot, always: their glyph (./StationGlyph.tsx) and a line beside it, how many
 * and who works while all is well, or what is wrong (the core's `trouble`: which, or how many; red while one fails). It
 * leads to the stations. Short of a station down, the line says what the core has been waiting on for a while, or ember
 * cloud not reached (the core's `status`: what, how long, how fast; each thing on hover). The glyph sleeps only while
 * every station is down as the device's network is (the core's `glyph.asleep`), not for still.fail cloud alone. Cloud
 * not reached, it offers to try again at once; a station down does not.
 */
export function StationTrouble({ scope, to }: { scope: string; to: string }) {
  // Only what it shows (the stations, their glyph and trouble): not each change of the list's rows.
  const view = useTopicSelect<ChatsView, ChatsView | undefined>(chatsTopic(scope, "all"), (s) => s.value,
    (a, b) => a?.stations === b?.stations && a?.glyph === b?.glyph && a?.trouble === b?.trouble);
  const status = useStatus(scope);
  if (!view || view.stations.length === 0) return status?.state ? <StatusWaiting status={status} /> : null;
  const counts = glyphCounts(view);
  const trouble = view.trouble;
  const waiting = !trouble && status?.state ? status : undefined;
  const text = trouble?.text ?? waiting?.text ?? view.glyph?.summary ?? "";
  // A station down offers no retry here (it may stay down for long; the stations' page is where to): only still.fail cloud not reached.
  const retry = waiting?.state === "trouble";
  const row = (
    <NavLink className={`${nav.navRow} ${nav.stationTrouble}`} to={to} data-state={trouble?.state ?? waiting?.state} data-retry={retry || undefined} aria-label={`Station：${trouble?.text ?? waiting?.text ?? view.glyph?.label ?? ""}`}>
      <span className={nav.stationTroubleMark}><StationGlyph counts={counts} size={18} /></span>
      <span className={nav.stationTroubleText}>{trouble ? <StationInWords station={trouble.station} text={text} /> : text}</span>
    </NavLink>
  );
  return (
    <div className={nav.stationRow}>
      {waiting?.items.length ? <Tip label={<WaitingItems status={waiting} />} side="top">{row}</Tip> : row}
      {retry && <Retry />}
    </div>
  );
}

/** What is wrong with the stations (the core's `trouble`: which, or how many; red while one fails): null when nothing, undefined before the list is read. */
export function useStationTrouble(scope: string): ChatsView["trouble"] | null | undefined {
  return useTopicSelect<ChatsView, ChatsView["trouble"] | null | undefined>(chatsTopic(scope, "all"), (s) => s.value ? s.value.trouble ?? null : undefined, (a, b) => a === b);
}

/**
 * The stations in the rail (Rail.tsx): their glyph, what the foot's line would say on hover, leading to the stations.
 */
export function RailStations({ scope, to, on, className }: { scope: string; to: string; on: boolean; className: string }) {
  const view = useTopicSelect<ChatsView, ChatsView | undefined>(chatsTopic(scope, "all"), (s) => s.value,
    (a, b) => a?.stations === b?.stations && a?.glyph === b?.glyph && a?.trouble === b?.trouble);
  const status = useStatus(scope);
  const counts = glyphCounts(view);
  const label = view?.trouble?.text ?? (status?.state ? status.text : undefined) ?? view?.glyph?.summary ?? "Station";
  return (
    <Tip label={label} side="right">
      <NavLink className={className} to={to} data-on={on || undefined} aria-label={`Station：${label}`}><StationGlyph counts={counts} size={20} /></NavLink>
    </Tip>
  );
}

/**
 * One of the lists, all, the viewer's or the watching ones: its states (connecting, failing, empty) and its days; an
 * offline station's chats say so row by row. Drawn again only when what it is given changes (its topic's value, the
 * filter shown): the sidebar around it drawing again (a page's change elsewhere, a side panel opening) left its every
 * row drawn and measured again (listMotion), all three lists of them.
 */
const ChatPane = memo(function ChatPane({ scope, filter, stationsPage, hidden }: { scope: string; filter: ChatFilter; stationsPage: string; hidden: boolean }) {
  const chats = useTopic<ChatsView>(chatsTopic(scope, filter));
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
      {days.length === 0 && (note.reading || note.failing.length > 0) && !chats.error && <Waiting note={note} sample={<ChatRowsSample lead={lead} />} />}
      {days.length === 0 && view && note.empty && (
        <p className={nav.navEmpty}>{filter === "mine" ? t("web-main.sidebar.noneMine")
          : filter === "watching" ? t("web-main.sidebar.noneWatching")
          : stations.length ? t("web-main.sidebar.none")
          : <>{t("web-main.sidebar.noStation.before")}<NavLink className={chatCss.inlineLink} to={stationsPage}>{t("web-main.sidebar.noStation.link")}</NavLink>{t("web-main.sidebar.noStation.after")}</>}</p>
      )}
      {days.map((day) => (
        <NavSection key={day.daysAgo} title={day.label} flip={`day:${day.daysAgo}`}>
          {day.items.map((item) => <ChatRow key={rowKey(item)} scope={scope} filter={filter} row={rowKey(item)} lead={lead} />)}
        </NavSection>
      ))}
    </div>
  );
});

/** The list's rows made up, for what it shows while it is read (in their bones): a day of them. */
export function ChatRowsSample({ lead }: { lead: "agents" | "people" }) {
  return <NavSection title={sampleWords(2)}>{SAMPLE_CHATS.map((item) => <ChatRowOf key={item.id} item={item} lead={lead} />)}</NavSection>;
}
const SAMPLE_CHATS = sampleChats(8);

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
const ChatRow = memo(function ChatRow({ scope, filter, row: key, lead }: { scope: string; filter: ChatFilter; row: string; lead: "agents" | "people" }) {
  const item = useTopicSelect<ChatsView, ChatItem | undefined>(chatsTopic(scope, filter), (s) => rowsOf(s.value).get(key));
  return item ? <ChatRowOf item={item} lead={lead} /> : null;
});

/** A list's rows by their key, made once for each value of its topic. */
const indexed = new WeakMap<ChatsView, Map<string, ChatItem>>();
function rowsOf(view: ChatsView | undefined): Map<string, ChatItem> {
  if (!view) return NO_ROWS;
  let rows = indexed.get(view);
  if (!rows) {
    rows = new Map(view.days.flatMap((d) => d.items.map((item) => [rowKey(item), item] as const)));
    indexed.set(view, rows);
  }
  return rows;
}
const NO_ROWS = new Map<string, ChatItem>();

/** The topic of one of the lists, all, the viewer's or the watching ones (as useChats subscribes to it). */
function chatsTopic(scope: string, filter: ChatFilter): Topic {
  return { topic: "chats", scope, mine: filter === "mine", ...(filter === "watching" ? { watching: true } : {}) };
}

function ChatRowOf({ item, lead }: { item: ChatItem; lead: "agents" | "people" }) {
  const { connect } = item;
  const to = `${stationBase(item.station)}/chats/${encodeURIComponent(item.id)}`;
  const move = useComposerMove();
  const archive = useArchive(item, to);
  // A chat keeping watch is archived only once asked, in the core's words.
  const [asking, setAsking] = useState(false);
  const archiveAsked = () => { if (item.watch) setAsking(true); else void archive(); };
  const pin = usePin(item);
  const keep = useKeep(item);
  const toast = useToast();
  const copyLink = useCopyChatLink(toast);
  const copyTranscripts = useCopyTranscripts(item.station, toast);
  const rename = useRename(item.station);
  const [editing, setEditing] = useState(false);
  // Pinned, renamed (its new name shown meanwhile) or brought back from the archive, until the station answers.
  const renamingTo = useRenaming(item.station, item.session);
  // Nothing while its station answers (the core's list has it so at once); failed, a red mark a few seconds, why on
  // hover (the menu that asked has closed).
  const saving = useDoingState(["chat.pin", "chat.rename", "chat.archive"], { station: item.station, session: item.session });
  const going = useGoing(to);
  const where = useHere();
  // A new chat its station has not made yet, or one on a station offline, is neither renamed nor archived.
  const menu = !item.offline && !item.pending;
  const row = (
    <NavLink className={`${nav.navRow} ${nav.navSession}`} to={to} data-unread={item.unread || undefined} data-offline={item.offline ? true : undefined} data-settled={item.settled || undefined} onClick={(e) => {
        if (editing) { e.preventDefault(); return; }
        chatClicked();
        if (e.button === 0 && !e.metaKey && !e.ctrlKey && !e.shiftKey && !e.altKey) jumpFromLine(item, e.target);
        move(e, to, "chat");
        const from = decodeURIComponent(where());
        if (from !== decodeURIComponent(to) && e.button === 0 && !e.metaKey && !e.ctrlKey && !e.shiftKey && !e.altKey) setGoing({ to: decodeURIComponent(to), from });
      }}
      data-going={going}
      // Pressing a chat does not take the focus from the composer: it stays there, focused, into the next chat.
      onMouseDown={(e) => e.preventDefault()}
      // Pointed at or pressed: its chat is read meanwhile, there when the page opens.
      onPointerEnter={() => primeChat(item)} onPointerDown={() => primeChat(item)} onFocus={() => primeChat(item)}>
      <span className={nav.navSessionText}>
        {/* Where the chat happens sits at the title's end, top right. */}
        <span className={nav.navSessionHead}>
          <span className={nav.navMarkSlot}><ChatMark item={item} inline /></span>
          {editing
            ? <TitleInput value={item.title} onDone={(title) => { setEditing(false); rename(item, title); }} />
            : <span className={nav.navSessionTitle}>{renamingTo ?? item.title}</span>}
          {saving.error !== undefined && !editing && <span className={nav.sessionKind}><DoingShown state={{ running: false, error: saving.error }} inline /></span>}
          {/* Only an agent that came from elsewhere (Slack) says so; one made on ember needs no mark. */}
          {/* Its station offline, or its link coming back: marked unplugged there (the core says which, row by row). A
              spinner on a row is only ever something its person did, under way. */}
          {item.offline || item.reconnecting
            ? <Tip label={item.offline ?? item.reconnecting}><span className={nav.sessionKind} aria-label={item.offline ?? item.reconnecting}><Unplug size={12} /></span></Tip>
            : connect && <Tip label={item.originText ?? "Slack"}><span className={nav.sessionKind}><ConnectKindIcon kind={item.originKind ?? "slack"} size={12} /></span></Tip>}
          {/* The station it runs on, by its icon (the core gives one only with several stations): last, so it stands in the same column at every row's end whatever marks come before it. */}
          {(item.stationEmoji || item.stationIcon) && !editing && <Tip label={item.stationName}><span className={nav.sessionKind} aria-label={item.stationName}><StationMark emoji={item.stationEmoji} icon={item.stationIcon} size={12} /></span></Tip>}
        </span>
        {/* The last thing said, who is in the chat, and when (in their place while pointed at). */}
        <span className={nav.navSessionMeta}>
          {/* Where it stands, when the core has words for it (奏 · …, 要你帮忙：…, 做完了), instead. */}
          {stateLine(item) ? <WaitingText slot alert={item.unsent === true} text={stateLine(item)!} lead={rowLead(item)} leadText={item.stateLeadText} rest={item.stateRest} className={nav.navSessionLast} />
            : item.last ? <LastMessage item={item} /> : <span className={nav.navSessionLast} />}
          <RowAside item={item} lead={lead} size={16} className={nav.rowAside} />
          <Time className={nav.navTime} stamp={item.time?.lastActiveAt} fixed />
        </span>
      </span>
    </NavLink>
  );
  return (
    <div className={nav.navSessionWrap} data-editing={editing || undefined} data-flip={rowKey(item)}>
    {menu ? (
      // Right-clicking a row: what can be done to the chat.
      <ContextMenu.Root modal={false}>
        <ContextMenu.Trigger asChild disabled={editing}>{row}</ContextMenu.Trigger>
        <ContextMenu.Portal>
          <ContextMenu.Content className={`${controlsCss.popover} ${controlsCss.menuList}`} collisionPadding={8} onCloseAutoFocus={(e) => e.preventDefault()}>
            {/* A station from before pins says nothing of them: its chats are not pinned from here. */}
            {item.pinned != null && <ContextMenu.Item className={controlsCss.menuItem} onSelect={() => void pin()}><Pin size={14} />{item.pinned ? t("web-main.chat.unpin") : t("web-main.chat.pin")}</ContextMenu.Item>}
            <ContextMenu.Item className={controlsCss.menuItem} onSelect={() => setEditing(true)}><Edit size={14} />{t("web-main.chat.rename")}</ContextMenu.Item>
            {/* Kept: never offered for archiving, nor archived on its own (a chat of its own only: a thread). Pinned, a
                chat is kept out of the archive already: none. */}
            {item.thread != null && !item.pinned && <ContextMenu.Item className={controlsCss.menuItem} onSelect={keep}><ShieldCheck size={14} />{item.kept ? t("web-main.chat.unkeep") : t("web-main.chat.keep")}</ContextMenu.Item>}
            {/* Its link, for another chat's agent to read it (chat_read / session_history), on any station of the workspace. */}
            <ContextMenu.Item className={controlsCss.menuItem} onSelect={() => copyLink(item)}><Copy size={14} />{t("web-main.chat.copyLink")}</ContextMenu.Item>
            {/* Relayed to a channel (docs/relay.md): a chat with an agent to go on there. */}
            {item.thread != null && item.agents.length > 0 && <ContextMenu.Item className={controlsCss.menuItem} onSelect={() => openRelay(item.station, item.thread!)}><ArrowUpRight size={14} />{t("web-main.relay.action")}</ContextMenu.Item>}
            {/* Where its agents' sessions are kept on the station's machine: each agent's, one per line. */}
            <ContextMenu.Item className={controlsCss.menuItem} onSelect={() => copyTranscripts(item.agents.length > 0 ? item.agents.map((a) => a.key) : [item.session])}><File size={14} />{t("web-main.chat.copyTranscript")}</ContextMenu.Item>
            <ContextMenu.Item className={controlsCss.menuItem} onSelect={archiveAsked}><Archive size={14} />{t("web-main.chat.archive")}</ContextMenu.Item>
          </ContextMenu.Content>
        </ContextMenu.Portal>
      </ContextMenu.Root>
    ) : row}
    {menu && !editing && <ArchiveButton item={item} archive={archiveAsked} />}
    {item.watch && <Confirm open={asking} title={t("web-main.chat.archiveAsk", { title: item.title })} description={item.watch.ask} action={t("web-main.chat.archive")}
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
  const here = useHere();
  const navigate = useGo();
  const toast = useToast();
  return async () => {
    // Move away now, to the chat beside it in the list (the list page if none); a slow response must not navigate over
    // a chat opened meanwhile.
    if (decodeURIComponent(here()) === decodeURIComponent(to) && !goToNeighbour(1) && !goToNeighbour(-1)) navigate(`${stationBase(item.station)}/chats`);
    try {
      await archiveSaid(api, item, item.title, toast);
    } catch (error) {
      toast(t("web-main.chat.archiveFailed", { error: error instanceof Error ? error.message : String(error) }));
    }
  };
}

/**
 * The chat a row's click is going to (`to`), from the page open then (`from`), while its page is on the way (the page
 * before stays until the chat is read, core/react.ts useReady): its row is the one shown selected meanwhile, so the click
 * answers at once. Both paths decoded.
 */
let going: { to: string; from: string } | null = null;
const goingHeard = new Set<() => void>();
function setGoing(next: { to: string; from: string } | null): void {
  if (going?.to === next?.to && going?.from === next?.from) return;
  going = next;
  for (const heard of goingHeard) heard();
}
const hearGoing = (heard: () => void) => { goingHeard.add(heard); return () => { goingHeard.delete(heard); }; };
/** A row's part in it (its page, `to`): the one gone to, the one left, or neither; only those two rows draw again. */
function useGoing(to: string): "here" | "away" | undefined {
  const path = decodeURIComponent(to);
  const now = () => (going === null ? undefined : going.to === path ? "here" : going.from === path ? "away" : undefined);
  return useSyncExternalStore(hearGoing, now, now);
}

/** The page it was going to is there (or another took its place): no row is going anywhere any more. */
function GoingArrived() {
  const path = useLocation().pathname;
  useEffect(() => setGoing(null), [path]);
  return null;
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
      toast(t(item.pinned ? "web-main.chat.unpinFailed" : "web-main.chat.pinFailed", { error: failure(error) }));
    }
  };
}

/** 保留 from a row's menu, or 取消保留 once kept: the toast says what it means for the archive. */
function useKeep(item: ChatItem) {
  const api = stationApi(useStationCall(item.station));
  const act = useAct();
  return () => {
    if (item.thread == null) return;
    const kept = item.kept === true;
    act(api.keepChat(item.thread, !kept), t(kept ? "web-main.chat.unkeep.what" : "web-main.chat.keep.what"), t(kept ? "web-main.chat.unkeep.done" : "web-main.chat.keep.done"));
  };
}

/** Beside a chat's row while pointed at: puts it in the archive. */
function ArchiveButton({ item, archive }: { item: ChatItem; archive: () => void }) {
  return (
    <Tip label={t("web-main.chat.archive")}>
      <button type="button" className={`${pageCss.iconBtn} ${nav.rowArchive}`} aria-label={t("web-main.chat.archiveNamed", { title: item.title })} onMouseDown={(e) => e.preventDefault()} onClick={archive}>
        <Archive size={14} />
      </button>
    </Tip>
  );
}

/** The last thing said in a chat, on one line (the row's picture says who is in it). */
function LastMessage({ item }: { item: ChatItem }) {
  return <span className={nav.navSessionLast}>{item.last!.preview}</span>;
}
