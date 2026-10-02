// An item's page on a narrow screen: its chat's messages (none before its agent has a chat), the composer, and each
// agent's execution history as a page opened from its mark or name. The messages are the wide screen's own (../Chat.tsx:
// the same rows, avatars, names, quotes, files, activity and list behaviour), with the avatar and name in line with the
// words rather than out in a margin. Long-press opens a message on its own page (Annotate.tsx); ＋ adds files.
import { useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode, type RefObject } from "react";
import { useLocation, useNavigate, useParams } from "react-router";
import { useReady } from "../core/react.ts";
import { stationApi, useApi, useChat, useChatJobs, useLives, useStationCall, type ChatMessage, type ChatThread, type ChatView, type Quote } from "../api.ts";
import { draftKeyOf, useHost, type HostComposer } from "./ChatHost.tsx";
import { DraftKey } from "../draft.ts";
import { OpenFile } from "../Viz.tsx";
import { fileService } from "../Preview.tsx";
import type { Draft as SharedDraft } from "../draft.ts";
import { chatImages, Gallery } from "../FilePreview.tsx";
import { ChatRows, historyLinkClicked, ownerIn, ownersOf, sendDraft, useAskedFile, useComposerText, useMessageList, useSelectionQuote } from "../Chat.tsx";
import { Archive, ArrowDown, ArrowUp, Camera, ChevronRight, ChevronLeft, File, More, Photo, Pin, Plus, Stop, Web } from "../icons.tsx";
import { stationBase, useStation } from "../station.tsx";
import { PENDING } from "../lastChat.ts";
import { SheetGrab, SheetHead, useApp, type MobileApp } from "./app.tsx";
import { ask, confirm } from "./sheets.tsx";
import { openHistory } from "./History.tsx";
import { annotatePath } from "./Annotate.tsx";
import { GroupLabel, InfoList, InfoRow, ModelMark, NavButton, QuotaRings, Seg, SlackMark, Spinner, stateOf } from "./parts.tsx";
import { AgentMark } from "../ui.tsx";
import { PeopleStack } from "../components.tsx";
import { JobDot, metaOf, NO_JOBS, useClearEnded, useJobLog, useStopJob } from "../Jobs.tsx";
import { stillfailLinkClicked } from "../stillfailLink.ts";
import { doingMatches, failed, useDoing, useDoingFailed, useDoingList } from "../doing.ts";
import type { ChatJobsView, Job } from "../core/shapes.ts";
import * as chatCss from "./styles/chat.css.ts";
import * as hostCss from "./ChatHost.css.ts";
import { sendingHere } from "../madeChat.ts";
import * as css from "./Chat.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as rootCss from "./styles/root.css.ts";
import * as sharedCss from "../Chat.css.ts";
import * as conversationCss from "../styles/conversation.css.ts";
import * as chatCss2 from "../styles/chat.css.ts";
import * as barsCss from "./styles/bars.css.ts";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as homeCss from "./styles/home.css.ts";
import * as listsCss from "./styles/lists.css.ts";

import { NAME } from "../channel.ts";
export function ChatScreen() {
  const { chat: address = "" } = useParams();
  // A chat made here keeps the key the core gave it when its address becomes its station's (below).
  const key = openedAs(address);
  const station = useStation();
  // A service's link (`?service=<job>`, from Slack): the service, full screen, over the chat.
  const app = useApp();
  const asked = new URLSearchParams(useLocation().search).get("service");
  useEffect(() => {
    if (asked) app.push(servicePath(station.address, key, asked));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [asked]);
  // The page slides in once its chat is read (from the device, mostly at once; 250 ms at most), not empty.
  useReady({ topic: "chat", station: station.address, session: key }, 250);
  const chat = useChat(station.address, { session: key });
  const view = chat.value;
  const navigate = useNavigate();
  const stationKey = key.startsWith(PENDING) ? view?.key : undefined;
  useEffect(() => {
    if (!stationKey) return;
    renamed.set(stationKey, key);
    navigate(`${stationBase(station.address)}/chats/${encodeURIComponent(stationKey)}`, { replace: true });
  }, [stationKey]);
  const lives = useLives(station.address, (view?.agents ?? []).map((a) => a.session.key));
  // Until the core has the chat, the page is already a chat's page (its bar, empty): what comes fills it in place.
  if (!view) {
    return (
      <div className={chatCss.mChat}>
        <BarFrame title="" more={false} />
        <div className={`${css.mCenter} ${partsCss.mMuted}`}>{chat.error ? `读不到这个对话：${chat.error.message}` : null}</div>
      </div>
    );
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
  const floor = useRef<HTMLDivElement>(null);
  // The page's composer is its host's (ChatHost.tsx): kept as a new chat becomes this chat.
  const { draft, use } = useHost();
  const here: Here = { station: station.address, key: sessionKey, view };
  useComposer(view, here, draft, use, list);
  return (
    <div className={chatCss.mChat}>
      <Messages view={view} lives={lives} list={list} floor={floor} draft={draft} here={here} stationName={station.name} />
      <ChatBar view={view} here={here} />
    </div>
  );
}

/** The chat's bar: back, its title, then its people, then its agents' marks (each opens its history), as the wide screen's title has them; "…" is the chat's own sheet. */
function ChatBar({ view, here }: { view: ChatView; here: Here }) {
  const app = useApp();
  const thread = view.thread;
  const jobs = useChatJobs(here.station, { session: here.key }).value;
  return (
    <BarFrame title={view.title} more={!!thread} onMore={() => thread && openChatInfo(app, here, thread)}
      trailing={<>
        {/* Nothing left in it (the core's `archivable`): archived with one tap. */}
        {view.archivable && thread && <ArchiveButton here={here} view={view} thread={thread} />}
        {jobs && jobs.jobs.length > 0 && <JobsButton here={here} alarm={jobs.alarm} />}
      </>}>
      <PeopleStack people={view.people} max={5} />
      {view.agents.map((a) => (
        <button key={a.session.key} type="button" className={css.mBarAgent} onClick={() => openHistory(app, here.station, here.key, a.session.key)} aria-label={`${a.session.agentText} 的执行历史`}>
          <AgentMark maker={a.session.maker} runtime={a.session.runtime} badge={a.badge} badgeText={a.session.badgeText} size={22} />
        </button>
      ))}
    </BarFrame>
  );
}

/** The bar's frame, the same while the chat loads and once it has: back, the title, what follows it, what is at its end, and "…". */
export function BarFrame({ title, more, onMore, trailing, children }: { title: string; more: boolean; onMore?: () => void; trailing?: ReactNode; children?: ReactNode }) {
  const app = useApp();
  return (
    <header className={`${css.mChatBar} ${pagesCss.mGlass}`}>
      <button type="button" className={css.mChatBack} onClick={app.pop} aria-label="返回"><ChevronLeft size={22} /></button>
      <span className={css.mChatBarTitle}><b>{title}</b>{children}</span>
      {trailing}
      {more && onMore && <NavButton icon={More} label="对话信息" onClick={onMore} />}
    </header>
  );
}

// ── the list ───────────────────────────────────────────────────────────

/** The wide screen's list (../Chat.tsx's ChatRows), in the page: over it, the bar; under it, the composer. */
function Messages({ view, lives, list, floor, draft, here, stationName }: {
  view: ChatView; lives: ReturnType<typeof useLives>; list: RefObject<HTMLDivElement | null>; floor: RefObject<HTMLDivElement | null>; draft: Draft; here: Here;
  stationName?: string | undefined;
}) {
  const app = useApp();
  const rows = useMessageList(list, floor, view, `${here.station}:${view.thread?.id ?? here.key}`, lives);
  // A chat made here is sent to by its key until its thread is known.
  const to = view.thread?.id ?? (here.key.startsWith(PENDING) ? here.key : null);
  const images = () => chatImages([...rows.messages, ...view.outbox.map((o) => ({ authorKind: "person", ...o }))], (f) => ownerIn(view, f));
  // The messages are kept as they are while nothing they show changes: what they are handed stays the same function,
  // the latest one behind it.
  const archive = useArchiveChat(here, view, view.thread ?? null);
  const latest = useRef({ here, draft, images, app, archive });
  latest.current = { here, draft, images, app, archive };
  const [stable] = useState(() => ({
    owner: (file: Parameters<typeof ownerIn>[1]) => ownerIn(latest.current.here.view, file),
    open: (key: string) => { const { app, here } = latest.current; openHistory(app, here.station, here.key, key); },
    quote: (q: Omit<Quote, "comment">) => latest.current.draft.quote(q),
    images: () => latest.current.images(),
    hold: (ts: string) => { const { app, here } = latest.current; app.push(annotatePath(here.station, here.key, ts)); },
    archive: () => latest.current.archive(),
  }));
  // Words selected with a mouse inside one message offer to quote them; a finger holds a message for its menu.
  const quoting = useSelectionQuote(list, stable.quote);
  const hold = useHold(list, rows.messages, stable.hold);
  const askedFile = useAskedFile(list, rows.messages, (f) => ownerIn(view, f));
  // ember's own links (/o/<workspace>/<station>/<session>, as agents post them) open here, as pages over this one (the
  // chat and what is being written stay under them): one of this chat's agents' web services, or another session. A
  // link to an agent's execution history opens it.
  const onClick = (event: React.MouseEvent) => {
    const history = historyLinkClicked(event);
    if (history) {
      event.preventDefault();
      openHistory(app, here.station, here.key, history.key);
      return;
    }
    const link = stillfailLinkClicked(event);
    if (!link) return;
    if (link.service && view.agents.some((a) => a.session.key === link.session)) {
      event.preventDefault();
      app.push(servicePath(here.station, here.key, link.service));
    } else if (link.sameOrigin) {
      event.preventDefault();
      const path = `/w/${link.workspace}/s/${link.station}/chats/${encodeURIComponent(link.session)}`;
      if (`${path}${link.search}` !== `${stationBase(here.station)}/chats/${encodeURIComponent(here.key)}`) app.push(`${path}${link.search}`);
    }
  };
  return (
    <OpenFile.Provider value={(session, file) => app.push(servicePath(here.station, here.key, fileService({ session, path: file.path, name: file.name })))}>
      {quoting.pop}
      {askedFile}
      <Gallery.Provider value={stable.images}>
      <div className={`${chatCss.mMessages} ${sharedCss.chatMessages} ${sharedCss.inlineHeads} ${rootCss.wide}`} ref={list} onClick={onClick} {...quoting.listProps} {...hold}>
        <DraftKey.Provider value={draftKeyOf(here.station, here.key)}>
          <ChatRows chat={view} rows={rows} to={to} owners={ownersOf(view)} owner={stable.owner} onOpenHistory={stable.open} onArchive={view.thread ? stable.archive : undefined} />
        </DraftKey.Provider>
        <div ref={floor} className={chatCss2.chatFloor} aria-hidden="true" />
      </div>
      </Gallery.Provider>
      {/* Over the send button, in line with it; it comes up growing and goes the way it came. */}
      {/* Short of the chat's end (a window of it), with how many new messages wait there. */}
      <button type="button" className={`${css.mJump} ${pagesCss.mFloating}`} data-shown={rows.away || undefined} data-count={rows.waiting > 0 || undefined}
        aria-label="跳到最新" onClick={rows.toEnd}><ArrowDown size={18} />{rows.waiting > 0 && <span>{rows.waiting} 条新消息</span>}</button>
    </OpenFile.Provider>
  );
}

/** A message's words as read, without markdown's marks: what a quote carries. */
function plain(text: string): string {
  return text.replace(/[`*#>]/g, "").replace(/\s+/g, " ").trim();
}

/**
 * Long-press on a message in the list (a right click with a mouse): its page, to pick passages of it to say something
 * about or to copy (Annotate.tsx). Not on what does its own thing in it (a name, a quote, a file).
 */
function useHold(list: RefObject<HTMLElement | null>, messages: ChatMessage[], onHold: (ts: string) => void) {
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const touched = useRef(false);
  const shown = useRef(messages);
  shown.current = messages;
  const held = (event: React.SyntheticEvent) => {
    const at = event.target as Element;
    const row = at.closest?.<HTMLElement>("[data-author][data-ts]");
    if (!row || !list.current?.contains(row) || at.closest("button, input, textarea")) return null;
    const m = shown.current.find((x) => x.ts === row.dataset.ts);
    if (!m || m.system || !m.text.trim()) return null;
    const words = row.querySelector<HTMLElement>(`.${conversationCss.msgBubble}, .${conversationCss.markdown}, .${chatCss2.msgPlain}`) ?? row;
    return { m, words };
  };
  const open = ({ m, words }: NonNullable<ReturnType<typeof held>>) => {
    // Marked for a moment as the page comes over it.
    words.dataset.pressed = "";
    setTimeout(() => { delete words.dataset.pressed; }, 600);
    navigator.vibrate?.(10);
    onHold(m.ts);
  };
  const cancel = () => clearTimeout(timer.current);
  // A finger holds for the menu; a mouse right-clicks for it (and selects words to quote a passage of them).
  return {
    onPointerDown: (e: React.PointerEvent<HTMLElement>) => {
      touched.current = e.pointerType !== "mouse";
      cancel();
      const at = touched.current ? held(e) : null;
      if (at) timer.current = setTimeout(() => open(at), 480);
    },
    onPointerUp: cancel, onPointerCancel: cancel,
    onPointerMove: (e: React.PointerEvent) => { if (Math.abs(e.movementY) > 4 || Math.abs(e.movementX) > 4) cancel(); },
    // A right click opens it; a long press, where the browser asks for its own menu too, already has.
    onContextMenu: (e: React.MouseEvent<HTMLElement>) => {
      const at = held(e);
      if (!at) return;
      e.preventDefault();
      if (!touched.current) open(at);
    },
  };
}

// ── the composer ───────────────────────────────────────────────────────

/** What is being written (../draft.ts), and asking for the field's focus (a quote's comment done, a tap on the capsule). */
export type Draft = SharedDraft & { focus: number; bumpFocus(): void };

/** ＋: take a photo, pick photos, pick files. */
export function openAttach(app: MobileApp, onPicked: (files: FileList) => void) {
  const pick = (accept: string, capture: boolean) => {
    const input = document.createElement("input");
    input.type = "file";
    input.accept = accept;
    input.multiple = !capture;
    if (capture) input.setAttribute("capture", "environment");
    input.onchange = () => { if (input.files?.length) onPicked(input.files); };
    input.click();
  };
  app.sheet({
    height: 0.32,
    content: () => (
      <>
        <SheetGrab />
        <SheetHead title="添加到消息" />
        <div className={css.mAttach}>
          {([["拍照", <Camera key="c" size={24} />, () => pick("image/*", true)], ["照片", <Photo key="p" size={24} />, () => pick("image/*", false)], ["文件", <File key="f" size={24} />, () => pick("*/*", false)]] as const).map(([label, icon, go]) => (
            <button key={label} type="button" onClick={() => { app.sheet(null); go(); }}>{icon}<span>{label}</span></button>
          ))}
        </div>
      </>
    ),
  });
}

/**
 * The bar, inside a floating capsule that is its frame: ＋, the wide screen's text box (../Chat.tsx's useComposerText:
 * @-references, pasted files, what a preview offers `draftKey`; growing to six lines here, and Enter starting a line on
 * a touch keyboard), and a round send button (a spinner while a new chat is made). The menu of chats goes over the
 * capsule (`menu`).
 */
export function useComposerBar({ draft, draftKey, sessionKey, placeholder, locked = false, onPlus, onType, onSend }: {
  draft: Draft; draftKey: string | undefined; sessionKey: string | null; placeholder: string; locked?: boolean;
  onPlus: () => void; onType: () => void; onSend: () => void;
}): { menu: ReactNode; bar: ReactNode } {
  const input = useRef<HTMLTextAreaElement>(null);
  const ready = draft.ready && !locked;
  useEffect(() => { if (draft.focus > 0) input.current?.focus(); }, [draft.focus]);
  const { menu, field } = useComposerText({
    draft, input, draftKey, sessionKey, locked, placeholder, className: css.mComposerField, lines: 6,
    enterSends: window.matchMedia("(hover: hover)").matches, onType, onSubmit: () => { if (ready) onSend(); },
  });
  const bar = (
    <div className={css.mComposerBar}>
      <button type="button" className={css.mPlus} onClick={onPlus} disabled={locked} aria-label="添加文件"><Plus size={18} /></button>
      {field}
      <button type="button" className={css.mSend} data-ready={ready || undefined} disabled={!ready} onClick={onSend} aria-label="发送">
        {draft.starting ? <Spinner size={16} color="var(--m-surface)" /> : <ArrowUp size={18} />}
      </button>
    </div>
  );
  return { menu, bar };
}

/**
 * What the chat's composer (its host's, ChatHost.tsx) writes to: this chat, as the wide screen's composer sends
 * (../Chat.tsx's sendDraft). The composer empties at once: the message lives in the chat's outbox until the station has
 * it (a failure shows there too). Before the agent has a chat, the first message makes one, bound to the agent, and the
 * page stays (the core shows the chat at the same address).
 */
function useComposer(view: ChatView, here: Here, draft: Draft, use: (spec: HostComposer) => void, list: RefObject<HTMLDivElement | null>) {
  const api = useApi();
  const call = useStationCall(here.station);
  const keeper = view.agents[0]?.session.key ?? null;
  const warmed = useRef(0);
  const send = (draft: Draft) => {
    if (view.offline || view.archived) return;
    // A chat made here is sent to by its key until its thread is known.
    const to = view.thread?.id ?? (here.key.startsWith(PENDING) ? here.key : null);
    // Its words stay where they were typed until its row is in the list, then go there (../madeChat.ts), over the composer.
    const into = list.current;
    const host = into?.closest<HTMLElement>(`.${hostCss.mChatHost}`);
    const field = host?.querySelector<HTMLElement>(`[data-made-composer] textarea:not([aria-hidden])`);
    into?.dispatchEvent(new Event("sent"));
    if (into && host && field) sendingHere(field, draft.text, { layer: host, z: "7", list: into });
    void sendDraft(draft, to, async () => ({ thread: (await stationApi(call).chatFor(here.key)).id }));
  };
  useLayoutEffect(() => use({
    station: here.station, session: keeper, placeholder: view.archived ? "还原对话后才能发送" : "发消息", offline: view.offline, archived: !!view.archived, send,
    restore: () => api.archive({ thread: view.thread?.id ?? null, session: here.key }, false),
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
function JobsButton({ here, alarm }: { here: Here; alarm: string | undefined }) {
  const app = useApp();
  return (
    <button type="button" className={`${barsCss.mNavButton} ${css.mJobsTrigger}`} aria-label="服务和后台任务" onClick={() => openJobs(app, here)}>
      <Web size={18} />
      {alarm && <span className={css.mJobsAlarm} data-alarm={alarm} aria-hidden="true" />}
    </button>
  );
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
      <SheetHead title="服务和后台任务" />
      <div className={`${sheetsCss.mSheetScroll} ${partsCss.mPad18}`}>
        {jobs.length === 0 && <div className={css.mJobsEmpty}><b>还没有服务或后台任务</b><span>agent 开网页、或挂上长期盯着的任务时，会列在这里。</span></div>}
        {jobs.length > 0 && shown.length === 0 && <p className={homeCss.mNote}>眼下没有在跑的服务或任务。</p>}
        <JobGroups here={here} view={view} jobs={shown} notes />
        {jobs.length > view.current && (
          <button type="button" className={css.mJobsAll} onClick={() => setAll(!all)}>
            {all ? "只看眼下的" : <>{view.allText}<span>{view.hiddenText}</span></>}
          </button>
        )}
        {view.ended > 0 && (
          <button type="button" className={css.mJobsAll} data-busy={clearing || undefined} disabled={clearing} onClick={() => clear(view.clear)}>
            <span className={css.mJobsAllLine}>{clearing && <Spinner size={13} />}{view.clearText}</span>
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
          <GroupLabel>服务{notes && view.servicesNote ? ` · ${view.servicesNote}` : ""}</GroupLabel>
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
          <GroupLabel>后台任务{notes && view.jobsNote ? ` · ${view.jobsNote}` : ""}</GroupLabel>
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
  if (!job) return <><SheetGrab /><SheetHead title="任务" />{jobs.value && <p className={homeCss.mNote}>这个任务已经不在了。</p>}</>;
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
        {!service && <Seg options={["通知", "输出"]} selected={tab} onSelect={setTab} fill height={34} />}
        {tab === 0
          ? (
            <div className={css.mJobNotices}>
              {(job.notices ?? []).length === 0 && <p className={homeCss.mNote}>还没有通知。</p>}
              {(job.notices ?? []).map((n, i) => <p key={`${n.at}-${i}`}><time>{n.clock}</time><span>{n.text}</span></p>)}
            </div>
          )
          : <JobOutput station={station} job={job} />}
        {tab === 0 && said && <div className={css.mJobLast}><span>{said}</span>{last?.last && <code>{last.last}</code>}</div>}
        {running && <button type="button" className={css.mJobStop} disabled={stopping} onClick={() => stop(job)}>{stopping ? <Spinner size={16} color="var(--m-red)" /> : <Stop size={16} />}{stopping ? "正在停止…" : "停止"}</button>}
        {running && !stopping && stopFailed !== undefined && <p className={partsCss.mError}>没能停止：{stopFailed}</p>}
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
    if (el && atEnd.current) el.scrollTop = el.scrollHeight;
  }, [log?.text]);
  return (
    <pre ref={box} className={css.mJobOutput} onScroll={(e) => { const el = e.currentTarget; atEnd.current = el.scrollHeight - el.scrollTop - el.clientHeight < 24; }}>
      {log === null ? "正在读取…" : log.text || "（还没有输出）"}
    </pre>
  );
}

// ── the chat's own sheet ───────────────────────────────────────────────

/** The chat itself: where it came from, who started it and takes part, its agents (each leads to its history). */
function openChatInfo(app: MobileApp, here: Here, thread: ChatThread) {
  app.sheet({ height: 0.72, draggable: true, content: () => <ChatInfo here={here} thread={thread} /> });
}

function ChatInfo({ here, thread: first }: { here: Here; thread: ChatThread }) {
  const app = useApp();
  const view = useChat(here.station, { session: here.key }).value ?? here.view;
  const jobs = useChatJobs(here.station, { session: here.key }).value ?? NO_JOBS;
  const thread = view.thread ?? first;
  const call = useStationCall(here.station);
  const pinning = useDoing("chat.pin", { station: here.station, session: here.key });
  const pinFailed = useDoingFailed("chat.pin", { station: here.station, session: here.key });
  return (
    <>
      <SheetGrab />
      <SheetHead title="对话信息" />
      <div className={`${sheetsCss.mSheetScroll} ${partsCss.mPad18}`}>
        {!view.archived && !view.offline && (
          <InfoList>
            <InfoRow onClick={() => ask(app, {
              title: "重命名对话", value: view.title, placeholder: "对话名称", action: "保存", empty: true, hint: "留空则用第一句话作名字",
              run: (title) => stationApi(call).rename({ thread: thread.id, session: here.key }, title),
            })}>
              <span className={css.mInfoLabel}>名称</span><span className={`${partsCss.mGrow} ${css.mInfoName}`}>{view.title}</span><ChevronRight size={14} className={partsCss.mSubtle} />
            </InfoRow>
            {/* A station from before pins says nothing of them: its chats are not pinned from here. */}
            {view.pinned != null && (
              <InfoRow busy={pinning} failed={pinFailed} onClick={() => { stationApi(call).pin({ session: here.key }, !view.pinned)
                .catch((error) => app.toast(`没能${view.pinned ? "取消固定" : "固定"}：${error instanceof Error ? error.message : String(error)}`)); }}>
                <Pin size={16} /><span className={partsCss.mGrow}>{view.pinned ? "取消固定" : "固定到列表顶部"}</span>
              </InfoRow>
            )}
          </InfoList>
        )}
        <InfoList>
          <InfoDetail label="来自" value={view.place ? `Slack · ${view.place}` : `${NAME} 对话`} />
          <InfoDetail label="发起" value={thread.creator?.shown?.display ?? "未记录"} />
          <InfoDetail label="参与" value={`${view.people.length} 人`} extra={<PeopleStack people={view.people} max={8} />} />
          <InfoDetail label="创建" value={thread.time?.createdAt?.ago ?? ""} />
          {thread.lastMessage && <InfoDetail label="最近消息" value={thread.lastMessage.time?.createdAt?.ago ?? ""} />}
        </InfoList>
        <JobGroups here={here} view={jobs} jobs={jobs.jobs} />
        {view.slackUrl && (
          <>
            <GroupLabel>在 Slack 里</GroupLabel>
            <InfoList><a className={listsCss.mInfoRow} href={view.slackUrl} target="_blank" rel="noopener"><SlackMark size={16} /><span className={partsCss.mGrow}>在 Slack 中打开</span><ChevronRight size={14} className={partsCss.mSubtle} /></a></InfoList>
          </>
        )}
        {view.agents.length > 0 && (
          <>
            <GroupLabel>参与的 agent · 点开看它的执行历史</GroupLabel>
            <InfoList>
              {view.agents.map((a) => {
                const s = a.session;
                // The account it runs on now, with what is left of it (so a glance here saves the trip to settings).
                const account = a.account ?? a.profile;
                return (
                  <InfoRow key={s.key} onClick={() => openHistory(app, here.station, here.key, s.key)}>
                    <ModelMark maker={s.maker} runtime={s.runtime} size={36} state={stateOf(a.badge)} around="var(--m-surface2)" />
                    <span className={`${partsCss.mGrow} ${css.mInfoAgent}`}>
                      <b>{s.agentText}</b>
                      <span>{a.connect && <SlackMark size={11} />}{[a.connect?.name, account?.name, s.processText, s.time?.lastActiveAt?.ago].filter(Boolean).join(" · ")}</span>
                    </span>
                    <QuotaRings quota={account?.quota} />
                    <ChevronRight size={14} className={partsCss.mSubtle} />
                  </InfoRow>
                );
              })}
            </InfoList>
          </>
        )}
        {!view.archived && !view.offline && <ArchiveRow here={here} view={view} thread={thread} />}
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
  // At once: the list's row says it is under way (Home.tsx), the toast how it ended.
  const archive = () => {
    app.sheet(null);
    app.pop();
    api.archive(of, true).then(() => app.toast("已归档"), (error) => app.toast(`没能归档：${error instanceof Error ? error.message : String(error)}`));
  };
  // Asked first: its sheet waits and says what went wrong; back to the list once it is done.
  const asked = () => api.archive(of, true).then(() => { app.pop(); app.toast("已归档"); });
  return (
    <>
      <GroupLabel>归档</GroupLabel>
      <InfoList>
        {/* A chat keeping watch is archived only once asked: its watch runs on in the archive (the core's words). */}
        <InfoRow onClick={() => view.watch ? confirm(app, { title: `归档「${view.title}」？`, text: view.watch.ask, action: "归档", run: asked }) : archive()}><Archive size={16} /><span className={partsCss.mGrow}>归档对话</span></InfoRow>
      </InfoList>
    </>
  );
}

/** In the bar while nothing is left in the chat: archives it with one tap, back to the list at once (as ArchiveRow). */
function ArchiveButton({ here, view, thread }: { here: Here; view: ChatView; thread: ChatThread }) {
  const archive = useArchiveChat(here, view, thread);
  return <NavButton icon={Archive} label="归档" onClick={archive} />;
}

/** Archives the chat and leaves its page (a chat keeping watch once asked): the bar's 归档, and the one in the list. */
function useArchiveChat(here: Here, view: ChatView, thread: ChatThread | null) {
  const app = useApp();
  const call = useStationCall(here.station);
  const api = useMemo(() => stationApi(call), [call]);
  const of = { thread: thread?.id ?? null, session: view.agents[0]?.session.key ?? here.key };
  return () => {
    if (view.watch) {
      confirm(app, { title: `归档「${view.title}」？`, text: view.watch.ask, action: "归档", run: () => api.archive(of, true).then(() => { app.pop(); app.toast("已归档"); }) });
      return;
    }
    app.pop();
    api.archive(of, true).then(() => app.toast("已归档"), (error) => app.toast(`没能归档：${error instanceof Error ? error.message : String(error)}`));
  };
}

function InfoDetail({ label, value, extra }: { label: string; value: string; extra?: ReactNode }) {
  return <InfoRow><span className={css.mInfoLabel}>{label}</span>{extra}<span className={partsCss.mGrow}>{value}</span></InfoRow>;
}
