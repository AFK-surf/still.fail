// Home is the `chats` view as the Android app lists it (apps/android/…/screens/Home.kt): one kind of item, newest first
// and grouped by day. A fixed head (settings · workspace · the filter · stations) and the new-chat button floating
// at the bottom. The lists (all, mine, watching) are followed at once, side by side: switching slides from one to another with nothing to wait for.
import { useFrameDraw } from "./gesture.ts";
import { StationMark } from "../StationMark.tsx";
import { Activity, memo, useCallback, useMemo, useEffect, useLayoutEffect, useRef, useState, type PointerEvent as ReactPointerEvent, type ReactNode } from "react";
import { motionValue } from "motion";
import { animate, MOVE, MOVE_EASE_CSS, MOVE_PAGE_MS, motionMs, play, type AnimationPlaybackControls } from "@stillfail/ui/motion.ts";
import { archiveSaid, stationApi, useChats, useSearch, useStationCall, useStations, type ChatItem, type ChatsView, type TopicState } from "../api.ts";
import type { FoundMessage, SearchItem } from "../core/shapes.ts";
import { jumpTo } from "../jumpTo.ts";
import { Marked } from "../Marked.tsx";
import { useWorkspaces } from "../cloud/api.ts";
import { Archive, Copy, ChevronDown, ChevronLeft, ChevronRight, Edit, Ling, Pin, Refresh, Search, Settings, Unplug } from "@stillfail/ui/icons.tsx";
import { ask, confirm } from "./sheets.tsx";
import { useCopyChatLink } from "../ChatRef.tsx";
import { setSidebarMode, stationBase, useChatFilter, type ChatFilter } from "../station.tsx";
import { useApp, useOpenPage } from "./app.tsx";
import { FailedMark, FilterMenu, Illustration, SectionHeader, SlackMark, ticked } from "./parts.tsx";
import { Waiting, WaitLine } from "@stillfail/ui/waiting.tsx";
import { ChatMark, chatTone, jumpFromLine, rowLead, stateLine, WaitingText } from "../ChatMark.tsx";
import * as chatMarkCss from "../ChatMark.css.ts";
import { useWorkspaceMarks } from "../lastChat.ts";
import { RowAside } from "../RowPicture.tsx";
import { sampleChats, sampleWords } from "../samples.ts";
import { FirstStation } from "./Stations.tsx";
import { OpenJobs } from "./OpenJobs.tsx";
import { filesPath } from "../searchOpen.ts";
import { ChangelogNews } from "./Changelog.tsx";
import * as barsCss from "./styles/bars.css.ts";
import { openWorkspaces } from "./Workspaces.tsx";
import { SecurityWaitingScreen } from "./Security.tsx";
import type { LockView } from "../cloud/Security.tsx";
import { usePullToReload } from "./pull.ts";
import * as css from "./Home.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as homeCss from "./styles/home.css.ts";
import { Tip } from "../ui.tsx";
import { SyncMark } from "../SyncMark.tsx";
import { useVirtualList, useVirtualModel } from "../virtual/list.tsx";
import type { Item } from "../virtual/model.ts";
import { useDoing, useDoingFailed } from "../doing.ts";
import { t } from "../i18n.ts";
import { marked, WorkspaceBadge } from "../WorkspaceMark.tsx";

export function Home() {
  const app = useApp();
  const scope = app.entry.id;
  const all = useChats(scope, false);
  const mine = useChats(scope, true);
  const watching = useChats(scope, false, true);
  const [filter] = useChatFilter();
  // Keep the departing pane alive through its slide; at rest only the chosen pane does UI work.
  const [leaving, setLeaving] = useState<ChatFilter[]>([]);
  const previous = useRef(filter);
  useLayoutEffect(() => {
    // Effects resume when Home is uncovered too: a transition interrupted by another page is over.
    if (previous.current === filter) { setLeaving((was) => was.length ? [] : was); return; }
    const from = previous.current;
    setLeaving((was) => was.includes(from) ? was : [...was, from]);
    previous.current = filter;
    const timer = setTimeout(() => setLeaving([]), motionMs(240));
    return () => clearTimeout(timer);
  }, [filter]);
  const awake = (pane: ChatFilter) => filter === pane || leaving.includes(pane) || previous.current === pane;
  const invited = useWorkspaces().value?.some((a) => a.invitations.length > 0) ?? false;
  // The other workspaces have something waiting: its dot by the name, before an invitation's.
  const marks = useWorkspaceMarks(scope);
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
          <div className={css.mHomeSlide}><Activity mode={awake("all") ? "visible" : "hidden"}><ChatPane chats={all} filter="all" onSearch={search} /></Activity></div>
          <div className={css.mHomeSlide}><Activity mode={awake("mine") ? "visible" : "hidden"}><ChatPane chats={mine} filter="mine" onSearch={search} /></Activity></div>
          <div className={css.mHomeSlide}><Activity mode={awake("watching") ? "visible" : "hidden"}><ChatPane chats={watching} filter="watching" onSearch={search} /></Activity></div>
        </div>
      )}
      <div ref={pull.mark} className={`${css.mPull} ${pagesCss.mFloating}`} aria-hidden="true"><Refresh size={18} /></div>
      {/* The lists run under both bars, which are frosted glass over them. */}
      <HomeBar others={marks?.others} othersLabel={marks?.othersLabel} invited={invited} filtering={(all.value?.stations.length ?? 0) > 0}
        filter={filter} syncing={all.value?.syncing} />
      {searching && <SearchPage from={searching} onLeave={() => setAway(false)} onClose={() => setSearching(null)} />}
    </div>
  );
}

/**
 * What a device waiting to be confirmed in the workspace's security mode sees in place of the workspace (index.tsx
 * LockGate): the waiting page under Home's top bar, its settings and the workspace's name, which switches to another
 * (2026-10-23: with the page in the workspace's place, there was no way to another workspace).
 */
export function WaitingHome({ lock }: { lock: LockView }) {
  const app = useApp();
  const invited = useWorkspaces().value?.some((a) => a.invitations.length > 0) ?? false;
  const marks = useWorkspaceMarks(app.entry.id);
  return (
    <div className={css.mHome}>
      <div className={css.mHomePanes}><SecurityWaitingScreen lock={lock} /></div>
      <HomeBar others={marks?.others} othersLabel={marks?.othersLabel} invited={invited} filtering={false} filter="all" />
    </div>
  );
}

/**
 * The list's top bar: the viewer's settings, the workspace (and whether others have something waiting), the filter (the
 * stations are on the bottom bar). Drawn again only when what it shows changes, not with each change of the lists under it.
 */
const HomeBar = memo(function HomeBar({ others, othersLabel, invited, filtering, filter, syncing }: {
  others: string | null | undefined; othersLabel: string | null | undefined; invited: boolean; filtering: boolean;
  filter: ChatFilter; syncing?: ChatsView["syncing"];
}) {
  const app = useApp();
  const here = useWorkspaces().value?.flatMap((a) => a.workspaces).find((w) => w.id === app.entry.id);
  return (
    <header className={`${css.mHomeBar} ${pagesCss.mGlass}`}>
      <button type="button" className={`${barsCss.mNavButton} ${css.mHomeMe}`} onClick={() => app.push(app.at("/settings"))} aria-label={t("web-mobile.settings.title")}>
        <Settings size={22} />
      </button>
      <button type="button" className={css.mHomeWorkspace} onClick={() => openWorkspaces(app)}>
        {/* its mark before its name; none where it has none, its letter only the name's first again beside it */}
        {here && marked(here) && <WorkspaceBadge w={here} size={20} still={false} />}
        <b>{app.entry.name}</b>
        {others
          ? <span className={chatMarkCss.chatMarkInline} data-tone={others} role="img" aria-label={othersLabel ?? ""} />
          : invited && <span className={css.mDot} aria-label={t("web-mobile.home.invited")} />}
        <ChevronDown size={16} />
      </button>
      {/* Catching up on what changed while away, the keys' size. */}
      <SyncMark syncing={syncing} size={34} mark={20} />
      {/* The filter, and the archive in its menu, as on the wide screen: nothing to narrow or look back on with no station. */}
      {filtering && <FilterButton filter={filter} />}
    </header>
  );
});

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
 * The search, over the lists (the core's `search`, as ⌘K's on the wide screen, docs/search.md): its field comes up from
 * where it was in the list to the top as the list goes up and away, narrowing as 取消 comes in (its place taken at
 * once, the move drawn back to it: FLIP);
 * under it the chats the words find, the messages, newest first, each opening its chat at it, then what the stations
 * find besides, each kind under its heading; 查看更多 lists that kind alone (全部结果 back). 取消 puts the field back in
 * the list.
 */
function SearchPage({ from, onLeave, onClose }: { from: DOMRect; onLeave: () => void; onClose: () => void }) {
  const app = useApp();
  const [query, setQuery] = useState("");
  const [kind, setKind] = useState<string | null>(null);
  const search = useSearch({ scope: app.entry.id, query, kind });
  const view = search.value;
  const words = query.trim() !== "";
  const chats = words ? view?.items ?? [] : [];
  const messages = words ? view?.messages ?? [] : [];
  const groups = words ? view?.groups ?? [] : [];
  const note = words ? [view?.wait?.text, view?.note].filter((w): w is string => !!w).join(" · ") : "";
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
    const timing = { duration: MOVE_PAGE_MS, easing: MOVE_EASE_CSS };
    play(field.current, frames(), timing);
    play(cancel.current, [{ opacity: 0 }, { opacity: 1 }], timing);
  }, []); // eslint-disable-line react-hooks/exhaustive-deps
  const close = () => {
    if (leaving.current) return;
    leaving.current = true;
    onLeave();
    page.current?.setAttribute("data-leaving", "");
    play(field.current, frames().reverse(), { duration: MOVE_PAGE_MS, easing: MOVE_EASE_CSS, fill: "forwards" })?.finished.then(onClose, onClose);
  };
  const more = (k: string) => <button type="button" className={css.mFoundMore} onClick={() => setKind(k)}>{t("web-mobile.home.searchMore")}<ChevronRight size={16} /></button>;
  return (
    <div ref={page} className={css.mSearchPage}>
      <div className={css.mSearchBar}>
        <div ref={field} className={css.mSearchInput}>
          <Search size={17} />
          <input autoFocus type="search" enterKeyHint="search" value={query} spellCheck={false} placeholder={t("web-mobile.home.search")} aria-label={t("web-mobile.home.search")}
            onChange={(e) => setQuery(e.target.value)} onKeyDown={(e) => { if (e.key === "Escape") { if (kind) setKind(null); else close(); } }} />
        </div>
        <button ref={cancel} type="button" className={css.mSearchCancel} onClick={close}>{t("web-mobile.home.searchCancel")}</button>
      </div>
      <div className={css.mSearchResults}>
        {kind && <button type="button" className={css.mFoundMore} onClick={() => setKind(null)}><ChevronLeft size={16} />{t("web-mobile.home.searchAll")}</button>}
        {words && search.error && !view && <Note text={t("web-mobile.home.searchUpdate")} error />}
        {words && !search.error && !view && <WaitLine className={homeCss.mNote} text={t("web-mobile.home.searching")} />}
        {words && view && !chats.length && !messages.length && !groups.length && !view.wait?.reading && <Note text={t("web-mobile.home.searchNone")} />}
        {chats.length > 0 && (
          <section>
            <SectionHeader title={t("web-mobile.home.searchChats")} />
            {chats.map((item) => (item.foundText ? <FoundChatRow key={`${item.station}/${item.id}`} item={item} /> : <ChatRow key={`${item.station}/${item.id}`} item={item} lead="agents" />))}
            {!kind && view?.chatsMore && more("chat")}
          </section>
        )}
        {messages.length > 0 && (
          <section>
            <SectionHeader title={t("web-mobile.home.searchMessages")} />
            {messages.map((m) => <FoundRow key={`${m.station}/${m.thread}/${m.seq}`} found={m} words={view?.words} />)}
            {!kind && view?.messagesMore && more("message")}
          </section>
        )}
        {groups.map((group) => (
          <section key={group.kind}>
            <SectionHeader title={group.title} />
            {group.items.map((item) => <FoundItemRow key={item.key} item={item} />)}
            {!kind && group.more && more(group.kind)}
          </section>
        ))}
        {note && <p className={css.mFoundNote}>{note}</p>}
      </div>
    </div>
  );
}

/** Where something a search found opens on the phone (`SearchItem.open`, the core's): its chat (a service's page over
 *  it), a station's page, the workspace's members, a place in a station's files. */
function openFound(app: ReturnType<typeof useApp>, item: SearchItem): void {
  const open = item.open;
  if (!open) return;
  const at = open.station.indexOf("/");
  const id = encodeURIComponent(at < 0 ? open.station : open.station.slice(at + 1));
  const chat = open.chat ? `${stationBase(open.station)}/chats/${encodeURIComponent(open.chat)}` : null;
  switch (open.to) {
    case "service":
      if (chat && open.job) return app.open(`${chat}/services/${encodeURIComponent(open.job)}`);
      break;
    case "station":
      return app.push(app.at(`/s/${id}/overview`));
    case "members":
      return app.push(app.at("/settings/members"));
    case "files":
      return app.push(filesPath(app.at(`/s/${id}`), open));
  }
  if (chat) app.open(chat);
}

/** Something found besides a chat or a message: what it is and where (its station, when), over its line that has the
 *  words; tapped, it opens where it is. */
function FoundItemRow({ item }: { item: SearchItem }) {
  const app = useApp();
  return (
    <button type="button" className={css.mChatRow} onClick={() => openFound(app, item)}>
      <span className={css.mChatText}>
        <span className={css.mChatLine1}>
          <span className={css.mFoundChat}>{item.title}</span>
          <span className={css.mFoundMeta}>{[item.kind === "station" ? null : item.stationName, item.time?.createdAt?.ago].filter(Boolean).join(" · ")}</span>
        </span>
        {item.text && (
          <span className={css.mChatLine2}>
            <span className={css.mLastText}><Marked text={item.text} marks={item.marks} className={css.mFoundHit} /></span>
          </span>
        )}
      </span>
    </button>
  );
}

/** A message the words found: the line that has them (those drawn out) the width of the row, over its chat, who said
 *  it and when; tapped,
 *  its chat opens at it, the words marked there (../jumpTo.ts). */
function FoundRow({ found, words }: { found: FoundMessage; words: string[] | undefined }) {
  const app = useApp();
  const item = found.chat;
  return (
    <button type="button" className={css.mChatRow}
      onClick={() => { jumpTo({ station: found.station, thread: found.thread, seq: found.seq, words }); app.open(`${stationBase(item.station)}/chats/${encodeURIComponent(item.id)}`); }}>
      <span className={css.mChatText}>
        <span className={css.mChatLine1}>
          <span className={css.mFoundChat}><Marked text={found.text} marks={found.marks} className={css.mFoundHit} /></span>
        </span>
        <span className={css.mChatLine2}>
          <span className={css.mFoundUnder}>{item.title}</span>
          <span className={css.mFoundMeta}>{[found.by, found.time?.createdAt?.ago].filter(Boolean).join(" · ")}</span>
        </span>
      </span>
    </button>
  );
}

/** A chat found by words its title shows late or not at all: the part of it that has them first, its title under it. */
function FoundChatRow({ item }: { item: ChatItem }) {
  const app = useApp();
  return (
    <button type="button" className={css.mChatRow} onClick={() => app.open(`${stationBase(item.station)}/chats/${encodeURIComponent(item.id)}`)}>
      <span className={css.mChatText}>
        <span className={css.mChatLine1}>
          <span className={css.mFoundChat}><Marked text={item.foundText ?? ""} marks={item.foundMarks ?? []} className={css.mFoundHit} /></span>
        </span>
        <span className={css.mChatLine2}>
          <span className={css.mFoundUnder}>{item.title}</span>
          <span className={css.mFoundMeta}>{[item.archived ? t("web-mobile.home.searchArchived") : null, item.time?.lastActiveAt?.ago].filter(Boolean).join(" · ")}</span>
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
        {!view ? <WaitLine className={homeCss.mNote} text={chats.error?.message ?? t("web-mobile.home.reading")} error={!!chats.error} />
          // No rows: what the list says in their place (the core's `note`), as the home list does.
          : !items.length ? view.note?.reading || view.note?.failing.length
            ? <WaitLine className={homeCss.mNote} text={view.note.reading ? view.note.text ?? t("web-mobile.home.reading") : view.note.failing[0]!.text} error={!view.note.reading} />
            : <Note text={t("web-mobile.home.none")} />
          : items.map((item) => <ChatRow key={`${item.station}/${item.id}`} item={item} lead={view.leading ?? "agents"} />)}
      </div>
      <button type="button" className={css.mRecentAll} onClick={app.home}>{t("web-mobile.home.allChats")}<ChevronRight size={16} /></button>
    </>
  );
}

/** 全部, 我参与的 or 监控中, and the archive, from a menu under it; marked in the accent while it narrows the list. */
const FilterButton = memo(function FilterButton({ filter }: { filter: ChatFilter }) {
  const app = useApp();
  const setFilter = (value: ChatFilter) => setSidebarMode(app.entry.id, value);
  return (
    <FilterMenu on={filter !== "all"}
      label={t("web-mobile.home.filterLabel", { filter: filter === "mine" ? t("web-mobile.home.filterMine") : filter === "watching" ? t("web-mobile.home.filterWatching") : t("web-mobile.home.filterAll") })}
      items={[
        { label: t("web-mobile.home.filterAll"), icon: ticked(filter === "all"), action: () => setFilter("all") },
        { label: t("web-mobile.home.filterMine"), icon: ticked(filter === "mine"), action: () => setFilter("mine") },
        { label: t("web-mobile.home.filterWatching"), icon: ticked(filter === "watching"), action: () => setFilter("watching") },
        { label: t("web-mobile.archive.title"), icon: <Archive size={16} />, action: () => app.push(app.at("/archive")) },
      ]} />
  );
});

/** One of the two lists, all or the viewer's: its states (connecting, failing, empty) and its days. */
// Each list drawn again only when its own chats change: Home draws for any of the three (and the rest of what it shows).
const ChatPane = memo(function ChatPane({ chats, filter, onSearch }: { chats: TopicState<ChatsView>; filter: ChatFilter; onSearch: (at: DOMRect) => void }) {
  const view = chats.value;
  const scope = useApp().entry.id;
  const lead = view?.leading ?? "agents";
  const pane = useRef<HTMLDivElement>(null);
  const made = useVirtualModel(`home:${scope}:${filter}`, 0, false);
  // Navigation starts at its head, unlike a conversation which follows its newest message.
  const opened = useRef<typeof made | null>(null);
  if (opened.current !== made) {
    // The intro can finish measuring before chats arrive. Even when it fits entirely, Home must keep its head
    // rather than begin following the end of the list that arrives next.
    made.model.reads(true);
    made.model.goto("intro", "start");
    opened.current = made;
  }
  const content = useMemo(() => {
    const items: Item[] = [{ key: "intro", estimate: 100 }];
    const drawn = new Map<string, ReactNode>();
    for (const day of view?.days ?? []) {
      const head = `day:${day.daysAgo}`;
      items.push({ key: head, estimate: 42 });
      drawn.set(head, <SectionHeader title={day.label} />);
      for (const item of day.items) {
        const key = `${item.station}/${item.id}`;
        // An archiving row folds to zero before the topic removes it: measure that motion.
        items.push({ key, estimate: 66, ...(!item.swipeArchive ? { exact: 66 } : {}) });
        drawn.set(key, <ChatRow item={item} lead={lead} />);
      }
    }
    return { items, drawn };
  }, [view?.days, lead]);
  const virtual = useVirtualList(pane, made, content.items, { cover: (lead) => lead, deferResize: true });
  const intro = <>
    {view && !view.note?.empty && <SearchField onOpen={onSearch} />}
    <ChangelogNews />
    {!view ? <Waiting text={t("web-mobile.home.reading")} error={chats.error?.message} sample={<ChatRowsSample lead={lead} n={7} />} /> : <>
      {(view.note?.reading || !!view.note?.failing.length) && <Waiting note={view.note} text={t("web-mobile.home.reading")} sample={<ChatRowsSample lead={lead} n={view.note.reading ? 7 : 4} />} />}
      {view.note?.empty && <Empty view={view} filter={filter} />}
      <OpenJobs scope={scope} />
    </>}
  </>;
  return (
    <div ref={pane} className={css.mHomePane} data-home-pane={filter}>
      {virtual.layout.rows.flatMap((row, i) => [virtual.above(row, i === 0),
        <div key={row.key} data-vk={row.key} className={css.mHomeItem}>{row.key === "intro" ? intro : content.drawn.get(row.key)}</div>,
      ])}
      {virtual.after()}
    </div>
  );
});

/** The list's rows made up, `n` of them, for what it shows while it is read (in their bones): a day's, as the list draws them. */
function ChatRowsSample({ lead, n }: { lead: "agents" | "people"; n: number }) {
  return <>
    <div className={css.mHomeItem}><SectionHeader title={sampleWords(2)} /></div>
    {SAMPLE_CHATS.slice(0, n).map((item) => <div key={item.id} className={css.mHomeItem}><ChatRow item={item} lead={lead} /></div>)}
  </>;
}
const SAMPLE_CHATS = sampleChats(7);

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
  // Pinned, renamed or archived from its menu (closed by then): nothing while its station answers (the core's list has
  // it so at once), a few seconds that it failed (the toast said why too).
  const pinning = useDoing("chat.pin", { station: item.station, session: item.session });
  const changing = useDoing(["chat.rename", "chat.archive"], { station: item.station, session: item.session, thread: item.thread });
  const busy = pinning || changing;
  // Both asked every time (hooks, in the same order each render), the first that failed said.
  const changeFailed = useDoingFailed(["chat.rename", "chat.archive"], { station: item.station, session: item.session, thread: item.thread });
  const pinFailed = useDoingFailed("chat.pin", { station: item.station, session: item.session });
  const failed = changeFailed ?? pinFailed;
  const menu = useRowMenu(item, busy);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  useEffect(() => () => clearTimeout(timer.current), []);
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
  const open = useOpenPage(path);
  // Made, its station there (the core's `swipeArchive`): swiped left, archived.
  const archivable = !!item.swipeArchive;
  const row = (
    <button type="button" className={css.mChatRow} data-held={held || undefined} data-offline={item.offline ? true : undefined}
      data-settled={item.settled || undefined} data-open={open || undefined} data-archivable={archivable || undefined}
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
        {failed !== undefined ? <span className={css.mChatMark}><FailedMark error={failed} size={12} /></span>
          // Its station offline, or its link coming back: unplugged (a spinner is only something its person did).
          : item.offline || item.reconnecting ? <Tip label={item.offline ?? item.reconnecting}><span className={css.mChatMark} aria-label={item.offline ?? item.reconnecting}><Unplug size={14} /></span></Tip>
          : <span className={css.mChatMark}>{item.connect && <Tip label={item.originText ?? "Slack"}><span><SlackMark kind={item.originKind} size={14} /></span></Tip>}</span>}
      </span>
      <span className={css.mChatLine2}>
        {/* Where it stands, when the core has words for it (奏 · …, 要你帮忙：…, 做完了), instead. */}
        <span className={css.mChatLast}>{stateLine(item)
          ? <span className={css.mLast}><WaitingText slot alert={item.unsent === true} text={stateLine(item)!} lead={rowLead(item)} leadText={item.stateLeadText} rest={item.stateRest} className={css.mLastText} /></span>
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
 * A row whose chat is made and station is there (the core's `swipeArchive`): swiped left, it is archived. The row
 * follows the finger, 归档 showing in ink where it uncovers; let go far enough or flung, it goes off and the list closes over it, else
 * it springs back. Read on the frame, which does not move (going up or down first is the list's scrolling).
 */
function SwipeArchive({ item, busy, onDrag, children }: { item: ChatItem; busy: boolean; onDrag: () => void; children: ReactNode }) {
  const archive = useRowArchive(item);
  const frame = useRef<HTMLDivElement>(null);
  const slide = useRef<HTMLDivElement>(null);
  const under = useRef<HTMLDivElement>(null);
  const [x] = useState(() => motionValue(0));
  const fingers = useFrameDraw<number>(value => x.set(value));
  const run = useRef<AnimationPlaybackControls | null>(null);
  const go = useRef<{ id: number; x: number; y: number; dragging: boolean; last: { x: number; t: number }[] } | null>(null);
  const swiped = useRef(false);
  useEffect(() => x.on("change", (v) => {
    const dx = Math.min(0, Math.round(v));
    if (slide.current) slide.current.style.transform = dx ? `translateX(${dx}px)` : "";
    // Slid in from the right as far as the row has gone (moved, not laid out anew each frame).
    if (under.current) under.current.style.transform = `translateX(calc(100% + ${dx}px))`;
  }), [x]);
  const back = () => {
    run.current?.stop();
    run.current = animate(x, 0, { ...MOVE, velocity: x.getVelocity() });
  };
  /** Off to the left, then the row closes up; archived once it is gone (the core takes it out of the list then). */
  const leave = async () => {
    const el = frame.current;
    if (!el) return;
    run.current?.stop();
    const off = animate(x, -el.offsetWidth, { type: "spring", visualDuration: 0.2, bounce: 0, velocity: Math.min(x.getVelocity(), 0) });
    run.current = off;
    await off.finished;
    el.dataset.leaving = "";
    await play(el, [{ height: `${el.offsetHeight}px` }, { height: "0px" }], { duration: 200, easing: "cubic-bezier(0.2, 0.7, 0.2, 1)", fill: "forwards" }).finished;
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
    if (!cancelled && g.dragging) fingers.set(Math.min(0, e.clientX - g.x));
    fingers.flush();
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
        fingers.cancel();
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
        fingers.set(dx < 0 ? dx : 0);
      }}
      onPointerUp={(e) => end(e, false)} onPointerCancel={(e) => end(e, true)}
      onClickCapture={(e) => { if (swiped.current) { swiped.current = false; e.preventDefault(); e.stopPropagation(); } }}>
      <div ref={under} className={css.mSwipeUnder} aria-hidden="true"><span>{t("web-mobile.home.archive")}</span></div>
      <div ref={slide} className={css.mSwipeSlide}>
        {children}
      </div>
    </div>
  );
}

/**
 * Archives a row's chat (a chat keeping watch once asked, the core's words): `leave` first takes the row away, `stay`
 * puts it back when it was not archived after all. Said at once by its title, why not if it was not.
 */
function useRowArchive(item: ChatItem) {
  const app = useApp();
  const api = stationApi(useStationCall(item.station));
  const go = () => archiveSaid(api, item, item.title, app.toast);
  return (leave: () => Promise<void>, stay: () => void) => {
    if (item.watch) {
      stay();
      confirm(app, { title: t("web-mobile.home.archiveAsk", { title: item.title }), text: item.watch.ask, action: t("web-mobile.home.archive"), run: go });
      return;
    }
    void leave().then(go).catch((error: unknown) => {
      stay();
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
    // A chat keeping watch is archived only once asked, in the core's words.
    { label: t("web-mobile.home.archive"), icon: <Archive size={16} />, action: () => {
      const archive = () => archiveSaid(api, item, item.title, app.toast);
      // Asked first when it keeps watch; either way said at once by its title, why not if it was not.
      if (item.watch) confirm(app, { title: t("web-mobile.home.archiveAsk", { title: item.title }), text: item.watch.ask, action: t("web-mobile.home.archive"), atOnce: "web-mobile.home.archiveFailed", run: archive });
      else archive().catch(failed("web-mobile.home.archiveFailed"));
    } },
  ] });
}

/** The last thing said, on one line, in the secondary colour (the row's picture says who is in it). */
function LastMessage({ item }: { item: ChatItem }) {
  return <span className={css.mLast}><span className={css.mLastText}>{item.last!.preview}</span></span>;
}


