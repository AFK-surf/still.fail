// Home is the `chats` view as the Android app lists it (apps/android/…/screens/Home.kt): one kind of item, newest first
// and grouped by day. A fixed head (settings · workspace · the filter · stations) and the new-chat button floating
// at the bottom. The lists (all, mine, watching) are followed at once, side by side: switching slides from one to another with nothing to wait for.
import { StationMark } from "../StationMark.tsx";
import { memo, useCallback, useEffect, useLayoutEffect, useRef, useState, type PointerEvent as ReactPointerEvent, type ReactNode } from "react";
import { motionValue } from "motion";
import { animate, MOVE, reducedMotion, type AnimationPlaybackControls } from "../motion.ts";
import { stationApi, useChats, useChatSearch, useStationCall, useStations, useStatus, type ChatItem, type ChatsView, type TopicState } from "../api.ts";
import type { FoundMessage } from "../core/shapes.ts";
import { jumpTo } from "../jumpTo.ts";
import { Marked } from "../Marked.tsx";
import { useWorkspaces } from "../cloud/api.ts";
import { Archive, Check, Copy, ChevronDown, ChevronRight, Edit, Filter, Ling, Num1, Num2, Num3, Num4, Num5, Num6, Num7, Num8, Num9, NumMore, Pin, Refresh, Search, Settings, Unplug, Zou } from "../icons.tsx";
import { ask, confirm } from "./sheets.tsx";
import { useCopyChatLink } from "../ChatRef.tsx";
import { stationBase, useChatFilter, type ChatFilter } from "../station.tsx";
import { useApp } from "./app.tsx";
import { FailedMark, Illustration, SectionHeader, SlackMark, Spinner } from "./parts.tsx";
import { ChatMark, chatTone, jumpFromLine, stateLine, WaitingText } from "../ChatMark.tsx";
import * as chatMarkCss from "../ChatMark.css.ts";
import { useWorkspaceMarks } from "../lastChat.ts";
import { RowAside } from "../RowPicture.tsx";
import { FirstStation } from "./Stations.tsx";
import { OpenJobs } from "./OpenJobs.tsx";
import { ChangelogNews } from "./Changelog.tsx";
import { LoadingPill, PlaceholderRows } from "./Loading.tsx";
import { StationGlyph, glyphCounts } from "../StationGlyph.tsx";
import * as barsCss from "./styles/bars.css.ts";
import { openWorkspaces } from "./Workspaces.tsx";
import { usePullToReload } from "./pull.ts";
import * as css from "./Home.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as homeCss from "./styles/home.css.ts";
import { Tip } from "../ui.tsx";
import { useDoing, useDoingFailed } from "../doing.ts";
import { t } from "../i18n.ts";

export function Home() {
  const app = useApp();
  const scope = app.entry.id;
  const all = useChats(scope, false);
  const mine = useChats(scope, true);
  const watching = useChats(scope, false, true);
  const [filter, setFilter] = useChatFilter();
  const invited = useWorkspaces().value?.some((a) => a.invitations.length > 0) ?? false;
  // The other workspaces have something waiting: its dot by the name, before an invitation's.
  const marks = useWorkspaceMarks(scope);
  const decisions = marks?.workspaces[scope]?.decisions ?? 0;
  // No station yet: nothing of the workspace's lists works, so adding the first station is the page.
  const none = useStations(scope).value?.length === 0;
  // Searching: where the field at the list's top was when it was tapped (the search's field comes from there).
  const [searching, setSearching] = useState<DOMRect | null>(null);
  // The lists away while it is open; back as it starts to close, with its field.
  const [away, setAway] = useState(false);
  const search = useCallback((at: DOMRect) => { setSearching(at); setAway(true); }, []);
  // Pulled down from its top, a list loads the page again (./pull.ts).
  const pull = usePullToReload(css.mHomePane);
  return (
    <div className={css.mHome} data-searching={searching ? "" : undefined} data-away={away ? "" : undefined}>
      {none ? (
        <div className={css.mHomePanes} {...pull.handlers}><div className={css.mHomePane} style={{ display: "flex", flexDirection: "column" }}><FirstStation /></div></div>
      ) : (
        <div className={css.mHomePanes} data-filter={filter} {...pull.handlers}>
          <ChatPane chats={all} filter="all" onSearch={search} />
          <ChatPane chats={mine} filter="mine" onSearch={search} />
          <ChatPane chats={watching} filter="watching" onSearch={search} />
        </div>
      )}
      <div ref={pull.mark} className={`${css.mPull} ${pagesCss.mFloating}`} aria-hidden="true"><Refresh size={18} /></div>
      {/* The lists run under both bars, which are frosted glass over them. */}
      <header className={`${css.mHomeBar} ${pagesCss.mGlass}`}>
        <button type="button" className={`${barsCss.mNavButton} ${css.mHomeMe}`} onClick={() => app.push(app.at("/settings"))} aria-label={t("web-mobile.settings.title")}>
          <Settings size={22} />
        </button>
        <button type="button" className={css.mHomeWorkspace} onClick={() => openWorkspaces(app)}>
          <b>{app.entry.name}</b>
          {marks?.others
            ? <span className={chatMarkCss.chatMarkInline} data-tone={marks.others} role="img" aria-label={marks.othersLabel ?? ""} />
            : invited && <span className={css.mDot} aria-label={t("web-mobile.home.invited")} />}
          <ChevronDown size={16} />
        </button>
        {/* The filter, and the archive in its menu, as on the wide screen: nothing to narrow or look back on with no station. */}
        {(all.value?.stations.length ?? 0) > 0 && <FilterButton filter={filter} setFilter={setFilter} />}
        {/* The stations at a glance (../StationGlyph.tsx); its page says which is which. */}
        <StationButton view={all.value} />
      </header>
      {/* The new-chat button alone, floating over the list at the bottom right: a disc in the accent. */}
      {!none && <div className={css.mHomeToolbar}>
        {/* The decisions waiting for the viewer (奏 N): a frosted capsule beside it, there at 0 too (奏 alone). */}
        <button type="button" className={`${pagesCss.mFloating} ${css.mDecisions}`} data-alone={decisions > 0 ? undefined : ""} onClick={() => app.push(app.at("/decisions"))} aria-label={t("web-mobile.home.decisions", { n: decisions })}>
          <Zou size={40} />{decisions > 0 && <Count n={decisions} />}
        </button>
        <div className={css.mHomeCapsule}>
          <button type="button" className={css.mNewChat} onClick={() => app.open(app.at("/new"))} aria-label={t("web-mobile.home.newChat")}><Ling size={44} /></button>
        </div>
      </div>}
      {searching && <SearchPage from={searching} onLeave={() => setAway(false)} onClose={() => setSearching(null)} />}
    </div>
  );
}

/** How many of the messages that have the words the search lists, under the chats. */
const FOUND_MESSAGES = 50;

/**
 * At the top of each list (scrolled to its top to be seen, as a phone's mail): tapped, the search opens from it
 * (`onOpen`, with where it is).
 */
function SearchField({ onOpen }: { onOpen: (at: DOMRect) => void }) {
  return (
    <button type="button" className={css.mSearchField} onClick={(e) => onOpen(e.currentTarget.getBoundingClientRect())}>
      <Search size={17} /><span>{t("web-mobile.home.search")}</span>
    </button>
  );
}

/**
 * The search, over the lists (the core's `chatSearch`, as ⌘K's on the wide screen): its field comes up from where it
 * was in the list to the top as the list goes up and away, narrowing as 取消 comes in (its place taken at once, the
 * move drawn back to it: FLIP);
 * under it the chats the words find, then the messages, newest first, each opening its chat at it. 取消 puts the field
 * back in the list.
 */
function SearchPage({ from, onLeave, onClose }: { from: DOMRect; onLeave: () => void; onClose: () => void }) {
  const app = useApp();
  const [query, setQuery] = useState("");
  const search = useChatSearch({ scope: app.entry.id, query, messages: FOUND_MESSAGES });
  const view = search.value;
  const words = query.trim() !== "";
  const chats = words ? view?.items ?? [] : [];
  const messages = words ? view?.messages ?? [] : [];
  const field = useRef<HTMLDivElement>(null);
  const page = useRef<HTMLDivElement>(null);
  const cancel = useRef<HTMLButtonElement>(null);
  const leaving = useRef(false);
  // The field as it was in the list (where, and as wide) and as it is here, the move's two ends: narrowing, it draws
  // 取消 in after its right edge (laid out after it), not jumping between the two widths.
  const frames = () => {
    const at = field.current?.getBoundingClientRect() ?? from;
    return [
      { transform: `translateY(${from.top - at.top}px)`, width: `${from.width}px`, flex: "none" },
      { transform: "none", width: `${at.width}px`, flex: "none" },
    ];
  };
  useLayoutEffect(() => {
    if (reducedMotion()) return;
    const timing = { duration: 280, easing: "cubic-bezier(.2, .8, .2, 1)" };
    field.current?.animate(frames(), timing);
    cancel.current?.animate([{ opacity: 0 }, { opacity: 1 }], timing);
  }, []); // eslint-disable-line react-hooks/exhaustive-deps
  const close = () => {
    if (leaving.current) return;
    leaving.current = true;
    onLeave();
    if (reducedMotion()) return onClose();
    page.current?.setAttribute("data-leaving", "");
    field.current?.animate(frames().reverse(), { duration: 240, easing: "cubic-bezier(.4, 0, .2, 1)", fill: "forwards" }).finished.then(onClose, onClose);
  };
  return (
    <div ref={page} className={css.mSearchPage}>
      <div className={css.mSearchBar}>
        <div ref={field} className={css.mSearchInput}>
          <Search size={17} />
          <input autoFocus type="search" enterKeyHint="search" value={query} spellCheck={false} placeholder={t("web-mobile.home.search")} aria-label={t("web-mobile.home.search")}
            onChange={(e) => setQuery(e.target.value)} onKeyDown={(e) => { if (e.key === "Escape") close(); }} />
        </div>
        <button ref={cancel} type="button" className={css.mSearchCancel} onClick={close}>{t("web-mobile.home.searchCancel")}</button>
      </div>
      <div className={css.mSearchResults}>
        {words && search.error && !view && <Note text={t("web-mobile.home.searchUpdate")} error />}
        {words && view && !chats.length && !messages.length && <Note text={t("web-mobile.home.searchNone")} />}
        {chats.length > 0 && (
          <section>
            <SectionHeader title={t("web-mobile.home.searchChats")} />
            {chats.map((item) => <ChatRow key={`${item.station}/${item.id}`} item={item} lead="agents" />)}
          </section>
        )}
        {messages.length > 0 && (
          <section>
            <SectionHeader title={t("web-mobile.home.searchMessages")} />
            {messages.map((m) => <FoundRow key={`${m.station}/${m.thread}/${m.seq}`} found={m} words={view?.words} />)}
          </section>
        )}
      </div>
    </div>
  );
}

/** A message the words found: its chat, who said it and when, over the line that has them (those drawn out); tapped,
 *  its chat opens at it, the words marked there (../jumpTo.ts). */
function FoundRow({ found, words }: { found: FoundMessage; words: string[] | undefined }) {
  const app = useApp();
  const item = found.chat;
  return (
    <button type="button" className={css.mChatRow}
      onClick={() => { jumpTo({ station: found.station, thread: found.thread, seq: found.seq, words }); app.open(`${stationBase(item.station)}/chats/${encodeURIComponent(item.id)}`); }}>
      <span className={css.mChatText}>
        <span className={css.mChatLine1}>
          <span className={css.mFoundChat}>{item.title}</span>
          <span className={css.mFoundMeta}>{[found.by, found.time?.createdAt?.ago].filter(Boolean).join(" · ")}</span>
        </span>
        <span className={css.mChatLine2}>
          <span className={css.mLastText}><Marked text={found.text} marks={found.marks} className={css.mFoundHit} /></span>
        </span>
      </span>
    </button>
  );
}

/**
 * The latest chats, over the page from the bottom left on a wider screen (app.tsx WIDE): the list's first few, the open
 * one marked; a new chat at their head, the whole list at their foot.
 */
export function Recent() {
  const app = useApp();
  const chats = useChats(app.entry.id, false);
  const view = chats.value;
  const items = view?.days.flatMap((day) => day.items).slice(0, 6) ?? [];
  return (
    <>
      <div className={css.mRecentHead}>
        <b>{t("web-mobile.app.recent")}</b>
        <button type="button" className={css.mNewChat} data-small onClick={() => app.open(app.at("/new"))} aria-label={t("web-mobile.home.newChat")}><Ling size={26} /></button>
      </div>
      <div className={css.mRecentRows}>
        {!view ? <Note text={chats.error?.message ?? t("web-mobile.home.reading")} error={!!chats.error} />
          // No rows: what the list says in their place (the core's `note`), as the home list does.
          : !items.length ? <Note text={view.note?.reading ? view.note.text ?? t("web-mobile.home.loading") : view.note?.failing[0]?.text ?? t("web-mobile.home.none")} error={!view.note?.reading && !!view.note?.failing.length} />
          : items.map((item) => <ChatRow key={`${item.station}/${item.id}`} item={item} lead={view.leading ?? "agents"} />)}
      </div>
      <button type="button" className={css.mRecentAll} onClick={app.home}>{t("web-mobile.home.allChats")}<ChevronRight size={16} /></button>
    </>
  );
}

/** 全部, 我参与的 or 监控中, and the archive, from a menu under it; marked in the accent while it narrows the list. */
function FilterButton({ filter, setFilter }: { filter: ChatFilter; setFilter: (value: ChatFilter) => void }) {
  const app = useApp();
  const mark = (on: boolean) => on ? <Check size={16} /> : <span style={{ width: 16 }} />;
  return (
    <button type="button" className={`${barsCss.mNavButton} ${css.mFilter}`} data-on={filter !== "all" || undefined}
      aria-label={t("web-mobile.home.filterLabel", { filter: filter === "mine" ? t("web-mobile.home.filterMine") : filter === "watching" ? t("web-mobile.home.filterWatching") : t("web-mobile.home.filterAll") })}
      onClick={(e) => {
        const r = e.currentTarget.getBoundingClientRect();
        // The menu is 180 wide (app.tsx MenuHost): its right edge under the button's.
        app.menu({ anchor: new DOMRect(r.right - 180, r.top, 0, r.height), items: [
          { label: t("web-mobile.home.filterAll"), icon: mark(filter === "all"), action: () => setFilter("all") },
          { label: t("web-mobile.home.filterMine"), icon: mark(filter === "mine"), action: () => setFilter("mine") },
          { label: t("web-mobile.home.filterWatching"), icon: mark(filter === "watching"), action: () => setFilter("watching") },
          { label: t("web-mobile.archive.title"), icon: <Archive size={16} />, action: () => app.push(app.at("/archive")) },
        ] });
      }}>
      <Filter size={20} />
    </button>
  );
}

/** The bar's way to the stations, drawn as how they are: what the core cannot reach at all (`status` in trouble) puts it to sleep. */
function StationButton({ view }: { view: ChatsView | undefined }) {
  const app = useApp();
  const status = useStatus(app.entry.id);
  const counts = glyphCounts(view, status?.state === "trouble");
  // Asleep, what the core cannot reach says it; else the stations in words (the core's), and what is wrong with them.
  const said = counts.asleep ? status?.text ?? "" : view?.glyph?.label ?? "";
  const label = view?.trouble ? t("web-mobile.home.stationTrouble", { said, trouble: view.trouble.text }) : t("web-mobile.home.station", { said });
  return (
    <button type="button" className={barsCss.mNavButton} onClick={() => app.push(app.at("/settings/stations"))} aria-label={label}>
      <StationGlyph counts={counts} />
    </button>
  );
}

/** One of the two lists, all or the viewer's: its states (connecting, failing, empty) and its days. */
// Each list drawn again only when its own chats change: Home draws for any of the three (and the rest of what it shows).
const ChatPane = memo(function ChatPane({ chats, filter, onSearch }: { chats: TopicState<ChatsView>; filter: ChatFilter; onSearch: (at: DOMRect) => void }) {
  const view = chats.value;
  const scope = useApp().entry.id;
  const lead = view?.leading ?? "agents";
  return (
    <div className={css.mHomePane}>
      {/* The search, at the list's top: there once the list is scrolled to it. */}
      {view && !view.note?.empty && <SearchField onOpen={onSearch} />}
      {/* What the last update brought (./Changelog.tsx), until it is seen: even while the list is being read. */}
      <ChangelogNews />
      {/* Not even the stations known yet: the rows to come, and what is wrong if the list cannot be read (./Loading.tsx). */}
      {!view ? <><LoadingPill text={chats.error?.message ?? t("web-mobile.home.loading")} error={!!chats.error} /><PlaceholderRows count={7} still={!!chats.error} /></> : (
        <>
          {/* A station's link coming back is said on its rows; only with no rows to show does the list say it (the core's
              `note`): what it waits on over the rows to come, or the stations it cannot read over faded ones. */}
          {view.note?.reading && <LoadingPill text={view.note.text ?? t("web-mobile.home.loading")} />}
          {view.note?.failing.map((s) => <LoadingPill key={`e/${s.station}`} text={s.text} error />)}
          {(view.note?.reading || !!view.note?.failing.length) && <PlaceholderRows count={view.note.reading ? 7 : 4} still={!view.note.reading} />}
          {view.note?.empty && <Empty view={view} filter={filter} />}
          {/* What is left up a long while on the stations (./OpenJobs.tsx): nothing while there is none. */}
          <OpenJobs scope={scope} />
          {view.days.map((day) => (
            <section key={day.daysAgo}>
              <SectionHeader title={day.label} />
              {day.items.map((item) => <ChatRow key={`${item.station}/${item.id}`} item={item} lead={lead} />)}
            </section>
          ))}
        </>
      )}
    </div>
  );
});

function Note({ text, error = false }: { text: string; error?: boolean }) {
  return <p className={homeCss.mNote} data-error={error || undefined}>{text}</p>;
}

function Empty({ view, filter }: { view: ChatsView; filter: ChatFilter }) {
  const app = useApp();
  const any = view.stations.length > 0;
  return (
    <div className={css.mEmpty}>
      <Illustration name={any ? "new-chat" : "station-offline"} width={240} />
      {filter === "mine" ? <p>{t("web-mobile.home.emptyMine")}</p>
        : filter === "watching" ? <p>{t("web-mobile.home.emptyWatching")}</p>
        : any ? <><p>{view.stations.length > 1 ? t("web-mobile.home.emptyMany") : t("web-mobile.home.emptyOne")}</p><button type="button" className={partsCss.mLink} onClick={() => app.push(app.at("/new"))}>{t("web-mobile.home.newChat")}</button></>
        : <><p>{t("web-mobile.home.noStations")}</p><button type="button" className={partsCss.mLink} onClick={() => app.push(app.at("/settings/stations"))}>{t("web-mobile.home.seeStations")}</button></>}
    </div>
  );
}

/**
 * A row: its title (bold while something in it is unread) and, for an agent that came from
 * Slack, the connect's mark; under it the last thing said; the chat's state a dot before its title (../ChatMark.tsx), who
 * is in it small at the second line's end (../RowPicture.tsx), as on the wide screen. Two lines,
 * always the same height. The time shows while the row is held (or, with a mouse, pointed at); held long, what can be
 * done to the chat, as the wide screen's right click (../Sidebar.tsx). One whose station is offline is greyed and says so.
 */
// The core's list comes anew at each change in it: a row is drawn again only when what it holds is different.
const ChatRow = memo(function ChatRow({ item, lead }: { item: ChatItem; lead: "agents" | "people" }) {
  const app = useApp();
  const [held, setHeld] = useState(false);
  // Pinned, renamed or archived from its menu (closed by then): the row says it is under way until it answers, and a
  // few seconds that it failed (the toast said why too).
  const pinning = useDoing("chat.pin", { station: item.station, session: item.session });
  const changing = useDoing(["chat.rename", "chat.archive"], { station: item.station, session: item.session, thread: item.thread });
  const busy = pinning || changing;
  // Both asked every time (hooks, in the same order each render), the first that failed said.
  const changeFailed = useDoingFailed(["chat.rename", "chat.archive"], { station: item.station, session: item.session, thread: item.thread });
  const pinFailed = useDoingFailed("chat.pin", { station: item.station, session: item.session });
  const failed = changeFailed ?? pinFailed;
  const menu = useRowMenu(item, busy);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const longPressed = useRef(false);
  const holding = useRef(false);
  const touched = useRef(false);
  const release = () => { clearTimeout(timer.current); if (!holding.current) setHeld(false); };
  const hold = (row: HTMLElement, x: number) => {
    longPressed.current = true;
    setHeld(true);
    if (!menu) return;
    navigator.vibrate?.(10);
    holding.current = true;
    // Always just below the row (over it when there is no room below), centred on the finger across (the menu is 180
    // wide, app.tsx MenuHost, which keeps it on the screen).
    const r = row.getBoundingClientRect();
    menu(new DOMRect(x - 90, r.top, 0, r.height), () => { holding.current = false; setHeld(false); });
  };
  const path = `${stationBase(item.station)}/chats/${encodeURIComponent(item.id)}`;
  // Nothing left in it (the core's `archivable`): archived with one tap, at the row's end.
  const archivable = !!item.archivable && !item.offline && !item.pending;
  const row = (
    <button type="button" className={css.mChatRow} data-held={held || undefined} data-offline={item.offline ? true : undefined}
      data-settled={item.settled || undefined} data-open={app.current === path || undefined} data-archivable={archivable || undefined}
      aria-label={item.offline ? `${item.title}（${item.offline}）` : undefined}
      onPointerDown={(e) => {
        longPressed.current = false;
        touched.current = e.pointerType !== "mouse";
        const row = e.currentTarget, x = e.clientX;
        if (touched.current) timer.current = setTimeout(() => hold(row, x), 450);
      }}
      onPointerUp={release} onPointerCancel={release} onPointerLeave={release}
      // A long press has its menu already; a right click with a mouse opens it.
      onContextMenu={(e) => { e.preventDefault(); if (!touched.current) hold(e.currentTarget, e.clientX); }}
      onClick={(e) => { if (!longPressed.current) { jumpFromLine(item, e.target); app.open(path); } }}>
      <span className={css.mChatText}>
      <span className={css.mChatLine1}>
        {/* The mark in a 10px column (its dots are 8px, its rings 10), the one the state line's icon stands in. */}
        {chatTone(item) && <span className={css.mMarkSlot}><ChatMark item={item} inline /></span>}
        <span className={css.mChatTitle} data-unread={item.unread || undefined}>{item.title}</span>
        {/* The station it runs on, by its icon (the core gives one only with several stations). */}
        {(item.stationEmoji || item.stationIcon) && <span className={css.mChatStation} aria-label={item.stationName}><StationMark emoji={item.stationEmoji} icon={item.stationIcon} size={12} /></span>}
        {/* Only an agent that came from elsewhere (Slack, the only kind of connect) says so; an offline station, too. */}
        {busy ? <span className={css.mChatMark} aria-label={t("web-mobile.home.busy")}><Spinner size={12} /></span>
          : failed !== undefined ? <span className={css.mChatMark}><FailedMark error={failed} size={12} /></span>
          // Its station offline, or its link coming back: unplugged (a spinner is only something its person did).
          : item.offline || item.reconnecting ? <Tip label={item.offline ?? item.reconnecting}><span className={css.mChatMark} aria-label={item.offline ?? item.reconnecting}><Unplug size={14} /></span></Tip>
          : <span className={css.mChatMark}>{item.connect && <Tip label={item.originText ?? "Slack"}><span><SlackMark size={14} /></span></Tip>}</span>}
      </span>
      <span className={css.mChatLine2}>
        {/* Where it stands, when the core has words for it (奏 · …, 要你帮忙：…, 做完了), instead. */}
        <span className={css.mChatLast}>{stateLine(item)
          ? <span className={css.mLast}><WaitingText slot text={stateLine(item)!} className={css.mLastText} /></span>
          : item.last && <LastMessage item={item} />}</span>
        <RowAside item={item} lead={lead} size={18} className={css.mRowAside} />
        <span className={css.mChatTime} data-shown={held || undefined}>{item.time?.lastActiveAt?.ago ?? ""}</span>
      </span>
      </span>
    </button>
  );
  if (!archivable) return row;
  // Swiped: not a long press, and not held.
  const dragged = () => { clearTimeout(timer.current); longPressed.current = true; setHeld(false); };
  return <SwipeArchive item={item} busy={busy} onDrag={dragged}>{row}</SwipeArchive>;
}, (a, b) => a.lead === b.lead && (a.item === b.item || JSON.stringify(a.item) === JSON.stringify(b.item)));

/** How far (of its width) a row is swiped before letting go archives it, and how fast a fling has to be (px/ms). */
const TAKES = 0.35;
const FLING = 0.6;

/**
 * A row whose chat has nothing left in it (the core's `archivable`): 归档 in words at its start, and swiped left it is
 * archived. The row follows the finger, 归档 showing in ink where it uncovers; let go far enough or flung, it goes off and
 * the list closes over it, else it springs back. Read on the frame, which does not move (going up or down first is the
 * list's scrolling).
 */
function SwipeArchive({ item, busy, onDrag, children }: { item: ChatItem; busy: boolean; onDrag: () => void; children: ReactNode }) {
  const archive = useRowArchive(item);
  const frame = useRef<HTMLDivElement>(null);
  const slide = useRef<HTMLDivElement>(null);
  const under = useRef<HTMLDivElement>(null);
  const [x] = useState(() => motionValue(0));
  const run = useRef<AnimationPlaybackControls | null>(null);
  const go = useRef<{ id: number; x: number; y: number; dragging: boolean; last: { x: number; t: number }[] } | null>(null);
  const swiped = useRef(false);
  useEffect(() => x.on("change", (v) => {
    const dx = Math.min(0, Math.round(v));
    if (slide.current) slide.current.style.transform = dx ? `translateX(${dx}px)` : "";
    if (under.current) under.current.style.width = `${-dx}px`;
  }), [x]);
  const back = () => {
    run.current?.stop();
    run.current = reducedMotion() ? (x.jump(0), null) : animate(x, 0, { ...MOVE, velocity: x.getVelocity() });
  };
  /** Off to the left, then the row closes up; archived once it is gone (the core takes it out of the list then). */
  const leave = async () => {
    const el = frame.current;
    if (!el || reducedMotion()) return;
    run.current?.stop();
    const off = animate(x, -el.offsetWidth, { type: "spring", visualDuration: 0.2, bounce: 0, velocity: Math.min(x.getVelocity(), 0) });
    run.current = off;
    await off.finished;
    el.dataset.leaving = "";
    await el.animate([{ height: `${el.offsetHeight}px` }, { height: "0px" }], { duration: 200, easing: "cubic-bezier(0.2, 0.7, 0.2, 1)", fill: "forwards" }).finished;
  };
  /** Not archived after all (asked first and kept, or it failed): back where it rests. */
  const stay = () => {
    const el = frame.current;
    if (el) { delete el.dataset.leaving; for (const a of el.getAnimations()) a.cancel(); }
    back();
  };
  const end = (e: ReactPointerEvent<HTMLDivElement>, cancelled: boolean) => {
    const g = go.current;
    if (!g || g.id !== e.pointerId) return;
    go.current = null;
    const el = frame.current;
    if (!g.dragging || !el) return;
    swiped.current = true;
    delete el.dataset.dragging;
    const dx = e.clientX - g.x;
    const first = g.last[0];
    const v = first && e.timeStamp > first.t ? (e.clientX - first.x) / (e.timeStamp - first.t) : 0;
    if (!cancelled && !busy && dx < 0 && (-dx > el.offsetWidth * TAKES || v < -FLING)) archive(leave, stay);
    else back();
  };
  return (
    <div ref={frame} className={css.mChatRowWrap}
      onPointerDown={(e) => {
        if (e.pointerType === "mouse") return;
        swiped.current = false;
        go.current = { id: e.pointerId, x: e.clientX, y: e.clientY, dragging: false, last: [{ x: e.clientX, t: e.timeStamp }] };
      }}
      onPointerMove={(e) => {
        const g = go.current;
        if (!g || g.id !== e.pointerId) return;
        const dx = e.clientX - g.x, dy = e.clientY - g.y;
        if (!g.dragging) {
          if (Math.abs(dy) > 8 && Math.abs(dy) >= Math.abs(dx)) { go.current = null; return; }
          if (Math.abs(dx) < 8) return;
          if (busy) { go.current = null; return; }
          g.dragging = true;
          e.currentTarget.setPointerCapture(e.pointerId);
          e.currentTarget.dataset.dragging = "";
          run.current?.stop();
          onDrag();
        }
        g.last.push({ x: e.clientX, t: e.timeStamp });
        // Its speed over the last 80 ms.
        while (g.last.length > 2 && e.timeStamp - g.last[0]!.t > 80) g.last.shift();
        // Only to the left: to the right it stays where it is.
        x.set(dx < 0 ? dx : 0);
      }}
      onPointerUp={(e) => end(e, false)} onPointerCancel={(e) => end(e, true)}
      onClickCapture={(e) => { if (swiped.current) { swiped.current = false; e.preventDefault(); e.stopPropagation(); } }}>
      <div ref={under} className={css.mSwipeUnder} aria-hidden="true"><span>{t("web-mobile.home.archive")}</span></div>
      <div ref={slide} className={css.mSwipeSlide}>
        <button type="button" className={css.mRowArchive} aria-label={t("web-mobile.home.archiveTitle", { title: item.title })} disabled={busy} onClick={() => archive()}>{t("web-mobile.home.archive")}</button>
        {children}
      </div>
    </div>
  );
}

/**
 * Archives a row's chat (a chat keeping watch once asked, the core's words): `leave` first takes the row away, `stay`
 * puts it back when it was not archived after all. The row says it is under way, the toast how it ended.
 */
function useRowArchive(item: ChatItem) {
  const app = useApp();
  const api = stationApi(useStationCall(item.station));
  const go = () => api.archive(item, true).then(() => app.toast(t("web-mobile.home.archived")));
  return (leave?: () => Promise<void>, stay?: () => void) => {
    if (item.watch) {
      stay?.();
      confirm(app, { title: t("web-mobile.home.archiveAsk", { title: item.title }), text: item.watch.ask, action: t("web-mobile.home.archive"), run: go });
      return;
    }
    void (leave ? leave() : Promise.resolve()).then(go).catch((error: unknown) => {
      stay?.();
      app.toast(t("web-mobile.home.archiveFailed", { error: error instanceof Error ? error.message : String(error) }));
    });
  };
}

/**
 * What can be done to a chat from its row: pin it, rename it, copy its link (for another chat's agent to read), archive
 * it. None for a new chat its station has not made
 * yet, or one on a station offline.
 */
function useRowMenu(item: ChatItem, busy: boolean) {
  const app = useApp();
  const api = stationApi(useStationCall(item.station));
  const copyLink = useCopyChatLink(app.toast);
  // One thing at a time: while one asked of it is under way, its menu waits.
  if (item.offline || item.pending || busy) return null;
  const failed = (key: string) => (error: unknown) => app.toast(t(key, { error: error instanceof Error ? error.message : String(error) }));
  return (anchor: DOMRect, onDismiss: () => void) => app.menu({ anchor, onDismiss, items: [
    // A station from before pins says nothing of them: its chats are not pinned from here.
    ...(item.pinned == null ? [] : [{ label: item.pinned ? t("web-mobile.home.unpin") : t("web-mobile.home.pin"), icon: <Pin size={16} />, action: () => { api.pin(item, !item.pinned).catch(failed(item.pinned ? "web-mobile.home.unpinFailed" : "web-mobile.home.pinFailed")); } }]),
    { label: t("web-mobile.home.rename"), icon: <Edit size={16} />, action: () => ask(app, {
      title: t("web-mobile.home.renameTitle"), value: item.title, placeholder: t("web-mobile.home.renamePlaceholder"), action: t("common.save"), empty: true, hint: t("web-mobile.home.renameHint"), atOnce: "web-main.rename.failed",
      run: (title) => api.rename(item, title),
    }) },
    { label: t("web-main.chat.copyLink"), icon: <Copy size={16} />, action: () => copyLink(item) },
    // A chat keeping watch is archived only once asked: its watch runs on in the archive (the core's words).
    { label: t("web-mobile.home.archive"), icon: <Archive size={16} />, action: () => {
      const archive = () => api.archive(item, true).then(() => app.toast(t("web-mobile.home.archived")));
      // Asked first when it keeps watch; either way the row says it is under way and the toast how it ended.
      if (item.watch) confirm(app, { title: t("web-mobile.home.archiveAsk", { title: item.title }), text: item.watch.ask, action: t("web-mobile.home.archive"), atOnce: "web-mobile.home.archiveFailed", run: archive });
      else archive().catch(failed("web-mobile.home.archiveFailed"));
    } },
  ] });
}

/** The last thing said, on one line, in the secondary colour (the row's picture says who is in it). */
function LastMessage({ item }: { item: ChatItem }) {
  return <span className={css.mLast}><span className={css.mLastText}>{item.last!.preview}</span></span>;
}

/** How many decisions wait, drawn (design/icons num-*): 1 to 9, and + past that. */
const NUMS = [Num1, Num2, Num3, Num4, Num5, Num6, Num7, Num8, Num9];
function Count({ n }: { n: number }) {
  const Shown = n > 9 ? NumMore : NUMS[n - 1] ?? NumMore;
  return <Shown size={24} />;
}
