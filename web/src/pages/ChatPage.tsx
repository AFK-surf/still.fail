import { StationUpdate } from "../StationUpdate.tsx";
// A chat: a thread (a Slack thread or a chat on still.fail's page) with its people
// and agents. The messages are the page; its agents' execution histories can
// be opened beside them, one tab per agent.
import { closePreview, PreviewSlot, previewKey } from "../Previews.tsx";
import { scopeOf, useLink, useStation } from "../station.tsx";
import { CreatorText, QuotaChip, MeterChips, PeopleStack } from "../components.tsx";
import { Archive, Boxes, Close, File, Folder, Info, PanelClose, PanelOpen, Users, Web } from "@stillfail/ui/icons.tsx";
import { DriveTab } from "./DriveTab.tsx";
import { carriesDrive, draggedNow, droppedFrom, droppedFromFinder, droppedOf, endDrag, nameByType, setDropOver } from "../drive/drag.ts";
import { takeOff } from "../drive/flight.ts";
import { offerToDraft } from "../draft.ts";
import { useThisMachine } from "../thisMachine.ts";
import { JobDot, JobsPopover, JobsTab, NO_JOBS } from "../Jobs.tsx";
import { Popover, Tabs } from "radix-ui";
import { memo, useEffect, useLayoutEffect, useRef, useState, type CSSProperties, type ReactElement, type ReactNode } from "react";
import { Link, Navigate, useHref, useNavigate, useParams, useSearchParams } from "react-router";
import { PENDING } from "../lastChat.ts";
import { ownOrigin } from "../stillfailLink.ts";
import { keepTabs } from "../chatTabs.ts";
import { usePrefs } from "../prefs.ts";
import type { ChatJobsView, ChatPublish, ChatShare, Host, StationView } from "../core/shapes.ts";
import { stationApi, useAction, useApi, useChat, useChatJobs, useChats, useHistory, useHost, useStationCall, useStationLook, useAgentCard, useStations, type ChatAgent, type ChatView, type ChatThread } from "../api.ts";
import { History } from "../History.tsx";
import { StationMark } from "../StationMark.tsx";
import { StationCornerDot, StationDot, useStationLink } from "../StationLink.tsx";
import * as linkCss from "../StationLink.css.ts";
import { StationPeek } from "../cloud/StationCards.tsx";
import { Hover } from "../Peeks.tsx";
import { AgentCard, UsageTiles } from "../AgentCard.tsx";
import { ModelTriple } from "../ModelTriple.tsx";
import { usePick } from "../pick.ts";
import { ChatPanel, FileTile, goToNeighbour } from "../Chat.tsx";
import { OpenFile } from "../Viz.tsx";
import { fileService, fileSourceOf } from "../Preview.tsx";
import { useShortcut } from "../keymap.ts";
import { animate, EASE_OUT, LOCAL_MS, reducedMotion, type AnimationPlaybackControls } from "@stillfail/ui/motion.ts";
import { ComposerSlot } from "../dock.tsx";
import { chatOpening, track } from "../telemetry.ts";
import { useReady, useTopicSelect } from "../core/react.ts";
import { chatPage, useChatPageActions } from "../chatPage.ts";
import { useAct, useToast } from "@stillfail/ui/toast.tsx";
import { useDoing, useDoingFailed } from "../doing.ts";
import { DoingShown, useDoingState } from "../DoingMark.tsx";
import { AgentMark, Button, Confirm, ConnectKindIcon, Dialog, Empty, ICON, IconButton, keptWidth, Loading, MobileBack, ModelLogo, PanelRow, ResizeHandle, SlackLogo, SwitchRow, Time, Tip } from "../ui.tsx";
import { StatusLine } from "../Status.tsx";
import { useRenaming } from "../Rename.tsx";
import * as sessionCss from "../styles/session.css.ts";
import * as jobsCss from "../styles/jobs.css.ts";
import * as sidebarCss from "../styles/sidebar.css.ts";
import * as conversationCss from "../styles/conversation.css.ts";
import * as css from "./ChatPage.css.ts";
import * as pagesCss from "../styles/pages.css.ts";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import * as shellCss from "../styles/shell.css.ts";

import { NAME } from "../channel.ts";
import { t } from "../i18n.ts";
import { tx } from "../cloud/words.tsx";
import { PublishDialog, PublishedLinks, RevokeConfirm } from "../Publish.tsx";
import * as pageCss from "@stillfail/ui/styles/page.css.ts";
/**
 * An item's page, one for every item: its chat's messages (none before its agent has a chat), the composer, and its
 * agents' execution histories beside them. The address is the item's: its chat's thread, or its agent's session key
 * until the first message makes the chat, and the page moves there.
 */
/** Pressed, the panel's switch leaves the focus where it was: the composer, typed in, keeps it (and its shape; taking
 * it away folded the composer to a capsule in the same frames the panel slid in). */
const keepFocus = (e: { preventDefault(): void }) => e.preventDefault();

/**
 * The side panel's width beside a page `page` wide, as its styles lay it out (session.css.ts: the width dragged, else
 * 38% and at least 360, leaving the chat 360; ChatPage.css.ts: over the chat where the page is narrow).
 */
function panelWidth(page: number, narrow: boolean): number {
  if (narrow) return Math.min(460, window.innerWidth);
  // The width dragged, as it is kept (and on the root from here on): read off the root alone, it was not there at the
  // first opening after a load (its handle puts it there, once the panel is made), and the panel slid in at the width
  // of none dragged, then jumped to the one kept.
  const wanted = keptWidth("--panel-w", PANEL_MIN, PANEL_MAX) ?? Math.max(360, Math.floor(page * 0.38));
  return Math.max(0, Math.min(wanted, page - 360));
}
/** How narrow and how wide the side panel is dragged. */
const PANEL_MIN = 320;
const PANEL_MAX = 960;

export function ChatPage() {
  const { chat } = useParams();
  const station = useStation();
  // There is always a chat in view: the one last open, or a new one; the workspace's page decides which.
  if (!chat) return <Navigate to={station.base.replace(/\/s\/[^/]+$/, "")} replace />;
  // An item is its agent's: the address is the session, whether or not it has a chat yet (the core shows the chat
  // once there is one, at the same address). A chat made here keeps the page it opened with under the core's key
  // when its address becomes its station's.
  const opened = renamed.get(chat) ?? chat;
  return <ChatScreen key={opened} session={opened} />;
}

/** Chats made here, by the key their station gave them: the core's key their page was opened with. */
const renamed = new Map<string, string>();

/** Reports how long the chat took to show its messages, once, when they first do. */
function useChatOpened(chat: ChatView | undefined): void {
  const [opening] = useState(chatOpening);
  const reported = useRef(false);
  useEffect(() => {
    if (!chat || reported.current) return;
    reported.current = true;
    const surface = !chat.thread || (chat.thread.surface === "ember" || chat.thread.surface === "stillfail") ? "ember" : "slack";
    // The frame after the commit: when the messages are on screen.
    requestAnimationFrame(() => track("chat_opened", { surface, open: opening.cold ? "cold" : "warm", ms: Math.round(performance.now() - opening.at) }));
  }, [chat, opening]);
}

function ChatScreen({ session: chatSession }: { session: string }) {
  const of: { thread: number } | { session: string } = { session: chatSession };
  const station = useStation();
  const link = useLink();
  const navigate = useNavigate();
  const call = useStationCall(station.address);
  // Coming from another page, that page stays until this chat is read from the device, rather than an empty one
  // showing between; not for one that has to come from its station: past LOCAL_MS this one shows, waiting.
  useReady({ topic: "chat", station: station.address, ...of }, LOCAL_MS);
  const chatView = useChat(station.address, of);
  useChatOpened(chatView.value);
  // A chat made here (`chat.create`) goes by the core's key until its station has made it: sent to by it meanwhile, and
  // then at the station's key, the address changed in place (the page stays as it is).
  const made = "session" in of && of.session.startsWith(PENDING) ? of.session : undefined;
  const stationKey = chatView.value?.key;
  useEffect(() => {
    if (!made || !stationKey) return;
    renamed.set(stationKey, made);
    navigate(`${link(`/chats/${encodeURIComponent(stationKey)}`)}${location.search}`, { replace: true });
  }, [made, stationKey]);
  const agents = chatView.value?.agents ?? [];
  // One history tab per agent, by its session's key (a chat may have several agents, each with its own): opened from
  // the agent (its avatar, its name, a row of what it does), closed alone, and with no tab open the panel goes away.
  // Each chat keeps its own tabs. One not opened before opens none (its agents' histories open from them when wanted),
  // except an agent with no chat yet, here or in Slack (the core's `noChat`): its page shows its history. Where the
  // panel would lie over the chat (the styles' `max-width: 1100px`), none opens by itself: the chat comes first.
  const chatKey = `${station.address}:${"thread" in of ? of.thread : of.session}`;
  // Kept by the core for each chat (its prefs' `chatTabs`): read from there, written there (keepTabs).
  const kept = usePrefs((p) => p.chatTabs[chatKey]);
  const chosen = kept?.tabs ?? null;
  const [folded] = useState(() => window.matchMedia("(max-width: 1100px)").matches);
  const view = chatView.value;
  const tabs = chosen ?? (view?.noChat && !folded && "session" in of ? [of.session] : []);
  const active = kept?.active ?? null;
  // The tabs as last left while the agents are not known yet: the panel holds its place instead of coming in later.
  // Its agents' background jobs; a service's tab (`service:<job>`) is the chat's own while one of them has it.
  const jobs = agents.flatMap((a) => a.jobs ?? []);
  // As its pages show them (the core's `chatJobs`).
  const jobsView = useChatJobs(station.address, of).value ?? NO_JOBS;
  // A kept web service that stopped is not kept any longer.
  useEffect(() => {
    for (const job of jobs) if (job.open === false) closePreview(previewKey(station.address, job.id));
  }, [jobs, station.address]);
  const known = agents.length ? tabs.filter((key) => key === JOBS || key === FILES || fileOf(key) !== null || (serviceOf(key) !== null && jobs.some((j) => j.id === serviceOf(key))) || agents.some((a) => a.session.key === key)) : tabs;
  const isAgent = (key: string) => agents.some((a) => a.session.key === key);
  const open = known;
  // The job picked in the 任务 tab.
  const [jobPicked, pickJob] = useState<string | null>(null);
  const shown = active && open.includes(active) ? active : open[0] ?? null;
  // The panel as it was when its last tab closed, kept while it slides out over the chat (which takes the room at once).
  const panelRef = useRef<HTMLDivElement>(null);
  const [leaving, setLeaving] = useState<{ tabs: string[]; shown: string; width: number } | null>(null);
  // Tabs and the one in front change together, and are kept for this chat in one write.
  const commit = (next: string[], front: string | null) => {
    if (next.length) setLeaving(null);
    else {
      setOpening(false);
      if (open.length && shown && panelRef.current && !reducedMotion()) setLeaving({ tabs: open, shown, width: panelRef.current.getBoundingClientRect().width });
    }
    keepTabs(chatKey, { tabs: next, active: front });
  };
  const saveTabs = (next: string[]) => commit(next, active);
  const setActive = (key: string | null) => commit(open, key);
  // Whether the panel is being opened here (it slides in then), not shown with the chat as it was left.
  const [opening, setOpening] = useState(false);
  // Opened, the panel's column widens from nothing and the chat narrows with it, frame by frame; closed, the other way.
  // The panel keeps its whole width all along and shows through its column as it grows, so it comes in from the right
  // edge without its content re-laying out. Turned back on its way, it goes on from the width it has. Where the panel
  // lies over the chat (`max-width: 1100px`) it slides instead.
  const sliding = leaving && !(open.length && shown) ? "out" : opening ? "in" : null;
  const pageRef = useRef<HTMLDivElement>(null);
  const slide = useRef<{ run: AnimationPlaybackControls; value: number } | null>(null);
  // The page's width as last laid out, told by an observer: the panel's width is worked out from it (as its styles
  // have it) rather than read off the panel just made, which laid the whole page out in the middle of the commit and
  // again for the frame.
  const pageWidth = useRef(0);
  useLayoutEffect(() => {
    // The width dragged for the panel is on the root from the page's first frame, not from the panel's first opening:
    // put there then, the whole page was styled anew in the frame of the click.
    keptWidth("--panel-w", PANEL_MIN, PANEL_MAX);
    const page = pageRef.current;
    if (!page) return;
    const seen = new ResizeObserver(([entry]) => { if (entry) pageWidth.current = entry.borderBoxSize[0]?.inlineSize ?? entry.contentRect.width; });
    seen.observe(page);
    return () => seen.disconnect();
  }, []);
  useLayoutEffect(() => {
    const page = pageRef.current;
    const el = panelRef.current;
    // Slid out: the page has laid itself out without the panel now, so the column it held is let go of in the same frame.
    if (!sliding) {
      page?.style.removeProperty("grid-template-columns");
      page?.style.removeProperty("--panel-visible-width");
      return;
    }
    if (!page || !el) return;
    const was = slide.current;
    was?.run.stop();
    const narrow = matchMedia("(max-width: 1100px)").matches;
    // Its width at rest, without what the motion holds.
    page.style.removeProperty("grid-template-columns");
    el.style.removeProperty("width");
    el.style.removeProperty("transform");
    const whole = sliding === "out" && leaving ? leaving.width : panelWidth(pageWidth.current || page.getBoundingClientRect().width, narrow);
    const start = was ? was.value : sliding === "in" ? 0 : whole;
    const goal = sliding === "in" ? whole : 0;
    const draw = (v: number) => {
      page.style.setProperty("--panel-visible-width", `${v}px`);
      el.style.width = `${whole}px`;
      if (narrow) el.style.transform = `translateX(${whole - v}px)`;
      else page.style.gridTemplateColumns = `minmax(0, 1fr) ${v}px`;
    };
    draw(start);
    const now = { value: start, run: animate(start, goal, {
      duration: sliding === "in" ? 0.28 : 0.24, ease: EASE_OUT,
      onUpdate: (v) => { now.value = v; draw(v); },
      onComplete: () => {
        if (slide.current !== now) return;
        slide.current = null;
        if (sliding === "out") return setLeaving(null);
        page.style.removeProperty("grid-template-columns");
        el.style.removeProperty("width");
        el.style.removeProperty("transform");
        setOpening(false);
      },
    }) };
    slide.current = now;
  }, [sliding]);
  const openTab = (key: string) => {
    if (open.length === 0 && !reducedMotion()) setOpening(true);
    // An agent's history goes after the histories already open, before the other tabs.
    if (isAgent(key) && !open.includes(key)) {
      const at = open.findLastIndex(isAgent) + 1;
      return commit([...open.slice(0, at), key, ...open.slice(at)], key);
    }
    commit(open.includes(key) ? open : [...open, key], key);
  };
  const closeTab = (key: string) => {
    const file = fileOf(key);
    const service = file ? fileService(file) : serviceOf(key);
    if (service) closePreview(previewKey(station.address, service));
    const next = open.filter((tab) => tab !== key);
    commit(next, shown === key ? next.at(-1) ?? null : active);
  };
  const openJobs = (job?: string) => {
    if (job) pickJob(job);
    openTab(JOBS);
  };
  const toggleHistory = (key: string) => (open.includes(key) && shown === key ? closeTab(key) : openTab(key));
  // An activity row: its agent's history, open at that entry.
  const [focus, setFocus] = useState<{ key: string; entry: number; n: number } | null>(null);
  // A link that names a web service of the chat's (`?service=<job>`, a service's link in Slack): its tab, open.
  const [search, setSearch] = useSearchParams();
  const asked = search.get("service");
  useEffect(() => {
    if (!asked) return;
    openTab(`service:${asked}`);
    setSearch((now) => { now.delete("service"); return now; }, { replace: true });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [asked]);
  // A link to one of its agents' execution history (`?history=<session>&entry=<n>`, copied from it): opened there.
  const askedHistory = search.get("history");
  useEffect(() => {
    if (!askedHistory) return;
    const entry = Number(search.get("entry"));
    openHistory(askedHistory, Number.isSafeInteger(entry) && entry >= 0 ? entry : 0);
    setSearch((now) => { now.delete("history"); now.delete("entry"); return now; }, { replace: true });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [askedHistory]);
  // still.fail's own links (/o/<workspace>/<station>/<session>, as agents post them): one of this chat's agents' web services
  // opens beside the chat; another session of the workspace opens here, in the page, not through the desktop app. In
  // the desktop app (at app://ember) still.fail cloud's links are its own too.
  const root = useHref("/").replace(/\/$/, "");
  const opens = useRef({ agents, openTab, root });
  opens.current = { agents, openTab, root };
  useEffect(() => {
    const onClick = (event: MouseEvent) => {
      if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      const anchor = (event.target as Element | null)?.closest?.("a[href]") as HTMLAnchorElement | null;
      if (!anchor) return;
      const url = new URL(anchor.href, location.href);
      // Another chat's page (as a reference to it is written, ChatRef.tsx): opened here, from this origin or from any of
      // still.fail cloud's (one written on app.still.fail, read on app.youdid.wtf or in the desktop app).
      const page = url.origin === location.origin && url.pathname.startsWith(`${opens.current.root}/`) ? url.pathname.slice(opens.current.root.length)
        : url.origin !== location.origin && ownOrigin(url) ? url.pathname : null;
      if (page && /^(\/w\/[^/]+\/s\/[^/]+)?\/chats\/[^/]+\/?$/.test(page)) {
        event.preventDefault();
        navigate(`${page}${url.search}`);
        return;
      }
      const item = /^\/o\/([^/]+)\/([^/]+)\/([^/]+)\/?$/.exec(url.pathname);
      if (!item) return;
      const session = decodeURIComponent(item[3]!);
      const service = url.searchParams.get("service");
      if (service && opens.current.agents.some((a) => a.session.key === session)) {
        event.preventDefault();
        opens.current.openTab(`service:${service}`);
      } else if (ownOrigin(url)) {
        event.preventDefault();
        navigate(`/w/${item[1]}/s/${item[2]}/chats/${encodeURIComponent(session)}${url.search}`);
      }
    };
    document.addEventListener("click", onClick, true);
    return () => document.removeEventListener("click", onClick, true);
  }, [navigate]);
  const openHistory = (key: string, entry?: number) => {
    if (entry === undefined) return toggleHistory(key);
    openTab(key);
    setFocus({ key, entry, n: Date.now() });
  };
  // A chat keeping watch is archived only once asked.
  const archiveAsked = () => { if (chatView.value?.watch) setAskArchive(true); else void archive(); };
  // What is in the page (its messages, its bar, its tabs) does these by the chat's key: it is handed none of them.
  useChatPageActions(chatKey, { history: openHistory, tab: openTab, jobs: openJobs, archive: archiveAsked });
  // A visualization in a message opens in a tab of the side panel: the same function while the page is this chat's.
  const [openFile] = useState(() => (session: string, file: { path: string; name: string }) => chatPage.tab(chatKey, fileTab(session, file.path, file.name)));
  const api = stationApi(call);
  const toast = useToast();
  const running = agents.filter((a) => a.status === "running" || a.status === "queued");
  const act = useAct();
  useShortcut("chat.stop", running.length ? () => {
    act(Promise.all(running.map((a) => api.stop(a.session.key))), t("web-pages.chat.stop"), t("web-pages.chat.stopAsked"));
  } : null);
  // A history tab in front closes the panel; else the first one open comes to the front, the chat's own agent's if none is.
  useShortcut("chat.history", agents[0] ? () => {
    if (shown && isAgent(shown)) saveTabs([]); else openTab(open.find(isAgent) ?? agents[0]!.session.key);
  } : null);
  useShortcut("chat.jobs", () => (shown === JOBS ? closeTab(JOBS) : openJobs()));
  // The stations' files beside the chat (DriveTab.tsx), where they have them: pressed again while in front, closed.
  const drive = useStationDrive(station.address);
  // Files dragged anywhere over the chat go into its message (useChatDrop).
  const drop = useChatDrop(chatKey, station.address);
  const toggleFiles = () => (open.includes(FILES) && shown === FILES ? closeTab(FILES) : openTab(FILES));
  useShortcut("panel.close", open.length ? () => saveTabs([]) : null);
  const thread = chatView.value?.thread?.id ?? null;
  const keeper = agents[0]?.session.key ?? ("session" in of ? of.session : null);
  const archive = async () => {
    if (!keeper) return;
    // On to the chat below it in the list (or above, at the end), so the keys go on working; the list page if none.
    if (!goToNeighbour(1) && !goToNeighbour(-1)) navigate(link("/chats"));
    try {
      await api.archive({ thread, session: keeper }, true);
      toast(t("web-pages.chat.archived"));
    } catch (error) {
      toast(t("web-pages.chat.archiveFailed", { error: error instanceof Error ? error.message : String(error) }));
    }
  };
  // A chat keeping watch is archived only once asked: its watch runs on in the archive (the core's words).
  const [askArchive, setAskArchive] = useState(false);
  useShortcut("chat.archive", chatView.value && !chatView.value.archived && !chatView.value.offline && keeper
    ? () => { if (chatView.value?.watch) setAskArchive(true); else void archive(); } : null);
  if (!chatView.value) {
    if (chatView.error) return <Empty><p>{t("web-pages.chat.loadFailed", { error: chatView.error.message })}</p></Empty>;
    // Laid out as the chat will be, its composer already in its place: coming from another chat page, the composer
    // moves there at once rather than going away until the chat is read (it cannot send until then).
    return (
      <div className={sessionCss.sessionPage} data-panel={open.length > 0}>
        <div className={jobsCss.sessionMain}>
          <section className={sessionCss.chat} aria-label={t("web-pages.decisions.back")} data-under-composer="" data-avoid-previews="">
            <Loading label={station.name ? t("web-pages.chat.loadingFrom", { name: station.name }) : t("web-pages.chat.loading")} detail={<StatusLine workspace={scopeOf(station.address)} />} />
            <ComposerSlot variant="chat" station={station} draftKey={chatKey} thread={null} sessionKey={null} locked />
          </section>
        </div>
      </div>
    );
  }
  const chat = chatView.value;
  const panel = open.length > 0;
  // What the panel shows: its tabs, or while it slides out, what it showed.
  const side = panel && shown ? { tabs: open, shown } : leaving;
  const slackUrl = chat.slackUrl;
  // Before its agent has a chat, what is sent goes to the agent: it waits in the outbox at once while the core has the
  // station make the chat behind it; the page stays (the core shows the chat at the same address once it is there).
  const sendTo = made ?? ("session" in of && !chat.thread ? of.session : undefined);
  return (
    <div ref={pageRef} className={sessionCss.sessionPage} data-panel={panel || leaving !== null}>
      {chat.watch && <Confirm open={askArchive} title={t("web-pages.chat.archiveConfirm", { title: chat.title })} description={chat.watch.ask} action={t("web-pages.chat.archive")}
        onConfirm={() => { setAskArchive(false); void archive(); }} onClose={() => setAskArchive(false)} />}
      <div className={`${jobsCss.sessionMain} ${css.dropZone}`} {...drop.handlers}>
      {/* Files over the chat: it frosts over, and says where they go. */}
      {drop.leaving && !drop.over && <div className={css.dropHint} data-leaving="" aria-hidden="true" onAnimationEnd={drop.gone}><div className={css.dropMarks} /><span>{drop.leaving}</span></div>}
      {drop.over && (
        <div className={css.dropHint} aria-hidden="true">
          {/* What is dragged, each by its mark, a few fanned out as a stack. */}
          <div ref={drop.shown} className={css.dropMarks} style={{ "--n": Math.min(3, Math.max(1, drop.over.marks.length)) } as CSSProperties}>
            {(drop.over.marks.length ? drop.over.marks : [{ name: "file", dir: false }]).slice(0, 3).map((m, i) => (
              <FileTile key={i} name={m.name} dir={m.dir} style={{ "--i": i } as CSSProperties} />
            ))}
          </div>
          <span>{drop.label(drop.over)}</span>
        </div>
      )}
      <header className={sidebarCss.pageBar}>
        <MobileBack to={link("/chats")} label={t("web-pages.decisions.back")} />
        {/* The chat's title, then who is in it: its people, then its agents (each opens its history). */}
        <div className={conversationCss.pageBarTitle}>
          {/* Text only, under the bar's drag in the desktop app: a chat is renamed in the sidebar. */}
          <ChatTitle station={station.address} session={keeper} title={chat.title} />
          <StationUpdate station={station.address} notice={chat.stationUpdate} />
          {agents.length === 0 && <ChatStation />}
          {chat.people.length > 0 && <PeopleStack people={chat.people} max={5} />}
          {agents.map((a, i) => (
            <AgentButton key={a.session.key} station={station.address} chat={chatKey} session={chatSession} agent={a.session.key} marked={agents.length > 1 && shown === a.session.key} first={i === 0} />
          ))}
        </div>
        {/* The chat's find bar takes this place while it is open (ChatFind.tsx): it covers none of the chat. */}
        <div className={css.pageBarActions} data-find-slot="">
          {/* Nothing left in it (the core's `archivable`): archived with one press. */}
          {chat.archivable && keeper && <IconButton label={t("web-pages.chat.archive")} icon={Archive} shortcut="chat.archive" onClick={archiveAsked} />}
          <JobsPanel station={station.address} session={chatSession} chat={chatKey} />
          {drive && <IconButton label={t("web-pages.chat.files")} icon={Folder} onMouseDown={keepFocus} onClick={toggleFiles} />}
          {chat.thread && <ChatInfo station={station.address} session={chatSession} />}
          {slackUrl && (
            <Tip label={t("web-pages.chat.openInSlack")}>
              <a className={pageCss.iconBtn} href={slackUrl} target="_blank" rel="noopener" aria-label={t("web-pages.chat.openInSlack")}><SlackLogo /></a>
            </Tip>
          )}
          {!panel && agents[0] && <IconButton label={t("web-pages.chat.openPanel")} icon={PanelOpen} shortcut="chat.history" onMouseDown={keepFocus} onClick={() => openTab(agents[0]!.session.key)} />}
        </div>
      </header>
      {/* The chat is the page; its agents' histories sit in a tab set that takes the whole right side. */}
      {/* A visualization in a message opens on its own in a tab of the side panel, beside the chat. */}
      <OpenFile.Provider value={openFile}>
        <ChatPanel session={chatSession} draftKey={chatKey} made={sendTo} />
      </OpenFile.Provider>
      </div>
        {side && (
          <Tabs.Root ref={panelRef} className={css.sidePanel} data-over-composer value={side.shown} onValueChange={setActive} inert={side === leaving}>
            <ResizeHandle variable="--panel-w" edge="left" min={PANEL_MIN} max={PANEL_MAX} label={t("web-pages.chat.resizePanel")}
              press={{ label: t("web-pages.chat.closePanel"), run: () => saveTabs([]) }} />
            <div className={css.sideBar}>
              <Tabs.List className={css.sideTabList} aria-label={t("web-pages.chat.history")}>
                {side.tabs.map((key) => {
                  if (key === JOBS) {
                    return (
                      <span key={key} className={css.sideTabWrap}>
                        <Tabs.Trigger className={css.sideTab} value={key} id={tabId(key)} aria-controls={paneId(key)}>
                          <span className={css.sideTabAgent}><Boxes size={14} strokeWidth={1.75} /><span className={css.sideTabText} data-text={t("web-pages.chat.jobs")}>{t("web-pages.chat.jobs")}</span></span>
                        </Tabs.Trigger>
                        <button type="button" className={css.sideTabClose} aria-label={t("web-pages.chat.closeJobs")} onClick={() => closeTab(key)}><Close size={12} strokeWidth={2} /></button>
                      </span>
                    );
                  }
                  if (key === FILES) {
                    return (
                      <span key={key} className={css.sideTabWrap}>
                        <Tabs.Trigger className={css.sideTab} value={key} id={tabId(key)} aria-controls={paneId(key)}>
                          <span className={css.sideTabAgent}><Folder size={14} strokeWidth={1.75} /><span className={css.sideTabText} data-text={t("web-pages.chat.files")}>{t("web-pages.chat.files")}</span></span>
                        </Tabs.Trigger>
                        <button type="button" className={css.sideTabClose} aria-label={t("web-pages.chat.closeFiles")} onClick={() => closeTab(key)}><Close size={12} strokeWidth={2} /></button>
                      </span>
                    );
                  }
                  const file = fileOf(key);
                  if (file) {
                    return (
                      <span key={key} className={css.sideTabWrap}>
                        <Tip label={file.name} cut><Tabs.Trigger className={css.sideTab} value={key} id={tabId(key)} aria-controls={paneId(key)}>
                          <span className={css.sideTabAgent}><File size={14} strokeWidth={1.75} /><span className={css.sideTabText} data-text={file.name}>{file.name}</span></span>
                        </Tabs.Trigger></Tip>
                        <button type="button" className={css.sideTabClose} aria-label={t("web-pages.chat.close", { name: file.name })} onClick={() => closeTab(key)}><Close size={12} strokeWidth={2} /></button>
                      </span>
                    );
                  }
                  const service = jobs.find((j) => j.id === serviceOf(key));
                  if (service) {
                    return (
                      <span key={key} className={css.sideTabWrap}>
                        <Tip label={service.name} cut><Tabs.Trigger className={css.sideTab} value={key} id={tabId(key)} aria-controls={paneId(key)}>
                          <span className={css.sideTabAgent}><JobDot tone={service.tone} /><span className={css.sideTabText} data-text={service.name}>{service.name}</span></span>
                        </Tabs.Trigger></Tip>
                        <button type="button" className={css.sideTabClose} aria-label={t("web-pages.chat.close", { name: service.name })} onClick={() => closeTab(key)}><Close size={12} strokeWidth={2} /></button>
                      </span>
                    );
                  }
                  const a = agents.find((x) => x.session.key === key);
                  // Not known yet: its place, empty, until it is.
                  if (!a) return <span key={key} className={css.sideTabWrap} />;
                  const label = a.session.agentText;
                  return (
                    <span key={key} className={css.sideTabWrap}>
                      <Tip label={label} cut><Tabs.Trigger className={css.sideTab} value={key} id={tabId(key)} aria-controls={paneId(key)}>
                        <span className={css.sideTabAgent}><ModelLogo maker={a.session.maker} runtime={a.session.runtime} size={14} /><span className={css.sideTabText} data-text={label}>{label}</span></span>
                      </Tabs.Trigger></Tip>
                      <button type="button" className={css.sideTabClose} aria-label={t("web-pages.chat.close", { name: label })} onClick={() => closeTab(key)}><Close size={12} strokeWidth={2} /></button>
                    </span>
                  );
                })}
              </Tabs.List>
              {/* The panel's switch stays in the top-right corner, open or closed. */}
              <IconButton label={t("web-pages.chat.closePanel")} icon={PanelClose} shortcut="panel.close" onMouseDown={keepFocus} onClick={() => saveTabs([])} />
            </div>
            {side.tabs.map((key) => {
              if (key === JOBS) {
                return (
                  <SidePane key={key} of={key} shown={side.shown}>
                    <JobsTab station={station.address} view={jobsView} picked={jobPicked} onPick={pickJob} chat={chatKey} />
                  </SidePane>
                );
              }
              if (key === FILES) {
                // Kept while another tab shows: the folder it is in stays.
                return (
                  <SidePane key={key} of={key} shown={side.shown} kept>
                    <DriveTab chat={chatKey} />
                  </SidePane>
                );
              }
              const file = fileOf(key);
              if (file) {
                // Kept as a web service is (Previews.tsx): small in the corner while another chat or page shows.
                return (
                  <SidePane key={key} of={key} shown={side.shown} kept>
                    <PreviewSlot station={station.address} file={file} name={file.name} restarting={null} draftKey={chatKey} />
                  </SidePane>
                );
              }
              const service = jobs.find((j) => j.id === serviceOf(key));
              // Kept loaded while another tab, chat or page shows (Previews.tsx): only closing its tab ends it.
              if (service) {
                return (
                  <SidePane key={key} of={key} shown={side.shown} kept>
                    {service.port != null && (service.state === "running" || service.state === "exited")
                      ? <PreviewSlot station={station.address} port={service.port} name={service.name} service={service.id} restarting={service.state === "exited" ? { restarts: service.restarts ?? 0 } : null} draftKey={chatKey} />
                      : <Empty><p>{service.state === "failed" ? t("web-pages.chat.serviceFailed", { name: service.name }) : t("web-pages.chat.serviceStopped", { name: service.name })}</p></Empty>}
                  </SidePane>
                );
              }
              const a = agents.find((x) => x.session.key === key);
              if (!a) return <SidePane key={key} of={key} shown={side.shown} />;
              return (
                <SidePane key={key} of={key} shown={side.shown}>
                  <AgentHistory station={station.address} session={chatSession} agent={key} focusEntry={focus?.key === key ? focus.entry : null} focusN={focus?.key === key ? focus.n : 0} />
                </SidePane>
              );
            })}
          </Tabs.Root>
        )}
    </div>
  );
}

/**
 * One of the chat's agents, as its avatar in the bar: pressed, its history's tab opens (or, in front, closes); on
 * hover, its card (AgentCard.tsx), the one its avatar beside its messages has. Those whose history shows are marked,
 * among several.
 */
const AgentButton = memo(function AgentButton({ station: address, chat, session: of, agent: key, marked, first }: {
  station: string; chat: string; session: string; agent: string; marked: boolean;
  /** The chat's first agent: one tile with the station it runs on. */
  first: boolean;
}) {
  const agent = useChatAgent(address, of, key);
  if (!agent) return null;
  return <AgentTile agent={agent} chat={chat} marked={marked} station={first} />;
});

function AgentTile({ agent, chat, marked, station }: { agent: ChatAgent; chat: string; marked: boolean; station: boolean }) {
  const { session } = agent;
  const onHistory = () => chatPage.history(chat, session.key);
  const where = useChatStation();
  const link = useStationLink(useStation().address);
  const label = t("web-pages.chat.historyOf", { agent: session.agentText });
  // With the station it runs on, one tile: the maker opens the history and has
  // the agent's card, the station's part its own; the agent's badge on the maker's corner, how the station is reached on the tile's.
  if (station && where) {
    return (
      <span className={`${css.agentStation} ${linkCss.corner}`} data-on={marked || undefined}>
        <AgentMark maker={session.maker} runtime={session.runtime} badge={agent.badge} badgeText={session.badgeText} size={20}
          wrap={(logo) => <Hover tile content={<AgentCard agent={agent} />}><button type="button" className={css.agentStationAgent} onClick={onHistory} aria-label={label}>{logo}</button></Hover>}>
          <StationPart where={where} />
        </AgentMark>
        <StationCornerDot link={link} />
      </span>
    );
  }
  return (
    <Hover tile content={<AgentCard agent={agent} />}>
      <button type="button" className={css.agentMarkBtn} data-on={marked || undefined} onClick={onHistory} aria-label={label}>
        <AgentMark maker={session.maker} runtime={session.runtime} badge={agent.badge} badgeText={session.badgeText} size={20} />
      </button>
    </Hover>
  );
}

/**
 * An agent's execution history in its tab, with its head (how it runs), what needs seeing to and its details: drawn
 * again only when the agent, the chat's title or the entry asked for changes, not with the rest of the chat's page.
 */
const AgentHistory = memo(function AgentHistory({ station, session, agent: key, focusEntry, focusN }: {
  station: string; session: string; agent: string;
  /** An entry to bring into view (`focusN` changes each time it is asked for); null: none. */
  focusEntry: number | null; focusN: number;
}) {
  const agent = useChatAgent(station, session, key);
  const title = useTopicSelect<ChatView, string | undefined>({ topic: "chat", station, session }, (s) => s.value?.title);
  if (!agent) return null;
  return (
    <History station={station} sessionKey={key} title={title} focusEntry={focusEntry} focusN={focusN}
      head={<SessionHead agent={agent} />}
      summary={agent.attention.length > 0 ? <HistorySummary agent={agent} /> : null}
      details={<SessionDetails agent={agent} />} />
  );
});

/** One of a chat's agents, by its key: the same object while it is. */
function useChatAgent(station: string, session: string, key: string): ChatAgent | undefined {
  return useTopicSelect<ChatView, ChatAgent | undefined>({ topic: "chat", station, session }, (s) => s.value?.agents.find((a) => a.session.key === key));
}

/** What is dragged over the chat, each shown by its mark (Chat.tsx FileTile): its name (or one its type gives), whether
 * it is a folder. */
type Over = { kind: "path" | "file"; marks: { name: string; dir: boolean }[] };

/**
 * The chat as a place to drop files on, all of it: while they are over it, it frosts over and shows them, each by its
 * mark (as its card will have it), with what letting go does; let go, they go into its message, and their marks fly
 * there, each onto its card (drive/flight.ts). The composer leaves a drop on it to this.
 */
function useChatDrop(chat: string, station: string) {
  const here = useThisMachine(station);
  const [over, setOver] = useState<Over | null>(null);
  // Let go: the frost going while the marks fly off it.
  const [leaving, setLeaving] = useState<string | null>(null);
  const depth = useRef(0);
  const shown = useRef<HTMLDivElement>(null);
  // The composer knows files are over its chat, and leaves them to it (Chat.tsx).
  useEffect(() => {
    setDropOver(over?.kind ?? null);
    return () => setDropOver(null);
  }, [over?.kind]);
  const kind = (dt: DataTransfer): "path" | "file" | null =>
    carriesDrive(dt) ? "path" : dt.types.includes("Files") ? (here && window.stillfailDesktop?.pathOf ? "path" : "file") : null;
  // A station's files dragged from this page are known by name; Finder's only by type, until they are dropped.
  const marks = (dt: DataTransfer) => carriesDrive(dt)
    ? (draggedNow() ?? []).map((d) => ({ name: d.name, dir: d.dir }))
    : [...dt.items].filter((i) => i.kind === "file").map((i) => ({ name: nameByType(i.type), dir: false }));
  const label = (o: Over) => (o.marks.length > 1 ? t("web-main.composer.dropMany", { n: o.marks.length }) : t("web-main.composer.dropHere"));
  const handlers = {
    onDragEnter: (e: React.DragEvent) => {
      const k = kind(e.dataTransfer);
      if (!k) return;
      depth.current++;
      if (depth.current === 1) setOver({ kind: k, marks: marks(e.dataTransfer) });
    },
    onDragOver: (e: React.DragEvent) => { if (!kind(e.dataTransfer)) return; e.preventDefault(); e.dataTransfer.dropEffect = "copy"; },
    onDragLeave: (e: React.DragEvent) => { if (!kind(e.dataTransfer)) return; depth.current = Math.max(0, depth.current - 1); if (depth.current === 0) setOver(null); },
    onDrop: (e: React.DragEvent) => {
      depth.current = 0;
      if (e.defaultPrevented || !kind(e.dataTransfer)) { setOver(null); return; }
      e.preventDefault();
      // Their marks take off from where they are shown; the frost fades as they fly.
      takeOff([...(shown.current?.querySelectorAll("svg") ?? [])]);
      setLeaving(over ? label(over) : null);
      setOver(null);
      endDrag();
      if (carriesDrive(e.dataTransfer)) { offerToDraft(chat, { files: [], quotes: [], dropped: droppedOf(e.dataTransfer).map(droppedFrom) }); return; }
      const named = droppedFromFinder(e.dataTransfer, here);
      offerToDraft(chat, named ? { files: [], quotes: [], dropped: named } : { files: [...e.dataTransfer.files], quotes: [] });
    },
  };
  return { over, leaving, gone: () => setLeaving(null), handlers, shown, label };
}

/** The 任务 tab's key: every service and job of the chat's agents. */
const JOBS = "jobs";
/** The 文件 tab's key: the files of the chat's station (DriveTab.tsx). */
const FILES = "files";

/** Whether any station of the chat's workspace has files to show (one from before the drive has none): only that, so
 * the page is not drawn again for the rest of their overviews. */
function useStationDrive(station: string): boolean {
  return useTopicSelect<StationView[], boolean>({ topic: "stations", scope: scopeOf(station) }, (s) => !!s.value?.some((x) => x.overview?.drive));
}
/** A side tab's and its pane's ids, each naming the other (a tab's key can hold a space; an id cannot). */
function tabId(key: string): string { return `side-tab-${encodeURIComponent(key)}`; }
function paneId(key: string): string { return `side-pane-${encodeURIComponent(key)}`; }
/** A side tab's pane: there while its tab is the one shown, `kept` there (not shown) under another too. Not Radix's
 * Tabs.Content, which reads its animation's name as it comes in: the style of the page worked out in the middle of
 * the panel opening. */
function SidePane({ of, shown, kept = false, children }: { of: string; shown: string; kept?: boolean; children?: ReactNode }) {
  const active = of === shown;
  if (!active && !kept) return null;
  return <div className={css.sideContent} role="tabpanel" id={paneId(of)} aria-labelledby={tabId(of)} data-state={active ? "active" : "inactive"} tabIndex={0}>{children}</div>;
}

/** A visualization's tab: its place among the previews (Preview.tsx's fileService), opened from its message. */
function fileTab(session: string, path: string, name: string): string {
  return fileService({ session, path, name });
}

const fileOf = (key: string) => fileSourceOf(key);

/** A web service's tab: its job, from its key (`service:<job>`); null for an agent's history tab. */
function serviceOf(key: string): string | null {
  return key.startsWith("service:") ? key.slice("service:".length) : null;
}

/** The chat's web services and background jobs, from the title bar: what matters now, the rest in the 任务 tab. */
function JobsPanel({ station, session, chat }: { station: string; session: string; chat: string }) {
  const view = useChatJobs(station, { session }).value ?? NO_JOBS;
  const [open, setOpen] = useState(false);
  const alarm = view.alarm;
  const close = (then: () => void) => { setOpen(false); then(); };
  return (
    <Popover.Root open={open} onOpenChange={setOpen}>
      <Tip label={t("web-pages.chat.services")} shortcut="chat.jobs">
        <Popover.Trigger asChild>
          <button type="button" className={`${pageCss.iconBtn} ${css.jobsTrigger}`} aria-label={t("web-pages.chat.services")} data-alarm={alarm} data-none={view.jobs.length === 0 || undefined}><Web {...ICON} /></button>
        </Popover.Trigger>
      </Tip>
      <Popover.Portal>
        <Popover.Content className={`${controlsCss.popover} ${css.jobsPanel}`} align="end" sideOffset={6} collisionPadding={8}>
          <JobsPopover station={station} view={view} onService={(job) => close(() => chatPage.tab(chat, `service:${job}`))} onTab={(job) => close(() => chatPage.jobs(chat, job))} />
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}

/** The connect a Slack chat's agents reach Slack through: links into Slack start at its workspace. */
function slackConnect(chat: ChatView) {
  return chat.agents.find((a) => a.connect?.kind === "slack")?.connect ?? null;
}

/** The chat itself: where it came from, who started it and takes part, its agents. Opens from the title bar. */
function ChatInfo({ station, session }: { station: string; session: string }) {
  const [open, setOpen] = useState(false);
  const [sharing, setSharing] = useState(false);
  // Its thread, while publishing it or asking before one of its links is revoked (the info closes meanwhile).
  const [publishing, setPublishing] = useState<number | null>(null);
  const [revoking, setRevoking] = useState<{ thread: number; id: string } | null>(null);
  return (
    <>
    <Popover.Root open={open} onOpenChange={setOpen}>
      <Tip label={t("web-pages.chat.info")}>
        <Popover.Trigger asChild>
          <button type="button" className={pageCss.iconBtn} aria-label={t("web-pages.chat.info")}><Info {...ICON} /></button>
        </Popover.Trigger>
      </Tip>
      <Popover.Portal>
        <Popover.Content className={`${controlsCss.popover} ${controlsCss.panelCard} ${css.chatInfo}`} align="end" sideOffset={6} collisionPadding={8}>
          <ChatInfoBody station={station} session={session} onShare={() => { setOpen(false); setSharing(true); }}
            onPublish={(thread) => { setOpen(false); setPublishing(thread); }} onRevoke={(thread, id) => { setOpen(false); setRevoking({ thread, id }); }} />
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
    {sharing && <ShareOf station={station} session={session} onClose={() => setSharing(false)} />}
    {publishing !== null && <PublishDialog station={station} thread={publishing} onClose={() => setPublishing(null)} />}
    <RevokeConfirm station={station} thread={revoking?.thread ?? 0} id={revoking?.id ?? null} onClose={() => setRevoking(null)} />
    </>
  );
}

/** The chat's sharing dialog, as the chat is now (read while it is open). */
function ShareOf({ station, session, onClose }: { station: string; session: string; onClose(): void }) {
  const chat = useChat(station, { session }).value;
  return chat?.xshare && chat.thread ? <ShareDialog share={chat.xshare} thread={chat.thread.id} onClose={onClose} /> : null;
}

/** What the chat's info says, as the chat is now: read only while it shows. */
function ChatInfoBody({ station, session, onShare, onPublish, onRevoke }: { station: string; session: string; onShare(): void; onPublish(thread: number): void; onRevoke(thread: number, id: string): void }) {
  const chat = useChat(station, { session }).value;
  const link = useLink();
  if (!chat?.thread) return null;
  const thread = chat.thread;
  const connect = slackConnect(chat);
  const row = (label: string, value: ReactNode) => <div className={css.detailRow}><dt>{label}</dt><dd>{value}</dd></div>;
  const where = chat.place;
  const share = chat.xshare;
  // A read-only member does not publish, but sees what is published.
  const publish = chat.publish && (chat.publish.may || chat.publish.links.length > 0) ? chat.publish : undefined;
  return (
    <>
      <dl className={css.details}>
        {row(t("web-pages.chat.info.from"), where
          ? <span className={css.detailInline}><SlackLogo size={13} />{connect ? <Link to={link(`/connects/${connect.id}`)} className={css.detailLink}>{connect.name}</Link> : "Slack"} · {where}</span>
          : t("web-pages.chat.info.native", { name: NAME }))}
        {row(t("web-pages.chat.info.started"), thread.creator ? <CreatorText creator={thread.creator} verb="started" /> : <span className={shellCss.muted}>{t("web-pages.chat.info.unknown")}</span>)}
        {row(t("web-pages.chat.info.people"), <span className={css.detailInline}><PeopleStack people={chat.people} max={8} />{t("web-pages.workspace.people", { n: chat.people.length })}</span>)}
        {row(t("web-pages.chat.info.created"), <Time stamp={thread.time?.createdAt} />)}
        {thread.lastMessage && row(t("web-pages.chat.info.lastMessage"), <Time stamp={thread.lastMessage.time?.createdAt} />)}
      </dl>
      {chat.agents.length > 0 && (
        <ul className={css.detailsList}>
          {chat.agents.map((a) => <AgentLine key={a.session.key} agent={a} />)}
        </ul>
      )}
      {(share || publish) && (
        <div className={`${css.infoRows} ${controlsCss.panelEdge}`}>
          {share && <ShareRow share={share} onOpen={onShare} />}
          {publish && <PublishRow publish={publish} onOpen={() => onPublish(thread.id)} />}
          {publish && <PublishedLinks links={publish.links} onRevoke={(id) => onRevoke(thread.id, id)} />}
        </div>
      )}
    </>
  );
}

/**
 * Making the chat public (docs/public-share.md), in its info: the row that opens what publishes it, for those who may
 * (not a read-only member), its links under it (PublishedLinks).
 */
function PublishRow({ publish, onOpen }: { publish: ChatPublish; onOpen(): void }) {
  return <PanelRow icon={<Web size={14} />} label={t("web-pages.chat.publish")} onClick={publish.may ? onOpen : undefined} />;
}

/**
 * The chat's sharing with the viewer's other workspaces (docs/chat-share.md), last in its info: where it is shared at
 * the row's end, under way a turning ring there. Only those who may change it (its starter, an owner or admin) open it.
 */
function ShareRow({ share, onOpen }: { share: ChatShare; onOpen(): void }) {
  const station = useStation().address;
  const state = useDoingState("chat.xshare", { station, session: share.session });
  const end = (
    <>
      <span className={css.shareText}>{share.text}</span>
      <DoingShown state={state} className={controlsCss.iconSpinner} size={12} label={t("web-pages.chat.xshare.saving")} />
    </>
  );
  return <PanelRow icon={<Users size={14} />} label={t("web-pages.chat.xshare")} end={end} onClick={share.may ? onOpen : undefined} />;
}

/**
 * Which of the viewer's other workspaces it is shared with, ticked, and whether their agents may send in it: done, the
 * dialog goes at once and the core shows it so while its station is told (`chat.xshare`).
 */
function ShareDialog({ share, thread, onClose }: { share: ChatShare; thread: number; onClose(): void }) {
  const station = useStation().address;
  const api = stationApi(useStationCall(station));
  const act = useAct();
  const [ticked, setTicked] = useState(() => new Set(share.places.filter((p) => p.on).map((p) => p.workspace)));
  const [write, setWrite] = useState(share.write);
  const toggle = (id: string) => setTicked((was) => { const next = new Set(was); if (next.has(id)) next.delete(id); else next.add(id); return next; });
  const save = () => {
    onClose();
    act(api.xshare({ thread, session: share.session }, share.places.filter((p) => ticked.has(p.workspace)).map((p) => p.workspace), write), t("web-pages.chat.xshare.verb"));
  };
  return (
    <Dialog open onClose={onClose} title={t("web-pages.chat.xshare")} description={t("web-pages.chat.xshare.lead")}
      footer={<Button variant="primary" onClick={save}>{t("common.done")}</Button>}>
      <ul className={css.shareList}>
        {share.places.map((p) => (
          <li key={p.workspace}>
            <label className={pagesCss.listRow}>
              <input type="checkbox" checked={ticked.has(p.workspace)} onChange={() => toggle(p.workspace)} />
              <span className={pagesCss.listRowTitle}>{p.name}</span>
            </label>
          </li>
        ))}
      </ul>
      <div className={css.shareWrite}>
        <SwitchRow title={t("web-pages.chat.xshare.write")} description={t("web-pages.chat.xshare.writeNote")} checked={write} onChange={setWrite} disabled={ticked.size === 0} />
      </div>
    </Dialog>
  );
}

/** An agent of the chat in its info: what it runs, where it came from, and how it stands. */
function AgentLine({ agent }: { agent: ChatAgent }) {
  const { session, connect } = agent;
  return (
    <li>
      <span className={css.detailInline}><AgentMark maker={session.maker} runtime={session.runtime} badge={agent.badge} badgeText={session.badgeText} size={14} />{session.agentText}</span>
      <span className={shellCss.muted}>
        {connect ? <><ConnectKindIcon kind={connect.kind} size={11} /> {connect.name} · </> : null}{session.processText} · {tx("web-pages.chat.lastActive", { time: <Time stamp={session.time?.lastActiveAt} /> })}
      </span>
    </li>
  );
}

/**
 * The history's line under its head: only what is worth a look now, as the core says (a quota running out, the disk
 * filling up, an account that cannot run); nothing when all is well.
 */
function HistorySummary({ agent }: { agent: ChatAgent }) {
  if (agent.attention.length === 0) return null;
  return (
    <span className={css.historySummary}>
      {agent.attention.map((a, i) => (
        a.quota ? (
          <Tip key={i} label={<>{a.text}{a.more && <><br />{a.more}</>}</>}>
            <span className={`${css.attention} ${css.attentionQuota}`}><QuotaChip window={a.quota} small bare /></span>
          </Tip>
        ) : (
          <span key={i} className={css.attention} data-tone={a.kind === "disk" ? "amber" : "red"}>{a.text}</span>
        )
      ))}
    </span>
  );
}

/**
 * The history's head: how it runs, in one control (the model, how hard it thinks, the account with its quota), shown
 * whether its details are open or not. Changes take from its next turn on.
 */
function SessionHead({ agent }: { agent: ChatAgent }) {
  const station = useStation();
  const toast = useToast();
  // What it runs on and what its control's panel picked, as the core has them (../pick.ts).
  const pick = usePick(station.address, `session:${agent.session.key}`);
  const change = useAction(() => pick.save(), () => toast(t("web-pages.chat.pickSaved")));
  return (
    <span className={css.sessionHead}>
      <ModelTriple pick={pick} onConfirm={() => void change.run()} />
      {change.error && <span className={controlsCss.fieldError} role="alert">{change.error.message}</span>}
    </span>
  );
}

/**
 * Unfolded under the history's head: what it has used, as its card says it (the figures that say most, large; the
 * rest in a quiet line), then a row each, its mark leading: what runs it (and its account's page), and the station it
 * runs on with what runs low on it.
 */
function SessionDetails({ agent }: { agent: ChatAgent }) {
  const { session } = agent;
  const station = useStation();
  const link = useLink();
  const host = useHost(station.address).value;
  const look = useStationLook(station.address);
  const card = useAgentCard(station.address, session.key).value;
  // A station older than the card's figures: what it has used in a line, as before.
  const usage = useHistory(station.address, session.key).value?.usageLine;
  const tiles = card && (card.cost || card.cache || card.context);
  const quiet = tiles ? [card.work, card.tokens].filter(Boolean).join(" · ") : usage;
  return (
    <div className={css.sessionDetails}>
      {tiles && <UsageTiles card={card} />}
      {quiet && <p className={css.sessionQuiet}>{quiet}</p>}
      <div className={css.sessionLine}>
        <span className={css.sessionLineMark}><AgentMark maker={session.maker} runtime={session.runtime} badge={undefined} size={16} /></span>
        <span className={css.sessionLineText}>
          {session.runtimeText} · {session.processText}
          {session.process === "warm" && <>{" · "}<Evict session={session.key} /></>}
        </span>
        <Link className={css.detailLink} to={link(`/settings/accounts/${session.profile}`)}>{t("web-pages.chat.profileDetails")}</Link>
      </div>
      <div className={css.sessionLine}>
        <span className={css.sessionLineMark}><StationMark emoji={look?.emoji} icon={look?.icon} size={16} /></span>
        <span className={css.sessionLineText}>
          <span className={css.sessionLineName}>{station.name || host?.hostname || t("web-pages.chat.thisMachine")}</span>
          {host?.identity ? ` · ${host.identity}` : ""}
        </span>
        {host && host.meters.some((m) => m.level !== "ok") && (
          <span className={css.resourceRings}>
            <MeterChips meters={host.meters} alerts />
          </span>
        )}
      </div>
    </div>
  );
}

/**
 * Its idle process, kept warm for the next message, ended now (the station ends it by itself in time): rarely wanted,
 * so in its details, beside where they say it is warm. Under way, a turning ring; failed, a red mark a few seconds.
 */
function Evict({ session }: { session: string }) {
  const api = useApi();
  const act = useAct();
  const station = useStation().address;
  const evicting = useDoing("session.evict", { station, key: session });
  const failed = useDoingFailed("session.evict", { station, key: session });
  return (
    <button type="button" className={`${css.detailLink} ${css.evict}`} disabled={evicting} onClick={() => act(api.evict(session), t("web-pages.chat.evict"), t("web-pages.chat.evicted"))}>
      {t("web-pages.chat.evict")}<DoingShown state={{ running: evicting, error: failed }} className={controlsCss.iconSpinner} size={12} />
    </button>
  );
}

/**
 * The machine the chat runs on: its name, how it looks (once its view comes) and, until then, its host in a line. Only
 * what is shown here is followed: its view changes much more often (its load, its agents), and is read by its card.
 */
function useChatStation() {
  const station = useStation();
  const listed = useTopicSelect<StationView[], boolean>({ topic: "stations", scope: scopeOf(station.address) }, (s) => s.value !== undefined);
  const look = useStationLook(station.address);
  const hostname = useTopicSelect<Host, string | undefined>({ topic: "host", station: station.address }, (s) => s.value?.hostname);
  const line = useTopicSelect<Host, string | undefined>({ topic: "host", station: station.address }, (s) => (look || !s.value ? undefined : `${s.value.hostname} · ${s.value.summary}`));
  if (!listed) return null;
  const name = station.name || hostname || t("web-pages.chat.thisMachine");
  return { name, address: station.address, look, line, settings: `${station.settings}/stations` };
}

/** The station at a glance on hover (its card, StationCards.tsx); before its view comes, its host in a line. */
function StationHover({ where, children }: { where: NonNullable<ReturnType<typeof useChatStation>>; children: ReactElement }) {
  const { look, line, name, address, settings } = where;
  if (look) return <Hover content={<StationCard address={address} settings={settings} />}>{children}</Hover>;
  return <Tip label={line ?? name}>{children}</Tip>;
}

/** The station's card, as its view is now: read only while it shows. */
function StationCard({ address, settings }: { address: string; settings: string }) {
  const view = useStations(scopeOf(address)).value?.find((s) => s.station === address);
  return view ? <StationPeek s={view} settings={settings} panel /> : null;
}

/** The station's part of its agent's tile: its icon, or its name where it has none (how it is reached is on the tile's corner). */
function StationPart({ where }: { where: NonNullable<ReturnType<typeof useChatStation>> }) {
  const { look, name, address } = where;
  const mark = look && (look.emoji || look.icon);
  const link = useStationLink(address);
  return (
    <StationHover where={where}>
      <span className={css.agentStationPart} data-name={mark ? undefined : true} tabIndex={look ? 0 : undefined} aria-label={link ? `${name} · ${link.text}` : mark ? name : undefined}>
        {mark ? <StationMark emoji={look.emoji} icon={look.icon} size={12} /> : name}
      </span>
    </StationHover>
  );
}

/** The machine the chat runs on, beside its title, while it has no agent to share a tile with; how it is reached, a dot before it. */
function ChatStation() {
  const where = useChatStation();
  const link = useStationLink(useStation().address);
  if (!where) return null;
  const { look, name } = where;
  return (
    <StationHover where={where}>
      <span className={css.chatStation} tabIndex={look ? 0 : undefined}>{link && <StationDot link={link} />}{(look?.emoji || look?.icon) && <StationMark emoji={look.emoji} icon={look.icon} size={12} />}{name}</span>
    </StationHover>
  );
}

/**
 * The chat's name in its bar: while a new one goes (`chat.rename`), that one, a turning ring beside it; its own again if
 * it did not, a red mark there a few seconds saying why.
 */
function ChatTitle({ station, session, title }: { station: string; session: string | null; title: string }) {
  const renamingTo = useRenaming(station, session);
  const renameFailed = useDoingFailed("chat.rename", { station, session: session ?? "" });
  return (
    <>
      <h1>{renamingTo ?? title}</h1>
      <DoingShown state={{ running: renamingTo !== undefined, error: session === null ? undefined : renameFailed }} className={controlsCss.iconSpinner} size={14} label={t("web-pages.settings.stations.renaming")} />
    </>
  );
}

/** What can be done to it right now: stop a turn, release an idle process. */
