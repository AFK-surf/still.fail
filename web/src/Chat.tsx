// ember's own chat with a session, after Zork's: your messages sit right in a
// bubble with only their time; everyone else (people and the agent) gets an
// avatar, a name and the time over their words. Passages of earlier messages
// can be quoted with a comment, and files ride along as cards (images shown).
import { ArrowUp, ChevronDown, ChevronUp, Download, FileText, Plus, Quote as QuoteIcon, X } from "lucide-react";
import { useEffect, useRef, useState, type ReactNode, type RefObject } from "react";
import { useApi, useChatSend, useIsMine, type Api, type Attachment, type ChatView, type LiveView, type MessageView, type Quote, type SessionSummary, type ShownPhase, type ShownStep, type TimelineEntry } from "./api.ts";
import { activityText, partialString, toolName } from "./History.tsx";
import { agentLabel, botUserIdOf, sessionStatus, slackThreadUrl, slackWorkspaceUrl } from "./format.ts";
import { Mark } from "./brand.tsx";
import { usePerson, useStation } from "./station.tsx";
import { Avatar, ModelLogo, SlackLogo, Time, Tip } from "./ui.tsx";
import { Prose } from "./Prose.tsx";
import { Dialog as RDialog } from "radix-ui";
import { useStickToBottom } from "./scroll.ts";

/** An agent of this chat as its messages and activity show it: who it is, and its execution history as it runs. */
interface ChatAgent { key: string; who: string; runtime: SessionSummary["runtime"]; model: string | null; session: SessionSummary; live: LiveView | undefined; turns: ChatView["agents"][number]["turns"] }

export function ChatPanel({ chat, lives, onOpenHistory }: { chat: ChatView; lives: ReadonlyMap<string, LiveView>; onOpenHistory(key: string): void }) {
  const list = useRef<HTMLDivElement>(null);
  const floor = useRef<HTMLDivElement>(null);
  const sending = useChatSend();
  const { thread, outbox } = chat;
  // Deleted messages keep their place for the station's cursors; here they are simply gone.
  const messages = chat.messages.filter((m) => m.deletedAt === null);
  const [quotes, setQuotes] = useState<DraftQuote[]>([]);
  const [focusQuote, setFocusQuote] = useState<string | null>(null);
  const [picked, setPicked] = useState<{ quote: DraftQuote; at: { x: number; y: number } } | null>(null);
  const member = usePerson();
  const isMine = useIsMine();
  const mineOf = (m: MessageView) => m.authorKind === "person" && isMine({ id: m.author, email: m.author });
  useStickToBottom(list, ".msg", floor);
  useOlderOnScroll(list, chat, () => sending.older(thread.id));
  useMarkRead(floor, chat, (seq) => sending.read(thread.id, seq));
  const divider = useUnreadLine(list, chat, messages, mineOf, () => sending.older(thread.id));
  // A message sent from here eases in once, from the outbox; its own copy that replaces it does not again.
  const sentHere = useRef(new Set<string>());
  for (const o of outbox) sentHere.current.add(o.text);
  // Messages there when the chat opened (and older pages loaded later) show at once; newer ones ease in, except a reply that already streamed in place.
  const firstSeq = useRef<number | null>(null);
  if (firstSeq.current === null) firstSeq.current = messages.at(-1)?.seq ?? 0;
  const wasWriting = useRef(false);
  const heldReply = useRef<{ agent: ChatAgent; text: string; count: number } | null>(null);
  const streamedTs = useRef(new Set<string>());
  const agents: ChatAgent[] = chat.agents.map(({ session, turns }) => {
    const live = lives.get(session.key);
    const model = live?.usage?.model ?? session.model;
    return { key: session.key, who: agentLabel(model, session.effort), runtime: session.runtime, model, session, live, turns };
  });
  const agentOf = (key: string) => agents.find((a) => a.key === key);
  // When the turn ends, the activity stays a moment to fade and fold away instead of vanishing.
  const lastAgents = useRef<AgentAtWork[] | null>(null);
  const [, rerender] = useState(0);
  const wasBusy = useRef(false);
  const working = agents.filter((a) => ["running", "queued"].includes(sessionStatus(a.session)));
  // A message on its way already counts: the activity shows at once (for every agent it goes to) instead of after the station answers.
  const sendingNow = outbox.some((o) => o.state === "sending");
  const busyAgents = working.length ? working : sendingNow ? agents : [];
  const busy = busyAgents.length > 0;
  // A turn ending and the next starting leave a moment of "not running"; only a pause over a second ends the activity.
  const [leaving, setLeaving] = useState(false);
  useEffect(() => {
    if (busy) { wasBusy.current = true; setLeaving(false); return; }
    if (!wasBusy.current) return;
    const fade = setTimeout(() => setLeaving(true), 1200);
    const gone = setTimeout(() => { wasBusy.current = false; lastAgents.current = null; setLeaving(false); rerender((n) => n + 1); }, 1200 + 520);
    return () => { clearTimeout(fade); clearTimeout(gone); };
  }, [busy]);
  const name = (m: MessageView) => member(m.author)?.name || m.authorName || (m.author === "local" ? "本机" : m.author);
  // Slack's <@U…> mentions by name: an agent's bot by its connect's, a person by theirs where known.
  const bots = new Map(chat.agents.flatMap((a) => { const id = botUserIdOf(a.connect ?? undefined); return id && a.connect ? [[id, a.connect.name] as const] : []; }));
  const mention = (text: string) => text.replace(/<@([A-Z0-9]+)>/g, (_, id: string) => `@${bots.get(id) ?? member(id)?.name ?? id}`);
  // The messages the agents have not taken yet are the last people wrote; after a second, yours show that they wait.
  const people = messages.filter((m) => m.authorKind === "person");
  const waiting = Math.max(0, ...agents.map((a) => a.session.pending));
  const pending = new Set(waiting > 0 ? people.slice(-waiting).map((m) => m.seq) : []);
  const [, tick] = useState(0);
  const youngest = messages.filter((m) => pending.has(m.seq)).reduce((t, m) => Math.max(t, m.createdAt), 0);
  useEffect(() => {
    const wait = youngest + 1000 - Date.now();
    if (!youngest || wait <= 0) return;
    const timer = setTimeout(() => tick((n) => n + 1), wait + 20);
    return () => clearTimeout(timer);
  }, [youngest]);
  // Where agents post to reach this chat.
  const address = `${thread.channel}/${thread.threadTs}`;
  // Files are kept in a session's workspace: what is sent here goes to the first agent's.
  const keeper = agents[0]?.key ?? null;
  const ownerOf = (file: Attachment) => agents.find((a) => file.path.startsWith(`${a.session.workspace}/`))?.key ?? keeper;

  // Selecting text inside one message offers to quote it.
  const onSelect = () => {
    const selection = window.getSelection();
    const text = selection?.toString().trim();
    if (!selection || !text || selection.rangeCount === 0) return setPicked(null);
    const range = selection.getRangeAt(0);
    const from = (range.commonAncestorContainer instanceof Element ? range.commonAncestorContainer : range.commonAncestorContainer.parentElement)?.closest<HTMLElement>("[data-author]");
    if (!from) return setPicked(null);
    const rect = range.getBoundingClientRect();
    const role = from.dataset.role === "agent" ? "agent" as const : "person" as const;
    setPicked({ quote: { id: `${Date.now()}`, author: from.dataset.author!, text, comment: "", ...(from.dataset.ts ? { ts: from.dataset.ts } : {}), role }, at: { x: rect.left + rect.width / 2, y: rect.top } });
  };

  return (
    <section className="chat" aria-label="对话">
      <div className="chat-list" ref={list} onMouseUp={() => setTimeout(onSelect, 0)} onScroll={() => setPicked(null)}>
        {chat.more && <div className="chat-older" aria-hidden="true"><span className="spinner" /></div>}
        {messages.length === 0 && (
          <div className="chat-empty">
            <p>{thread.surface === "ember" ? "在这里发消息，这个对话里的 agent 会在这里回复。" : "这个 thread 里还没有消息。"}</p>
          </div>
        )}
        {messages.map((m) => {
          const fresh = m.seq > firstSeq.current!;
          if (fresh && m.authorKind === "agent" && wasWriting.current && !streamedTs.current.has(m.ts)) {
            streamedTs.current.add(m.ts);
            wasWriting.current = false;
          }
          const mine = mineOf(m);
          const enter = fresh && !streamedTs.current.has(m.ts) && !(mine && sentHere.current.has(m.text)) ? true : undefined;
          const line = m.seq === divider ? <div key={`new-${m.seq}`} className="chat-unread-line" data-unread-line role="separator"><span>以下是新消息</span></div> : null;
          if (mine) {
            return [line, (
              <div key={m.seq} className="msg msg-mine" data-author="你" data-ts={m.ts} data-role="person" data-enter={enter}>
                <Quotes quotes={m.quotes} />
                {m.text && <div className="msg-bubble"><div className="msg-plain">{m.text}</div></div>}
                <Files owner={ownerOf} files={m.attachments} />
                {pending.has(m.seq) && Date.now() - m.createdAt > 1000
                  ? <span className="msg-time msg-waiting"><span className="spinner" aria-hidden="true" />等待 agent 接收</span>
                  : <Time className="msg-time" at={m.createdAt} />}
              </div>
            )];
          }
          const agent = m.authorKind === "agent" ? agentOf(m.author) : undefined;
          const who = m.authorKind === "agent" ? agent?.who ?? m.authorName ?? "agent" : m.authorKind === "ember" ? "ember" : name(m);
          return [line, (
            <div key={m.seq} className="msg msg-row" data-author={who} data-ts={m.ts} data-role={m.authorKind === "agent" ? "agent" : "person"} data-enter={enter}>
              <div className="msg-main">
                <div className="msg-head">
                  <MessageAvatar message={m} name={who} agent={agent} />
                  {agent
                    ? <button type="button" className="msg-name msg-agent" onClick={() => onOpenHistory(agent.key)} title="打开或关闭执行历史">{who}</button>
                    : <span className="msg-name">{who}</span>}
                  <Time className="msg-time" at={m.createdAt} />
                </div>
                <Quotes quotes={m.quotes} />
                {m.authorKind === "person"
                  ? m.text && <div className="msg-plain">{mention(m.text)}</div>
                  : <div className="markdown"><Prose>{m.text}</Prose></div>}
                <Files owner={ownerOf} files={m.attachments} />
              </div>
            </div>
          )];
        })}
        {outbox.map((o) => (
          <div key={o.id} className="msg msg-mine" data-author="你" data-role="person" data-enter>
            <Quotes quotes={o.quotes} />
            {o.text && <div className="msg-bubble"><div className="msg-plain">{o.text}</div></div>}
            <Files owner={ownerOf} files={o.attachments} />
            {o.state === "failed"
              ? <span className="msg-time msg-failed">发送失败{o.error ? `：${o.error}` : ""}
                  <button type="button" className="inline-link" onClick={() => void sending.retry(thread.id, o.id).catch(() => {})}>重试</button>
                  <button type="button" className="inline-link" onClick={() => void sending.discard(thread.id, o.id)}>删除</button>
                </span>
              : <span className="msg-time msg-waiting msg-sending"><span className="spinner" aria-hidden="true" />正在发送</span>}
          </div>
        ))}
        {(() => {
          // An agent writing to this chat right now: its chat_post, as far as it has streamed.
          let writer: ChatAgent | undefined;
          let text: string | null = null;
          for (const a of agents) {
            const step = a.live?.steps.find((s) => s.step === "tool" && !s.ended && toolName(s.tool) === "chat_post" && partialString(s.input, "to") === address);
            text = step ? partialString(step.input, "text") : null;
            if (text) { writer = a; break; }
          }
          // Once written, the reply stays in place until the posted message arrives, so it never blinks out between the two.
          let reply: { agent: ChatAgent; text: string } | null = null;
          if (text && writer) {
            reply = { agent: writer, text };
            heldReply.current = { ...reply, count: messages.length };
          } else if (heldReply.current && messages.length === heldReply.current.count) reply = heldReply.current;
          else heldReply.current = null;
          if (reply) wasWriting.current = true;
          // The reply being written, under the activity (which stays while the agent works).
          const writingNow = reply ? (
            <div className="msg msg-row" data-author={reply.agent.who}>
              <div className="msg-main">
                <div className="msg-head">
                  <span className="msg-avatar msg-avatar-agent"><ModelLogo model={reply.agent.model} runtime={reply.agent.runtime} size={12} /></span>
                  <button type="button" className="msg-name msg-agent" onClick={() => onOpenHistory(reply.agent.key)}>{reply.agent.who}</button>
                  <span className="msg-time">正在输入</span>
                </div>
                <div className="markdown h-live"><Prose>{reply.text}</Prose></div>
              </div>
            </div>
          ) : null;
          if (!busy && !lastAgents.current) return writingNow;
          const atWork: AgentAtWork[] = busy ? busyAgents.map((a) => ({
            key: a.key, who: a.who, runtime: a.runtime, model: a.model,
            timeline: a.live?.timeline ?? [], live: a.live?.steps ?? [], phase: a.live?.phase ?? null,
            since: a.turns.at(-1)?.endedAt == null ? a.turns.at(-1)?.startedAt ?? null : null,
          })) : lastAgents.current!;
          if (busy) lastAgents.current = atWork;
          // The activity is always the last thing in the chat; the reply being written comes before it.
          return <>{writingNow}<Activities onOpenHistory={onOpenHistory} agents={atWork} leaving={leaving} /></>;
        })()}
        <div ref={floor} className="chat-floor" aria-hidden="true" />
      </div>
      {picked && (
        <button type="button" className="quote-pop" style={{ left: picked.at.x, top: picked.at.y }}
          onMouseDown={(e) => e.preventDefault()}
          onClick={() => { setQuotes((all) => [...all, picked.quote]); setFocusQuote(picked.quote.id); setPicked(null); window.getSelection()?.removeAllRanges(); }}>
          <QuoteIcon size={12} strokeWidth={2.2} />引用
        </button>
      )}
      {thread.surface === "ember"
        ? <Composer thread={thread.id} sessionKey={keeper} quotes={quotes} setQuotes={setQuotes} focusQuote={focusQuote} onFocused={() => setFocusQuote(null)} />
        : <SlackReply chat={chat} />}
    </section>
  );
}

/** Where a Slack thread's composer would be: people answer it in Slack. */
function SlackReply({ chat }: { chat: ChatView }) {
  const connect = chat.agents.find((a) => a.connect?.kind === "slack")?.connect ?? null;
  const url = slackThreadUrl(slackWorkspaceUrl(connect), chat.thread.channel, chat.thread.threadTs);
  return (
    <div className="composer-wrap">
      <p className="chat-slack-reply">
        {url
          ? <a className="inline-link" href={url} target="_blank" rel="noopener"><SlackLogo size={13} />在 Slack 里回复</a>
          : <span className="muted"><SlackLogo size={13} />在 Slack 里回复</span>}
      </p>
    </div>
  );
}

/**
 * The line over the first message the viewer had not read when the chat
 * opened (not their own), and the jump to it: the read position is taken as
 * the chat opens and does not move during the visit, so the line stays put as
 * the chat is read. Older pages are loaded first when it lies above them.
 * Nothing unread: no line, and the chat opens at its bottom. Answers the seq
 * of the message the line goes over.
 */
function useUnreadLine(ref: RefObject<HTMLElement | null>, chat: ChatView, messages: MessageView[], mine: (m: MessageView) => boolean, older: () => Promise<unknown>): number | null {
  // What was unread when the chat opened: after the read position, up to the newest message then.
  const [open] = useState(() => ({ read: chat.thread.read, newest: chat.thread.last?.seq ?? 0, unread: chat.thread.unread > 0 }));
  const first = messages[0]?.seq;
  // Those not loaded yet may hold it: the pages before are loaded first.
  const above = open.unread && chat.more && first !== undefined && first > open.read;
  const target = open.unread && !above ? messages.find((m) => m.seq > open.read && m.seq <= open.newest && !mine(m))?.seq ?? null : null;
  const asked = useRef<number | undefined>(undefined);
  const jumped = useRef(!open.unread);
  const load = useRef(older);
  load.current = older;
  useEffect(() => {
    if (!above || asked.current === first) return;
    asked.current = first;
    void load.current().catch(() => { asked.current = undefined; });
  }, [above, first]);
  useEffect(() => {
    if (jumped.current || above) return;
    jumped.current = true;
    const pane = ref.current;
    const line = pane?.querySelector<HTMLElement>("[data-unread-line]");
    if (!pane || !line) return;
    // A reader's move: the pane lets it take the position instead of holding its bottom.
    pane.dispatchEvent(new WheelEvent("wheel"));
    pane.scrollTop += line.getBoundingClientRect().top - pane.getBoundingClientRect().top - 12;
  }, [ref, above, target]);
  return target;
}

/**
 * Loads the page of messages before those shown when the reader comes near
 * the top (or when what is loaded does not fill the pane). What is on screen
 * stays put: the pane keeps its distance from the bottom as content grows
 * above (scroll.ts).
 */
function useOlderOnScroll(ref: RefObject<HTMLElement | null>, chat: ChatView, older: () => Promise<unknown>): void {
  // The oldest message a page was asked before: one request per page.
  const asked = useRef<number | undefined>(undefined);
  const more = chat.more;
  const first = chat.messages[0]?.seq;
  const load = useRef(older);
  load.current = older;
  useEffect(() => {
    const el = ref.current;
    if (!el || !more) return;
    const check = () => {
      if (asked.current === first || el.scrollTop > 300) return;
      asked.current = first;
      void load.current().catch(() => { asked.current = undefined; });
    };
    check();
    el.addEventListener("scroll", check, { passive: true });
    return () => el.removeEventListener("scroll", check);
  }, [ref, more, first]);
}

/**
 * Records how far the viewer has read: up to the newest message, whenever the
 * chat's bottom is in view on a visible page.
 */
function useMarkRead(floor: RefObject<HTMLElement | null>, chat: ChatView, read: (seq: number) => Promise<unknown>): void {
  const newest = chat.messages.at(-1)?.seq ?? 0;
  const known = chat.thread.read;
  const sent = useRef(0);
  const record = useRef(read);
  record.current = read;
  useEffect(() => {
    const el = floor.current;
    if (!el || newest <= known) return;
    let seen = false;
    const mark = () => {
      if (!seen || document.visibilityState !== "visible" || sent.current >= newest) return;
      sent.current = newest;
      void record.current(newest).catch(() => { sent.current = 0; });
    };
    const observer = new IntersectionObserver((entries) => {
      seen = entries.some((e) => e.isIntersecting);
      mark();
    });
    observer.observe(el);
    document.addEventListener("visibilitychange", mark);
    return () => {
      observer.disconnect();
      document.removeEventListener("visibilitychange", mark);
    };
  }, [floor, newest, known]);
}

function MessageAvatar({ message, name, agent }: { message: MessageView; name: string; agent: ChatAgent | undefined }) {
  const member = usePerson();
  if (message.authorKind === "agent") return <span className="msg-avatar msg-avatar-agent">{agent ? <ModelLogo model={agent.model} runtime={agent.runtime} size={12} /> : <Mark size={12} />}</span>;
  if (message.authorKind === "ember") return <span className="msg-avatar msg-avatar-agent"><Mark size={12} /></span>;
  const picture = member(message.author)?.picture;
  return picture
    ? <img className="msg-avatar" src={picture} alt="" width={18} height={18} referrerPolicy="no-referrer" />
    : <span className="msg-avatar"><Avatar id={message.author} name={name} size={18} /></span>;
}

/**
 * Quotes as sent, each a card of its own ahead of the message: the quoted
 * part on a warm ground (whose message, the passage) leading back to it, then
 * what was said about it.
 */
function Quotes({ quotes }: { quotes: Quote[] | undefined }) {
  if (!quotes?.length) return null;
  const jump = (ts: string | undefined, text: string) => {
    const target = ts ? document.querySelector<HTMLElement>(`.chat-list [data-ts="${ts}"]`) : null;
    if (!target) return;
    // A reader's move: the pane lets it take the position.
    target.closest(".chat-list")?.dispatchEvent(new WheelEvent("wheel"));
    const range = findText(target, text);
    if (range && "highlights" in CSS) {
      const rect = range.getBoundingClientRect();
      const pane = target.closest<HTMLElement>(".chat-list");
      if (pane) pane.scrollTop += rect.top + rect.height / 2 - (pane.getBoundingClientRect().top + pane.clientHeight / 2);
      flashRange(range);
      return;
    }
    target.scrollIntoView({ block: "center" });
    target.classList.remove("msg-flash");
    void target.offsetWidth;
    target.classList.add("msg-flash");
  };
  return (
    <div className="quote-cards">
      {quotes.map((q, i) => <QuoteCard key={i} quote={q} onJump={q.ts ? () => jump(q.ts, q.text) : undefined} />)}
    </div>
  );
}

/** One quote: the passage with whose it is, and the comment. Also the composer's pending quote, with an editable comment. */
function QuoteCard({ quote, onJump, comment, onRemove }: { quote: Quote; onJump?: (() => void) | undefined; comment?: ReactNode; onRemove?: () => void }) {
  return (
    <div className="quote-card">
      <button type="button" className="quote-card-source" onClick={onJump} disabled={!onJump} title={onJump ? "跳到原消息" : undefined}>
        <span className="quote-card-text"><QuoteIcon size={11} strokeWidth={2.4} aria-hidden="true" /><span className="quote-card-who">{quote.author}：</span>{quote.text}</span>
      </button>
      {comment ?? (quote.comment ? <div className="quote-card-comment">{quote.comment}</div> : null)}
      {onRemove && <button type="button" className="quote-card-remove" aria-label="移除引用" onClick={onRemove}><X size={12} /></button>}
    </div>
  );
}

// ── files ───────────────────────────────────────────────────────────────

export function fileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

const IMAGE = /\.(png|jpe?g|gif|webp)$/i;
const storedName = (a: Attachment) => a.path.split("/").at(-1)!;

// Files sent never change: each is fetched once per page, and the most recent are kept for a chat opened again.
const blobs = new Map<string, Promise<Blob>>();
const KEEP_BLOBS = 100;

function fetchFile(api: Api, station: string, sessionKey: string, file: Attachment): Promise<Blob> {
  const id = `${station}/${sessionKey}/${file.path}`;
  let blob = blobs.get(id);
  if (!blob) {
    blob = api.file(sessionKey, storedName(file));
    // A failure is not kept: the next look tries again.
    blob.catch(() => blobs.delete(id));
    blobs.set(id, blob);
    if (blobs.size > KEEP_BLOBS) blobs.delete(blobs.keys().next().value!);
  }
  return blob;
}

/** A file as a blob URL, fetched from the station once and kept while shown. */
function useFileUrl(sessionKey: string, file: Attachment, enabled: boolean): string | null {
  const api = useApi();
  const station = useStation();
  const [url, setUrl] = useState<string | null>(null);
  useEffect(() => {
    if (!enabled) return;
    let u: string | null = null;
    let current = true;
    fetchFile(api, station.address, sessionKey, file).then((blob) => {
      if (!current) return;
      u = URL.createObjectURL(blob);
      setUrl(u);
    }, () => {});
    return () => {
      current = false;
      if (u) URL.revokeObjectURL(u);
    };
  }, [api, station.address, sessionKey, file.path, enabled]);
  return url;
}

/** A message's files; `owner` says which session of the chat keeps each (null: none can show it). */
function Files({ owner, files }: { owner: (file: Attachment) => string | null; files: Attachment[] | undefined }) {
  if (!files?.length) return null;
  return <div className="msg-files">{files.map((f) => <FileItem key={f.path} sessionKey={owner(f)} file={f} />)}</div>;
}

/** Images show themselves at their own proportions and open in a lightbox; other files are a card. */
function FileItem({ sessionKey, file }: { sessionKey: string | null; file: Attachment }) {
  const image = IMAGE.test(file.name);
  const url = useFileUrl(sessionKey ?? "", file, image && sessionKey !== null);
  const [open, setOpen] = useState(false);
  if (image) {
    return (
      <>
        <button type="button" className="msg-image" onClick={() => url && setOpen(true)} title={file.path} aria-label={`查看 ${file.name}`} style={imageBox(file)}>
          {url ? <img src={url} alt={file.name} /> : <span className="msg-image-wait" />}
        </button>
        {url && <Lightbox open={open} onClose={() => setOpen(false)} url={url} file={file} />}
      </>
    );
  }
  return <FileCard file={file} />;
}

/**
 * The box an image takes in the chat, known before it loads: its own
 * proportions (sent with it) within 360×300, or a fixed box for images sent
 * before sizes were recorded.
 */
function imageBox(file: Attachment): { width: number; height: number } {
  if (!file.width || !file.height) return { width: 240, height: 160 };
  const scale = Math.min(1, 360 / file.width, 300 / file.height);
  return { width: Math.max(40, Math.round(file.width * scale)), height: Math.max(40, Math.round(file.height * scale)) };
}

/** An image at full size over a dimmed page; Esc or a click outside closes it. */
function Lightbox({ open, onClose, url, file }: { open: boolean; onClose(): void; url: string; file: Attachment }) {
  return (
    <RDialog.Root open={open} onOpenChange={(o) => { if (!o) onClose(); }}>
      <RDialog.Portal>
        <RDialog.Overlay className="lightbox-overlay" />
        <RDialog.Content className="lightbox" aria-describedby={undefined} onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}>
          <RDialog.Title className="sr-only">{file.name}</RDialog.Title>
          <img className="lightbox-image" src={url} alt={file.name} />
          <div className="lightbox-bar">
            <span className="lightbox-name">{file.name}</span>
            <span className="lightbox-size">{fileSize(file.size)}</span>
            <a className="lightbox-action" href={url} download={file.name}><Download size={14} />下载</a>
            <RDialog.Close className="lightbox-action" aria-label="关闭"><X size={14} /></RDialog.Close>
          </div>
        </RDialog.Content>
      </RDialog.Portal>
    </RDialog.Root>
  );
}

function FileCard({ file, onRemove, pending, error }: { file: Pick<Attachment, "name" | "size"> & { path?: string }; onRemove?: () => void; pending?: boolean; error?: string | null }) {
  return (
    <span className="file-card" title={file.path ?? file.name} data-error={error ? true : undefined}>
      {pending ? <span className="spinner" aria-hidden="true" /> : <FileText size={16} aria-hidden="true" />}
      <span className="file-card-text">
        <span className="file-card-name">{file.name}</span>
        <span className="file-card-meta">{error ?? (pending ? "正在上传…" : fileSize(file.size))}</span>
      </span>
      {onRemove && <button type="button" className="file-card-remove" aria-label={`移除 ${file.name}`} onClick={(e) => { e.stopPropagation(); onRemove(); }}><X size={12} /></button>}
    </span>
  );
}

// ── quotes being written ────────────────────────────────────────────────

export interface DraftQuote extends Quote { id: string }

// ── composer ────────────────────────────────────────────────────────────

const MAX_FILE = 50 * 1024 * 1024;

/** A file on its way to the station: uploading, uploaded, or failed. */
interface Pending { id: number; name: string; size: number; done: Attachment | null; error: string | null; preview?: string }

/**
 * Where people write to a chat; a new chat is made by the first message or
 * file. Zork's composer: a soft frame that grows with the text, a round send
 * button, the files and quotes waiting to go above it. Files (picked, pasted
 * or dropped) go to the workspace of a session in the chat on the station as
 * soon as they are added.
 */
export function Composer({ thread, sessionKey, quotes = [], setQuotes = () => {}, focusQuote = null, onFocused = () => {}, ensureChat, onSent, toolbar, placeholder = "发消息", locked = false, roomy = false }: {
  /** The chat written to, and the session its files go to; both null for a new chat, made by `ensureChat` on the first file or message. */
  thread: number | null;
  sessionKey: string | null;
  quotes?: DraftQuote[]; setQuotes?(update: (all: DraftQuote[]) => DraftQuote[]): void;
  /** A quote just added: its comment line takes the focus. */
  focusQuote?: string | null; onFocused?(): void;
  ensureChat?: () => Promise<{ key: string; thread: number }>;
  onSent?: (thread: number) => void;
  /** Choices shown in the toolbar, between attach and send (a new chat's station, model and effort). */
  toolbar?: ReactNode;
  placeholder?: string;
  /** While true (a new chat being made) nothing can be sent. */
  locked?: boolean;
  /** Text above, toolbar below, even for one line (a new chat, whose toolbar holds choices). */
  roomy?: boolean;
}) {
  const api = useApi();
  const [text, setText] = useState("");
  const [files, setFiles] = useState<Pending[]>([]);
  const [dragging, setDragging] = useState(false);
  const input = useRef<HTMLTextAreaElement>(null);
  const picker = useRef<HTMLInputElement>(null);
  const nextId = useRef(1);
  // Typing starts the session's runtime, so a cold start overlaps the writing.
  const warmed = useRef(0);
  const warm = () => {
    if (!sessionKey || Date.now() - warmed.current < 60_000) return;
    warmed.current = Date.now();
    void api.warm(sessionKey).catch(() => {});
  };
  const quoteInputs = useRef(new Map<string, HTMLInputElement>());
  useEffect(() => {
    if (!focusQuote) return;
    quoteInputs.current.get(focusQuote)?.focus();
    onFocused();
  }, [focusQuote]);
  const target = async (): Promise<{ key: string | null; thread: number }> => (thread !== null ? { key: sessionKey, thread } : await ensureChat!());
  const chat = useChatSend();
  const [starting, setStarting] = useState(false);
  const [sendError, setSendError] = useState<Error | null>(null);
  // The composer empties at once: the message lives in the chat's outbox until the station has it (a failure shows there too).
  const send = async (value: string) => {
    const kept = { text, files, quotes };
    const attachments = files.flatMap((f) => (f.done ? [f.done] : []));
    const sent = quotes.map(({ author, text: t, comment, ts, role }) => ({ author, text: t, comment: comment.trim(), ...(ts ? { ts } : {}), ...(role ? { role } : {}) }));
    setText(""); setFiles([]); setQuotes(() => []); setSendError(null);
    let to: number;
    try {
      setStarting(thread === null);
      to = (await target()).thread;
    } catch (error) {
      // No chat to send into (a new one could not be made): the draft comes back.
      setText(kept.text); setFiles(kept.files); setQuotes(() => kept.quotes);
      setSendError(error instanceof Error ? error : new Error(String(error)));
      return;
    } finally {
      setStarting(false);
    }
    for (const f of kept.files) if (f.preview) URL.revokeObjectURL(f.preview);
    void chat.send(to, value, attachments, sent).catch(() => {});
    onSent?.(to);
  };
  const add = (list: FileList | File[]) => {
    for (const file of Array.from(list)) {
      const id = nextId.current++;
      const tooBig = file.size > MAX_FILE;
      // Images show at once from the local file; the preview URL lives until the file leaves the composer.
      const preview = file.type.startsWith("image/") ? URL.createObjectURL(file) : undefined;
      setFiles((all) => [...all, { id, name: file.name, size: file.size, done: null, error: tooBig ? "超过 50 MB" : null, ...(preview ? { preview } : {}) }]);
      if (tooBig) continue;
      target().then(({ key }) => {
        if (!key) throw new Error("这个对话里没有 agent，文件无处可放");
        return api.uploadFile(key, file);
      }).then(
        (done) => setFiles((all) => all.map((f) => (f.id === id ? { ...f, done } : f))),
        (error: unknown) => setFiles((all) => all.map((f) => (f.id === id ? { ...f, error: error instanceof Error ? error.message : "上传失败" } : f))),
      );
    }
  };
  // Switching to a chat puts the cursor in its composer (not on touch screens, where it would raise the keyboard).
  useEffect(() => {
    if (window.matchMedia("(pointer: fine)").matches) input.current?.focus();
  }, [thread]);
  // Grow with the text up to the frame's limit; the frame is never resized by hand.
  useEffect(() => {
    const el = input.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = `${Math.min(el.scrollHeight, 160)}px`;
  }, [text]);
  const uploading = files.some((f) => !f.done && !f.error);
  const ready = (Boolean(text.trim()) || files.some((f) => f.done) || quotes.length > 0) && !uploading && !starting && !locked;
  const submit = () => {
    if (ready) void send(text.trim());
  };
  return (
    <div className="composer-wrap">
      <form className="composer-box" data-multiline={roomy || text.includes("\n") || text.length > 60 || files.length > 0 || quotes.length > 0 || undefined} data-dragging={dragging || undefined}
        onSubmit={(e) => { e.preventDefault(); submit(); }} onClick={() => input.current?.focus()}
        onDragOver={(e) => { if (e.dataTransfer.types.includes("Files")) { e.preventDefault(); setDragging(true); } }}
        onDragLeave={() => setDragging(false)}
        onDrop={(e) => { if (e.dataTransfer.files.length) { e.preventDefault(); setDragging(false); add(e.dataTransfer.files); } }}>
        {quotes.length > 0 && (
          <div className="composer-quotes">
            {quotes.map((q) => (
              <div key={q.id} className="composer-quote" onClick={(e) => e.stopPropagation()}>
                <QuoteCard quote={q} onRemove={() => setQuotes((all) => all.filter((x) => x.id !== q.id))} comment={
                  <input ref={(el) => { if (el) quoteInputs.current.set(q.id, el); else quoteInputs.current.delete(q.id); }}
                    className="quote-card-comment quote-card-input" value={q.comment} placeholder="对这段说点什么（可以不写）" aria-label={`对 ${q.author} 这段的批注`}
                    onChange={(e) => { const v = e.target.value; setQuotes((all) => all.map((x) => (x.id === q.id ? { ...x, comment: v } : x))); }}
                    onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing) { e.preventDefault(); input.current?.focus(); } }} />
                } />
              </div>
            ))}
          </div>
        )}
        {files.length > 0 && (
          <div className="composer-files">
            {files.map((f) => {
              const remove = () => { if (f.preview) URL.revokeObjectURL(f.preview); setFiles((all) => all.filter((x) => x.id !== f.id)); };
              return f.preview ? (
                <span key={f.id} className="composer-thumb" title={f.error ?? f.name} data-error={f.error ? true : undefined}>
                  <img src={f.preview} alt={f.name} />
                  {!f.done && !f.error && <span className="composer-thumb-busy"><span className="spinner" aria-hidden="true" /></span>}
                  <button type="button" className="composer-thumb-remove" aria-label={`移除 ${f.name}`} onClick={(e) => { e.stopPropagation(); remove(); }}><X size={11} /></button>
                </span>
              ) : <FileCard key={f.id} file={f.done ?? f} pending={!f.done && !f.error} error={f.error} onRemove={remove} />;
            })}
          </div>
        )}
        <textarea ref={input} className="composer-text" rows={1} value={text} placeholder={placeholder} aria-label="消息"
          onChange={(e) => { setText(e.target.value); warm(); }}
          onPaste={(e) => { if (e.clipboardData.files.length) { e.preventDefault(); add(e.clipboardData.files); } }}
          onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) { e.preventDefault(); submit(); } }} />
        <div className="composer-toolbar">
          <input ref={picker} type="file" multiple hidden onChange={(e) => { if (e.target.files) add(e.target.files); e.target.value = ""; }} />
          <Tip label="发送文件">
            <button type="button" className="attach-btn" aria-label="发送文件" onClick={(e) => { e.stopPropagation(); picker.current?.click(); }}>
              <Plus size={18} />
            </button>
          </Tip>
          {toolbar && <div className="composer-choices" onClick={(e) => e.stopPropagation()}>{toolbar}</div>}
          <Tip label={uploading ? "文件还在上传" : "发送"}>
            <button type="submit" className="send-btn" disabled={!ready} aria-label="发送" aria-busy={starting || undefined}>
              {starting ? <span className="spinner" aria-hidden="true" /> : <ArrowUp size={16} strokeWidth={2} />}
            </button>
          </Tip>
        </div>
      </form>
      {sendError && <p className="field-error chat-error" role="alert">{sendError.message}</p>}
    </div>
  );
}

/** An agent in this chat that is at work: who it is, its execution history, and its running turn. */
interface AgentAtWork {
  key: string; who: string; runtime: SessionSummary["runtime"]; model: string | null;
  timeline: TimelineEntry[]; live: ShownStep[]; phase: ShownPhase | null; since: number | null;
}

/** A row of an agent's activity: one entry of its execution history, or a step still streaming. */
interface ActivityRow { key: string; text: string; live: boolean }

/**
 * The running turn's rows: execution history since the last message the agent
 * received, then what is still streaming. Rows say what the agent did for the
 * person watching: a reply being written shows as the message itself, not a
 * row; recording state and the agent's own narration are left out.
 */
function activityRows(timeline: TimelineEntry[], live: ShownStep[], phase: ShownPhase | null): ActivityRow[] {
  let start = timeline.length;
  while (start > 0 && !(timeline[start - 1]!.kind === "user" && !timeline[start - 1]!.subagent)) start--;
  const done = (tool: string | undefined, input: string): string | null => {
    const name = toolName(tool);
    if (name === "chat_state") return null;
    if (name === "chat_post") return "发出回复";
    if (name === "chat_history") return "查看对话";
    return activityText(tool, input).replace(/^正在/, "");
  };
  const rows: ActivityRow[] = [];
  timeline.slice(start).forEach((e, i) => {
    if (e.subagent) return;
    const text = e.kind === "tool_call" ? done(e.tool, e.text) : e.kind === "thinking" ? "思考" : null;
    if (text) rows.push({ key: `t${start + i}`, text, live: false });
  });
  for (const s of live) {
    if (s.ended || s.subagent || s.step === "text") continue;
    const name = toolName(s.tool);
    if (s.step === "tool" && (name === "chat_post" || name === "chat_state")) continue;
    rows.push({ key: s.id, text: s.step === "thinking" ? "正在思考" : activityText(s.tool, s.input), live: true });
  }
  if (!rows.some((r) => r.live) && phase) {
    const waiting = phase.phase === "starting" ? "正在启动" : phase.phase === "requesting" ? "等待模型响应" : phase.phase === "responding" ? "正在思考" : null;
    if (waiting) rows.push({ key: `phase-${phase.phase}-${phase.since}`, text: waiting, live: true });
  }
  return rows;
}

const ACTIVITY_COLLAPSED = "ember.activityCollapsed";

/**
 * One activity per agent of the chat that is at work, drawn like its
 * messages. A runtime's own sub-agents are not agents of the chat; their
 * work is one row of the agent's.
 */
function Activities({ agents, onOpenHistory, leaving = false }: { agents: AgentAtWork[]; onOpenHistory(key: string): void; leaving?: boolean }) {
  const [collapsed, setCollapsed] = useState(() => localStorage.getItem(ACTIVITY_COLLAPSED) === "1");
  const toggle = () => {
    localStorage.setItem(ACTIVITY_COLLAPSED, collapsed ? "0" : "1");
    setCollapsed(!collapsed);
  };
  return <>{agents.map((a) => <Activity key={a.key} agent={a} collapsed={collapsed} onToggle={toggle} onOpen={() => onOpenHistory(a.key)} leaving={leaving} />)}</>;
}

/**
 * An agent at work: its last three rows in three fixed lines (or the newest
 * in one). A new row comes in from below and pushes the oldest out above.
 */
function Activity({ agent, collapsed, onToggle, onOpen, leaving }: { agent: AgentAtWork; collapsed: boolean; onToggle(): void; onOpen(): void; leaving: boolean }) {
  const rows = activityRows(agent.timeline, agent.live, agent.phase);
  const count = collapsed ? 1 : 3;
  // Rows fill from the top; once there are more than fit, one extra row is kept above so it can slide out as the rest move up.
  if (!rows.length) rows.push({ key: "idle", text: "正在处理", live: true });
  const shown = rows.slice(-(count + 1));
  const overflowing = shown.length > count;
  const newest = shown.at(-1)?.key ?? "none";
  return (
    <div className="msg msg-row agent-activity" data-transient="" data-collapsed={collapsed || undefined} data-leaving={leaving || undefined}>
      <div className="msg-main">
        <div className="msg-head">
          <span className="msg-avatar msg-avatar-agent"><ModelLogo model={agent.model} runtime={agent.runtime} size={12} /></span>
          <button type="button" className="msg-name msg-agent" onClick={onOpen} title="打开执行历史">{agent.who}</button>
          <span className="msg-time">工作中{agent.since ? <> · <Elapsed since={agent.since} /></> : null}</span>
          <button type="button" className="activity-toggle" onClick={onToggle} aria-label={collapsed ? "展开为三行" : "收起为一行"}>
            {collapsed ? <ChevronDown size={13} /> : <ChevronUp size={13} />}
          </button>
        </div>
        <div className="activity-window">
          <div key={overflowing ? newest : "fill"} className="activity-rows" data-shift={overflowing || undefined}>
            {shown.map((r) => (
              <span key={r.key} className="activity-row" data-live={r.live || undefined}>
                <span className="activity-mark" aria-hidden="true">{r.live ? <span className="activity-pulse" /> : <span className="activity-done" />}</span>
                <span className="activity-what">{r.text}{r.live ? "…" : ""}</span>
              </span>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

/** Seconds (then minutes) since a moment, ticking. */
function Elapsed({ since }: { since: number }) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, []);
  const s = Math.max(0, Math.floor((now - since) / 1000));
  return <>{s < 60 ? `${s}s` : `${Math.floor(s / 60)}m ${s % 60}s`}</>;
}

/** The quoted passage inside a message, as a range over its text nodes (whitespace-insensitive), or null. */
function findText(root: Element, wanted: string): Range | null {
  const nodes: Text[] = [];
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  for (let n = walker.nextNode(); n; n = walker.nextNode()) nodes.push(n as Text);
  // Collapse whitespace on both sides, keeping a map from the collapsed text back to node offsets.
  let flat = "";
  const map: { node: Text; offset: number }[] = [];
  for (const node of nodes) {
    const t = node.data;
    for (let i = 0; i < t.length; i++) {
      const c = /\s/.test(t[i]!) ? " " : t[i]!;
      if (c === " " && flat.endsWith(" ")) continue;
      flat += c;
      map.push({ node, offset: i });
    }
  }
  const needle = wanted.replace(/\s+/g, " ").trim();
  const at = needle ? flat.indexOf(needle) : -1;
  if (at < 0) return null;
  const start = map[at]!, end = map[at + needle.length - 1]!;
  const range = document.createRange();
  range.setStart(start.node, start.offset);
  range.setEnd(end.node, end.offset + 1);
  return range;
}

let flashTimer: ReturnType<typeof setTimeout> | undefined;
/** Highlights a range for a moment (CSS custom highlights; the style fades via the ::highlight rule). */
function flashRange(range: Range): void {
  const highlights = (CSS as unknown as { highlights: Map<string, unknown> }).highlights;
  const Highlight = (window as unknown as { Highlight: new (...r: Range[]) => unknown }).Highlight;
  highlights.set("quote-flash", new Highlight(range));
  document.documentElement.dataset.quoteFlash = "on";
  clearTimeout(flashTimer);
  flashTimer = setTimeout(() => { document.documentElement.dataset.quoteFlash = "fading"; }, 1600);
  setTimeout(() => {
    if (document.documentElement.dataset.quoteFlash === "fading") { highlights.delete("quote-flash"); delete document.documentElement.dataset.quoteFlash; }
  }, 2600);
}
