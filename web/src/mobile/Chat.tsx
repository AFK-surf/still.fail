import { outsideScroll, scrollToEnd } from "../scrollBounds.ts";
import { pickAttachment } from "../pickAttachment.ts";
import { StationUpdate } from "../StationUpdate.tsx";
// An item's page on a narrow screen: its chat's messages (none before its agent has a chat), the composer, and each
// agent's execution history as a page opened from its mark or name. The messages are the wide screen's own (../Chat.tsx:
// the same rows, avatars, names, quotes, files, activity and list behaviour), with the avatar and name in line with the
// words rather than out in a margin. A long press on a message's words picks a passage of them where it is, to quote or
// copy (pick.tsx); ＋ adds files.
import { memo, useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode, type RefObject } from "react";
import { useLocation, useNavigate, useParams } from "react-router";
import { topicNow, useCall, useReady, useTopicSelect } from "../core/react.ts";
import { useAct } from "@stillfail/ui/toast.tsx";
import { archiveSaid, stationApi, useApi, useChat, useChatJobs, useListedChat, useLives, useStationCall, useStationLook, useStations, type ChatAgent, type ChatThread, type ChatView, type Quote, type Attachment } from "../api.ts";
import { draftKeyOf, useHost, type HostComposer } from "./ChatHost.tsx";
import { DraftKey } from "../draft.ts";
import { OpenFile } from "../Viz.tsx";
import { fileService } from "../Preview.tsx";
import type { Draft as SharedDraft } from "../draft.ts";
import { Gallery } from "../FilePreview.tsx";
import { chatPage, useChatPageActions } from "../chatPage.ts";
import { useChatFind } from "../ChatFind.tsx";
import { askClear, ChatRows, ChatSample, historyLinkClicked, ImageQuote, sendDraft, useAskedFile, useAsksShown, useComposerText, useMessageList, useSelectionQuote } from "../Chat.tsx";
import { jumpTo } from "../jumpTo.ts";
import { Archive, ArrowDown, ArrowUp, ArrowUpRight, Bell, Camera, Chats, ChevronRight, ChevronLeft, Copy, Edit, External, File, ImageUpload, List, More, Photo, Pin, Plus, Search, Server, Stop, Users, Web } from "@stillfail/ui/icons.tsx";
import { scopeOf, stationBase, useStation } from "../station.tsx";
import { StationMark } from "../StationMark.tsx";
import { StationCornerDot, StationDot, useStationLink } from "../StationLink.tsx";
import * as linkCss from "../StationLink.css.ts";
import { StationPeek } from "../cloud/StationCards.tsx";
import { GoRow } from "./Settings.tsx";
import { Spinner, Waiting, WaitLine } from "@stillfail/ui/waiting.tsx";
import { PENDING } from "../lastChat.ts";
import { LOCAL_MS } from "@stillfail/ui/motion.ts";
import { SheetGrab, SheetHead, useApp, type MobileApp } from "./app.tsx";
import { ask, confirm } from "./sheets.tsx";
import { useRelay } from "../Relay.tsx";
import { openHistory } from "./History.tsx";
import { AgentSince, openAgent } from "./AgentSheet.tsx";
import { HOLD, usePick } from "./pick.tsx";
import { Button, Gone, GroupLabel, InfoList, InfoRow, LinkButton, ModelMark, NavButton, PickRow, QuotaRings, Seg, SlackMark, stateOf } from "./parts.tsx";
import { AgentMark, ElsewhereLogo } from "../ui.tsx";
import { OutsideList, outsideOf, shareOutside, type Outside } from "../OutsideShare.tsx";
import { useAction } from "../action.ts";
import { PeopleStack, PersonNamed } from "../components.tsx";
import { JobDot, metaOf, NO_JOBS, useClearEnded, useJobLog, useStopJob } from "../Jobs.tsx";
import { Letters } from "../Letters.tsx";
import { PullMark, pullTitle, ThingMenu, Things, useChatThings } from "../Things.tsx";
import { TermText } from "../TermText.tsx";
import { screenLinkClicked, stillfailLinkClicked } from "../stillfailLink.ts";
import { doingMatches, failed, useDoing, useDoingFailed, useDoingList } from "../doing.ts";
import type { ChatCcTo, ChatJobsView, ChatPublish, ChatPublished, ChatShare, Job } from "../core/shapes.ts";
import { keptCount, PublishPicture, savePicture, takePicture, usePublishPreview, useTicking } from "../Publish.tsx";
import * as chatCss from "./styles/chat.css.ts";
import * as hostCss from "./ChatHost.css.ts";
import { sendingHere, sentAfter } from "../madeChat.ts";
import * as css from "./Chat.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as rootCss from "./styles/root.css.ts";
import * as sharedCss from "../Chat.css.ts";
import * as barsCss from "./styles/bars.css.ts";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as homeCss from "./styles/home.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as connectsCss from "./Connects.css.ts";

import { WorkspaceBadge } from "../WorkspaceMark.tsx";
import { t } from "../i18n.ts";
export function ChatScreen() {
  const { chat: address = "" } = useParams();
  // A chat made here keeps the key the core gave it when its address becomes its station's (below).
  const key = openedAs(address);
  const station = useStation();
  // A service's link (`?service=<job>`, from Slack): the service, full screen, over the chat.
  const app = useApp();
  const asked = new URLSearchParams(useLocation().search).get("service");
  const service = asked ? servicePath(station.address, key, asked) : null;
  // The link is an instruction for this visit, not for every resumption of its hidden page's effects.
  const openedService = useRef<string | null>(null);
  useEffect(() => {
    if (!service || openedService.current === service) return;
    openedService.current = service;
    app.push(service);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [service]);
  // The page slides in once its chat is read from the device (LOCAL_MS at most), not empty; one that has to come from
  // its station is not waited for: the page slides in, showing it coming.
  useReady({ topic: "chat", station: station.address, session: key }, LOCAL_MS);
  const chat = useChat(station.address, { session: key });
  const view = chat.value;
  const navigate = useNavigate();
  const stationKey = key.startsWith(PENDING) ? view?.key : undefined;
  useEffect(() => {
    if (!stationKey || address === stationKey) return;
    renamed.set(stationKey, key);
    navigate(`${stationBase(station.address)}/chats/${encodeURIComponent(stationKey)}`, { replace: true });
  }, [stationKey, address]);
  const lives = useLives(station.address, (view?.agents ?? []).map((a) => a.session.key));
  const listed = useListedChat(station.address, key);
  // Until the core has the chat, the page is already a chat's page (its bar, with its title as the list has it): what
  // comes fills it in place.
  if (!view) {
    // Read from its station meanwhile, over the messages to come; what is wrong in red, over faded ones.
    return <ChatWaiting title={listed?.title} text={station.name ? t("web-mobile.chat.readingFrom", { station: station.name }) : t("web-mobile.chat.reading")}
      error={chat.error ? t("web-mobile.chat.failed", { error: chat.error.message }) : undefined} />;
  }
  return <Chat view={view} sessionKey={key} lives={lives} />;
}

/** Chats made here, by the key their station gave them: the core's key their page was opened with. */
const renamed = new Map<string, string>();
/** The key a chat's page goes by: the one it was opened with, for a chat made here. */
export const openedAs = (address: string) => renamed.get(address) ?? address;

/** What the page knows of an agent: its chat entry and its live view. */
interface Here { station: string; key: string; view: ChatView }

/** A web service's page (./Preview.tsx), over its chat. */
function servicePath(station: string, key: string, job: string): string {
  return `${stationBase(station)}/chats/${encodeURIComponent(key)}/services/${encodeURIComponent(job)}`;
}

function Chat({ view, sessionKey, lives }: { view: ChatView; sessionKey: string; lives: ReturnType<typeof useLives> }) {
  const station = useStation();
  const app = useApp();
  const list = useRef<HTMLDivElement>(null);
  // The page's composer is its host's (ChatHost.tsx): kept as a new chat becomes this chat.
  const { now: draft, use } = useHost();
  const here: Here = { station: station.address, key: sessionKey, view };
  useComposer(view, here, use, list);
  return (
    <div className={chatCss.mChat}>
      <Messages view={view} lives={lives} list={list} draft={draft} here={here} stationName={station.name} />
      <ChatBar station={station.address} session={sessionKey} />
    </div>
  );
}

/** What the chat's bar shows of it: the same while that is, whatever else of the chat changes (a message, its times). */
interface Bar {
  title: string; thread: ChatThread | null; archivable: boolean; people: ChatView["people"]; stationUpdate: ChatView["stationUpdate"];
  agents: { key: string; maker: ChatAgent["session"]["maker"]; runtime: ChatAgent["session"]["runtime"]; badge: ChatAgent["badge"]; badgeText: ChatAgent["session"]["badgeText"]; agentText: string }[];
}
const barOf = (view: ChatView): Bar => ({
  title: view.title, thread: view.thread ?? null, archivable: !!view.archivable, people: view.people, stationUpdate: view.stationUpdate,
  agents: view.agents.map((a) => ({ key: a.session.key, maker: a.session.maker, runtime: a.session.runtime, badge: a.badge, badgeText: a.session.badgeText, agentText: a.session.agentText })),
});
// Its thread compared by what the bar does with it (its id): the thread's own times change with every message.
const sameBar = (a: Bar | undefined, b: Bar | undefined) => a === b || (!!a && !!b && a.thread?.id === b.thread?.id
  && JSON.stringify({ ...a, thread: null }) === JSON.stringify({ ...b, thread: null }));

/**
 * The chat's bar: back, its title, then its people, then its agents' marks (each opens its card), as the wide screen's
 * title has them; "…" is the chat's own sheet. Given the chat's keys, it reads only what it shows; what a tap opens reads
 * the chat as it is then.
 */
const ChatBar = memo(function ChatBar({ station: address, session }: { station: string; session: string }) {
  const app = useApp();
  const topic = { topic: "chat", station: address, session } as const;
  const bar = useTopicSelect<ChatView, Bar | undefined>(topic, (s) => (s.value ? barOf(s.value) : undefined), sameBar);
  const jobs = useChatJobs(address, { session }).value;
  const station = useChatStation(address);
  const link = useStationLink(address);
  const here = (): Here | null => {
    const view = topicNow<ChatView>(topic);
    return view ? { station: address, key: session, view } : null;
  };
  if (!bar) return null;
  const thread = bar.thread;
  return (
    <BarFrame title={bar.title} more={!!thread} onMore={() => { const h = here(); if (h && thread) openChatInfo(app, h, thread); }}
      trailing={<>
        {/* Nothing left in it (the core's `archivable`): archived with one tap. */}
        {bar.archivable && thread && <ArchiveButton station={address} session={session} />}
        {jobs && jobs.jobs.length > 0 && <JobsButton station={address} session={session} alarm={jobs.alarm} />}
      </>}>
      {bar.agents.length === 0 && <StationChip station={address} />}
      <StationUpdate station={address} notice={bar.stationUpdate} />
      <PeopleStack people={bar.people} max={5} />
      {bar.agents.map((a, i) => {
        const card = () => { const h = here(); if (h) agentCard(app, h, a.key); };
        const label = t("web-mobile.agent.card", { agent: a.agentText });
        // The first shares its tile with the station it runs on: its icon, or its name where it has none. One tap for
        // the whole tile (two halves are too small to tell apart under a finger): the agent's card, which leads on to
        // the station's.
        return (
          <button key={a.key} type="button" className={`${css.mBarAgent} ${linkCss.corner}`} onClick={card} aria-label={label}>
            {i === 0 && station ? (
              <AgentMark maker={a.maker} runtime={a.runtime} badge={a.badge} badgeText={a.badgeText} size={22}
                wrap={(logo) => <span className={css.mBarJoinedAgent}>{logo}</span>}>
                <span className={css.mBarJoinedStation} data-name={station.emoji || station.icon ? undefined : true}>
                  {station.emoji || station.icon ? <StationMark emoji={station.emoji} icon={station.icon} size={13} /> : station.name}
                </span>
              </AgentMark>
            ) : <AgentMark maker={a.maker} runtime={a.runtime} badge={a.badge} badgeText={a.badgeText} size={22} />}
            {i === 0 && station && <StationCornerDot link={link} />}
          </button>
        );
      })}
    </BarFrame>
  );
});

/**
 * The station the chat runs on, after its title: its icon and name; a tap opens its
 * card in a sheet (the wide screen's is a hover card over the same tag, ../cloud/StationCards.tsx StationPeek).
 */
function StationChip({ station }: { station: string }) {
  const app = useApp();
  const s = useChatStation(station);
  const link = useStationLink(station);
  if (!s) return null;
  return (
    <button type="button" className={css.mBarStation} aria-label={s.name} onClick={() => openStationSheet(app, station)}>
      {link && <StationDot link={link} />}{(s.emoji || s.icon) && <StationMark emoji={s.emoji} icon={s.icon} size={12} />}<span>{s.name}</span>
    </button>
  );
}

/** How the station the chat runs on looks: followed alone, not each change of the stations' views. */
function useChatStation(station: string) {
  return useStationLook(station);
}

/** The card of the station a chat runs on, in a sheet (in place of any open: the agent's card leads to it). */
function openStationSheet(app: MobileApp, station: string) {
  app.sheet({ height: 0.55, content: () => <StationSheet station={station} /> });
}

function StationSheet({ station }: { station: string }) {
  const app = useApp();
  const s = useStations(scopeOf(station)).value?.find((x) => x.station === station);
  return (
    <>
      <SheetGrab />
      <div className={`${sheetsCss.mSheetScroll} ${css.mStationSheet}`}>
        {s && <StationPeek s={s} footer={<>
          {/* Its files (docs/drive.md), where it has a drive: a way there from where it is named, as the wide screen's card has. */}
          {s.overview?.drive && <GoRow title={t("web-pages.drive.title")} value={s.overview.drive.roots.length ? t("web-pages.drive.rootsCount", { n: s.overview.drive.roots.length }) : t("web-pages.drive.notShared")} onClick={() => { app.sheet(null); app.push(app.at(`/s/${s.id}/files`)); }} />}
          <GoRow title={t("web-mobile.chat.stationDetails")} onClick={() => { app.sheet(null); app.push(app.at(`/s/${s.id}/overview`)); }} />
        </>} />}
      </div>
    </>
  );
}

/**
 * A chat's page before its chat is there: its bar (its `title` as the list has it, if it has it) and under it the messages to come in their bones, with what
 * it waits on (@stillfail/ui waiting.tsx) or in red what is wrong; `gone`: there is nothing to wait for (no such
 * station), said instead.
 */
export function ChatWaiting({ title = "", text, error, gone }: { title?: string | undefined; text?: string; error?: string | undefined; gone?: string }) {
  return (
    <div className={chatCss.mChat}>
      <BarFrame title={title} more={false} />
      <div className={css.mChatWaiting}>{gone !== undefined ? <Gone text={gone} /> : <Waiting text={text} error={error} sample={<ChatSample className={`${chatCss.mMessages} ${chatCss.mMessagesHeld} ${sharedCss.chatMessages} ${sharedCss.inlineHeads} ${rootCss.wide}`} />} />}</div>
    </div>
  );
}

/** The bar's frame, the same while the chat loads and once it has: back, the title, what follows it, what is at its end, and "…". */
export function BarFrame({ title, more, onMore, trailing, children }: { title: string; more: boolean; onMore?: () => void; trailing?: ReactNode; children?: ReactNode }) {
  const app = useApp();
  return (
    <header className={`${css.mChatBar} ${pagesCss.mGlass}`} data-find-slot="">
      <button type="button" className={css.mChatBack} onClick={app.pop} aria-label={t("common.back")}><ChevronLeft size={22} /></button>
      <span className={css.mChatBarTitle}><b>{title}</b>{children}</span>
      {trailing}
      {more && onMore && <NavButton icon={More} label={t("web-mobile.chat.info")} onClick={onMore} />}
    </header>
  );
}

// ── the list ───────────────────────────────────────────────────────────

/** What the bar covers of the list's top: its padding (`lead`) less the room it leaves under the bar (styles/chat.css.ts). */
const belowBar = (lead: number) => Math.max(0, lead - 8);

/** The wide screen's list (../Chat.tsx's ChatRows), in the page: over it, the bar; under it, the composer. */
function Messages({ view, lives, list, draft, here, stationName }: {
  view: ChatView; lives: ReturnType<typeof useLives>; list: RefObject<HTMLDivElement | null>; draft: RefObject<Draft>; here: Here;
  stationName?: string | undefined;
}) {
  const app = useApp();
  // The phone's bar floats over the list's top: its messages show from a little above where the list's padding ends.
  const rows = useMessageList(list, view, `${here.station}:${view.thread?.id ?? here.key}`, lives, 20, belowBar);
  // Its own find ("…" → 在对话中查找): its bar takes the page's bar's place; what is found is put clear of what the
  // list's padding leaves for the bar and the composer.
  const find = useChatFind(list, rows.virtual, view.thread?.id ?? null, rows.messages, null, null);
  const asks = useAsksShown(rows.virtual, view);
  const asking = asks.length > 0 && !!view.thread;
  const [turn, setTurn] = useState(0);
  // Sent to by the page's key until its thread is known (a chat made here, or the agent's: useComposer).
  const to = view.thread?.id ?? here.key;
  // The messages are kept as they are while nothing they show changes: what they are handed stays the same function,
  // the latest one behind it.
  const archive = useArchiveChat(here.station, here.key);
  // An image opened here steps through the chat's (the core tells those beside it, as this page's chat names it).
  const gallery = useMemo(() => ({ chat: { session: here.key } }), [here.key]);
  const latest = useRef({ here, draft, app, view, messages: rows.messages });
  latest.current = { here, draft, app, view, messages: rows.messages };
  // What is in the list (an agent's name, its activity, 归档) does these by the chat's key (../chatPage.ts).
  const chatKey = draftKeyOf(here.station, here.key);
  useChatPageActions(chatKey, {
    history: (key, entry) => openHistory(app, here.station, here.key, key, entry),
    agent: (key) => agentCard(app, here, key),
    tab: (key) => { if (key.startsWith("service:")) app.push(servicePath(here.station, here.key, key.slice("service:".length))); },
    archive,
    find: find.show,
  });
  const [stable] = useState(() => ({
    quote: (q: Omit<Quote, "comment">, file?: Attachment) => latest.current.draft.current.quote(q, file),
    // The turn of the message `ts` shared as a picture, in the sheet the chat's own sharing has.
    share: (ts: string) => {
      const seq = latest.current.messages.find((m) => m.ts === ts)?.seq;
      if (seq !== undefined) stable.shareSeq(seq);
    },
    shareSeq: (seq: number) => {
      const { app, here, view } = latest.current;
      if (!view.thread) return;
      const thread = view.thread.id;
      app.sheet({ height: 0.9, content: () => <PublishSheet here={here} thread={thread} turn={seq} /> });
    },
    file: (session: string, file: { path: string; name: string }) => {
      const { app, here } = latest.current;
      app.push(servicePath(here.station, here.key, fileService({ session, path: file.path, name: file.name })));
    },
  }));
  // Words selected with a mouse inside one message offer to quote them; a finger held on them picks them in place.
  const quoting = useSelectionQuote(list, stable.quote, stable.shareSeq);
  const picking = usePick(list, stable.quote, stable.share);
  const hold = useLinkHold(list);
  const askedFile = useAskedFile(list, rows.messages);
  // still.fail's own links (/o/<workspace>/<station>/<session>, as agents post them; a chat's page, as a reference is
  // written), on any of its cloud's hosts, open here, as pages over this one (the chat and what is being written stay under them): one of this chat's agents' web services, or another session. A
  // link to an agent's execution history opens it.
  const onClick = (event: React.MouseEvent) => {
    // One of this chat's agents' (another's goes to its chat, below).
    const history = historyLinkClicked(event);
    if (history && view.agents.some((a) => a.session.key === history.key)) {
      event.preventDefault();
      openHistory(app, here.station, here.key, history.key, history.entry);
      return;
    }
    // One of a station's screens (an agent asking a person to take over): its viewer, over this chat.
    const screen = screenLinkClicked(event);
    if (screen?.own) {
      event.preventDefault();
      app.push(screen.path);
      return;
    }
    const link = stillfailLinkClicked(event);
    if (!link) return;
    const elsewhere = link.own && history ? history : null;
    if (elsewhere) {
      // Another chat's agent's execution history, at the entry it names: over this chat, as its page would open it.
      event.preventDefault();
      app.push(`/w/${link.workspace}/s/${link.station}/chats/${encodeURIComponent(link.session)}/history/${encodeURIComponent(elsewhere.key)}?entry=${elsewhere.entry}`);
    } else if (link.service && view.agents.some((a) => a.session.key === link.session)) {
      event.preventDefault();
      app.push(servicePath(here.station, here.key, link.service));
    } else if (link.own) {
      event.preventDefault();
      const path = `/w/${link.workspace}/s/${link.station}/chats/${encodeURIComponent(link.session)}`;
      if (`${path}${link.search}` !== `${stationBase(here.station)}/chats/${encodeURIComponent(here.key)}`) app.push(`${path}${link.search}`);
    }
  };
  return (
    <OpenFile.Provider value={stable.file}>
      {quoting.pop}
      {askedFile}
      {find.bar}
      <Gallery.Provider value={gallery}>
      <div className={`${chatCss.mMessages} ${sharedCss.chatMessages} ${sharedCss.inlineHeads} ${rootCss.wide}`} ref={list} style={askClear(view, 38)} onClick={onClick} {...quoting.listProps} {...hold} {...sentAfter(view)}>
        <DraftKey.Provider value={chatKey}>
          <ImageQuote.Provider value={quoting.images}><ChatRows chat={view} rows={rows} to={to} /></ImageQuote.Provider>
        </DraftKey.Provider>
      </div>
      </Gallery.Provider>
      {picking}
      {/* Over the send button, in line with it; it comes up growing and goes the way it came. */}
      {/* Short of the chat's end (a window of it), with how many new messages wait there. */}
      <button type="button" className={`${css.mJump} ${pagesCss.mFloating}`} data-shown={rows.away || undefined} data-count={rows.waiting > 0 || undefined}
        aria-label={t("web-mobile.chat.toLatest")} onClick={rows.toEnd}><ArrowDown size={18} />{rows.waiting > 0 && <span>{t("web-mobile.chat.newMessages", { n: rows.waiting })}</span>}</button>
      {/* What waits to be decided and does not show: a bell there (over the way to the end when both show), leading to its post, then the next one's. */}
      <button type="button" className={`${css.mJump} ${css.mJumpAsk} ${pagesCss.mFloating}`} data-shown={asking || undefined} data-above={rows.away || undefined}
        aria-label={t("web-main.chat.asks.go")} onClick={() => { const next = asks[turn % asks.length]; if (next && view.thread) { jumpTo({ station: here.station, thread: view.thread.id, seq: next.seq }); setTurn((n) => n + 1); } }}><Bell size={18} /></button>
    </OpenFile.Provider>
  );
}

/**
 * Long-press on a web link in a message of the list: the link's menu (open it, copy it), as the Android app has it; a
 * right click there is the browser's own menu, with its link items. A long press elsewhere on a message's words picks
 * them (pick.tsx); the system's own menu for it never comes.
 */
function useLinkHold(list: RefObject<HTMLElement | null>) {
  const app = useApp();
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const touched = useRef(false);
  /** The web link pressed in one of the messages (a reference to a chat too), or null. */
  const linkAt = (event: React.SyntheticEvent) => {
    const a = (event.target as Element).closest?.<HTMLAnchorElement>("a[href]");
    return a && /^https?:\/\//i.test(a.getAttribute("href") ?? "") && a.closest("[data-author][data-ts]") && list.current?.contains(a) ? a : null;
  };
  const linkMenu = (a: HTMLAnchorElement, x: number, y: number) => {
    navigator.vibrate?.(10);
    // Under the line held (over it when there is no room below), centred on the finger: the menu is 180 wide (app.tsx MenuHost).
    const line = [...a.getClientRects()].find((r) => y >= r.top && y <= r.bottom) ?? a.getBoundingClientRect();
    const failed = (e: unknown) => app.toast(t("common.link.copyFailed", { error: e instanceof Error ? e.message : String(e) }));
    app.menu({ anchor: new DOMRect(x - 90, line.top, 0, line.height), items: [
      // As a tap on it: still.fail's own open here (the list's onClick), any other in a tab of its own.
      { label: t("common.link.open"), icon: <External size={16} />, action: () => a.click() },
      { label: t("common.link.copy"), icon: <Copy size={16} />, action: () => { navigator.clipboard.writeText(a.href).then(() => app.toast(t("common.link.copied")), failed); } },
    ] });
  };
  const cancel = () => clearTimeout(timer.current);
  return {
    onPointerDown: (e: React.PointerEvent<HTMLElement>) => {
      touched.current = e.pointerType !== "mouse";
      cancel();
      if (!touched.current) return;
      const link = linkAt(e);
      const { clientX: x, clientY: y } = e;
      if (link) timer.current = setTimeout(() => linkMenu(link, x, y), HOLD);
    },
    onPointerUp: cancel, onPointerCancel: cancel,
    onPointerMove: (e: React.PointerEvent) => { if (Math.abs(e.movementY) > 4 || Math.abs(e.movementX) > 4) cancel(); },
    // Where a long press asks for the browser's own menu too: not over a message.
    onContextMenu: (e: React.MouseEvent<HTMLElement>) => {
      const row = (e.target as Element).closest?.("[data-author][data-ts]");
      if (touched.current && row && list.current?.contains(row)) e.preventDefault();
    },
  };
}

// ── the composer ───────────────────────────────────────────────────────

/** What is being written (../draft.ts), and asking for the field's focus (a quote's comment done, a tap on the capsule). */
export type Draft = SharedDraft & { focus: number; bumpFocus(): void };

/**
 * ＋: take a photo, pick photos, pick files; or (`onStation`) a station's files, named by their path (StationFiles.tsx).
 * A menu over the composer's capsule (`plus` its ＋), as a long-pressed message's: the phone app's sheet of recent
 * photos needs the gallery, which a page cannot read.
 */
export function openAttach(app: MobileApp, plus: HTMLElement, onPicked: (files: FileList) => void, onStation?: () => void, cc?: { to: ChatCcTo[]; toggle(to: ChatCcTo): void }) {
  const pick = (accept: string, capture: boolean) => {
    pickAttachment(accept, capture, onPicked);
  };
  // From ＋'s left, over all of the capsule (its files and quotes too), as it is once ＋ has taken the focus.
  requestAnimationFrame(() => {
    const capsule = (plus.closest("[data-made-composer]") ?? plus.parentElement!).getBoundingClientRect();
    const anchor = new DOMRect(plus.getBoundingClientRect().left, capsule.top, 0, capsule.height);
    app.menu({ anchor, items: [
      { label: t("web-mobile.chat.camera"), icon: <Camera size={18} />, action: () => pick("image/*", true) },
      { label: t("web-mobile.chat.photos"), icon: <Photo size={18} />, action: () => pick("image/*", false) },
      { label: t("web-mobile.chat.files"), icon: <File size={18} />, action: () => pick("*/*", false) },
      ...(onStation ? [{ label: t("web-pages.chat.files"), icon: <Server size={18} />, action: onStation }] : []),
      // Copying what is sent to the chat's Slack or Feishu thread, on or off (`chat.cc`).
      ...(cc ? cc.to.map((o) => ({ label: t(o.on ? "web-mobile.chat.ccStop" : "web-mobile.chat.ccStart", { place: o.place }), icon: <ElsewhereLogo kind={o.via} size={18} />, action: () => cc.toggle(o) })) : []),
    ] });
  });
}

/**
 * The bar, inside a floating capsule that is its frame: ＋, the wide screen's text box (../Chat.tsx's useComposerText:
 * @-references, pasted files, what a preview offers `draftKey`; growing to six lines here, and Enter starting a line on
 * a touch keyboard), and a round send button (a spinner while a new chat is made). The menu of chats goes over the
 * capsule (`menu`).
 */
export function useComposerBar({ draft, draftKey, sessionKey, placeholder, locked = false, noFiles = locked, onPlus, onType, onSend }: {
  draft: Draft; draftKey: string | undefined; sessionKey: string | null; placeholder: string; locked?: boolean;
  /** No file is taken in, though it may be written (its station down). */
  noFiles?: boolean;
  onPlus: (plus: HTMLElement) => void; onType: () => void; onSend: () => void;
}): { menu: ReactNode; bar: ReactNode; expanded: boolean } {
  const input = useRef<HTMLTextAreaElement>(null);
  const [focused, setFocused] = useState(false);
  const expanded = focused || draft.text !== "" || draft.files.length > 0 || draft.quotes.length > 0;
  const ready = draft.ready && !locked;
  useEffect(() => { if (draft.focus > 0) input.current?.focus(); }, [draft.focus]);
  const { menu, field } = useComposerText({
    draft, input, draftKey, sessionKey, locked, noFiles, placeholder, className: css.mComposerField, lines: 6, layout: expanded,
    enterSends: window.matchMedia("(hover: hover)").matches, onType, onSubmit: () => { if (ready) onSend(); },
  });
  const bar = (
    <div className={css.mComposerBar} data-expanded={expanded || undefined}
      onFocus={() => setFocused(true)} onBlur={(e) => { if (!e.currentTarget.contains(e.relatedTarget)) setFocused(false); }}>
      <button type="button" className={css.mPlus} onClick={(e) => onPlus(e.currentTarget)} disabled={noFiles} aria-label={t("web-mobile.chat.addFiles")}><Plus size={18} /></button>
      {field}
      <button type="button" className={css.mSend} data-ready={ready || undefined} disabled={!ready} onClick={onSend} aria-label={t("web-mobile.chat.send")}>
        {draft.starting ? <Spinner className={partsCss.mSpinOnColor} /> : <ArrowUp size={18} />}
      </button>
    </div>
  );
  return { menu, bar, expanded };
}

/**
 * What the chat's composer (its host's, ChatHost.tsx) writes to: this chat, as the wide screen's composer sends
 * (../Chat.tsx's sendDraft). The composer empties at once: the message lives in the chat's outbox until the station has
 * it (a failure shows there too). Before the agent has a chat, what is sent waits in its outbox while the core has the
 * station make one, bound to the agent, and the page stays (the core shows the chat at the same address).
 */
/** What a chat's composer shows of it (its host draws it, ChatHost.tsx): where it writes, what it says till something is
 *  written, and what holds it back. */
export function composerShown(view: ChatView, station: string): Pick<HostComposer, "station" | "session" | "placeholder" | "offline" | "offlineNote" | "archived" | "cacheCold"> {
  return {
    station, session: view.agents[0]?.session.key ?? null,
    placeholder: view.archived ? t("web-mobile.chat.restoreFirst") : view.cc?.some((o) => o.on) ? t("web-mobile.chat.placeholderCc", { place: view.cc.filter((o) => o.on).map((o) => o.place).join("、") }) : t("web-mobile.chat.placeholder"),
    offline: view.offline, ...(view.offlineNote ? { offlineNote: view.offlineNote } : {}), archived: !!view.archived,
    ...(view.cacheCold ? { cacheCold: view.cacheCold } : {}),
  };
}

function useComposer(view: ChatView, here: Here, use: (spec: HostComposer) => void, list: RefObject<HTMLDivElement | null>) {
  const api = useApi();
  const call = useCall();
  const act = useAct();
  const keeper = view.agents[0]?.session.key ?? null;
  const warmed = useRef(0);
  const send = (draft: Draft) => {
    // Sent to by the page's key until its thread is known: a chat made here, or the agent whose page it is (what is sent
    // waits in the outbox at once while the core has the station make its chat).
    const to = view.thread?.id ?? here.key;
    // Its words stay where they were typed until its row is in the list, then go there (../madeChat.ts), over the composer.
    const into = list.current;
    const host = into?.closest<HTMLElement>(`.${hostCss.mChatHost}`);
    const field = host?.querySelector<HTMLElement>(`[data-made-composer] textarea:not([aria-hidden])`);
    into?.dispatchEvent(new Event("sent"));
    if (into && host && field) sendingHere(field, draft.text, { layer: host, z: "7", list: into });
    void sendDraft(draft, to, undefined);
  };
  useLayoutEffect(() => use({
    ...composerShown(view, here.station), send,
    restore: () => api.archive({ thread: view.thread?.id ?? null, session: here.key }, false),
    afresh: api.afresh,
    ...(view.cc?.length && view.thread ? { cc: { to: view.cc, toggle: (o: ChatCcTo) => act(call("chat.cc", { station: here.station, thread: view.thread!.id, to: o.thread, on: !o.on }), t("web-mobile.chat.ccStart", { place: o.place })) } } : {}),
    // Typing starts the session's runtime, so a cold start overlaps the writing.
    type: () => {
      if (view.offline || view.archived || !keeper || Date.now() - warmed.current < 60_000) return;
      warmed.current = Date.now();
      api.warm(keeper).catch(() => {});
    },
  }));
}

// ── services and background jobs ───────────────────────────────────────
// As the core puts them (the `chatJobs` view): those that matter now first, what is over faded and last.

/** The bar's button for the chat's services and jobs, with a dot when one died lately (red) or a service restarts (amber). */
function JobsButton({ station, session, alarm }: { station: string; session: string; alarm: string | undefined }) {
  const app = useApp();
  const open = () => {
    const view = topicNow<ChatView>({ topic: "chat", station, session });
    if (view) openJobs(app, { station, key: session, view });
  };
  return (
    <button type="button" className={`${barsCss.mNavButton} ${css.mJobsTrigger}`} aria-label={t("web-mobile.chat.jobs")} onClick={open}>
      <Web size={18} />
      {alarm && <span className={css.mJobsAlarm} data-alarm={alarm} aria-hidden="true" />}
    </button>
  );
}

/** How many letters the chat's agents and other chats' wrote each other, and opening them; none when there are none. */
function lettersOf(app: MobileApp, here: Here): { n: number; open(): void } | undefined {
  const n = here.view.letters ?? 0;
  const thread = here.view.thread?.id;
  const keeper = here.view.agents[0]?.session.key;
  return n > 0 && thread != null && keeper ? { n, open: () => openLetters(app, here.station, thread, keeper) } : undefined;
}

/** What the chat's agents and other chats' wrote each other, not in the chat (Letters.tsx), in a sheet. */
function openLetters(app: MobileApp, station: string, thread: number, keeper: string) {
  app.sheet({ height: 0.8, draggable: true, content: () => (
    <>
      <SheetGrab />
      <SheetHead title={t("web-main.letters.title")} />
      <div className={sheetsCss.mSheetScroll}><Letters station={station} thread={thread} keeper={keeper} /></div>
    </>
  ) });
}

/** What was said in the chat besides words (Things.tsx), in a sheet; 在对话中查看 closes it and goes to the message. */
function openThings(app: MobileApp, station: string, thread: number, keeper: string, initial?: "pulls") {
  app.sheet({ height: 0.8, draggable: true, content: () => (
    <>
      <SheetGrab />
      <SheetHead title={t("web-main.things.title")} />
      <div className={sheetsCss.mSheetScroll}><Things station={station} thread={thread} keeper={keeper} initial={initial}
        onShow={(seq) => { app.sheet(null); jumpTo({ station, thread, seq }); }} /></div>
    </>
  ) });
}

/** One of the chat's agents in brief, in a sheet (AgentSheet.tsx): from its name, its mark in the bar, its row in the chat's sheet. */
function agentCard(app: MobileApp, here: Here, key: string) {
  const agent = here.view.agents.find((a) => a.session.key === key);
  if (!agent) return;
  openAgent(app, { station: here.station, chat: here.key, key }, agent, {
    history: () => openHistory(app, here.station, here.key, key),
    jobs: () => openJobs(app, here),
    station: () => openStationSheet(app, here.station),
  }, here.view.screens?.length ?? 0);
}

/** What matters now of the chat's services and jobs, as the desktop's title bar popover has it; the rest a tap away. */
function openJobs(app: MobileApp, here: Here) {
  app.sheet({ height: 0.62, draggable: true, content: () => <JobsNow here={here} /> });
}

function JobsNow({ here }: { here: Here }) {
  const view = useChatJobs(here.station, { session: here.key }).value ?? NO_JOBS;
  const { jobs } = view;
  const [all, setAll] = useState(false);
  const shown = all ? jobs : jobs.filter((j) => j.current);
  const clear = useClearEnded(here.station);
  // Clearing: under way while any of its sessions' is.
  const clearing = useDoingList().some((d) => !failed(d) && view.clear.some((session) => doingMatches(d, "job.clearEnded", { station: here.station, session })));
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-mobile.chat.jobs")} />
      <div className={`${sheetsCss.mSheetScroll} ${partsCss.mPad18}`}>
        {jobs.length === 0 && <div className={css.mJobsEmpty}><b>{t("web-mobile.chat.jobsNone")}</b><span>{t("web-mobile.chat.jobsNoneNote")}</span></div>}
        {jobs.length > 0 && shown.length === 0 && <p className={homeCss.mNote}>{t("web-mobile.chat.jobsIdle")}</p>}
        <JobGroups here={here} view={view} jobs={shown} notes />
        {jobs.length > view.current && (
          <button type="button" className={css.mJobsAll} onClick={() => setAll(!all)}>
            {all ? t("web-mobile.chat.jobsCurrent") : <>{view.allText}<span>{view.hiddenText}</span></>}
          </button>
        )}
        {view.ended > 0 && (
          <button type="button" className={css.mJobsAll} data-busy={clearing || undefined} disabled={clearing} onClick={() => clear(view.clear)}>
            <span className={css.mJobsAllLine}>{clearing && <Spinner inline />}{view.clearText}</span>
          </button>
        )}
      </div>
    </>
  );
}

/**
 * Services, then background jobs. A service up or restarting opens its page; one that did not start (or is over), and
 * any job, opens what it said and its output. With `notes` each group's head says how many are up or alive.
 */
function JobGroups({ here, view, jobs, notes = false }: { here: Here; view: ChatJobsView; jobs: Job[]; notes?: boolean }) {
  const app = useApp();
  const services = jobs.filter((j) => j.service);
  const plain = jobs.filter((j) => !j.service);
  const details = (j: Job) => app.sheet({ height: 0.8, draggable: true, content: () => <JobSheet station={here.station} sessionKey={here.key} jobId={j.id} /> });
  return (
    <>
      {services.length > 0 && (
        <>
          <GroupLabel>{t("web-mobile.chat.services")}{notes && view.servicesNote ? ` · ${view.servicesNote}` : ""}</GroupLabel>
          <InfoList>
            {services.map((j) => {
              const up = j.tone === "up" || j.tone === "restart";
              return <JobInfoRow key={j.id} job={j} onClick={up ? () => app.push(servicePath(here.station, here.key, j.id)) : () => details(j)} />;
            })}
          </InfoList>
        </>
      )}
      {plain.length > 0 && (
        <>
          <GroupLabel>{t("web-mobile.chat.backgroundJobs")}{notes && view.jobsNote ? ` · ${view.jobsNote}` : ""}</GroupLabel>
          <InfoList>
            {plain.map((j) => <JobInfoRow key={j.id} job={j} onClick={() => details(j)} />)}
          </InfoList>
        </>
      )}
    </>
  );
}

/** A job's row in the chat's sheets: its dot on its name's line, what it is up to under it. */
function JobInfoRow({ job, onClick }: { job: Job; onClick?: (() => void) | undefined }) {
  const body = (
    <>
      <span className={css.mJob} data-off={job.tone === "off" || undefined}>
        <JobDot tone={job.tone} />
        <span className={`${partsCss.mGrow} ${css.mJobText}`}><b>{job.name}</b><span>{metaOf(job)}</span></span>
      </span>
      {onClick && <ChevronRight size={14} className={partsCss.mSubtle} />}
    </>
  );
  return onClick ? <InfoRow onClick={onClick}>{body}</InfoRow> : <InfoRow>{body}</InfoRow>;
}

/**
 * A service or a job, from the chat's sheets: its command, then what it said or its output as it grows (a service, its
 * output); stopped from here.
 */
function JobSheet({ station, sessionKey, jobId }: { station: string; sessionKey: string; jobId: string }) {
  const jobs = useChatJobs(station, { session: sessionKey });
  const job = jobs.value?.jobs.find((j) => j.id === jobId);
  const stop = useStopJob(station);
  const [picked, setTab] = useState(0);
  const service = !!job?.service;
  const tab = service ? 1 : picked;
  const running = job?.state === "running";
  const stopping = useDoing("job.stop", { station, id: jobId });
  const stopFailed = useDoingFailed("job.stop", { station, id: jobId });
  // Its last line, as it grows.
  const last = useJobLog(station, job && tab === 0 ? job.id : null, 1);
  if (!job) return <><SheetGrab /><SheetHead title={t("web-mobile.chat.job")} />{jobs.value && <p className={homeCss.mNote}>{t("web-mobile.chat.jobGone")}</p>}</>;
  const said = last ? last.said : job.outputSaid;
  return (
    <>
      <SheetGrab />
      <div className={css.mJobHead}>
        <JobDot tone={job.tone} />
        <span className={partsCss.mGrow}><b>{job.name}</b><span>{metaOf(job)}</span></span>
      </div>
      <div className={`${partsCss.mPad18} ${css.mJobBody}`}>
        {job.command && <div className={css.mJobCommand}>{job.command}</div>}
        {!service && <Seg options={[t("web-mobile.chat.notices"), t("web-mobile.chat.output")]} selected={tab} onSelect={setTab} fill height={34} />}
        {tab === 0
          ? (
            <div className={css.mJobNotices}>
              {(job.notices ?? []).length === 0 && <p className={homeCss.mNote}>{t("web-mobile.chat.noNotices")}</p>}
              {(job.notices ?? []).map((n, i) => <p key={`${n.at}-${i}`}><time>{n.clock}</time><span>{n.text}</span></p>)}
            </div>
          )
          : <JobOutput station={station} job={job} />}
        {tab === 0 && said && <div className={css.mJobLast}><span>{said}</span>{last?.last && <code>{last.last}</code>}</div>}
        {running && <button type="button" className={css.mJobStop} disabled={stopping} onClick={() => stop(job)}>{stopping ? <Spinner className={partsCss.mSpinOnColor} /> : <Stop size={16} />}{stopping ? t("web-mobile.chat.stopping") : t("web-mobile.history.stop")}</button>}
        {running && !stopping && stopFailed !== undefined && <p className={partsCss.mError}>{t("web-mobile.chat.stopFailed", { error: stopFailed })}</p>}
      </div>
    </>
  );
}

/** A job's output, following its end while it is scrolled there (as the desktop's 任务 tab has it). */
function JobOutput({ station, job }: { station: string; job: Job }) {
  const log = useJobLog(station, job.id, 300);
  const box = useRef<HTMLPreElement>(null);
  const atEnd = useRef(true);
  useEffect(() => {
    const el = box.current;
    if (el && atEnd.current) scrollToEnd(el);
  }, [log?.text]);
  if (log === null) return <WaitLine />;
  return (
    <pre ref={box} className={css.mJobOutput} onScroll={(e) => { const el = e.currentTarget; if (outsideScroll(el)) return; atEnd.current = el.scrollHeight - el.scrollTop - el.clientHeight < 24; }}>
      {log.text ? <TermText text={log.text} runs={log.runs} /> : t("web-mobile.chat.noOutput")}
    </pre>
  );
}

// ── the chat's own sheet ───────────────────────────────────────────────

/**
 * The chat itself, from "…": its name (with a way to change it) over who started it, how many take part and when it was
 * last written in, in a line; its agents, each where it stands (a tap opens its card); then what can be done with it,
 * within reach: pin it, open it in Slack, archive it.
 */
function openChatInfo(app: MobileApp, here: Here, thread: ChatThread) {
  const publish = shownPublish(here.view);
  const rows = here.view.agents.length * 56 + ((here.view.pinned != null ? 1 : 0) + (here.view.letters ? 1 : 0) + (here.view.slackUrl ? 1 : 0) + (here.view.feishuUrl ? 1 : 0) + (here.view.xshare ? 1 : 0) + (relayable(here.view) ? 1 : 0) + 2) * 41
    + (publish ? ((publish.may ? 1 : 0) + publish.links.length) * 41 + 10 : 0);
  // As tall as what it shows: its name and line, its agents, its rows.
  app.sheet({ height: Math.min(0.9, (25 + 84 + rows + 10 + 34) / window.innerHeight), content: () => <ChatInfo here={here} thread={thread} /> });
}

function ChatInfo({ here, thread: first }: { here: Here; thread: ChatThread }) {
  const app = useApp();
  const view = useChat(here.station, { session: here.key }).value ?? here.view;
  const thread = view.thread ?? first;
  const call = useStationCall(here.station);
  const pinning = useDoing("chat.pin", { station: here.station, session: here.key });
  const pinFailed = useDoingFailed("chat.pin", { station: here.station, session: here.key });
  const open = !view.archived && !view.offline;
  const publish = shownPublish(view);
  const letters = lettersOf(app, { ...here, view });
  // What was said in it besides words: its pull requests, the latest 3 named here, the rest counted on the row to them.
  const things = useChatThings(here.station, thread.id);
  const keeper = view.agents[0]?.session.key ?? here.key;
  const pulls = things?.pulls ?? [];
  const said = things ? things.counts.media + things.counts.files + things.counts.links : 0;
  const rename = () => ask(app, {
    title: t("web-mobile.home.renameTitle"), value: view.title, placeholder: t("web-mobile.home.renamePlaceholder"), action: t("common.save"), empty: true, hint: t("web-mobile.home.renameHint"), atOnce: "web-main.rename.failed",
    run: (title) => stationApi(call).rename({ thread: thread.id, session: here.key }, title),
  });
  // Who started it and when, how many take part, when it was last written in: what there is of them, in a line.
  const creator = thread.creator?.shown?.display;
  const created = thread.time?.createdAt?.ago;
  const facts = [
    view.place ? `Slack · ${view.place}` : null,
    creator && created ? t("web-mobile.chat.startedByAt", { name: creator, ago: created }) : creator ?? created ?? null,
    view.people.length > 1 ? t("web-mobile.chat.peopleCount", { n: view.people.length }) : null,
    thread.lastMessage?.time?.createdAt?.ago ? t("web-mobile.chat.latestAt", { ago: thread.lastMessage.time.createdAt.ago }) : null,
  ].filter(Boolean).join(" · ");
  return (
    <>
      <SheetGrab />
      <div className={`${sheetsCss.mSheetScroll} ${partsCss.mPad18}`}>
        <div className={css.mInfoHead}>
          <b>{view.title}</b>
          {open && <button type="button" className={css.mInfoEdit} aria-label={t("web-mobile.home.renameTitle")} onClick={rename}><Edit size={16} /></button>}
        </div>
        <div className={css.mInfoFacts}><PeopleStack people={view.people} max={5} /><span>{facts}</span></div>
        {view.agents.length > 0 && (
          <InfoList>
            {view.agents.map((a) => {
              const s = a.session;
              // The account it runs on now, with what is left of it (so a glance here saves the trip to settings).
              const account = a.account ?? a.profile;
              return (
                <InfoRow key={s.key} onClick={() => agentCard(app, { ...here, view }, s.key)}>
                  <ModelMark maker={s.maker} runtime={s.runtime} size={36} state={stateOf(a.badge)} around="var(--m-surface2)" />
                  <span className={`${partsCss.mGrow} ${css.mInfoAgent}`}>
                    <b>{s.agentText}</b>
                    <span className={css.mInfoStatus}>{s.statusText}<AgentSince agent={a} /></span>
                  </span>
                  <QuotaRings quota={account?.quota} />
                  <ChevronRight size={14} className={partsCss.mSubtle} />
                </InfoRow>
              );
            })}
          </InfoList>
        )}
        {/* Then what is in it, one card: who works in it before what it made, what it holds apart from what is done with it. */}
        {(pulls.length > 0 || said > 0 || letters) && (
          <InfoList>
            {/* Held, 在对话中查看 and its link copied, as on the page of them. */}
            {pulls.slice(0, 3).map((p) => (
              <ThingMenu key={p.key} thing={p} onShow={(seq) => { app.sheet(null); jumpTo({ station: here.station, thread: thread.id, seq }); }}>
                <div>
                  <InfoRow onClick={() => { app.sheet(null); window.open(p.url!, "_blank", "noopener"); }}>
                    <PullMark pull={p} size={16} /><span className={partsCss.mGrow}>{pullTitle(p)}</span><span className={partsCss.mMuted}>#{p.number}</span>
                  </InfoRow>
                </div>
              </ThingMenu>
            ))}
            {pulls.length > 3 && (
              <InfoRow onClick={() => openThings(app, here.station, thread.id, keeper, "pulls")}>
                <List size={16} /><span className={partsCss.mGrow}>{t("web-main.things.pullsAll", { n: pulls.length })}</span><ChevronRight size={14} className={partsCss.mSubtle} />
              </InfoRow>
            )}
            {said > 0 && (
              <InfoRow onClick={() => openThings(app, here.station, thread.id, keeper)}>
                <Photo size={16} /><span className={partsCss.mGrow}>{t("web-main.things.title")}</span>
                <span className={partsCss.mMuted}>{said}</span><ChevronRight size={14} className={partsCss.mSubtle} />
              </InfoRow>
            )}
            {letters && (
              <InfoRow onClick={letters.open}>
                <Chats size={16} /><span className={partsCss.mGrow}>{t("web-main.letters.title")}</span>
                <span className={partsCss.mMuted}>{t("web-main.letters.count", { n: letters.n })}</span><ChevronRight size={14} className={partsCss.mSubtle} />
              </InfoRow>
            )}
          </InfoList>
        )}
        {(
          <InfoList>
            {/* A station from before pins says nothing of them: its chats are not pinned from here. */}
            {open && view.pinned != null && (
              <InfoRow busy={pinning} failed={pinFailed} onClick={() => { stationApi(call).pin({ session: here.key }, !view.pinned)
                .catch((error) => app.toast(t(view.pinned ? "web-mobile.home.unpinFailed" : "web-mobile.home.pinFailed", { error: error instanceof Error ? error.message : String(error) }))); }}>
                <Pin size={16} /><span className={partsCss.mGrow}>{view.pinned ? t("web-mobile.home.unpin") : t("web-mobile.chat.pinTop")}</span>
              </InfoRow>
            )}
            <InfoRow onClick={() => { app.sheet(null); chatPage.find(draftKeyOf(here.station, here.key)); }}>
              <Search size={16} /><span className={partsCss.mGrow}>{t("web-mobile.chat.find")}</span>
            </InfoRow>
            {/* Relayed to a channel (docs/relay.md): a chat with an agent to go on there. */}
            {relayable(view) && (
              <InfoRow onClick={() => app.sheet({ height: 0.9, content: () => <RelaySheet station={here.station} thread={thread.id} /> })}>
                <ArrowUpRight size={16} /><span className={partsCss.mGrow}>{t("web-main.relay.action")}</span><ChevronRight size={14} className={partsCss.mSubtle} />
              </InfoRow>
            )}
            {view.xshare && <ShareRow here={here} thread={thread} share={view.xshare} />}
            {view.slackUrl && <a className={listsCss.mInfoRow} href={view.slackUrl} target="_blank" rel="noopener"><SlackMark size={16} /><span className={partsCss.mGrow}>{t("web-mobile.chat.openSlack")}</span><ChevronRight size={14} className={partsCss.mSubtle} /></a>}
            {view.feishuUrl && <a className={listsCss.mInfoRow} href={view.feishuUrl} target="_blank" rel="noopener"><SlackMark kind="feishu" size={16} /><span className={partsCss.mGrow}>{t("web-mobile.chat.openFeishu")}</span><ChevronRight size={14} className={partsCss.mSubtle} /></a>}
            {open && <ArchiveRow here={here} view={view} thread={thread} />}
          </InfoList>
        )}
        {publish && <PublishList here={here} thread={thread} publish={publish} />}
      </div>
    </>
  );
}

/** Whether the chat can be relayed to a channel: open, with an agent to go on there. */
const relayable = (view: ChatView) => !view.archived && !view.offline && view.agents.length > 0 && view.thread != null;

/**
 * Relays the chat to a channel (the phone's; the wide screen's is Relay.tsx RelayDialog, picking the same way): the
 * search (or a Slack link), the places, the note, 「接力」; done, the sheet goes and a toast says where.
 */
function RelaySheet({ station, thread }: { station: string; thread: number }) {
  const app = useApp();
  const relay = useRelay(station, thread, app.toast, () => app.sheet(null), false);
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-main.relay.title")} />
      <div className={`${sheetsCss.mSheetScroll} ${css.mPublishBody}`}>
        <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>{t("web-main.relay.lead")}</p>
        {relay.body}
        <Button primary label={relay.label} busy={relay.busy} enabled={relay.ready} onClick={relay.go} />
      </div>
    </>
  );
}

/** A chat's public links as its sheet shows them: to those who may publish it, or when it has some (a read-only member sees them). */
function shownPublish(view: ChatView): ChatPublish | undefined {
  return view.publish && (view.publish.may || view.publish.links.length > 0) ? view.publish : undefined;
}

/**
 * Sharing the chat, a card of its own: 「分享图片」 opens the sheet that draws it as a picture, for those who may (not a
 * read-only member); each public link made of it before pictures under it (docs/public-share.md: they still open), when
 * and by whom, 复制, and 撤销 for who published it or an owner or admin (asked first; gone from here at once).
 */
function PublishList({ here, thread, publish }: { here: Here; thread: ChatThread; publish: ChatPublish }) {
  const app = useApp();
  return (
    <InfoList>
      {publish.may && (
        <InfoRow onClick={() => app.sheet({ height: 0.9, content: () => <PublishSheet here={here} thread={thread.id} /> })}>
          <ImageUpload size={16} /><span className={partsCss.mGrow}>{t("web-pages.chat.shareImage")}</span><ChevronRight size={14} className={partsCss.mSubtle} />
        </InfoRow>
      )}
      {publish.links.map((l) => <PublishedRow key={l.id} here={here} thread={thread.id} link={l} />)}
    </InfoList>
  );
}

function PublishedRow({ here, thread, link }: { here: Here; thread: number; link: ChatPublished }) {
  const app = useApp();
  const call = useStationCall(here.station);
  const copy = () => void navigator.clipboard.writeText(link.link).then(() => app.toast(t("common.link.copied")), (e: unknown) => app.toast(t("common.link.copyFailed", { error: e instanceof Error ? e.message : String(e) })));
  const revoke = () => confirm(app, {
    title: t("web-pages.chat.publish.revokeAsk"), text: t("web-pages.chat.publish.revokeNote"), action: t("web-pages.chat.publish.revoke"), danger: true,
    atOnce: "web-pages.chat.publish.revokeFailed", run: () => stationApi(call).unpublish(thread, link.id),
  });
  return (
    <div className={`${listsCss.mInfoRow} ${css.mPublished}`}>
      <Web size={16} className={partsCss.mSubtle} />
      <span className={`${partsCss.mGrow} ${css.mPublishedText}`}>{link.time?.createdAt?.ago} · <PersonNamed name={link.byName} picture={link.byPicture} size={16} /></span>
      <LinkButton label={t("common.copy")} onClick={copy} />
      {link.mayRevoke && <LinkButton label={t("web-pages.chat.publish.revoke")} onClick={revoke} />}
    </div>
  );
}

/**
 * Shares the chat as a picture (the phone's; the wide screen's is Publish.tsx PublishDialog), or one turn of it
 * (`turn`: a message's n, from its pick's 分享这一轮): the picture as it would be, the messages and attachments to tick
 * (all at first), how much was hidden; at its foot 「取消」 and 「保存图片」 (2026-10-26:
 * 「应该放下面，俩按钮，一个取消一个保存到相册」): the picture handed to the system's share sheet (where it is saved to the
 * photos, or sent), or saved as a file where there is none.
 */
function PublishSheet({ here, thread, turn }: { here: Here; thread: number; turn?: number }) {
  const app = useApp();
  const preview = usePublishPreview(here.station, thread, turn);
  const ticking = useTicking();
  const paper = useRef<HTMLDivElement | null>(null);
  const [taking, setTaking] = useState(false);
  const p = "ok" in preview ? preview.ok : null;
  const save = async () => {
    if (!paper.current || taking) return;
    setTaking(true);
    try {
      const png = await takePicture(paper.current);
      const file = new globalThis.File([png], "still.fail.png", { type: "image/png" });
      if (!navigator.canShare?.({ files: [file] })) savePicture(png);
      else {
        // (the press long past by the time it is made, where the browser holds a share to it: saved as a file then)
        await navigator.share({ files: [file] }).catch((e: unknown) => {
          if (e instanceof DOMException && e.name === "NotAllowedError") savePicture(png);
          else if (!(e instanceof DOMException && e.name === "AbortError")) throw e;
        });
      }
    } catch (e) {
      app.toast(t("web-pages.chat.shareImage.failed", { error: e instanceof Error ? e.message : String(e) }));
    } finally {
      setTaking(false);
    }
  };
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-pages.chat.shareImage")} />
      <div className={`${sheetsCss.mSheetScroll} ${css.mPublishBody}`}>
        {"reading" in preview ? (
          <WaitLine text={t("web-pages.chat.publish.reading")} />
        ) : "error" in preview ? (
          <p className={partsCss.mError}>{preview.error}</p>
        ) : p!.list.length === 0 ? (
          <p className={partsCss.mMuted}>{t("web-pages.chat.publish.empty")}</p>
        ) : (
          <>
            <PublishPicture preview={p!} ticking={ticking} paper={paper} inline />
            {p!.hiddenText && <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>{p!.hiddenText}</p>}
          </>
        )}
      </div>
      <div className={sheetsCss.mSheetFoot}>
        <Button label={t("common.cancel")} primary={false} onClick={() => app.sheet(null)} />
        <Button primary label={t("web-pages.chat.shareImage.save")} enabled={!!p && keptCount(p, ticking) > 0} busy={taking} onClick={() => void save()} />
      </div>
    </>
  );
}

/**
 * The chat's sharing with the viewer's other workspaces (docs/chat-share.md): where it is shared at the row's end, under
 * way a spinner there; a tap opens the sheet that changes it, for those who may (its starter, an owner or admin).
 */
function ShareRow({ here, thread, share }: { here: Here; thread: ChatThread; share: ChatShare }) {
  const app = useApp();
  const session = share.session;
  const busy = useDoing("chat.xshare", { station: here.station, session });
  const failed = useDoingFailed("chat.xshare", { station: here.station, session });
  const body = <><Users size={16} /><span className={css.mShareLabel}>{t("web-pages.chat.xshare")}</span><span className={css.mShareText}>{share.text}</span></>;
  if (!share.may) return <InfoRow>{body}</InfoRow>;
  // As tall as what it shows: its head and line, a row a workspace, the switch, the button.
  const open = () => app.sheet({ height: Math.min(0.9, (25 + 48 + 44 + share.places.length * 52 + 12 + 66 + 48) / window.innerHeight), content: () => <ShareSheet here={here} thread={thread} share={share} /> });
  return <InfoRow busy={busy} failed={failed} onClick={open}>{body}{!busy && failed === undefined && <ChevronRight size={14} className={partsCss.mSubtle} />}</InfoRow>;
}

/** Which of the viewer's other workspaces it is shared with, ticked, and whether their agents may send: done, the sheet goes at once. */
function ShareSheet({ here, thread, share }: { here: Here; thread: ChatThread; share: ChatShare }) {
  const app = useApp();
  const call = useStationCall(here.station);
  const api = useMemo(() => stationApi(call), [call]);
  const [ticked, setTicked] = useState(() => new Set(share.places.filter((p) => p.on).map((p) => p.workspace)));
  const [write, setWrite] = useState(share.write);
  const save = () => {
    app.sheet(null);
    api.xshare({ thread: thread.id, session: share.session }, share.places.filter((p) => ticked.has(p.workspace)).map((p) => p.workspace), write)
      .catch((error) => app.toast(t("web-main.act.failed", { what: t("web-pages.chat.xshare.verb"), error: error instanceof Error ? error.message : String(error) })));
  };
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-pages.chat.xshare")} />
      <div className={sheetsCss.mSheetScroll}>
        <p className={`${partsCss.mMuted} ${partsCss.mPad} ${partsCss.mSmall}`}>{t("web-pages.chat.xshare.lead")}</p>
        {share.places.map((p) => <PickRow key={p.workspace} label={p.name} leading={<WorkspaceBadge w={p} size={20} />} checked={ticked.has(p.workspace)}
          onClick={() => setTicked((was) => { const next = new Set(was); if (next.has(p.workspace)) next.delete(p.workspace); else next.add(p.workspace); return next; })} />)}
        <div className={css.mShareWrite}>
          <button type="button" className={connectsCss.mSwitchRow} disabled={ticked.size === 0} onClick={() => setWrite(!write)}>
            <span className={partsCss.mGrow}><b>{t("web-pages.chat.xshare.write")}</b><span>{t("web-pages.chat.xshare.writeNote")}</span></span>
            <span className={connectsCss.mSwitch} data-on={(write && ticked.size > 0) || undefined} />
          </button>
        </div>
        <div className={partsCss.mPad}>
          <Button primary label={t("common.done")} onClick={save} />
        </div>
      </div>
    </>
  );
}

/**
 * Sends what `text` says by `go`, written on `station`, once this workspace's agents can read what it refers to: the
 * chats of the viewer's other workspaces not shared with it yet are asked about first (../OutsideShare.tsx), as every
 * composer of the phone's does (ChatHost.tsx).
 */
export function sendSharing(app: MobileApp, station: string, text: string, go: () => void) {
  void outsideOf(station, text).catch((): Outside[] => []).then((chats) => {
    if (chats.length === 0) go();
    else openOutside(app, chats, station, text, go);
  });
}

/** Asks to share the chats of other workspaces a message refers to with this one; shared (or sent anyway), `go` sends it. */
function openOutside(app: MobileApp, chats: Outside[], station: string, text: string, go: () => void) {
  app.sheet({ height: Math.min(0.9, (25 + 48 + 44 + chats.length * 52 + 12 + 66 + 24) / window.innerHeight), content: () => <OutsideSheet chats={chats} station={station} text={text} go={go} /> });
}

function OutsideSheet({ chats, station, text, go }: { chats: Outside[]; station: string; text: string; go: () => void }) {
  const app = useApp();
  const sharable = chats.some((c) => c.may);
  const operation = useAction(() => (sharable ? shareOutside(station, text) : Promise.resolve()), () => { app.sheet(null); go(); });
  const error = operation.error ? t("web-main.outside.failed", { error: operation.error.message }) : null;
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-main.outside.title")} />
      <div className={`${sheetsCss.mSheetScroll} ${sheetsCss.mForm}`}>
        <p className={partsCss.mMuted}>{t("web-main.outside.lead")}</p>
        <OutsideList chats={chats} />
        {error && <p className={partsCss.mError}>{error}</p>}
        <div className={sheetsCss.mFormActions}>
          <Button label={t("common.cancel")} primary={false} onClick={() => app.sheet(null)} />
          <Button label={sharable ? t("web-main.outside.share") : t("web-main.outside.anyway")} primary busy={operation.busy} onClick={() => void operation.run()} />
        </div>
      </div>
    </>
  );
}

/** Puts the chat in the archive (its first agent's session with it when it is that session's own), as the wide screen's row button does; back to the list at once. */
function ArchiveRow({ here, view, thread }: { here: Here; view: ChatView; thread: ChatThread }) {
  const app = useApp();
  // A sheet lies over the page, outside its station's context: the API by the station's address.
  const call = useStationCall(here.station);
  const api = useMemo(() => stationApi(call), [call]);
  const of = { thread: thread.id, session: view.agents[0]?.session.key ?? here.key };
  // At once: said by its title (the core has it out of the list), why not if it was not.
  const archive = () => {
    app.sheet(null);
    app.pop();
    archiveSaid(api, of, view.title, app.toast).catch((error: unknown) => app.toast(t("web-mobile.home.archiveFailed", { error: error instanceof Error ? error.message : String(error) })));
  };
  // Asked first, then as at once.
  const asked = () => { app.pop(); return archiveSaid(api, of, view.title, app.toast); };
  // A chat keeping watch is archived only once asked: its watch runs on in the archive (the core's words).
  return <InfoRow onClick={() => view.watch ? confirm(app, { title: t("web-mobile.home.archiveAsk", { title: view.title }), text: view.watch.ask, action: t("web-mobile.home.archive"), atOnce: "web-mobile.home.archiveFailed", run: asked }) : archive()}><Archive size={16} /><span className={partsCss.mGrow}>{t("web-mobile.chat.archive")}</span></InfoRow>;
}

/** In the bar while nothing is left in the chat: archives it with one tap, back to the list at once (as ArchiveRow). */
function ArchiveButton({ station, session }: { station: string; session: string }) {
  const archive = useArchiveChat(station, session);
  return <NavButton icon={Archive} label={t("web-mobile.home.archive")} onClick={archive} />;
}

/** Archives the chat and leaves its page (a chat keeping watch once asked): the bar's 归档, and the one in the list. */
function useArchiveChat(station: string, session: string) {
  const app = useApp();
  const call = useStationCall(station);
  const api = useMemo(() => stationApi(call), [call]);
  // The chat as it is when tapped.
  return () => {
    const view = topicNow<ChatView>({ topic: "chat", station, session });
    if (!view) return;
    const of = { thread: view.thread?.id ?? null, session: view.agents[0]?.session.key ?? session };
    if (view.watch) {
      confirm(app, { title: t("web-mobile.home.archiveAsk", { title: view.title }), text: view.watch.ask, action: t("web-mobile.home.archive"), atOnce: "web-mobile.home.archiveFailed",
        run: () => { app.pop(); return archiveSaid(api, of, view.title, app.toast); } });
      return;
    }
    app.pop();
    archiveSaid(api, of, view.title, app.toast).catch((error: unknown) => app.toast(t("web-mobile.home.archiveFailed", { error: error instanceof Error ? error.message : String(error) })));
  };
}

