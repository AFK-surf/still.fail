// An item's page on a narrow screen, as the Android app has it (apps/android/…/screens/Chat.kt): its chat's messages
// (none before its agent has a chat), the composer, and each agent's execution history as a sheet opened from its mark
// or name. Your messages sit right in a bubble; everyone else gets a face, a name and the time over their words.
// Long-press quotes or copies a message; ＋ adds files. The list's behaviour (following its end, older pages, what is
// read, the unread line, where it was left, messages coming out of an agent's avatar) is the desktop's (../Chat.tsx).
import { useEffect, useLayoutEffect, useRef, useState, type ReactNode, type RefObject } from "react";
import { useLocation, useParams } from "react-router";
import { useApi, useChat, useChatSend, useLives, useStationCall, type Attachment, type ChatAgent, type ChatMessage, type ChatThread, type ChatView, type Outgoing, type Quote } from "../api.ts";
import { useHost, type HostComposer } from "./ChatHost.tsx";
import { Activity, fileSize, Lightbox, useAwayFromBottom, useEmissions, useFileUrl, useLinger, useMarkRead, useOlderOnScroll, useRememberPlace, useUnreadLine, type AgentAtWork } from "../Chat.tsx";
import { ArrowDown, ArrowUp, Camera, ChevronLeft, ChevronRight, Close, Copy, File, More, Photo, Plus, Quote as QuoteIcon, Stop, Web } from "../icons.tsx";
import { Prose } from "../Prose.tsx";
import { useStickToBottom } from "../scroll.ts";
import { stationBase, useStation } from "../station.tsx";
import { ask } from "./sheets.tsx";
import { SheetGrab, SheetHead, useApp, type MobileApp } from "./app.tsx";
import { openHistory } from "./History.tsx";
import { Avatar, GroupLabel, InfoList, InfoRow, Mark, ModelMark, NavButton, PeopleStack, Seg, SlackMark, Spinner, stateOf } from "./parts.tsx";
import { ago, alarmOf, clock, isCurrent, isService, JobDot, metaOf, sorted, toneOf, useJobLog, useNow, useStopJob, type Tone } from "../Jobs.tsx";
import { emberLinkClicked } from "../emberLink.ts";
import type { Job } from "../core/shapes.ts";

export function ChatScreen() {
  const { chat: key = "" } = useParams();
  const station = useStation();
  // A service's link (`?service=<job>`, from Slack): the service, full screen, over the chat.
  const app = useApp();
  const asked = new URLSearchParams(useLocation().search).get("service");
  useEffect(() => {
    if (asked) app.push(servicePath(station.address, key, asked));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [asked]);
  const chat = useChat(station.address, { session: key });
  const view = chat.value;
  const lives = useLives(station.address, (view?.agents ?? []).map((a) => a.session.key));
  // Until the core has the chat, the page is already a chat's page (its bar, empty): what comes fills it in place.
  if (!view) {
    return (
      <div className="m-chat">
        <BarFrame title="" more={false} />
        <div className="m-center m-muted">{chat.error ? `读不到这个对话：${chat.error.message}` : null}</div>
      </div>
    );
  }
  return <Chat view={view} sessionKey={key} lives={lives} />;
}

/** What the page knows of an agent: its chat entry and its live view. */
interface Here { station: string; key: string; view: ChatView }

/** A web service's page (./Preview.tsx), over its chat. */
function servicePath(station: string, key: string, job: string): string {
  return `${stationBase(station)}/chats/${encodeURIComponent(key)}/services/${encodeURIComponent(job)}`;
}

function Chat({ view, sessionKey, lives }: { view: ChatView; sessionKey: string; lives: ReturnType<typeof useLives> }) {
  const station = useStation();
  const list = useRef<HTMLDivElement>(null);
  const floor = useRef<HTMLDivElement>(null);
  // The page's composer is its host's (ChatHost.tsx): kept as a new chat becomes this chat.
  const { draft, use } = useHost();
  const here: Here = { station: station.address, key: sessionKey, view };
  useComposer(view, here, draft, use);
  return (
    <div className="m-chat">
      <Messages view={view} lives={lives} list={list} floor={floor} draft={draft} here={here} />
      <ChatBar view={view} here={here} />
    </div>
  );
}

/** The chat's bar: back, its title, then its people, then its agents' marks (each opens its history); "…" is the chat's own sheet. */
function ChatBar({ view, here }: { view: ChatView; here: Here }) {
  const app = useApp();
  const thread = view.thread;
  const jobs = jobsOf(view);
  return (
    <BarFrame title={view.title} more={!!thread} onMore={() => thread && openChatInfo(app, here, thread)}
      trailing={jobs.length > 0 ? <JobsButton here={here} jobs={jobs} /> : null}>
      {view.people.length > 0 && <PeopleStack people={view.people.slice(0, 5)} size={16} />}
      {view.agents.map((a) => (
        <button key={a.session.key} type="button" className="m-bar-agent" onClick={() => openHistory(app, here.station, here.key, a.session.key)} aria-label={`${a.session.agentText} 的执行历史`}>
          <ModelMark maker={a.session.maker} runtime={a.session.runtime} size={22} state={stateOf(a.badge)} />
        </button>
      ))}
    </BarFrame>
  );
}

/** The bar's frame, the same while the chat loads and once it has: back, the title, what follows it, what is at its end, and "…". */
export function BarFrame({ title, more, onMore, trailing, children }: { title: string; more: boolean; onMore?: () => void; trailing?: ReactNode; children?: ReactNode }) {
  const app = useApp();
  return (
    <header className="m-chat-bar m-glass">
      <button type="button" className="m-chat-back" onClick={app.pop} aria-label="返回"><ChevronLeft size={22} /></button>
      <span className="m-chat-bar-title"><b>{title}</b>{children}</span>
      {trailing}
      {more && onMore && <NavButton icon={More} label="对话信息" onClick={onMore} />}
    </header>
  );
}

// ── the list ───────────────────────────────────────────────────────────

function Messages({ view, lives, list, floor, draft, here }: {
  view: ChatView; lives: ReturnType<typeof useLives>; list: RefObject<HTMLDivElement | null>; floor: RefObject<HTMLDivElement | null>; draft: Draft; here: Here;
}) {
  const app = useApp();
  const sending = useChatSend();
  const thread = view.thread;
  const id = thread?.id ?? null;
  const messages = view.messages;
  const mine = (m: ChatMessage) => m.mine;
  useStickToBottom(list, ".msg", floor);
  const older = () => (id === null ? Promise.resolve() : sending.older(id));
  useOlderOnScroll(list, view, older);
  useMarkRead(floor, view, (seq) => (id === null ? Promise.resolve() : sending.read(id, seq)));
  const returning = useRememberPlace(list, `${here.station}:${thread?.id ?? here.key}`, messages.length > 0);
  const divider = useUnreadLine(list, view, messages, mine, older, returning);
  const away = useAwayFromBottom(list);
  // Messages there when the chat opened (and older pages loaded later) show at once; newer ones come up as they fade in.
  const firstSeq = useRef<number | null>(null);
  if (firstSeq.current === null) firstSeq.current = messages.at(-1)?.seq ?? 0;
  const sentHere = useRef(new Set<string>());
  for (const o of view.outbox) sentHere.current.add(o.text);
  const working = view.agents.filter((a) => a.status === "running");
  // Only an agent that has taken a message and runs is at work: until then the message itself says it waits.
  const atWork: AgentAtWork[] = working.map((a) => ({ key: a.session.key, who: a.session.agentText, runtime: a.session.runtime, maker: a.session.maker, activity: lives.get(a.session.key)?.activity ?? null, since: a.since }));
  const emissions = useEmissions(list);
  const shown = useLinger(atWork, emissions.keeps);
  emissions.take(messages, firstSeq.current, new Set(shown.map((s) => s.agent.key)));
  const agentOf = (key: string | undefined) => view.agents.find((a) => a.session.key === key);
  // Words selected with a mouse inside one message offer to quote them.
  const [picked, setPicked] = useState<{ quote: Omit<Quote, "comment">; x: number; y: number } | null>(null);
  // ember's own links (/o/<workspace>/<station>/<session>, as agents post them) open here, as pages over this one (the
  // chat and what is being written stay under them): one of this chat's agents' web services, or another session.
  const onLink = (event: React.MouseEvent) => {
    const link = emberLinkClicked(event);
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
    <>
      {picked && (
        <button type="button" className="m-quote-pop" style={{ left: picked.x, top: picked.y }} onMouseDown={(e) => e.preventDefault()}
          onClick={() => { draft.quote(picked.quote); setPicked(null); window.getSelection()?.removeAllRanges(); }}>
          <QuoteIcon size={12} strokeWidth={2.2} />引用
        </button>
      )}
      <div className="m-messages" ref={list} onClick={onLink} onMouseUp={() => setTimeout(() => setPicked(selectedQuote(list.current)), 0)} onScroll={() => setPicked(null)}>
        {view.more && <div className="m-older"><Spinner size={16} /></div>}
        {messages.length === 0 && view.outbox.length === 0 && <p className="m-chat-empty">在这里发消息，这个对话里的 agent 会在这里回复。</p>}
        {messages.map((m) => {
          const fresh = m.seq > firstSeq.current!;
          const enter = fresh && !(m.mine && sentHere.current.has(m.text)) && !emissions.emits(m.seq) ? true : undefined;
          const state = emissions.stateOf(m.seq);
          return [
            m.seq === divider ? <UnreadLine key={`line-${m.seq}`} /> : null,
            <div key={m.seq} className="msg m-row" data-seq={m.seq} data-ts={m.ts} data-enter={enter}
              data-author={m.mine ? "你" : m.by.name} data-role={m.authorKind === "agent" ? "agent" : "person"}
              data-held={state === "held" || undefined} data-emitting={state === "emitting" || undefined} data-covered={state === "emitting" || undefined}>
              <Said m={m} agent={agentOf(m.by.agent)} here={here} draft={draft} list={list} />
            </div>,
          ];
        })}
        {view.outbox.map((o) => <div key={o.id} className="msg m-row" data-enter><Out o={o} here={here} /></div>)}
        {shown.map(({ agent, leaving }) => (
          <Activity key={agent.key} agent={agent} leaving={leaving} pose={emissions.poseOf(agent.key)} className="m-activity"
            mark={<ModelMark maker={agent.maker} runtime={agent.runtime} size={20} />} onOpen={() => openHistory(app, here.station, here.key, agent.key)} />
        ))}
        <div ref={floor} className="chat-floor" aria-hidden="true" />
      </div>
      {/* Over the send button, in line with it; it comes up growing and goes the way it came. */}
      <button type="button" className="m-jump m-floating" data-shown={away || undefined} aria-label="跳到最新"
        onClick={() => list.current?.dispatchEvent(new Event("to-bottom"))}><ArrowDown size={18} /></button>
    </>
  );
}

/** The passage selected inside one message, as a quote of it, and where to offer it (over the selection). */
function selectedQuote(list: HTMLElement | null): { quote: Omit<Quote, "comment">; x: number; y: number } | null {
  const selection = window.getSelection();
  const text = selection?.toString().trim();
  if (!list || !selection || !text || selection.rangeCount === 0) return null;
  const range = selection.getRangeAt(0);
  const node = range.commonAncestorContainer;
  const row = (node instanceof Element ? node : node.parentElement)?.closest<HTMLElement>("[data-author]");
  if (!row || !list.contains(row)) return null;
  const rect = range.getBoundingClientRect();
  const role = row.dataset.role === "agent" ? "agent" as const : "person" as const;
  return { quote: { author: row.dataset.author!, text, ...(row.dataset.ts ? { ts: row.dataset.ts } : {}), role }, x: rect.left + rect.width / 2, y: rect.top };
}

function UnreadLine() {
  return <div className="m-unread-line" data-unread-line role="separator"><i /><span>以下是新消息</span><i /></div>;
}

/** A message's words as read, without markdown's marks: what a quote carries. */
function plain(text: string): string {
  return text.replace(/[`*#>]/g, "").replace(/\s+/g, " ").trim();
}

/** Long-press on a message: quote it, or copy it. While its menu is open the message is marked. */
function useHold(text: string, who: string, ts: string | undefined, role: "agent" | "person", draft: Draft) {
  const app = useApp();
  const [pressed, setPressed] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const open = (el: HTMLElement) => {
    setPressed(true);
    app.menu({
      anchor: el.getBoundingClientRect(),
      items: [
        { label: "引用", icon: <QuoteIcon size={16} />, action: () => draft.quote({ author: who, text: plain(text), ...(ts ? { ts } : {}), role }) },
        { label: "拷贝", icon: <Copy size={16} />, action: () => { void navigator.clipboard.writeText(text).then(() => app.toast("已拷贝")); } },
      ],
      onDismiss: () => setPressed(false),
    });
  };
  const cancel = () => clearTimeout(timer.current);
  // A finger holds for the menu; a mouse right-clicks for it (and selects words to quote a passage of them).
  const touched = useRef(false);
  return {
    pressed,
    props: {
      onPointerDown: (e: React.PointerEvent<HTMLElement>) => {
        touched.current = e.pointerType !== "mouse";
        if (!touched.current) return;
        const el = e.currentTarget;
        cancel();
        timer.current = setTimeout(() => open(el), 480);
      },
      onPointerUp: cancel, onPointerCancel: cancel, onPointerMove: (e: React.PointerEvent) => { if (Math.abs(e.movementY) > 4 || Math.abs(e.movementX) > 4) cancel(); },
      // A right click opens it; a long press, where the browser asks for its own menu too, already has.
      onContextMenu: (e: React.MouseEvent<HTMLElement>) => { e.preventDefault(); if (!touched.current) open(e.currentTarget); },
    },
  };
}

function Said({ m, agent, here, draft, list }: { m: ChatMessage; agent: ChatAgent | undefined; here: Here; draft: Draft; list: RefObject<HTMLDivElement | null> }) {
  const app = useApp();
  const jump = (ts: string) => {
    const target = list.current?.querySelector<HTMLElement>(`[data-ts="${ts}"]`);
    if (!target) return;
    list.current!.dispatchEvent(new WheelEvent("wheel"));
    list.current!.scrollTop += target.getBoundingClientRect().top - list.current!.getBoundingClientRect().top - 80;
  };
  const who = m.by.name;
  const hold = useHold(m.text, m.mine ? "你" : who, m.ts, m.authorKind === "agent" ? "agent" : "person", draft);
  // What ember itself says: a notice across the chat, apart from people's and agents' messages.
  if (m.system) {
    return <div className="m-system"><Mark size={14} /><div className="m-markdown m-md-14"><Prose>{m.text}</Prose></div></div>;
  }
  if (m.mine) {
    return (
      <div className="m-mine">
        {m.quotes.map((q, i) => <QuoteCard key={i} q={q} onJump={jump} />)}
        {m.text && <div className="m-bubble" data-pressed={hold.pressed || undefined} {...hold.props}>{m.text}</div>}
        <Files here={here} files={m.attachments} />
        {m.waiting
          ? <span className="m-meta m-waiting"><Spinner size={10} />等待 agent 接收</span>
          : <span className="m-meta">{m.time?.createdAt?.ago ?? ""}</span>}
      </div>
    );
  }
  return (
    <div className="m-said">
      <div className="msg-head m-said-head">
        {agent ? (
          <button type="button" className="m-agent-head" onClick={() => openHistory(app, here.station, here.key, agent.session.key)}>
            <span className="msg-avatar"><ModelMark maker={agent.session.maker} runtime={agent.session.runtime} size={20} /></span>
            <b>{who}</b>
          </button>
        ) : (
          <span className="m-agent-head">
            <span className="msg-avatar">{m.authorKind === "agent" || m.authorKind === "ember" ? <Mark size={18} /> : <Avatar id={m.author} name={who} size={18} picture={m.by.picture} />}</span>
            <b>{who}</b>
          </span>
        )}
        <span className="m-meta">{m.time?.createdAt?.ago ?? ""}</span>
      </div>
      {m.quotes.map((q, i) => <QuoteCard key={i} q={q} onJump={jump} />)}
      <div className="m-said-body" data-pressed={hold.pressed || undefined} {...hold.props}>
        {m.authorKind === "person" ? m.text && <p className="m-plain">{m.text}</p> : <div className="m-markdown"><Prose>{m.text}</Prose></div>}
      </div>
      <Files here={here} files={m.attachments} />
    </div>
  );
}

/** A message sent from here that the chat does not show yet: on its way, or failed with a way to send it again or drop it. */
function Out({ o, here }: { o: Outgoing; here: Here }) {
  const app = useApp();
  const sending = useChatSend();
  const thread = here.view.thread;
  return (
    <div className="m-mine" data-unsent={o.state === "failed" || undefined}>
      {o.quotes.map((q, i) => <QuoteCard key={i} q={q} />)}
      {o.text && <div className="m-bubble">{o.text}</div>}
      <Files here={here} files={o.attachments} />
      {o.state === "failed" ? (
        // Not sent: said briefly (a tap says why); sending it again or dropping it right beside.
        <div className="m-unsent">
          <button type="button" className="m-unsent-note" onClick={() => app.toast(o.error ? `没发出去：${o.error}` : "没发出去")}>未发送</button>
          <button type="button" className="m-unsent-btn" onClick={() => void (thread && sending.retry(thread.id, o.id).catch(() => {}))}>重试</button>
          <button type="button" className="m-unsent-btn" onClick={() => void (thread && sending.discard(thread.id, o.id))}>删除</button>
        </div>
      ) : <span className="m-meta m-waiting"><Spinner size={10} />正在发送</span>}
    </div>
  );
}

/** A quote as sent: the quoted part on a warm ground (whose message, the passage) leading back to it, then what was said about it. */
function QuoteCard({ q, onJump }: { q: Quote; onJump?: (ts: string) => void }) {
  const ts = q.ts;
  return (
    <div className="m-quote">
      <button type="button" className="m-quote-source" disabled={!ts || !onJump} onClick={() => ts && onJump?.(ts)}>
        <QuoteIcon size={11} strokeWidth={2.4} />
        <span><b>{q.author}：</b>{q.text}</span>
      </button>
      {q.comment && <div className="m-quote-comment">{q.comment}</div>}
    </div>
  );
}

// ── the running turn ───────────────────────────────────────────────────

// ── files ──────────────────────────────────────────────────────────────

const IMAGE = /\.(png|jpe?g|gif|webp)$/i;

function Files({ here, files }: { here: Here; files: Attachment[] | undefined }) {
  if (!files?.length) return null;
  // Files are kept in a session's workspace: the agent whose workspace holds it, else the first.
  const owner = (f: Attachment) => here.view.agents.find((a) => f.path.startsWith(`${a.session.workspace}/`))?.session.key ?? here.view.agents[0]?.session.key ?? null;
  return (
    <div className="m-files">
      {files.map((f) => {
        const key = owner(f);
        return IMAGE.test(f.name) && key ? <StationImage key={f.path} sessionKey={key} file={f} /> : <FileCard key={f.path} name={f.name} size={f.size} />;
      })}
    </div>
  );
}

/** An image at its own proportions within 240×200 (known before it loads); a tap shows it whole. */
function StationImage({ sessionKey, file }: { sessionKey: string; file: Attachment }) {
  const url = useFileUrl(sessionKey, file, true);
  const [open, setOpen] = useState(false);
  const box = file.width && file.height
    ? (() => { const scale = Math.min(1, 240 / file.width, 200 / file.height); return { width: Math.max(40, file.width * scale), height: Math.max(40, file.height * scale) }; })()
    : { width: 170, height: 120 };
  return (
    <>
      <button type="button" className="m-image" style={box} disabled={!url} onClick={() => setOpen(true)}>{url && <img src={url} alt={file.name} />}</button>
      {url && <Lightbox open={open} onClose={() => setOpen(false)} url={url} file={file} />}
    </>
  );
}

function FileCard({ name, size, note, busy = false, onRemove, inComposer = false }: { name: string; size: number; note?: string | null | undefined; busy?: boolean; onRemove?: () => void; inComposer?: boolean }) {
  return (
    <span className="m-file" data-composer={inComposer || undefined}>
      {busy ? <Spinner size={16} /> : <File size={18} />}
      <span className="m-file-text"><span>{name}</span><small data-error={note && !busy ? true : undefined}>{note ?? fileSize(size)}</small></span>
      {onRemove && <button type="button" className="m-file-remove" onClick={onRemove} aria-label={`移除 ${name}`}><Close size={12} /></button>}
    </span>
  );
}

// ── the composer ───────────────────────────────────────────────────────

/** A file on its way to the station: uploading, uploaded, or failed. */
interface Pending { id: number; name: string; size: number; preview: string | null; done: Attachment | null; error: string | null }
/** A passage quoted in the message being written, with what is said about it. */
interface DraftQuote extends Quote { id: number }

/** What is being written: text, quotes, files. Kept while the chat is open. */
export interface Draft {
  text: string; setText: (t: string) => void;
  quotes: DraftQuote[]; setQuotes: (f: (q: DraftQuote[]) => DraftQuote[]) => void;
  files: Pending[]; setFiles: (f: (p: Pending[]) => Pending[]) => void;
  focusQuote: number | null; setFocusQuote: (id: number | null) => void;
  quote: (q: Omit<Quote, "comment">) => void;
  starting: boolean; setStarting: (on: boolean) => void;
  error: string | null; setError: (e: string | null) => void;
  focus: number; bumpFocus: () => void;
}

export function useDraft(): Draft {
  const [text, setText] = useState("");
  const [quotes, setQuotes] = useState<DraftQuote[]>([]);
  const [files, setFiles] = useState<Pending[]>([]);
  const [focusQuote, setFocusQuote] = useState<number | null>(null);
  const [starting, setStarting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [focus, setFocus] = useState(0);
  return {
    text, setText, quotes, setQuotes, files, setFiles, focusQuote, setFocusQuote, starting, setStarting, error, setError, focus,
    bumpFocus: () => setFocus((n) => n + 1),
    quote: (q) => { const id = Date.now(); setQuotes((all) => [...all, { ...q, comment: "", id }]); setFocusQuote(id); },
  };
}

const MAX_FILE = 50 * 1024 * 1024;

/** Files go to the station as soon as they are added, and wait there in no chat: the message that sends them takes them into its chat. */
export function useUpload(draft: Draft, station: string) {
  const call = useStationCall(station);
  return (picked: FileList | File[]) => {
    for (const file of Array.from(picked)) {
      const id = Date.now() + Math.random();
      const preview = file.type.startsWith("image/") ? URL.createObjectURL(file) : null;
      draft.setFiles((all) => [...all, { id, name: file.name, size: file.size, preview, done: null, error: file.size > MAX_FILE ? "超过 50 MB" : null }]);
      if (file.size > MAX_FILE) continue;
      call.upload(file).then(
        (done) => draft.setFiles((all) => all.map((p) => (p.id === id ? { ...p, done } : p))),
        (error: unknown) => draft.setFiles((all) => all.map((p) => (p.id === id ? { ...p, error: error instanceof Error ? error.message : String(error) } : p))),
      );
    }
  };
}

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
        <div className="m-attach">
          {([["拍照", <Camera key="c" size={24} />, () => pick("image/*", true)], ["照片", <Photo key="p" size={24} />, () => pick("image/*", false)], ["文件", <File key="f" size={24} />, () => pick("*/*", false)]] as const).map(([label, icon, go]) => (
            <button key={label} type="button" onClick={() => { app.sheet(null); go(); }}>{icon}<span>{label}</span></button>
          ))}
        </div>
      </>
    ),
  });
}

/** What waits to go with the message: the quotes (each with a line for a comment), then the files. */
export function DraftExtras({ draft }: { draft: Draft }) {
  return (
    <>
      {draft.quotes.map((q) => (
        <div key={q.id} className="m-draft-quote">
          <div className="m-draft-quote-source">
            <QuoteIcon size={12} strokeWidth={2.4} />
            <span><b>{q.author}：</b>{q.text}</span>
            <button type="button" onClick={() => draft.setQuotes((all) => all.filter((x) => x.id !== q.id))} aria-label="移除引用"><Close size={13} /></button>
          </div>
          <QuoteComment draft={draft} q={q} />
        </div>
      ))}
      {draft.files.length > 0 && (
        <div className="m-draft-files">
          {draft.files.map((f) => {
            const remove = () => draft.setFiles((all) => all.filter((x) => x.id !== f.id));
            return f.preview ? (
              <span key={f.id} className="m-draft-thumb">
                <img src={f.preview} alt={f.name} />
                {!f.done && <span className="m-draft-thumb-wait" data-error={f.error ? true : undefined}>{f.error ? "失败" : <Spinner size={16} color="#fff" />}</span>}
                <button type="button" onClick={remove} aria-label={`移除 ${f.name}`}><Close size={10} /></button>
              </span>
            ) : <FileCard key={f.id} name={f.done?.name ?? f.name} size={f.done?.size ?? f.size} note={f.error ?? (f.done ? null : "正在上传…")} busy={!f.done && !f.error} onRemove={remove} inComposer />;
          })}
        </div>
      )}
    </>
  );
}

function QuoteComment({ draft, q }: { draft: Draft; q: DraftQuote }) {
  const input = useRef<HTMLInputElement>(null);
  useEffect(() => {
    if (draft.focusQuote !== q.id) return;
    input.current?.focus();
    draft.setFocusQuote(null);
  }, [draft.focusQuote]); // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <input ref={input} className="m-draft-quote-comment" value={q.comment} placeholder="对这段说点什么（可以不写）"
      onChange={(e) => draft.setQuotes((all) => all.map((x) => (x.id === q.id ? { ...x, comment: e.target.value } : x)))}
      onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); draft.bumpFocus(); } }} />
  );
}

/** The bar, inside a floating capsule that is its frame: ＋, a field that grows with the text, and a round send button (a spinner while a new chat is made). */
export function ComposerBar({ draft, placeholder, locked = false, onPlus, onType, onSend }: { draft: Draft; placeholder: string; locked?: boolean; onPlus: () => void; onType: () => void; onSend: () => void }) {
  const field = useRef<HTMLTextAreaElement>(null);
  const uploading = draft.files.some((f) => !f.done && !f.error);
  const ready = (draft.text.trim() !== "" || draft.files.some((f) => f.done) || draft.quotes.length > 0) && !uploading && !draft.starting && !locked;
  useEffect(() => { if (draft.focus > 0) field.current?.focus(); }, [draft.focus]);
  // The field grows with what is typed, up to six lines.
  useLayoutEffect(() => {
    const el = field.current;
    if (!el) return;
    el.style.height = "0px";
    el.style.height = `${Math.min(el.scrollHeight, 21 * 6)}px`;
  }, [draft.text]);
  return (
    <div className="m-composer-bar">
      <button type="button" className="m-plus" onClick={onPlus} disabled={locked} aria-label="添加文件"><Plus size={18} /></button>
      <textarea ref={field} className="m-composer-field" rows={1} value={draft.text} placeholder={placeholder}
        onChange={(e) => { draft.setText(e.target.value); onType(); }}
        onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing && window.matchMedia("(hover: hover)").matches) { e.preventDefault(); if (ready) onSend(); } }} />
      <button type="button" className="m-send" data-ready={ready || undefined} disabled={!ready} onClick={onSend} aria-label="发送">
        {draft.starting ? <Spinner size={16} color="var(--m-surface)" /> : <ArrowUp size={18} />}
      </button>
    </div>
  );
}

/**
 * What the chat's composer (its host's, ChatHost.tsx) writes to: this chat. The composer empties at once: the message
 * lives in the chat's outbox until the station has it (a failure shows there too). Before the agent has a chat, the
 * first message makes one, bound to the agent, and the page stays (the core shows the chat at the same address).
 */
function useComposer(view: ChatView, here: Here, draft: Draft, use: (spec: HostComposer) => void) {
  const api = useApi();
  const call = useStationCall(here.station);
  const sending = useChatSend();
  const keeper = view.agents[0]?.session.key ?? null;
  const warmed = useRef(0);
  const send = (draft: Draft) => {
    const text = draft.text.trim();
    const files = draft.files;
    const quotes = draft.quotes;
    draft.setText(""); draft.setFiles(() => []); draft.setQuotes(() => []); draft.setError(null);
    void (async () => {
      let thread = view.thread?.id;
      if (thread === undefined) {
        draft.setStarting(true);
        try {
          thread = (await call.request<{ id: number }>("POST", "/threads", { session: here.key })).id;
        } catch (error) {
          // No chat to send into: the draft comes back.
          draft.setText(text); draft.setFiles(() => files); draft.setQuotes(() => quotes);
          draft.setError(error instanceof Error ? error.message : String(error));
          return;
        } finally {
          draft.setStarting(false);
        }
      }
      sending.send(thread, text, files.flatMap((f) => (f.done ? [f.done] : [])), quotes.map(({ id: _, ...q }) => q)).catch(() => {});
    })();
  };
  useLayoutEffect(() => use({
    station: here.station, placeholder: "发消息", offline: view.offline, send,
    // Typing starts the session's runtime, so a cold start overlaps the writing.
    type: () => {
      if (!keeper || Date.now() - warmed.current < 60_000) return;
      warmed.current = Date.now();
      api.warm(keeper).catch(() => {});
    },
  }));
}

// ── services and background jobs ───────────────────────────────────────

/** The chat's agents' services and background jobs: those that matter now first, what is over faded and last. */
function jobsOf(view: ChatView) {
  return sorted(view.agents.flatMap((a) => a.jobs ?? []));
}

/** The bar's button for the chat's services and jobs, with a dot when one died lately (red) or a service restarts (amber). */
function JobsButton({ here, jobs }: { here: Here; jobs: Job[] }) {
  const app = useApp();
  const alarm = alarmOf(jobs, useNow(30_000));
  return (
    <button type="button" className="m-nav-button m-jobs-trigger" aria-label="服务和后台任务" onClick={() => openJobs(app, here)}>
      <Web size={18} />
      {alarm && <span className="m-jobs-alarm" data-alarm={alarm} aria-hidden="true" />}
    </button>
  );
}

/** What matters now of the chat's services and jobs, as the desktop's title bar popover has it; the rest a tap away. */
function openJobs(app: MobileApp, here: Here) {
  app.sheet({ height: 0.62, draggable: true, content: () => <JobsNow here={here} /> });
}

function JobsNow({ here }: { here: Here }) {
  const now = useNow();
  const view = useChat(here.station, { session: here.key }).value ?? here.view;
  const jobs = jobsOf(view);
  const [all, setAll] = useState(false);
  const current = jobs.filter((j) => isCurrent(j, now));
  const shown = all ? jobs : current;
  const hidden = jobs.length - current.length;
  return (
    <>
      <SheetGrab />
      <SheetHead title="服务和后台任务" />
      <div className="m-sheet-scroll m-pad-18">
        {jobs.length === 0 && <div className="m-jobs-empty"><b>还没有服务或后台任务</b><span>agent 开网页、或挂上长期盯着的任务时，会列在这里。</span></div>}
        {jobs.length > 0 && shown.length === 0 && <p className="m-note">眼下没有在跑的服务或任务。</p>}
        <JobGroups here={here} view={view} jobs={shown} now={now} notes />
        {hidden > 0 && (
          <button type="button" className="m-jobs-all" onClick={() => setAll(!all)}>
            {all ? "只看眼下的" : <>全部 {jobs.length} 个<span>另有 {hidden} 个已停止或结束</span></>}
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
function JobGroups({ here, view, jobs, now, notes = false }: { here: Here; view: ChatView; jobs: Job[]; now: number; notes?: boolean }) {
  const app = useApp();
  const services = jobs.filter(isService);
  const plain = jobs.filter((j) => !isService(j));
  const count = (list: Job[], tone: Tone) => list.filter((j) => toneOf(j) === tone).length;
  const serviceNote = [count(services, "up") && `${count(services, "up")} 个在线`, count(services, "restart") && `${count(services, "restart")} 个在重启`].filter(Boolean).join("，");
  const plainNote = count(plain, "live") ? `${count(plain, "live")} 个在盯着` : "";
  const details = (j: Job) => app.sheet({ height: 0.8, draggable: true, content: () => <JobSheet station={here.station} sessionKey={here.key} jobId={j.id} view={view} /> });
  return (
    <>
      {services.length > 0 && (
        <>
          <GroupLabel>服务{notes && serviceNote ? ` · ${serviceNote}` : ""}</GroupLabel>
          <InfoList>
            {services.map((j) => {
              const up = toneOf(j) === "up" || toneOf(j) === "restart";
              return <JobInfoRow key={j.id} job={j} now={now} onClick={up ? () => app.push(servicePath(here.station, here.key, j.id)) : () => details(j)} />;
            })}
          </InfoList>
        </>
      )}
      {plain.length > 0 && (
        <>
          <GroupLabel>后台任务{notes && plainNote ? ` · ${plainNote}` : ""}</GroupLabel>
          <InfoList>
            {plain.map((j) => <JobInfoRow key={j.id} job={j} now={now} onClick={() => details(j)} />)}
          </InfoList>
        </>
      )}
    </>
  );
}

/** A job's row in the chat's sheets: its dot on its name's line, what it is up to under it. */
function JobInfoRow({ job, now, onClick }: { job: Job; now: number; onClick?: (() => void) | undefined }) {
  const tone = toneOf(job);
  const body = (
    <>
      <span className="m-job" data-off={tone === "off" || undefined}>
        <JobDot tone={tone} />
        <span className="m-grow m-job-text"><b>{job.name}</b><span>{metaOf(job, now)}</span></span>
      </span>
      {onClick && <ChevronRight size={14} className="m-subtle" />}
    </>
  );
  return onClick ? <InfoRow onClick={onClick}>{body}</InfoRow> : <InfoRow>{body}</InfoRow>;
}

/**
 * A service or a job, from the chat's sheets: its command, then what it said or its output as it grows (a service, its
 * output); stopped from here.
 */
function JobSheet({ station, sessionKey, jobId, view: first }: { station: string; sessionKey: string; jobId: string; view: ChatView }) {
  const here = useChat(station, { session: sessionKey }).value ?? first;
  const job = here.agents.flatMap((a) => a.jobs ?? []).find((j) => j.id === jobId);
  const now = useNow();
  const stop = useStopJob(station);
  const [picked, setTab] = useState(0);
  const service = !!job && isService(job);
  const tab = service ? 1 : picked;
  const running = job?.state === "running";
  // Its last line: read again while it runs, once when it is over.
  const last = useJobLog(station, job && tab === 0 ? job.id : null, 1, running ? 3000 : 600_000);
  if (!job) return <><SheetGrab /><SheetHead title="任务" /><p className="m-note">这个任务已经不在了。</p></>;
  const lastAt = last?.outputAt ?? job.outputAt;
  return (
    <>
      <SheetGrab />
      <div className="m-job-head">
        <JobDot tone={toneOf(job)} />
        <span className="m-grow"><b>{job.name}</b><span>{metaOf(job, now)}</span></span>
      </div>
      <div className="m-pad-18 m-job-body">
        {job.command && <div className="m-job-command">{job.command}</div>}
        {!service && <Seg options={["通知", "输出"]} selected={tab} onSelect={setTab} fill height={34} />}
        {tab === 0
          ? (
            <div className="m-job-notices">
              {(job.notices ?? []).length === 0 && <p className="m-note">还没有通知。</p>}
              {(job.notices ?? []).map((n, i) => <p key={`${n.at}-${i}`}><time>{clock(n.at, now)}</time><span>{n.text}</span></p>)}
            </div>
          )
          : <JobOutput station={station} job={job} />}
        {tab === 0 && (lastAt || last?.text) && <div className="m-job-last"><span>最后输出{lastAt ? ` · ${ago(lastAt, now)}` : ""}</span>{last?.text && <code>{last.text.trim()}</code>}</div>}
        {running && <button type="button" className="m-job-stop" onClick={() => stop(job)}><Stop size={16} />停止</button>}
      </div>
    </>
  );
}

/** A job's output, following its end while it is scrolled there (as the desktop's 任务 tab has it). */
function JobOutput({ station, job }: { station: string; job: Job }) {
  const log = useJobLog(station, job.id, 300, job.state === "running" ? 2000 : 60_000);
  const box = useRef<HTMLPreElement>(null);
  const atEnd = useRef(true);
  useEffect(() => {
    const el = box.current;
    if (el && atEnd.current) el.scrollTop = el.scrollHeight;
  }, [log?.text]);
  return (
    <pre ref={box} className="m-job-output" onScroll={(e) => { const el = e.currentTarget; atEnd.current = el.scrollHeight - el.scrollTop - el.clientHeight < 24; }}>
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
  const now = useNow();
  const view = useChat(here.station, { session: here.key }).value ?? here.view;
  const thread = view.thread ?? first;
  return (
    <>
      <SheetGrab />
      <SheetHead title="对话信息" />
      <div className="m-sheet-scroll m-pad-18">
        <InfoList>
          <InfoDetail label="来自" value={view.place ? `Slack · ${view.place}` : "ember 对话"} />
          <InfoDetail label="发起" value={thread.creator?.shown?.display ?? "未记录"} />
          <InfoDetail label="参与" value={`${view.people.length} 人`} extra={view.people.length ? <PeopleStack people={view.people.slice(0, 8)} size={16} ring="var(--m-surface2)" /> : null} />
          <InfoDetail label="创建" value={thread.time?.createdAt?.ago ?? ""} />
          {thread.lastMessage && <InfoDetail label="最近消息" value={thread.lastMessage.time?.createdAt?.ago ?? ""} />}
        </InfoList>
        <JobGroups here={here} view={view} jobs={jobsOf(view)} now={now} />
        {view.slackUrl && (
          <>
            <GroupLabel>在 Slack 里</GroupLabel>
            <InfoList><a className="m-info-row" href={view.slackUrl} target="_blank" rel="noopener"><SlackMark size={16} /><span className="m-grow">在 Slack 中打开</span><ChevronRight size={14} className="m-subtle" /></a></InfoList>
          </>
        )}
        {view.agents.length > 0 && (
          <>
            <GroupLabel>参与的 agent · 点开看它的执行历史</GroupLabel>
            <InfoList>
              {view.agents.map((a) => {
                const s = a.session;
                return (
                  <InfoRow key={s.key} onClick={() => openHistory(app, here.station, here.key, s.key)}>
                    <ModelMark maker={s.maker} runtime={s.runtime} size={36} state={stateOf(a.badge)} around="var(--m-surface2)" />
                    <span className="m-grow m-info-agent">
                      <b>{s.agentText}</b>
                      <span>{a.connect && <SlackMark size={11} />}{[a.connect?.name, s.processText, s.time?.lastActiveAt?.ago].filter(Boolean).join(" · ")}</span>
                    </span>
                    <ChevronRight size={14} className="m-subtle" />
                  </InfoRow>
                );
              })}
            </InfoList>
          </>
        )}
      </div>
    </>
  );
}

function InfoDetail({ label, value, extra }: { label: string; value: string; extra?: ReactNode }) {
  return <InfoRow><span className="m-info-label">{label}</span>{extra}<span className="m-grow">{value}</span></InfoRow>;
}
