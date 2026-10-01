// Home is the `chats` view as the Android app lists it (apps/android/…/screens/Home.kt): one kind of item, newest first
// and grouped by day. A fixed head (settings · workspace · the filter · stations) and the new-chat button floating
// at the bottom. The lists (all, mine, watching) are followed at once, side by side: switching slides from one to another with nothing to wait for.
import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent, type ReactNode } from "react";
import { motionValue } from "motion";
import { animate, MOVE, reducedMotion, type AnimationPlaybackControls } from "../motion.ts";
import { stationApi, useChats, useStationCall, useStations, useStatus, type ChatItem, type ChatsView, type StatusView, type TopicState } from "../api.ts";
import { useWorkspaces } from "../cloud/api.ts";
import { Archive, Check, ChevronDown, ChevronRight, Edit, Filter, Pin, Settings, Unplug } from "../icons.tsx";
import { ask, confirm } from "./sheets.tsx";
import { stationBase, useChatFilter, type ChatFilter } from "../station.tsx";
import { useApp } from "./app.tsx";
import { FailedMark, Illustration, SectionHeader, SlackMark, Spinner } from "./parts.tsx";
import { ChatMark, jumpFromLine, stateLine, WaitingText } from "../ChatMark.tsx";
import * as chatMarkCss from "../ChatMark.css.ts";
import { useWorkspaceMarks } from "../lastChat.ts";
import { RowAside } from "../RowPicture.tsx";
import { FirstStation } from "./Stations.tsx";
import { OpenJobs } from "./OpenJobs.tsx";
import { ChangelogNews } from "./Changelog.tsx";
import { StationGlyph, glyphCounts } from "../StationGlyph.tsx";
import * as barsCss from "./styles/bars.css.ts";
import { openWorkspaces } from "./Workspaces.tsx";
import * as css from "./Home.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as homeCss from "./styles/home.css.ts";
import { Tip } from "../ui.tsx";
import { useDoing, useDoingFailed } from "../doing.ts";

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
  return (
    <div className={css.mHome}>
      {none ? (
        <div className={css.mHomePanes}><div className={css.mHomePane} style={{ display: "flex", flexDirection: "column" }}><FirstStation /></div></div>
      ) : (
        <div className={css.mHomePanes} data-filter={filter}>
          <ChatPane chats={all} filter="all" />
          <ChatPane chats={mine} filter="mine" />
          <ChatPane chats={watching} filter="watching" />
        </div>
      )}
      {/* The lists run under both bars, which are frosted glass over them. */}
      <header className={`${css.mHomeBar} ${pagesCss.mGlass}`}>
        <button type="button" className={`${barsCss.mNavButton} ${css.mHomeMe}`} onClick={() => app.push(app.at("/settings"))} aria-label="设置">
          <Settings size={22} />
        </button>
        <button type="button" className={css.mHomeWorkspace} onClick={() => openWorkspaces(app)}>
          <b>{app.entry.name}</b>
          {marks?.others
            ? <span className={chatMarkCss.chatMarkInline} data-tone={marks.others} role="img" aria-label={marks.othersLabel ?? ""} />
            : invited && <span className={css.mDot} aria-label="有邀请" />}
          <ChevronDown size={16} />
        </button>
        {/* The filter, and the archive in its menu, as on the wide screen: nothing to narrow or look back on with no station. */}
        {(all.value?.stations.length ?? 0) > 0 && <FilterButton filter={filter} setFilter={setFilter} />}
        {/* The stations at a glance (../StationGlyph.tsx); its page says which is which. */}
        <StationButton view={all.value} />
      </header>
      {/* The new-chat button alone, floating over the list at the bottom right: a disc in the accent in a glass ring. */}
      {!none && <div className={css.mHomeToolbar}>
        {/* The decisions waiting for the viewer (奏 N): a frosted capsule beside it, only while there are some. */}
        {decisions > 0 && (
          <button type="button" className={`${pagesCss.mFloating} ${css.mDecisions}`} onClick={() => app.push(app.at("/decisions"))} aria-label={`奏：${decisions} 件等你决定`}>
            <b>奏</b><span>{decisions}</span>
          </button>
        )}
        <div className={`${pagesCss.mFloating} ${css.mHomeCapsule}`}>
          <button type="button" className={css.mNewChat} onClick={() => app.open(app.at("/new"))} aria-label="新建对话"><Edit size={20} /></button>
        </div>
      </div>}
    </div>
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
        <b>最近的会话</b>
        <button type="button" className={css.mNewChat} data-small onClick={() => app.open(app.at("/new"))} aria-label="新建对话"><Edit size={17} /></button>
      </div>
      <div className={css.mRecentRows}>
        {!view ? <Note text={chats.error?.message ?? "正在读取会话…"} error={!!chats.error} /> : items.map((item) => <ChatRow key={`${item.station}/${item.id}`} item={item} lead={view.leading ?? "agents"} />)}
      </div>
      <button type="button" className={css.mRecentAll} onClick={app.home}>全部会话<ChevronRight size={16} /></button>
    </>
  );
}

/** 全部, 我参与的 or 监控中, and the archive, from a menu under it; marked in the accent while it narrows the list. */
function FilterButton({ filter, setFilter }: { filter: ChatFilter; setFilter: (value: ChatFilter) => void }) {
  const app = useApp();
  const mark = (on: boolean) => on ? <Check size={16} /> : <span style={{ width: 16 }} />;
  return (
    <button type="button" className={`${barsCss.mNavButton} ${css.mFilter}`} data-on={filter !== "all" || undefined}
      aria-label={`筛选会话：${filter === "mine" ? "我参与的" : filter === "watching" ? "监控中" : "全部"}`}
      onClick={(e) => {
        const r = e.currentTarget.getBoundingClientRect();
        // The menu is 180 wide (app.tsx MenuHost): its right edge under the button's.
        app.menu({ anchor: new DOMRect(r.right - 180, r.top, 0, r.height), items: [
          { label: "全部", icon: mark(filter === "all"), action: () => setFilter("all") },
          { label: "我参与的", icon: mark(filter === "mine"), action: () => setFilter("mine") },
          { label: "监控中", icon: mark(filter === "watching"), action: () => setFilter("watching") },
          { label: "已归档", icon: <Archive size={16} />, action: () => app.push(app.at("/archive")) },
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
  const label = view?.trouble ? `Station：${said}（${view.trouble.text}）` : `Station：${said}`;
  return (
    <button type="button" className={barsCss.mNavButton} onClick={() => app.push(app.at("/settings/stations"))} aria-label={label}>
      <StationGlyph counts={counts} />
    </button>
  );
}

/** "Reading", and what the core has been waiting on for a while if anything (the core's `status`). */
function reading(status: StatusView | undefined): string {
  return status?.text ? `正在读取会话… ${status.text}` : "正在读取会话…";
}

/** One of the two lists, all or the viewer's: its states (connecting, failing, empty) and its days. */
function ChatPane({ chats, filter }: { chats: TopicState<ChatsView>; filter: ChatFilter }) {
  const view = chats.value;
  const scope = useApp().entry.id;
  const status = useStatus(scope);
  const lead = view?.leading ?? "agents";
  return (
    <div className={css.mHomePane}>
      {/* What the last update brought (./Changelog.tsx), until it is seen: even while the list is being read. */}
      <ChangelogNews />
      {!view ? <Note text={chats.error?.message ?? reading(status)} error={!!chats.error} /> : (
        <>
          {/* A station's link coming back is said on its rows; only with no rows to show does the list say it. */}
          {view.note?.reading && <Note text={reading(status)} />}
          {view.note?.failing.map((s) => <Note key={`e/${s.station}`} text={s.text} error />)}
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
}

function Note({ text, error = false }: { text: string; error?: boolean }) {
  return <p className={homeCss.mNote} data-error={error || undefined}>{text}</p>;
}

function Empty({ view, filter }: { view: ChatsView; filter: ChatFilter }) {
  const app = useApp();
  const any = view.stations.length > 0;
  return (
    <div className={css.mEmpty}>
      <Illustration name={any ? "new-chat" : "station-offline"} width={240} />
      {filter === "mine" ? <p>没有你参与的会话。</p>
        : filter === "watching" ? <p>没有在监控的会话。</p>
        : any ? <><p>还没有会话。在 Slack 里 @ {view.stations.length > 1 ? "它们" : "它"}，或者</p><button type="button" className={partsCss.mLink} onClick={() => app.push(app.at("/new"))}>新建对话</button></>
        : <><p>还没有 station。</p><button type="button" className={partsCss.mLink} onClick={() => app.push(app.at("/settings/stations"))}>看看 Station</button></>}
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
function ChatRow({ item, lead }: { item: ChatItem; lead: "agents" | "people" }) {
  const app = useApp();
  const [held, setHeld] = useState(false);
  // Pinned, renamed or archived from its menu (closed by then): the row says it is under way until it answers, and a
  // few seconds that it failed (the toast said why too).
  const pinning = useDoing("chat.pin", { station: item.station, session: item.session });
  const changing = useDoing(["chat.rename", "chat.archive"], { station: item.station, session: item.session, thread: item.thread });
  const busy = pinning || changing;
  const failed = useDoingFailed(["chat.rename", "chat.archive"], { station: item.station, session: item.session, thread: item.thread })
    ?? useDoingFailed("chat.pin", { station: item.station, session: item.session });
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
        <ChatMark item={item} inline />
        <span className={css.mChatTitle} data-unread={item.unread || undefined}>{item.title}</span>
        {/* Only an agent that came from elsewhere (Slack, the only kind of connect) says so; an offline station, too. */}
        {busy ? <span className={css.mChatMark} aria-label="正在处理"><Spinner size={12} /></span>
          : failed !== undefined ? <span className={css.mChatMark}><FailedMark error={failed} size={12} /></span>
          // Its station offline, or its link coming back: unplugged (a spinner is only something its person did).
          : item.offline || item.reconnecting ? <Tip label={item.offline ?? item.reconnecting}><span className={css.mChatMark} aria-label={item.offline ?? item.reconnecting}><Unplug size={14} /></span></Tip>
          : <span className={css.mChatMark}>{item.connect && <Tip label={item.originText ?? "Slack"}><span><SlackMark size={14} /></span></Tip>}</span>}
      </span>
      <span className={css.mChatLine2}>
        {/* Where it stands, when the core has words for it (奏 · …, 要你帮忙：…, 做完了), instead. */}
        <span className={css.mChatLast}>{stateLine(item)
          ? <span className={css.mLast}><WaitingText text={stateLine(item)!} className={css.mLastText} /></span>
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
}

/** How far (of its width) a row is swiped before letting go archives it, and how fast a fling has to be (px/ms). */
const TAKES = 0.35;
const FLING = 0.6;

/**
 * A row whose chat has nothing left in it (the core's `archivable`): 归档 in words at its end, and swiped left it is
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
      <div ref={under} className={css.mSwipeUnder} aria-hidden="true"><span>归档</span></div>
      <div ref={slide} className={css.mSwipeSlide}>
        {children}
        <button type="button" className={css.mRowArchive} aria-label={`归档「${item.title}」`} disabled={busy} onClick={() => archive()}>归档</button>
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
  const go = () => api.archive(item, true).then(() => app.toast("已归档"));
  return (leave?: () => Promise<void>, stay?: () => void) => {
    if (item.watch) {
      stay?.();
      confirm(app, { title: `归档「${item.title}」？`, text: item.watch.ask, action: "归档", run: go });
      return;
    }
    void (leave ? leave() : Promise.resolve()).then(go).catch((error: unknown) => {
      stay?.();
      app.toast(`没能归档：${error instanceof Error ? error.message : String(error)}`);
    });
  };
}

/**
 * What can be done to a chat from its row: pin it, rename it, archive it. None for a new chat its station has not made
 * yet, or one on a station offline.
 */
function useRowMenu(item: ChatItem, busy: boolean) {
  const app = useApp();
  const api = stationApi(useStationCall(item.station));
  // One thing at a time: while one asked of it is under way, its menu waits.
  if (item.offline || item.pending || busy) return null;
  const failed = (what: string) => (error: unknown) => app.toast(`没能${what}：${error instanceof Error ? error.message : String(error)}`);
  return (anchor: DOMRect, onDismiss: () => void) => app.menu({ anchor, onDismiss, items: [
    // A station from before pins says nothing of them: its chats are not pinned from here.
    ...(item.pinned == null ? [] : [{ label: item.pinned ? "取消固定" : "固定", icon: <Pin size={16} />, action: () => { api.pin(item, !item.pinned).catch(failed(item.pinned ? "取消固定" : "固定")); } }]),
    { label: "重命名", icon: <Edit size={16} />, action: () => ask(app, {
      title: "重命名对话", value: item.title, placeholder: "对话名称", action: "保存", empty: true, hint: "留空则用第一句话作名字",
      run: (title) => api.rename(item, title),
    }) },
    // A chat keeping watch is archived only once asked: its watch runs on in the archive (the core's words).
    { label: "归档", icon: <Archive size={16} />, action: () => {
      const archive = () => api.archive(item, true).then(() => app.toast("已归档"));
      // Asked first, its sheet says what went wrong and stays; else the toast does.
      if (item.watch) confirm(app, { title: `归档「${item.title}」？`, text: item.watch.ask, action: "归档", run: archive });
      else archive().catch(failed("归档"));
    } },
  ] });
}

/** The last thing said, on one line, in the secondary colour (the row's picture says who is in it). */
function LastMessage({ item }: { item: ChatItem }) {
  return <span className={css.mLast}><span className={css.mLastText}>{item.last!.preview}</span></span>;
}
