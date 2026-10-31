import { StationUpdate } from "../StationUpdate.tsx";
// A chat: a thread (a Slack thread or a chat on still.fail's page) with its people
// and agents. The messages are the page; its agents' execution histories can
// be opened beside them, one tab per agent.
import { closePreview, PreviewSlot, previewKey } from "../Previews.tsx";
import { scopeOf, useLink, useStation } from "../station.tsx";
import { CreatorText, QuotaChip, MeterChips, PeopleStack } from "../components.tsx";
import { Archive, ArrowUpRight, Boxes, Chats, Close, File, Folder, ImageUpload, Info, List, Monitor, More, PanelClose, PanelOpen, Phone, Photo, Refresh, Shrink, Users, Web } from "@stillfail/ui/icons.tsx";
import { Letters } from "../Letters.tsx";
import { PullMark, pullTitle, ThingMenu, Things, useChatThings } from "../Things.tsx";
import { LinkHover } from "../Peeks.tsx";
import { jumpTo } from "../jumpTo.ts";
import { DriveTab } from "./DriveTab.tsx";
import { DropHint, FILES, FilesTab, keepFocus, PANEL_MAX, PANEL_MIN, SidePane, paneId, tabId, useChatDrop, useSidePanel, useStationDrive } from "./ChatSide.tsx";
import { JobDot, JobsPopover, JobsTab, NO_JOBS } from "../Jobs.tsx";
import { Popover, Tabs } from "radix-ui";
import { memo, useEffect, useRef, useState, type ReactElement, type ReactNode } from "react";
import { Link, Navigate, useHref, useNavigate, useParams, useSearchParams } from "react-router";
import { PENDING } from "../lastChat.ts";
import { ownOrigin } from "../stillfailLink.ts";
import { changeTabs } from "../chatTabs.ts";
import { usePrefs } from "../prefs.ts";
import type { ChatJobsView, ChatPublish, ChatScreen, ChatShare, Host, StationView } from "../core/shapes.ts";
import { archiveSaid, stationApi, useAction, useApi, useStatus, useChat, useChatJobs, useListedChat, useHistory, useHost, useStationCall, useStationLook, useAgentCard, useStations, type ChatAgent, type ChatView, type ChatThread } from "../api.ts";
import { History } from "../History.tsx";
import { StationMark } from "../StationMark.tsx";
import { StationCornerDot, StationDot, useStationLink } from "../StationLink.tsx";
import * as linkCss from "../StationLink.css.ts";
import { StationPeek } from "../cloud/StationCards.tsx";
import { Hover } from "../Peeks.tsx";
import { AgentCard, UsageTiles, WorkMark } from "../AgentCard.tsx";
import * as cardCss from "../AgentCard.css.ts";
import { ModelTriple } from "../ModelTriple.tsx";
import { usePick } from "../pick.ts";
import { ChatPanel, ChatSample, goToNeighbour } from "../Chat.tsx";
import { OpenFile } from "../Viz.tsx";
import { OpenScreen, screenOfTab, screenTab, useScreenCard } from "../screen/ScreenLink.tsx";
import { ScreenViewer } from "../screen/ScreenViewer.tsx";
import { fileService, fileSourceOf } from "../Preview.tsx";
import { useShortcut } from "../keymap.ts";
import { useCommands } from "../commands.ts";
import { openRelay } from "../Relay.tsx";
import { LOCAL_MS } from "@stillfail/ui/motion.ts";
import { ComposerSlot } from "../dock.tsx";
import { chatOpening, track } from "../telemetry.ts";
import { useReady, useTopicSelect } from "../core/react.ts";
import { chatPage, useChatPageActions } from "../chatPage.ts";
import { failure, useAct, useToast } from "@stillfail/ui/toast.tsx";
import { useDoing, useDoingFailed } from "../doing.ts";
import { DoingShown, useDoingState } from "../DoingMark.tsx";
import { AgentMark, Button, Confirm, ConnectKindIcon, Dialog, ElsewhereLogo, Empty, FeishuLogo, ICON, IconButton, Menu, MobileBack, ModelLogo, PanelRow, ResizeHandle, SlackLogo, SwitchRow, Time, Tip, Waiting } from "../ui.tsx";
import { useRenaming } from "../Rename.tsx";
import * as sessionCss from "../styles/session.css.ts";
import * as jobsCss from "../styles/jobs.css.ts";
import * as sidebarCss from "../styles/sidebar.css.ts";
import * as conversationCss from "../styles/conversation.css.ts";
import * as css from "./ChatPage.css.ts";
import * as pagesCss from "../styles/pages.css.ts";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import * as shellCss from "../styles/shell.css.ts";

import { t } from "../i18n.ts";
import { WorkspaceNamed } from "../WorkspaceMark.tsx";
import { tx } from "../cloud/words.tsx";
import { PublishDialog, PublishedLinks, RevokeConfirm } from "../Publish.tsx";
import * as pageCss from "@stillfail/ui/styles/page.css.ts";
/**
 * An item's page, one for every item: its chat's messages (none before its agent has a chat), the composer, and its
 * agents' execution histories beside them. The address is the item's: its chat's thread, or its agent's session key
 * until the first message makes the chat, and the page moves there.
 */
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
    const surface = !chat.thread || (chat.thread.surface === "ember" || chat.thread.surface === "stillfail") ? "ember" : chat.thread.surface.startsWith("feishu:") ? "feishu" : "slack";
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
  // Each chat keeps its own tabs. Which are open and in front is the core's (the chat's `tabs`: those kept for it that
  // it has, client/core-ts/src/chat-tabs.ts), as are the changes (`chat.tabs.*`, changeTabs). One not opened before
  // opens none (its agents' histories open from them when wanted), except an agent with no chat yet, here or in Slack:
  // its page shows its history (`tabs.auto`). Where the panel would lie over the chat (the styles' `max-width: 1100px`),
  // none opens by itself: the chat comes first.
  const chatKey = `${station.address}:${"thread" in of ? of.thread : of.session}`;
  const [folded] = useState(() => window.matchMedia("(max-width: 1100px)").matches);
  const said = chatView.value?.tabs;
  const bare = !!said?.auto && folded;
  // The tabs as last left while the chat is not read yet: the page holds the panel's place instead of it coming in later.
  const kept = usePrefs((p) => (said ? undefined : p.chatTabs[chatKey]?.tabs));
  const open = said ? (bare ? NO_TABS : said.open) : kept ?? NO_TABS;
  const shown = said && !bare ? said.shown ?? null : null;
  // Its agents' background jobs; a service's tab (`service:<job>`) is the chat's own while one of them has it.
  const jobs = agents.flatMap((a) => a.jobs ?? []);
  // As its pages show them (the core's `chatJobs`).
  const jobsView = useChatJobs(station.address, of).value ?? NO_JOBS;
  // A kept web service that stopped is not kept any longer.
  useEffect(() => {
    for (const job of jobs) if (job.open === false) closePreview(previewKey(station.address, job.id));
  }, [jobs, station.address]);
  const isAgent = (key: string) => agents.some((a) => a.session.key === key);
  // The job picked in the 任务 tab.
  const [jobPicked, pickJob] = useState<string | null>(null);
  const sidePanel = useSidePanel(open, shown);
  const { pageRef, panelRef, leaving } = sidePanel;
  // Asked of the core, the panel told first whether any tab will be open (it slides in or out as they come).
  const change = (action: "open" | "close" | "front" | "clear", key: string | undefined, any: boolean) => {
    sidePanel.changing(any);
    changeTabs(chatKey, action, key, !folded);
  };
  const setActive = (key: string) => change("front", key, true);
  const openTab = (key: string) => change("open", key, true);
  // A web service's or a visualization's tab closed ends it: not left small in the corner (Previews.tsx).
  const endPreview = (key: string) => {
    const file = fileOf(key);
    const service = file ? fileService(file) : serviceOf(key);
    if (service) closePreview(previewKey(station.address, service));
  };
  const closeTab = (key: string) => {
    endPreview(key);
    change("close", key, open.some((tab) => tab !== key));
  };
  // The panel closed closes all its tabs.
  const closePanel = () => {
    for (const key of open) endPreview(key);
    change("clear", undefined, false);
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
  // A task of the chat's (`?job=<id>`, a search's find): its services and tasks, at it.
  const askedJob = search.get("job");
  useEffect(() => {
    if (!askedJob) return;
    openJobs(askedJob);
    setSearch((now) => { now.delete("job"); return now; }, { replace: true });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [askedJob]);
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
  // opens beside the chat; another session of the workspace opens here, in the page, not through the desktop app.
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
      // still.fail cloud's (one written on app.still.fail, read on app.youdid.wtf).
      const page = url.origin === location.origin && url.pathname.startsWith(`${opens.current.root}/`) ? url.pathname.slice(opens.current.root.length)
        : url.origin !== location.origin && ownOrigin(url) ? url.pathname : null;
      if (page && /^(\/w\/[^/]+\/s\/[^/]+)?\/chats\/[^/]+\/?$/.test(page)) {
        event.preventDefault();
        navigate(`${page}${url.search}`);
        return;
      }
      // One of a station's screens (an agent asking a person to take over: docs/remote-screens.md): its viewer, here.
      if (page && /^\/w\/[^/]+\/s\/[^/]+\/screen\/[^/]+\/?$/.test(page)) {
        event.preventDefault();
        navigate(page.replace(/\/$/, ""));
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
  // One of its turns shared as a picture (a message's words picked: 分享这一轮), by its thread and the message's n.
  const [sharingTurn, setSharingTurn] = useState<{ thread: number; seq: number } | null>(null);
  const shareTurn = (seq: number) => { const thread = chatView.value?.thread?.id; if (thread !== undefined) setSharingTurn({ thread, seq }); };
  // What is in the page (its messages, its bar, its tabs) does these by the chat's key: it is handed none of them.
  useChatPageActions(chatKey, { history: openHistory, tab: openTab, jobs: openJobs, archive: archiveAsked, share: shareTurn });
  // A visualization in a message opens in a tab of the side panel: the same function while the page is this chat's.
  const [openFile] = useState(() => (session: string, file: { path: string; name: string }) => chatPage.tab(chatKey, fileTab(session, file.path, file.name)));
  // A station's screen linked in a message opens beside the chat as well (ScreenLink.tsx), and from there on its own page.
  const [openScreen] = useState(() => (at: string, screen: string) => chatPage.tab(chatKey, screenTab(at, screen)));
  const screenPage = (at: string, screen: string) => {
    const [workspace, id] = at.split("/");
    navigate(`/w/${workspace}/s/${id}/screen/${encodeURIComponent(screen)}`);
  };
  const api = stationApi(call);
  const toast = useToast();
  const running = agents.filter((a) => a.status === "running" || a.status === "queued");
  const act = useAct();
  useShortcut("chat.stop", running.length ? () => {
    act(Promise.all(running.map((a) => api.stop(a.session.key))), t("web-pages.chat.stop"), t("web-pages.chat.stopAsked"));
  } : null);
  // A history tab in front closes the panel; else the first one open comes to the front, the chat's own agent's if none is.
  useShortcut("chat.history", agents[0] ? () => {
    if (shown && isAgent(shown)) closePanel(); else openTab(open.find(isAgent) ?? agents[0]!.session.key);
  } : null);
  useShortcut("chat.jobs", () => (shown === JOBS ? closeTab(JOBS) : openJobs()));
  // The station's own display (else its first screen) beside the chat (ScreensButton).
  const firstScreen = chatView.value?.screens?.[0];
  useShortcut("chat.screen", firstScreen ? () => openScreen(station.address, firstScreen.id) : null);
  // The stations' files beside the chat (DriveTab.tsx), where they have them: pressed again while in front, closed.
  const drive = useStationDrive(station.address);
  // Files dragged anywhere over the chat go into its message (useChatDrop).
  const drop = useChatDrop(chatKey);
  const toggleFiles = () => (open.includes(FILES) && shown === FILES ? closeTab(FILES) : openTab(FILES));
  const toggleLetters = () => (open.includes(LETTERS) && shown === LETTERS ? closeTab(LETTERS) : openTab(LETTERS));
  // What was said in it besides words (Things.tsx), opened at its pull requests from the info's 全部 N 个 PR.
  const [thingsAt, setThingsAt] = useState<"pulls" | undefined>(undefined);
  const openThings = (kind?: "pulls") => { setThingsAt(kind); openTab(THINGS); };
  useShortcut("panel.close", open.length ? closePanel : null);
  const thread = chatView.value?.thread?.id ?? null;
  const keeper = agents[0]?.session.key ?? ("session" in of ? of.session : null);
  const archive = async () => {
    if (!keeper) return;
    // On to the chat below it in the list (or above, at the end), so the keys go on working; the list page if none.
    if (!goToNeighbour(1) && !goToNeighbour(-1)) navigate(link("/chats"));
    try {
      await archiveSaid(api, { thread, session: keeper }, chatView.value?.title ?? "", toast);
    } catch (error) {
      toast(t("web-pages.chat.archiveFailed", { error: error instanceof Error ? error.message : String(error) }));
    }
  };
  // A chat keeping watch is archived only once asked, in the core's words.
  const [askArchive, setAskArchive] = useState(false);
  useShortcut("chat.archive", chatView.value && !chatView.value.archived && !chatView.value.offline && keeper
    ? () => { if (chatView.value?.watch) setAskArchive(true); else void archive(); } : null);
  // Relayed to a channel (docs/relay.md): a chat with an agent to go on there, from ⌘K and the title bar.
  const relayable = thread !== null && agents.length > 0 && !chatView.value?.archived && !chatView.value?.offline;
  const relay = () => { if (thread !== null) openRelay(station.address, thread); };
  useCommands(relayable ? [{ id: "chat.relay", icon: ArrowUpRight, run: relay }] : []);
  if (!chatView.value) {
    if (chatView.error) return <Empty><p>{t("web-pages.chat.loadFailed", { error: chatView.error.message })}</p></Empty>;
    // Laid out as the chat will be, its composer already in its place: coming from another chat page, the composer
    // moves there at once rather than going away until the chat is read (it cannot send until then).
    return (
      <div className={sessionCss.sessionPage} data-panel={open.length > 0}>
        <div className={jobsCss.sessionMain}>
          <header className={sidebarCss.pageBar}>
            <MobileBack to={link("/chats")} label={t("web-pages.decisions.back")} />
            <div className={conversationCss.pageBarTitle}><ListedTitle session={chatSession} /></div>
          </header>
          <section className={sessionCss.chat} aria-label={t("web-pages.decisions.back")} data-under-composer="" data-avoid-previews="">
            <ChatWaiting />
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
  // Before its agent has a chat, what is sent goes to the agent: it waits in the outbox at once while the core has the
  // station make the chat behind it; the page stays (the core shows the chat at the same address once it is there).
  const sendTo = made ?? ("session" in of && !chat.thread ? of.session : undefined);
  return (
    <div ref={pageRef} className={sessionCss.sessionPage} data-panel={panel || leaving !== null}>
      {sharingTurn && <PublishDialog station={station.address} thread={sharingTurn.thread} turn={sharingTurn.seq} onClose={() => setSharingTurn(null)} />}
      {chat.watch && <Confirm open={askArchive} title={t("web-pages.chat.archiveConfirm", { title: chat.title })} description={chat.watch.ask} action={t("web-pages.chat.archive")}
        onConfirm={() => { setAskArchive(false); void archive(); }} onClose={() => setAskArchive(false)} />}
      <div className={`${jobsCss.sessionMain} ${css.dropZone}`} {...drop.handlers}>
      <DropHint drop={drop} />
      <header className={sidebarCss.pageBar}>
        <MobileBack to={link("/chats")} label={t("web-pages.decisions.back")} />
        {/* The chat's title, then who is in it: its people, then its agents (each opens its history). */}
        <div className={conversationCss.pageBarTitle}>
          {/* Text only: a chat is renamed in the sidebar. */}
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
          <ScreensButton screens={chat.screens ?? []} onOpen={(id) => openScreen(station.address, id)} />
          {/* The rest of what is done with the chat, in one place: its own panel (its files, what its agents and other
              chats' wrote each other, relaying it, where it is in Slack, sharing and publishing it). */}
          {/* A chat of a Slack or Feishu thread alone too: where it is, its agents and the way there. */}
          <ChatInfo station={station.address} session={chatSession} onLetters={toggleLetters} onThings={openThings} onFiles={drive ? toggleFiles : undefined}
            onRelay={relayable ? relay : undefined} />
          {!panel && agents[0] && <IconButton label={t("web-pages.chat.openPanel")} icon={PanelOpen} shortcut="chat.history" onMouseDown={keepFocus} onClick={() => openTab(agents[0]!.session.key)} />}
        </div>
      </header>
      {/* The chat is the page; its agents' histories sit in a tab set that takes the whole right side. */}
      {/* A visualization in a message opens on its own in a tab of the side panel, beside the chat. */}
      <OpenFile.Provider value={openFile}>
        <OpenScreen.Provider value={openScreen}>
          <ChatPanel session={chatSession} draftKey={chatKey} made={sendTo} />
        </OpenScreen.Provider>
      </OpenFile.Provider>
      </div>
        {side && (
          <Tabs.Root ref={panelRef} className={css.sidePanel} data-over-composer value={side.shown} onValueChange={setActive} inert={side === leaving}>
            <ResizeHandle variable="--panel-w" edge="left" min={PANEL_MIN} max={PANEL_MAX} label={t("web-pages.chat.resizePanel")}
              press={{ label: t("web-pages.chat.closePanel"), run: closePanel }} />
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
                  if (key === FILES) return <FilesTab key={key} onClose={() => closeTab(key)} />;
                  if (key === LETTERS) {
                    return (
                      <span key={key} className={css.sideTabWrap}>
                        <Tabs.Trigger className={css.sideTab} value={key} id={tabId(key)} aria-controls={paneId(key)}>
                          <span className={css.sideTabAgent}><Chats size={14} strokeWidth={1.75} /><span className={css.sideTabText} data-text={t("web-main.letters.title")}>{t("web-main.letters.title")}</span></span>
                        </Tabs.Trigger>
                        <button type="button" className={css.sideTabClose} aria-label={t("web-main.letters.close")} onClick={() => closeTab(key)}><Close size={12} strokeWidth={2} /></button>
                      </span>
                    );
                  }
                  if (key === THINGS) {
                    return (
                      <span key={key} className={css.sideTabWrap}>
                        <Tabs.Trigger className={css.sideTab} value={key} id={tabId(key)} aria-controls={paneId(key)}>
                          <span className={css.sideTabAgent}><Photo size={14} strokeWidth={1.75} /><span className={css.sideTabText} data-text={t("web-main.things.title")}>{t("web-main.things.title")}</span></span>
                        </Tabs.Trigger>
                        <button type="button" className={css.sideTabClose} aria-label={t("web-main.things.close")} onClick={() => closeTab(key)}><Close size={12} strokeWidth={2} /></button>
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
                  const seen = screenOfTab(key);
                  if (seen) return <ScreenTabTrigger key={key} tab={key} station={seen.station} screen={seen.screen} onClose={() => closeTab(key)} />;
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
              <IconButton label={t("web-pages.chat.closePanel")} icon={PanelClose} shortcut="panel.close" onMouseDown={keepFocus} onClick={closePanel} />
            </div>
            {side.tabs.map((key) => {
              if (key === JOBS) {
                return (
                  <SidePane key={key} of={key} shown={side.shown}>
                    <JobsTab station={station.address} view={jobsView} picked={jobPicked} onPick={pickJob} chat={chatKey} />
                  </SidePane>
                );
              }
              if (key === LETTERS) {
                return (
                  <SidePane key={key} of={key} shown={side.shown}>
                    {thread !== null && keeper && <Letters station={station.address} thread={thread} keeper={keeper} />}
                  </SidePane>
                );
              }
              if (key === THINGS) {
                return (
                  <SidePane key={key} of={key} shown={side.shown}>
                    {thread !== null && keeper && <Things key={thingsAt ?? ""} station={station.address} thread={thread} keeper={keeper} initial={thingsAt}
                      onShow={(seq) => jumpTo({ station: station.address, thread, seq })} />}
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
              const seen = screenOfTab(key);
              if (seen) {
                // Seen only while its tab is in front: a view is not kept open behind another.
                return (
                  <SidePane key={key} of={key} shown={side.shown}>
                    <div className={css.sideScreen}>
                      <ScreenViewer station={seen.station} screen={seen.screen} backLabel={t("common.close")} onBack={() => closeTab(key)}
                        panel={{ onExpand: () => screenPage(seen.station, seen.screen) }} />
                    </div>
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

/** A chat's title as the list has it, while the chat itself is read (nothing, where the list has it not). */
function ListedTitle({ session }: { session: string }) {
  const item = useListedChat(useStation().address, session);
  return item ? <h1>{item.title}</h1> : null;
}

/**
 * A chat not read yet: its messages in their bones, and over them what it waits on: what the core says is slow
 * (正在连接 Studio), else where it reads from; a connection down, in red.
 */
function ChatWaiting() {
  const station = useStation();
  const status = useStatus(scopeOf(station.address));
  const text = status?.text ?? (station.name ? t("web-pages.chat.loadingFrom", { name: station.name }) : t("web-pages.chat.loading"));
  return <Waiting fill text={text} error={status?.state === "trouble" ? text : null} sample={<ChatSample />} />;
}

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

/** No tab open. */
const NO_TABS: string[] = [];

/** A station's screen's tab: its kind's mark and its title, as a link to it says them. */
function ScreenTabTrigger({ tab, station, screen, onClose }: { tab: string; station: string; screen: string; onClose: () => void }) {
  const item = useScreenCard(station, screen);
  const label = item?.title || t("web-pages.screen.title");
  return (
    <span className={css.sideTabWrap}>
      <Tip label={label} cut><Tabs.Trigger className={css.sideTab} value={tab} id={tabId(tab)} aria-controls={paneId(tab)}>
        <span className={css.sideTabAgent}><ScreenMark kind={item?.kind ?? (screen.startsWith("simulator:") ? "simulator" : screen.startsWith("browser:") ? "browser" : "desktop")} /><span className={css.sideTabText} data-text={label}>{label}</span></span>
      </Tabs.Trigger></Tip>
      <button type="button" className={css.sideTabClose} aria-label={t("web-pages.chat.close", { name: label })} onClick={onClose}><Close size={12} strokeWidth={2} /></button>
    </span>
  );
}

/** A screen's kind at a tab's size: a phone for a simulator, the globe for a browser's tab, a display for a desktop. */
function ScreenMark({ kind }: { kind: string }) {
  if (kind === "browser") return <Web size={14} strokeWidth={1.75} />;
  if (kind !== "simulator") return <Monitor size={14} strokeWidth={1.75} />;
  return <Phone size={14} />;
}
/** The 任务 tab's key: every service and job of the chat's agents. */
const JOBS = "jobs";
/** The agent 往来 tab's key: what the chat's agents and other chats' wrote each other (Letters.tsx). */
const LETTERS = "letters";
/** The tab of what was said in the chat besides words (Things.tsx). */
const THINGS = "things";
/** How many pull requests the chat's info names itself (the rest: 全部 N 个 PR). */
const PULLS_SHOWN = 3;
/** A visualization's tab: its place among the previews (Preview.tsx's fileService), opened from its message. */
function fileTab(session: string, path: string, name: string): string {
  return fileService({ session, path, name });
}

const fileOf = (key: string) => fileSourceOf(key);

/** A web service's tab: its job, from its key (`service:<job>`); null for an agent's history tab. */
function serviceOf(key: string): string | null {
  return key.startsWith("service:") ? key.slice("service:".length) : null;
}

/** A screen's mark by its kind: a tab of the station's browser, a simulator, else its display. */
const screenIcon = (kind: string) => (kind === "browser" ? Web : kind === "simulator" ? Phone : Monitor);

/**
 * The screens of the station the chat runs on (the chat view's `screens`), from the title bar: the one alone opened
 * beside the chat, more a menu of them (its own display first); marked while an agent drives one, as it is seen working.
 */
function ScreensButton({ screens, onOpen }: { screens: ChatScreen[]; onOpen(id: string): void }) {
  if (screens.length === 0) return null;
  const label = t("web-pages.chat.screen");
  const driven = screens.some((s) => s.agent) ? "agent" : undefined;
  if (screens.length === 1) {
    return (
      <Tip label={label} shortcut="chat.screen">
        <button type="button" className={`${pageCss.iconBtn} ${css.jobsTrigger}`} aria-label={label} data-alarm={driven} onClick={() => onOpen(screens[0]!.id)}><Monitor {...ICON} /></button>
      </Tip>
    );
  }
  return (
    <Menu label={label} items={screens.map((s) => ({ label: s.title, icon: screenIcon(s.kind), ...(s.agent ? { note: t("web-pages.chat.screenAgent") } : {}), onSelect: () => onOpen(s.id) }))}
      trigger={<button type="button" className={`${pageCss.iconBtn} ${css.jobsTrigger}`} aria-label={label} title={label} data-alarm={driven}><Monitor {...ICON} /></button>} />
  );
}

/** The chat's web services and background jobs, from the title bar: what matters now, the rest in the 任务 tab. */
function JobsPanel({ station, session, chat }: { station: string; session: string; chat: string }) {
  const view = useChatJobs(station, { session }).value ?? NO_JOBS;
  const [open, setOpen] = useState(false);
  const alarm = view.alarm;
  // None: nothing in the bar (the shortcut still opens its tab).
  if (view.jobs.length === 0) return null;
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

/** The connect a Slack chat's agents reach Slack through (links into Slack start at its workspace); a Feishu chat's, by
 * its surface. */
function slackConnect(chat: ChatView) {
  const feishu = chat.thread?.surface.startsWith("feishu:") ? chat.thread.surface.slice("feishu:".length) : null;
  return chat.agents.find((a) => (feishu !== null ? a.connect?.id === feishu : a.connect?.kind === "slack"))?.connect ?? null;
}

/** The chat itself: where it came from, who started it and takes part, its agents. Opens from the title bar. */
function ChatInfo({ station, session, onLetters, onThings, onFiles, onRelay }: { station: string; session: string;
  /** What its agents and other chats' wrote each other: their tab beside the chat (Letters.tsx). */
  onLetters(): void;
  /** What was said in it besides words: their tab beside the chat (Things.tsx), at its pull requests where asked. */
  onThings(kind?: "pulls"): void;
  /** The stations' files beside the chat (DriveTab.tsx), where they have them. */
  onFiles?: (() => void) | undefined;
  /** Relaying it to a channel (docs/relay.md), where it can be. */
  onRelay?: (() => void) | undefined }) {
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
          <button type="button" className={pageCss.iconBtn} aria-label={t("web-pages.chat.info")}><More {...ICON} /></button>
        </Popover.Trigger>
      </Tip>
      <Popover.Portal>
        <Popover.Content className={`${controlsCss.popover} ${controlsCss.panelCard} ${css.chatInfo}`} align="end" sideOffset={6} collisionPadding={8}>
          <ChatInfoBody station={station} session={session} onShare={() => { setOpen(false); setSharing(true); }}
            onPublish={(thread) => { setOpen(false); setPublishing(thread); }} onRevoke={(thread, id) => { setOpen(false); setRevoking({ thread, id }); }}
            onLetters={() => { setOpen(false); onLetters(); }} onThings={(kind) => { setOpen(false); onThings(kind); }}
            onShow={(thread, seq) => { setOpen(false); jumpTo({ station, thread, seq }); }}
            onFiles={onFiles && (() => { setOpen(false); onFiles(); })} onRelay={onRelay && (() => { setOpen(false); onRelay(); })} />
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
function ChatInfoBody({ station, session, onShare, onPublish, onRevoke, onLetters, onThings, onShow, onFiles, onRelay }: { station: string; session: string; onShare(): void; onPublish(thread: number): void; onRevoke(thread: number, id: string): void; onLetters(): void; onThings(kind?: "pulls"): void; onShow(thread: number, seq: number): void; onFiles?: (() => void) | undefined; onRelay?: (() => void) | undefined }) {
  const chat = useChat(station, { session }).value;
  const link = useLink();
  const things = useChatThings(station, chat?.thread?.id ?? null);
  if (!chat) return null;
  // What was said in it besides words: its pull requests, the latest 3 named here (most chats have one or two), the
  // rest counted on the row to their tab.
  const pulls = things?.pulls ?? [];
  const said = things ? things.counts.media + things.counts.files + things.counts.links : 0;
  // (none here for a chat of a Slack or Feishu thread alone: who started it and when are its thread's)
  const thread = chat.thread;
  const feishu = thread ? thread.surface.startsWith("feishu:") : !!chat.feishuUrl;
  const connect = slackConnect(chat);
  const row = (label: string, value: ReactNode) => <div className={css.detailRow}><dt>{label}</dt><dd>{value}</dd></div>;
  const where = chat.place;
  const onlyStarter = chat.people.length === 0 || (chat.people.length === 1 && !!thread?.creator?.id && chat.people[0]!.id === thread.creator.id);
  const share = chat.xshare;
  // A read-only member does not publish, but sees what is published.
  const publish = chat.publish && (chat.publish.may || chat.publish.links.length > 0) ? chat.publish : undefined;
  return (
    <>
      <dl className={css.details}>
        {/* Where it came from only when that is not here: a still.fail chat's says nothing. */}
        {where && row(t("web-pages.chat.info.from"),
          <span className={css.detailInline}><ElsewhereLogo kind={feishu ? "feishu" : "slack"} size={13} />{connect ? <Link to={link(`/connects/${connect.id}`)} className={css.detailLink}>{connect.name}</Link> : feishu ? t("web-pages.connect.feishu.name") : "Slack"} · {where}</span>)}
        {thread && <>
          {row(t("web-pages.chat.info.started"), thread.creator ? <CreatorText creator={thread.creator} verb="started" /> : <span className={shellCss.muted}>{t("web-pages.chat.info.unknown")}</span>)}
          {/* Who takes part only when that is more than who started it. */}
          {!onlyStarter && row(t("web-pages.chat.info.people"), <span className={css.detailInline}><PeopleStack people={chat.people} max={8} />{t("web-pages.workspace.people", { n: chat.people.length })}</span>)}
          {row(t("web-pages.chat.info.created"), <Time stamp={thread.time?.createdAt} />)}
          {thread.lastMessage && row(t("web-pages.chat.info.lastMessage"), <Time stamp={thread.lastMessage.time?.createdAt} />)}
        </>}
      </dl>
      {chat.agents.length > 0 && (
        <ul className={css.detailsList}>
          {chat.agents.map((a) => <AgentLine key={a.session.key} agent={a} />)}
        </ul>
      )}
      {/* What is in it: its pull requests, what else was said in it, the stations' files, its agents' letters, it in Slack or Feishu. */}
      {(pulls.length > 0 || said > 0 || onFiles || chat.letters || chat.slackUrl || chat.feishuUrl) && <div className={`${css.infoTools} ${controlsCss.panelEdge}`}>
        {/* Pointed at, its card (as a message's link to it); right clicked, 在对话中查看 and its link copied. */}
        {pulls.slice(0, PULLS_SHOWN).map((p) => (
          <ThingMenu key={p.key} thing={p} onShow={(seq) => { if (thread) onShow(thread.id, seq); }}>
            <div className={css.infoPull}><LinkHover href={p.url!} label={pullTitle(p)} side="left"><div className={css.infoPull}><PanelRow icon={<PullMark pull={p} />} label={pullTitle(p)} end={`#${p.number}`} onClick={() => window.open(p.url!, "_blank", "noopener")} /></div></LinkHover></div>
          </ThingMenu>
        ))}
        {pulls.length > PULLS_SHOWN && <PanelRow icon={<List size={14} />} label={t("web-main.things.pullsAll", { n: pulls.length })} onClick={() => onThings("pulls")} />}
        {said > 0 && <PanelRow icon={<Photo size={14} />} label={t("web-main.things.title")} end={String(said)} onClick={() => onThings()} />}
        {onFiles && <PanelRow icon={<Folder size={14} />} label={t("web-pages.chat.files")} onClick={onFiles} />}
        {/* What its agents and other chats' wrote each other, not in the chat: their tab beside it. */}
        {chat.letters && <PanelRow icon={<Chats size={14} />} label={t("web-main.letters.title")} end={t("web-main.letters.count", { n: chat.letters })} onClick={onLetters} />}
        {chat.slackUrl && <PanelRow icon={<SlackLogo size={14} />} label={t("web-pages.chat.openInSlack")} onClick={() => window.open(chat.slackUrl!, "_blank", "noopener")} />}
        {chat.feishuUrl && <PanelRow icon={<FeishuLogo size={14} />} label={t("web-pages.chat.openInFeishu")} onClick={() => window.open(chat.feishuUrl!, "_blank", "noopener")} />}
      </div>}
      {/* What is done with it, last: relaying it, sharing it, a picture of it. */}
      {thread && (onRelay || share || publish) && (
        <div className={`${css.infoTools} ${controlsCss.panelEdge}`}>
          {onRelay && <PanelRow icon={<ArrowUpRight size={14} />} label={t("web-main.relay.action")} onClick={onRelay} />}
          {share && <ShareRow share={share} onOpen={onShare} />}
          {publish && <PublishRow publish={publish} onOpen={() => onPublish(thread.id)} />}
          {publish && <PublishedLinks links={publish.links} onRevoke={(id) => onRevoke(thread.id, id)} />}
        </div>
      )}
    </>
  );
}

/**
 * Sharing the chat as a picture, in its info: the row that opens the page it is made in, for those who may (not a
 * read-only member); the public links made of it before pictures under it (PublishedLinks, docs/public-share.md).
 */
function PublishRow({ publish, onOpen }: { publish: ChatPublish; onOpen(): void }) {
  // (a picture going out: not the photo of 图片、文件和链接 above it)
  return <PanelRow icon={<ImageUpload size={14} />} label={t("web-pages.chat.shareImage")} onClick={publish.may ? onOpen : undefined} />;
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
      <DoingShown state={state} inline label={t("web-pages.chat.xshare.saving")} />
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
              <WorkspaceNamed w={p} className={pagesCss.listRowTitle} />
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
  const context = useContextActions(session.key, session.canCompact === true, session.canClear === true);
  return (
    <div className={css.sessionDetails}>
      {tiles && <UsageTiles card={card} context={context} />}
      {/* (its work past its turns at the line's end: the first to give way) */}
      {quiet && <p className={`${css.sessionQuiet} ${cardCss.workQuiet}`}><span className={cardCss.workQuietText}>{quiet}</span><WorkMark station={station.address} session={session.key} /></p>}
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
      {context.items.length > 0 && <ContextLine actions={context} used={card?.context?.text} />}
      {context.dialog}
      <TranscriptLine session={session.key} />
    </div>
  );
}

/**
 * Its context by hand, between turns: compacted (the chat is told when it is done), or cleared so its next message
 * starts a new conversation (asked first). The menu's items, whether one is under way or failed, and the dialog that
 * asks, for its context's tile and its line.
 */
function useContextActions(session: string, compact: boolean, clear: boolean) {
  const api = useApi();
  const act = useAct();
  const station = useStation().address;
  const calls = ["session.compact", "session.clear"] as const;
  const busy = useDoing(calls, { station, key: session });
  const failed = useDoingFailed(calls, { station, key: session });
  const [asking, setAsking] = useState(false);
  const items = [
    ...(compact ? [{ label: t("web-pages.chat.compact"), icon: Shrink, disabled: busy, onSelect: () => act(api.compact(session), t("web-pages.chat.compact")) }] : []),
    ...(clear ? [{ label: t("web-pages.chat.clear"), icon: Refresh, danger: true, disabled: busy, onSelect: () => setAsking(true) }] : []),
  ];
  const dialog = (
    <Confirm open={asking} title={t("web-pages.chat.clearConfirm")} description={t("web-pages.chat.clearBody")} action={t("web-pages.chat.clear")}
      onConfirm={() => { setAsking(false); act(api.clear(session), t("web-pages.chat.clear")); }} onClose={() => setAsking(false)} />
  );
  return { items, busy, failed, compacts: compact, dialog };
}

/** Its context's line: how full it is, and the same menu as its tile's, behind 管理. */
function ContextLine({ actions, used }: { actions: ReturnType<typeof useContextActions>; used: string | undefined }) {
  return (
    <div className={css.sessionLine}>
      <span className={css.sessionLineMark}><Shrink size={16} /></span>
      <span className={css.sessionLineText}>{t("web-pages.chat.context")}{used ? ` · ${used}` : ""}</span>
      <DoingShown state={{ running: actions.busy, error: actions.failed }} inline />
      <Menu label={t("web-pages.chat.contextActions")} trigger={<button type="button" className={`${css.detailLink} ${css.detailButton}`} aria-label={t("web-pages.chat.contextActions")}>{t("web-pages.chat.contextManage")}</button>} items={actions.items} />
    </div>
  );
}

/**
 * Where its runtime keeps the session's transcript on the station's machine: its file's name (the whole path on
 * hover), and its path to copy. Nothing before it is written, nor from a station from before it (404).
 */
function TranscriptLine({ session }: { session: string }) {
  const api = useApi();
  const toast = useToast();
  const [path, setPath] = useState<string | null>(null);
  useEffect(() => {
    let current = true;
    setPath(null);
    api.transcriptPath(session).then((p) => { if (current) setPath(p); }, () => {});
    return () => { current = false; };
  }, [api, session]);
  if (path === null) return null;
  const copy = () => navigator.clipboard.writeText(path).then(
    () => toast(t("web-main.chat.transcriptCopied")),
    (e: unknown) => toast(t("web-main.chat.copyFailed", { error: failure(e) })),
  );
  return (
    <div className={css.sessionLine}>
      <span className={css.sessionLineMark}><File size={16} /></span>
      <Tip label={path}>
        <span className={css.sessionLineText}>{t("web-pages.chat.transcript")} · <span className={css.sessionFile}>{path.split(/[\\/]/).pop()}</span></span>
      </Tip>
      <button type="button" className={`${css.detailLink} ${css.detailButton}`} onClick={() => void copy()}>{t("web-pages.chat.copyPath")}</button>
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
    <button type="button" className={`${css.detailLink} ${css.detailButton}`} disabled={evicting} onClick={() => act(api.evict(session), t("web-pages.chat.evict"), t("web-pages.chat.evicted"))}>
      {t("web-pages.chat.evict")}<DoingShown state={{ running: evicting, error: failed }} inline />
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
      <DoingShown state={{ running: renamingTo !== undefined, error: session === null ? undefined : renameFailed }} label={t("web-pages.settings.stations.renaming")} />
    </>
  );
}

/** What can be done to it right now: stop a turn, release an idle process. */
