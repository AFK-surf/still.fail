import { StationUpdate } from "../StationUpdate.tsx";
// A chat: a thread (a Slack thread or a chat on still.fail's page) with its people
// and agents. The messages are the page; each agent's execution history can
// be opened beside them, one tab per agent.
import { closePreview, PreviewSlot, previewKey } from "../Previews.tsx";
import { scopeOf, useLink, useStation } from "../station.tsx";
import { CreatorText, PeopleStack, QuotaRing, Ring } from "../components.tsx";
import { Archive, Boxes, Close, Edit, File, Info, PanelClose, PanelOpen, Stop, Unplug, Web } from "../icons.tsx";
import { JobDot, JobsPopover, JobsTab, NO_JOBS } from "../Jobs.tsx";
import { Popover, Tabs } from "radix-ui";
import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { Link, Navigate, useHref, useNavigate, useParams, useSearchParams } from "react-router";
import { PENDING } from "../lastChat.ts";
import { keepTabs, keptTabs } from "../chatTabs.ts";
import type { ChatJobsView } from "../core/shapes.ts";
import { stationApi, useAction, useApi, useChat, useChatJobs, useChats, useHistory, useHost, useLives, useStationCall, type ChatAgent, type ChatView, type Session, type Status, type ChatThread } from "../api.ts";
import { History } from "../History.tsx";
import { ModelTriple } from "../ModelTriple.tsx";
import { usePick } from "../pick.ts";
import { ChatPanel, goToNeighbour } from "../Chat.tsx";
import { OpenFile } from "../Viz.tsx";
import { fileService, fileSourceOf } from "../Preview.tsx";
import { useShortcut } from "../keymap.ts";
import { animate, EASE_OUT, reducedMotion, type AnimationPlaybackControls } from "../motion.ts";
import { ComposerSlot } from "../dock.tsx";
import { chatOpening, track } from "../telemetry.ts";
import { useReady } from "../core/react.ts";
import { failure, useAct, useToast } from "../toast.tsx";
import { useDoing, useDoingFailed } from "../doing.ts";
import { DoingShown } from "../DoingMark.tsx";
import { AgentMark, Confirm, ConnectKindIcon, Empty, ICON, IconButton, Loading, MobileBack, ModelLogo, ResizeHandle, SlackLogo, Time, Tip } from "../ui.tsx";
import { StatusLine } from "../Status.tsx";
import { TitleInput, useRenaming } from "../Rename.tsx";
import * as renameCss from "../Rename.css.ts";
import * as sessionCss from "../styles/session.css.ts";
import * as jobsCss from "../styles/jobs.css.ts";
import * as sidebarCss from "../styles/sidebar.css.ts";
import * as conversationCss from "../styles/conversation.css.ts";
import * as css from "./ChatPage.css.ts";
import * as pagesCss from "../styles/pages.css.ts";
import * as controlsCss from "../styles/controls.css.ts";
import * as shellCss from "../styles/shell.css.ts";

import { NAME } from "../channel.ts";
import { t } from "../i18n.ts";
import { tx } from "../cloud/words.tsx";
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
  return <ChatScreen key={opened} of={{ session: opened }} />;
}

const READY_MS = 250;

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

function ChatScreen({ of }: { of: { thread: number } | { session: string } }) {
  const station = useStation();
  const link = useLink();
  const navigate = useNavigate();
  const call = useStationCall(station.address);
  // Coming from another page, that page stays until this chat is read (from the device, mostly at once), rather than
  // an empty one showing between; past READY_MS this one shows, waiting.
  useReady({ topic: "chat", station: station.address, ...of }, READY_MS);
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
  const lives = useLives(station.address, agents.map((a) => a.session.key));
  // One history tab per agent, by session key; each can be closed, and with none open the panel goes away.
  // Each chat keeps its own tabs. One not opened before opens none (its agents' histories open from them when wanted),
  // except an agent with no chat yet: its page shows its history. Where the panel would lie over the chat (the styles'
  // `max-width: 1100px`), none opens by itself: the chat comes first.
  const chatKey = `${station.address}:${"thread" in of ? of.thread : of.session}`;
  const [kept] = useState(() => keptTabs(chatKey));
  const [chosen, setTabs] = useState<string[] | null>(() => kept?.tabs ?? null);
  const [folded] = useState(() => window.matchMedia("(max-width: 1100px)").matches);
  const view = chatView.value;
  const tabs = chosen ?? (view && !view.thread && !view.pending && !folded && "session" in of ? [of.session] : []);
  const [active, setActiveState] = useState<string | null>(kept?.active ?? null);
  // The tabs as last left while the agents are not known yet: the panel holds its place instead of coming in later.
  // Its agents' background jobs; a service's tab (`service:<job>`) is the chat's own while one of them has it.
  const jobs = agents.flatMap((a) => a.jobs ?? []);
  // As its pages show them (the core's `chatJobs`).
  const jobsView = useChatJobs(station.address, of).value ?? NO_JOBS;
  // A kept web service that stopped is not kept any longer.
  useEffect(() => {
    for (const job of jobs) if (job.open === false) closePreview(previewKey(station.address, job.id));
  }, [jobs, station.address]);
  const open = agents.length ? tabs.filter((key) => key === JOBS || fileOf(key) !== null || (serviceOf(key) !== null && jobs.some((j) => j.id === serviceOf(key))) || agents.some((a) => a.session.key === key)) : tabs;
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
    setTabs(next);
    setActiveState(front);
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
  useLayoutEffect(() => {
    const page = pageRef.current;
    const el = panelRef.current;
    // Slid out: the page has laid itself out without the panel now, so the column it held is let go of in the same frame.
    if (!sliding) return void page?.style.removeProperty("grid-template-columns");
    if (!page || !el) return;
    const was = slide.current;
    was?.run.stop();
    const narrow = matchMedia("(max-width: 1100px)").matches;
    // Its width at rest, without what the motion holds.
    page.style.removeProperty("grid-template-columns");
    el.style.removeProperty("width");
    el.style.removeProperty("transform");
    const whole = sliding === "out" && leaving ? leaving.width : el.getBoundingClientRect().width;
    const start = was ? was.value : sliding === "in" ? 0 : whole;
    const goal = sliding === "in" ? whole : 0;
    const draw = (v: number) => {
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
      // Another chat's page on this origin (as a reference to it is written, ChatRef.tsx): opened here.
      const page = url.origin === location.origin && url.pathname.startsWith(`${opens.current.root}/`) ? url.pathname.slice(opens.current.root.length) : null;
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
      } else if (url.origin === location.origin || url.origin === window.stillfailDesktop?.cloudOrigin) {
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
  const api = stationApi(call);
  const toast = useToast();
  const running = agents.filter((a) => a.status === "running" || a.status === "queued");
  const act = useAct();
  useShortcut("chat.stop", running.length ? () => {
    act(Promise.all(running.map((a) => api.stop(a.session.key))), t("web-pages.chat.stop"), t("web-pages.chat.stopAsked"));
  } : null);
  // The history tab in front closes the panel; else the first agent's opens.
  useShortcut("chat.history", agents[0] ? () => {
    const front = agents.find((a) => a.session.key === shown);
    if (front) saveTabs([]); else openTab(agents[0]!.session.key);
  } : null);
  useShortcut("chat.jobs", () => (shown === JOBS ? closeTab(JOBS) : openJobs()));
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
  // The chat's name, changed where it is shown: double-click it, or F2.
  const [renaming, setRenaming] = useState(false);
  const renamable = !!(chatView.value && !chatView.value.archived && !chatView.value.offline && !chatView.value.pending && keeper);
  useShortcut("chat.rename", renamable && !renaming ? () => setRenaming(true) : null);
  const rename = (title: string | null) => {
    setRenaming(false);
    if (title === null || !keeper) return;
    api.rename({ thread, session: keeper }, title).catch((error: unknown) => toast(t("web-pages.settings.workspace.renameFailed", { error: failure(error) })));
  };
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
  // A chat keeping watch is archived only once asked.
  const archiveAsked = () => { if (chat.watch) setAskArchive(true); else void archive(); };
  // What the panel shows: its tabs, or while it slides out, what it showed.
  const side = panel && shown ? { tabs: open, shown } : leaving;
  const slackUrl = chat.slackUrl;
  // Before its agent has a chat, the first message makes one, bound to the agent; the page stays (the core shows the
  // chat at the same address once it is there).
  const session = "session" in of && !chat.thread && !made ? of.session : null;
  const firstMessage = session === null ? {} : {
    ensureChat: async () => ({ key: session, thread: (await stationApi(call).chatFor(session)).id }),
  };
  return (
    <div ref={pageRef} className={sessionCss.sessionPage} data-panel={panel || leaving !== null}>
      {chat.watch && <Confirm open={askArchive} title={t("web-pages.chat.archiveConfirm", { title: chat.title })} description={chat.watch.ask} action={t("web-pages.chat.archive")}
        onConfirm={() => { setAskArchive(false); void archive(); }} onClose={() => setAskArchive(false)} />}
      <div className={jobsCss.sessionMain}>
      <header className={sidebarCss.pageBar}>
        <MobileBack to={link("/chats")} label={t("web-pages.decisions.back")} />
        {/* The chat's title, then who is in it: its people, then its agents (each opens its history). */}
        <div className={conversationCss.pageBarTitle}>
          {renaming
            ? <TitleInput value={chat.title} onDone={rename} className={renameCss.titleInputBar} />
            : <ChatTitle station={station.address} session={keeper} title={chat.title} onRename={renamable ? () => setRenaming(true) : undefined} />}
          {renamable && !renaming && <IconButton label={t("web-pages.chat.rename")} icon={Edit} shortcut="chat.rename" className={css.renameBtn} onClick={() => setRenaming(true)} />}
          <StationUpdate station={station.address} notice={chat.stationUpdate} />
          {chat.people.length > 0 && <PeopleStack people={chat.people} max={5} />}
          {agents.map((a) => (
            <Tip key={a.session.key} label={`${a.session.agentText}${a.session.badgeText ? ` · ${a.session.badgeText}` : ""} · ${t("web-pages.chat.history")}`}>
              <button type="button" className={css.agentMarkBtn} onClick={() => toggleHistory(a.session.key)} aria-label={t("web-pages.chat.historyOf", { agent: a.session.agentText })}>
                <AgentMark maker={a.session.maker} runtime={a.session.runtime} badge={a.badge} badgeText={a.session.badgeText} size={20} />
              </button>
            </Tip>
          ))}
        </div>
        <div className={css.pageBarActions}>
          {/* Nothing left in it (the core's `archivable`): archived with one press. */}
          {chat.archivable && keeper && <IconButton label={t("web-pages.chat.archive")} icon={Archive} shortcut="chat.archive" onClick={archiveAsked} />}
          <JobsPanel station={station.address} view={jobsView} onService={(job) => openTab(`service:${job}`)} onTab={openJobs} />
          {chat.thread && <ChatInfo chat={chat} thread={chat.thread} />}
          {slackUrl && (
            <Tip label={t("web-pages.chat.openInSlack")}>
              <a className={pagesCss.iconBtn} href={slackUrl} target="_blank" rel="noopener" aria-label={t("web-pages.chat.openInSlack")}><SlackLogo /></a>
            </Tip>
          )}
          {!panel && agents[0] && <IconButton label={t("web-pages.chat.openPanel")} icon={PanelOpen} shortcut="chat.history" onClick={() => openTab(agents[0]!.session.key)} />}
        </div>
      </header>
      {/* The chat is the page; its agents' histories sit in a tab set that takes the whole right side. */}
      {/* A visualization in a message opens on its own in a tab of the side panel, beside the chat. */}
      <OpenFile.Provider value={(session, file) => openTab(fileTab(session, file.path, file.name))}>
        <ChatPanel chat={chat} draftKey={chatKey} lives={lives} onOpenHistory={openHistory} onArchive={chat.archivable && keeper ? archiveAsked : undefined} {...firstMessage} {...(made ? { made } : {})} />
      </OpenFile.Provider>
      </div>
        {side && (
          <Tabs.Root ref={panelRef} className={css.sidePanel} data-over-composer value={side.shown} onValueChange={setActive} inert={side === leaving}>
            <ResizeHandle variable="--panel-w" edge="left" min={320} max={960} label={t("web-pages.chat.resizePanel")} />
            <div className={css.sideBar}>
              <Tabs.List className={css.sideTabList} aria-label={t("web-pages.chat.history")}>
                {side.tabs.map((key) => {
                  if (key === JOBS) {
                    return (
                      <span key={key} className={css.sideTabWrap}>
                        <Tabs.Trigger className={css.sideTab} value={key}>
                          <span className={css.sideTabAgent}><Boxes size={14} strokeWidth={1.75} /><span className={css.sideTabText} data-text={t("web-pages.chat.jobs")}>{t("web-pages.chat.jobs")}</span></span>
                        </Tabs.Trigger>
                        <button type="button" className={css.sideTabClose} aria-label={t("web-pages.chat.closeJobs")} onClick={() => closeTab(key)}><Close size={12} strokeWidth={2} /></button>
                      </span>
                    );
                  }
                  const file = fileOf(key);
                  if (file) {
                    return (
                      <span key={key} className={css.sideTabWrap}>
                        <Tip label={file.name} cut><Tabs.Trigger className={css.sideTab} value={key}>
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
                        <Tip label={service.name} cut><Tabs.Trigger className={css.sideTab} value={key}>
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
                      <Tip label={label} cut><Tabs.Trigger className={css.sideTab} value={key}>
                        <span className={css.sideTabAgent}><ModelLogo maker={a.session.maker} runtime={a.session.runtime} size={14} /><span className={css.sideTabText} data-text={label}>{label}</span></span>
                      </Tabs.Trigger></Tip>
                      <button type="button" className={css.sideTabClose} aria-label={t("web-pages.chat.closeHistory", { agent: label })} onClick={() => closeTab(key)}><Close size={12} strokeWidth={2} /></button>
                    </span>
                  );
                })}
              </Tabs.List>
              {/* The panel's switch stays in the top-right corner, open or closed. */}
              <IconButton label={t("web-pages.chat.closePanel")} icon={PanelClose} shortcut="panel.close" onClick={() => saveTabs([])} />
            </div>
            {side.tabs.map((key) => {
              if (key === JOBS) {
                return (
                  <Tabs.Content key={key} className={css.sideContent} value={key}>
                    <JobsTab station={station.address} view={jobsView} picked={jobPicked} onPick={pickJob} onService={(job) => openTab(`service:${job}`)} />
                  </Tabs.Content>
                );
              }
              const file = fileOf(key);
              if (file) {
                // Kept as a web service is (Previews.tsx): small in the corner while another chat or page shows.
                return (
                  <Tabs.Content key={key} className={css.sideContent} value={key} forceMount>
                    <PreviewSlot station={station.address} file={file} name={file.name} restarting={null} draftKey={chatKey} />
                  </Tabs.Content>
                );
              }
              const service = jobs.find((j) => j.id === serviceOf(key));
              // Kept loaded while another tab, chat or page shows (Previews.tsx): only closing its tab ends it.
              if (service) {
                return (
                  <Tabs.Content key={key} className={css.sideContent} value={key} forceMount>
                    {service.port != null && (service.state === "running" || service.state === "exited")
                      ? <PreviewSlot station={station.address} port={service.port} name={service.name} service={service.id} restarting={service.state === "exited" ? { restarts: service.restarts ?? 0 } : null} draftKey={chatKey} />
                      : <Empty><p>{service.state === "failed" ? t("web-pages.chat.serviceFailed", { name: service.name }) : t("web-pages.chat.serviceStopped", { name: service.name })}</p></Empty>}
                  </Tabs.Content>
                );
              }
              const a = agents.find((x) => x.session.key === key);
              if (!a) return <Tabs.Content key={key} className={css.sideContent} value={key} />;
              return (
                <Tabs.Content key={key} className={css.sideContent} value={key}>
                  <History station={station.address} sessionKey={key} actions={<SessionActions session={a.session} status={a.status} />}
                    focus={focus?.key === key ? focus : null}
                    summary={<HistorySummary agent={a} />}
                    details={<SessionDetails agent={a} />} />
                </Tabs.Content>
              );
            })}
          </Tabs.Root>
        )}
    </div>
  );
}

/** The 任务 tab's key: every service and job of the chat's agents. */
const JOBS = "jobs";

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
function JobsPanel({ station, view, onService, onTab }: { station: string; view: ChatJobsView; onService: (job: string) => void; onTab: (job?: string) => void }) {
  const [open, setOpen] = useState(false);
  const alarm = view.alarm;
  const close = (then: () => void) => { setOpen(false); then(); };
  return (
    <Popover.Root open={open} onOpenChange={setOpen}>
      <Tip label={t("web-pages.chat.services")} shortcut="chat.jobs">
        <Popover.Trigger asChild>
          <button type="button" className={`${pagesCss.iconBtn} ${css.jobsTrigger}`} aria-label={t("web-pages.chat.services")} data-alarm={alarm} data-none={view.jobs.length === 0 || undefined}><Web {...ICON} /></button>
        </Popover.Trigger>
      </Tip>
      <Popover.Portal>
        <Popover.Content className={`${controlsCss.popover} ${css.jobsPanel}`} align="end" sideOffset={6} collisionPadding={8}>
          <JobsPopover station={station} view={view} onService={(job) => close(() => onService(job))} onTab={(job) => close(() => onTab(job))} />
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
function ChatInfo({ chat, thread }: { chat: ChatView; thread: ChatThread }) {
  const link = useLink();
  const connect = slackConnect(chat);
  const row = (label: string, value: ReactNode) => <div className={css.detailRow}><dt>{label}</dt><dd>{value}</dd></div>;
  const where = chat.place;
  return (
    <Popover.Root>
      <Tip label={t("web-pages.chat.info")}>
        <Popover.Trigger asChild>
          <button type="button" className={pagesCss.iconBtn} aria-label={t("web-pages.chat.info")}><Info {...ICON} /></button>
        </Popover.Trigger>
      </Tip>
      <Popover.Portal>
        <Popover.Content className={`${controlsCss.popover} ${css.chatInfo}`} align="end" sideOffset={6} collisionPadding={8}>
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
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
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
            <span className={`${css.attention} ${css.attentionQuota}`}><QuotaRing left={a.quota.left} level={a.quota.level} size={20} /><span className="quota-ring-letter">{a.quota.mark}</span></span>
          </Tip>
        ) : (
          <span key={i} className={css.attention} data-tone={a.kind === "disk" ? "amber" : "red"}>{a.text}</span>
        )
      ))}
    </span>
  );
}

/**
 * Unfolded under the history's head, by how much each thing matters: the account it runs on (with its quota) first,
 * which can be changed here, or left to the station; then the model and effort; then what it has used; the station
 * last, folded. Changes take from its next turn on.
 */
function SessionDetails({ agent }: { agent: ChatAgent }) {
  const { session } = agent;
  const station = useStation();
  const link = useLink();
  const toast = useToast();
  const host = useHost(station.address).value;
  // What it runs on and what its control's panel picked, as the core has them (../pick.ts).
  const pick = usePick(station.address, `session:${session.key}`);
  const change = useAction(() => pick.save(), () => toast(t("web-pages.chat.pickSaved")));
  const usage = useHistory(station.address, session.key).value?.usageLine;
  return (
    <div className={css.sessionDetails}>
      {/* How it runs, in one row: the model, how hard it thinks, then the account it runs on (with its quota). */}
      <ModelTriple pick={pick} onConfirm={() => void change.run()} />
      {change.error && <p className={controlsCss.fieldError} role="alert">{change.error.message}</p>}
      {/* What it used: a line, quiet. */}
      <p className={`${css.runUsage} ${shellCss.muted}`}>
        {session.runtimeText} · {session.processText}
        {usage && <> · {usage}</>}
        {" · "}<Link className={css.detailLink} to={link(`/settings/accounts/${session.profile}`)}>{t("web-pages.chat.profileDetails")}</Link>
      </p>
      {/* The station it runs on, and how loaded it is. */}
      <div className={css.runStation}>
        <p className={shellCss.muted}>{station.name || host?.hostname || t("web-pages.chat.thisMachine")}{host ? ` · ${host.summary}` : ""}</p>
        {host && (
          <div className={css.resourceRings}>
            {host.meters.map((m) => <Ring key={m.label} percent={m.percent} level={m.level} label={m.short} title={`${m.label} ${m.value}`} />)}
          </div>
        )}
      </div>
    </div>
  );
}

/**
 * The chat's name in its bar: while a new one goes (`chat.rename`), that one, a turning ring beside it; its own again if
 * it did not, a red mark there a few seconds saying why.
 */
function ChatTitle({ station, session, title, onRename }: { station: string; session: string | null; title: string; onRename: (() => void) | undefined }) {
  const renamingTo = useRenaming(station, session);
  const renameFailed = useDoingFailed("chat.rename", { station, session: session ?? "" });
  return (
    <>
      <h1 onDoubleClick={onRename}>{renamingTo ?? title}</h1>
      <DoingShown state={{ running: renamingTo !== undefined, error: session === null ? undefined : renameFailed }} className={controlsCss.iconSpinner} size={14} label={t("web-pages.settings.stations.renaming")} />
    </>
  );
}

/** What can be done to it right now: stop a turn, release an idle process. */
function SessionActions({ session, status }: { session: Session; status: Status }) {
  const api = useApi();
  const act = useAct();
  const station = useStation().address;
  // Under way: the button turns, wherever it was asked from (the shortcut too); failed, a red mark there a few seconds.
  const stopping = useDoing("session.stop", { station, key: session.key });
  const evicting = useDoing("session.evict", { station, key: session.key });
  const stopFailed = useDoingFailed("session.stop", { station, key: session.key });
  const evictFailed = useDoingFailed("session.evict", { station, key: session.key });
  return (
    <>
      {(status === "running" || status === "queued") && <IconButton label={t("web-pages.chat.stopTurn")} icon={Stop} shortcut="chat.stop" busy={stopping} failed={stopFailed}
        onClick={() => act(api.stop(session.key), t("web-pages.chat.stop"), t("web-pages.chat.stopAsked"))} />}
      {session.process === "warm" && <IconButton label={t("web-pages.chat.evict")} icon={Unplug} busy={evicting} failed={evictFailed} onClick={() => act(api.evict(session.key), t("web-pages.chat.evict"), t("web-pages.chat.evicted"))} />}
    </>
  );
}
