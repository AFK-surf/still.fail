// ember's own chat with a session, after Zork's: your messages sit right in a
// bubble with only their time; everyone else (people and the agent) gets an
// avatar, a name and the time over their words. Passages of earlier messages
// can be quoted with a comment, and files ride along as cards (images shown).
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ArrowUp, ChevronDown, ChevronUp, FileText, Plus, Quote as QuoteIcon, X } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { keys, useApi, type Attachment, type ChatMessageRow, type Quote, type SessionDetail, type ShownPhase, type ShownStep } from "./api.ts";
import { activityText, partialString, toolName } from "./History.tsx";
import { absoluteTime, agentLabel, relativeTime, sessionStatus } from "./format.ts";
import { useIsMine, usePerson, useStation } from "./station.tsx";
import { Avatar, ModelLogo, Time, Tip } from "./ui.tsx";
import { Prose } from "./Prose.tsx";

export function ChatPanel({ detail, chat, live = [], phase = null, onOpenHistory }: { detail: SessionDetail; chat: SessionDetail["chats"][number] | undefined; live?: ShownStep[]; phase?: ShownPhase | null; onOpenHistory(): void }) {
  const list = useRef<HTMLDivElement>(null);
  const messages = chat?.messages ?? [];
  const [quotes, setQuotes] = useState<DraftQuote[]>([]);
  const [focusQuote, setFocusQuote] = useState<string | null>(null);
  const [picked, setPicked] = useState<{ quote: DraftQuote; at: { x: number; y: number } } | null>(null);
  useEffect(() => {
    if (list.current) list.current.scrollTop = list.current.scrollHeight;
  }, [messages.length]);
  // Messages there when the chat opened show at once; later ones ease in, except a reply that already streamed in place.
  const firstCount = useRef<number | null>(null);
  if (firstCount.current === null) firstCount.current = messages.length;
  const wasWriting = useRef(false);
  const streamedTs = useRef(new Set<string>());
  const status = sessionStatus(detail.session);
  const busy = status === "running" || status === "queued";
  const member = usePerson();
  const isMine = useIsMine();
  const name = (id: string) => member(id)?.name || detail.people[id] || (id === "local" ? "本机" : id);
  // Your messages the runtime has not taken yet; after a second they show that they wait.
  const pendingTs = new Set(detail.inbound.filter((i) => i.status === "pending").map((i) => i.ts));
  const [, tick] = useState(0);
  const youngest = messages.filter((m) => pendingTs.has(m.ts)).reduce((t, m) => Math.max(t, m.createdAt), 0);
  useEffect(() => {
    const wait = youngest + 1000 - Date.now();
    if (!youngest || wait <= 0) return;
    const timer = setTimeout(() => tick((n) => n + 1), wait + 20);
    return () => clearTimeout(timer);
  }, [youngest]);
  const agent = agentLabel(detail.transcript?.usage?.model ?? detail.session.model, detail.session.effort);

  // Selecting text inside one message offers to quote it.
  const onSelect = () => {
    const selection = window.getSelection();
    const text = selection?.toString().trim();
    if (!selection || !text || selection.rangeCount === 0) return setPicked(null);
    const range = selection.getRangeAt(0);
    const from = (range.commonAncestorContainer instanceof Element ? range.commonAncestorContainer : range.commonAncestorContainer.parentElement)?.closest<HTMLElement>("[data-author]");
    if (!from) return setPicked(null);
    const rect = range.getBoundingClientRect();
    setPicked({ quote: { id: `${Date.now()}`, author: from.dataset.author!, text, comment: "" }, at: { x: rect.left + rect.width / 2, y: rect.top } });
  };

  return (
    <section className="chat" aria-label="对话">
      <div className="chat-list" ref={list} onMouseUp={() => setTimeout(onSelect, 0)} onScroll={() => setPicked(null)}>
        {messages.length === 0 && (
          <div className="chat-empty">
            <p>在这里给这个会话发消息，agent 会在这里回复。</p>
            <p className="muted">{detail.threads.some((t) => t.channel !== "EMBER") ? "它在 Slack 里的来往，在右边的执行历史里能看到。" : ""}</p>
          </div>
        )}
        {messages.map((m, index) => {
          if (index >= firstCount.current! && m.role === "agent" && wasWriting.current && !streamedTs.current.has(m.ts)) {
            streamedTs.current.add(m.ts);
            wasWriting.current = false;
          }
          const enter = index >= firstCount.current! && !streamedTs.current.has(m.ts) ? true : undefined;
          const mine = m.role === "person" && isMine({ id: m.user, email: m.user });
          if (mine) {
            return (
              <div key={m.ts} className="msg msg-mine" data-author="你" data-enter={enter}>
                {(m.text || m.quotes?.length) ? (
                  <div className="msg-bubble">
                    <Quotes quotes={m.quotes} />
                    {m.text && <div className="msg-plain">{m.text}</div>}
                  </div>
                ) : null}
                <Files sessionKey={detail.session.key} files={m.attachments} />
                {pendingTs.has(m.ts) && Date.now() - m.createdAt > 1000
                  ? <span className="msg-time msg-waiting"><span className="spinner" aria-hidden="true" />等待 agent 接收</span>
                  : <Time className="msg-time" at={m.createdAt} />}
              </div>
            );
          }
          const who = m.role === "agent" ? agent : name(m.user);
          return (
            <div key={m.ts} className="msg msg-row" data-author={who} data-enter={enter}>
              <div className="msg-main">
                <div className="msg-head">
                  <MessageAvatar message={m} name={who} runtime={detail.session.runtime} model={detail.transcript?.usage?.model ?? detail.session.model} />
                  {m.role === "agent"
                    ? <button type="button" className="msg-name msg-agent" onClick={onOpenHistory} title="打开或关闭执行历史">{who}</button>
                    : <span className="msg-name">{who}</span>}
                  <Time className="msg-time" at={m.createdAt} />
                </div>
                <Quotes quotes={m.quotes} />
                {m.role === "agent"
                  ? <div className="markdown"><Prose>{m.text}</Prose></div>
                  : m.text && <div className="msg-plain">{m.text}</div>}
                <Files sessionKey={detail.session.key} files={m.attachments} />
              </div>
            </div>
          );
        })}
        {(() => {
          // The agent writing to this chat right now: its chat_post, as far as it has streamed.
          const writing = live.find((s) => s.step === "tool" && !s.ended && toolName(s.tool) === "chat_post" && (partialString(s.input, "to") ?? "").startsWith("EMBER/"));
          const text = writing ? partialString(writing.input, "text") : null;
          if (text) wasWriting.current = true;
          if (text) {
            return (
              <div className="msg msg-row" data-author={agent}>
                <div className="msg-main">
                  <div className="msg-head">
                    <span className="msg-avatar msg-avatar-agent"><ModelLogo model={detail.transcript?.usage?.model ?? detail.session.model} runtime={detail.session.runtime} size={12} /></span>
                    <button type="button" className="msg-name msg-agent" onClick={onOpenHistory}>{agent}</button>
                    <span className="msg-time">正在输入</span>
                  </div>
                  <div className="markdown h-live"><Prose>{text}</Prose></div>
                </div>
              </div>
            );
          }
          if (!busy) return null;
          return <Activity steps={live} phase={phase} agent={agent} onOpenHistory={onOpenHistory} />;
        })()}
      </div>
      {picked && (
        <button type="button" className="quote-pop" style={{ left: picked.at.x, top: picked.at.y }}
          onMouseDown={(e) => e.preventDefault()}
          onClick={() => { setQuotes((all) => [...all, picked.quote]); setFocusQuote(picked.quote.id); setPicked(null); window.getSelection()?.removeAllRanges(); }}>
          <QuoteIcon size={12} strokeWidth={2.2} />引用
        </button>
      )}
      <Composer sessionKey={detail.session.key} quotes={quotes} setQuotes={setQuotes} focusQuote={focusQuote} onFocused={() => setFocusQuote(null)} />
    </section>
  );
}

function MessageAvatar({ message, name, runtime, model }: { message: ChatMessageRow; name: string; runtime: SessionDetail["session"]["runtime"]; model: string | null }) {
  const member = usePerson();
  if (message.role === "agent") return <span className="msg-avatar msg-avatar-agent"><ModelLogo model={model} runtime={runtime} size={12} /></span>;
  const picture = member(message.user)?.picture;
  return picture
    ? <img className="msg-avatar" src={picture} alt="" width={18} height={18} referrerPolicy="no-referrer" />
    : <span className="msg-avatar"><Avatar id={message.user} name={name} size={18} /></span>;
}

/** Quoted passages as sent: who said it, the passage, then the comment. */
function Quotes({ quotes }: { quotes: Quote[] | undefined }) {
  if (!quotes?.length) return null;
  return (
    <div className="msg-quotes">
      {quotes.map((q, i) => (
        <div key={i} className="msg-quote">
          <span className="msg-quote-author">{q.author}</span>
          <blockquote>{q.text}</blockquote>
          {q.comment && <div className="msg-plain">{q.comment}</div>}
        </div>
      ))}
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

/** A file as a blob URL, fetched from the station once and kept while shown. */
function useFileUrl(sessionKey: string, file: Attachment, enabled: boolean): string | null {
  const api = useApi();
  const station = useStation();
  const blob = useQuery({
    queryKey: ["file", station.id, sessionKey, file.path],
    queryFn: () => api.file(sessionKey, storedName(file)),
    enabled, staleTime: Infinity, gcTime: 10 * 60_000,
  });
  const [url, setUrl] = useState<string | null>(null);
  useEffect(() => {
    if (!blob.data) return;
    const u = URL.createObjectURL(blob.data);
    setUrl(u);
    return () => URL.revokeObjectURL(u);
  }, [blob.data]);
  return url;
}

function Files({ sessionKey, files }: { sessionKey: string; files: Attachment[] | undefined }) {
  if (!files?.length) return null;
  return <div className="msg-files">{files.map((f) => <FileItem key={f.path} sessionKey={sessionKey} file={f} />)}</div>;
}

/** Images show themselves at their own proportions; other files are a card that opens them. */
function FileItem({ sessionKey, file }: { sessionKey: string; file: Attachment }) {
  const image = IMAGE.test(file.name);
  const url = useFileUrl(sessionKey, file, image);
  if (image) {
    return (
      <a className="msg-image" href={url ?? undefined} target="_blank" rel="noopener" title={file.path}>
        {url ? <img src={url} alt={file.name} /> : <span className="msg-image-wait" />}
      </a>
    );
  }
  return <FileCard file={file} />;
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

interface DraftQuote extends Quote { id: string }

// ── composer ────────────────────────────────────────────────────────────

const MAX_FILE = 50 * 1024 * 1024;

/** A file on its way to the station: uploading, uploaded, or failed. */
interface Pending { id: number; name: string; size: number; done: Attachment | null; error: string | null }

/**
 * Where people write to the session; the first message makes its chat. Zork's
 * composer: a soft frame that grows with the text, a round send button, the
 * files and quotes waiting to go above it. Files (picked, pasted or dropped)
 * go to the session's workspace on the station as soon as they are added.
 */
function Composer({ sessionKey, quotes, setQuotes, focusQuote, onFocused }: {
  sessionKey: string; quotes: DraftQuote[]; setQuotes(update: (all: DraftQuote[]) => DraftQuote[]): void;
  /** A quote just added: its comment line takes the focus. */
  focusQuote: string | null; onFocused(): void;
}) {
  const api = useApi();
  const station = useStation();
  const client = useQueryClient();
  const [text, setText] = useState("");
  const [files, setFiles] = useState<Pending[]>([]);
  const [dragging, setDragging] = useState(false);
  const input = useRef<HTMLTextAreaElement>(null);
  const picker = useRef<HTMLInputElement>(null);
  const nextId = useRef(1);
  // Typing starts the session's runtime, so a cold start overlaps the writing.
  const warmed = useRef(0);
  const warm = () => {
    if (Date.now() - warmed.current < 60_000) return;
    warmed.current = Date.now();
    void api.warm(sessionKey).catch(() => {});
  };
  const quoteInputs = useRef(new Map<string, HTMLInputElement>());
  useEffect(() => {
    if (!focusQuote) return;
    quoteInputs.current.get(focusQuote)?.focus();
    onFocused();
  }, [focusQuote]);
  const send = useMutation({
    mutationFn: (value: string) => api.sayToSession(sessionKey, value, files.flatMap((f) => (f.done ? [f.done] : [])), quotes.map(({ author, text: t, comment }) => ({ author, text: t, comment: comment.trim() }))),
    onSuccess: () => { setText(""); setFiles([]); setQuotes(() => []); void client.invalidateQueries({ queryKey: keys.session(station.id, sessionKey) }); },
  });
  const add = (list: FileList | File[]) => {
    for (const file of Array.from(list)) {
      const id = nextId.current++;
      const tooBig = file.size > MAX_FILE;
      setFiles((all) => [...all, { id, name: file.name, size: file.size, done: null, error: tooBig ? "超过 50 MB" : null }]);
      if (tooBig) continue;
      api.uploadFile(sessionKey, file).then(
        (done) => setFiles((all) => all.map((f) => (f.id === id ? { ...f, done } : f))),
        (error: unknown) => setFiles((all) => all.map((f) => (f.id === id ? { ...f, error: error instanceof Error ? error.message : "上传失败" } : f))),
      );
    }
  };
  // Switching to a session puts the cursor in its composer (not on touch screens, where it would raise the keyboard).
  useEffect(() => {
    if (window.matchMedia("(pointer: fine)").matches) input.current?.focus();
  }, [sessionKey]);
  // Grow with the text up to the frame's limit; the frame is never resized by hand.
  useEffect(() => {
    const el = input.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = `${Math.min(el.scrollHeight, 160)}px`;
  }, [text]);
  const uploading = files.some((f) => !f.done && !f.error);
  const ready = (Boolean(text.trim()) || files.some((f) => f.done) || quotes.length > 0) && !uploading && !send.isPending;
  const submit = () => {
    if (ready) send.mutate(text.trim());
  };
  return (
    <div className="composer-wrap">
      <form className="composer-box" data-multiline={text.includes("\n") || text.length > 60 || files.length > 0 || quotes.length > 0 || undefined} data-dragging={dragging || undefined}
        onSubmit={(e) => { e.preventDefault(); submit(); }} onClick={() => input.current?.focus()}
        onDragOver={(e) => { if (e.dataTransfer.types.includes("Files")) { e.preventDefault(); setDragging(true); } }}
        onDragLeave={() => setDragging(false)}
        onDrop={(e) => { if (e.dataTransfer.files.length) { e.preventDefault(); setDragging(false); add(e.dataTransfer.files); } }}>
        {quotes.length > 0 && (
          <div className="composer-quotes">
            {quotes.map((q) => (
              <div key={q.id} className="composer-quote" onClick={(e) => e.stopPropagation()}>
                <div className="composer-quote-source"><span className="composer-quote-author">{q.author}</span>{q.text}</div>
                <input ref={(el) => { if (el) quoteInputs.current.set(q.id, el); else quoteInputs.current.delete(q.id); }}
                  className="composer-quote-comment" value={q.comment} placeholder="对这段说点什么（可以不写）" aria-label={`对 ${q.author} 这段的批注`}
                  onChange={(e) => { const v = e.target.value; setQuotes((all) => all.map((x) => (x.id === q.id ? { ...x, comment: v } : x))); }}
                  onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing) { e.preventDefault(); input.current?.focus(); } }} />
                <button type="button" className="composer-quote-remove" aria-label="移除引用" onClick={() => setQuotes((all) => all.filter((x) => x.id !== q.id))}><X size={12} /></button>
              </div>
            ))}
          </div>
        )}
        {files.length > 0 && (
          <div className="composer-files">
            {files.map((f) => (
              <FileCard key={f.id} file={f.done ?? f} pending={!f.done && !f.error} error={f.error} onRemove={() => setFiles((all) => all.filter((x) => x.id !== f.id))} />
            ))}
          </div>
        )}
        <textarea ref={input} className="composer-text" rows={1} value={text} placeholder="给这个会话发消息" aria-label="消息"
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
          <Tip label={uploading ? "文件还在上传" : "发送"}>
            <button type="submit" className="send-btn" disabled={!ready} aria-label="发送" aria-busy={send.isPending || undefined}>
              {send.isPending ? <span className="spinner" aria-hidden="true" /> : <ArrowUp size={16} strokeWidth={2} />}
            </button>
          </Tip>
        </div>
      </form>
      {send.error && <p className="field-error chat-error" role="alert">{send.error.message}</p>}
    </div>
  );
}

const ACTIVITY_COLLAPSED = "ember.activityCollapsed";

/**
 * Who is doing what right now: the agent and each sub-agent it started, one
 * line each, three at most. Collapses to one line; the choice is remembered.
 */
function Activity({ steps, phase, agent, onOpenHistory }: { steps: ShownStep[]; phase: ShownPhase | null; agent: string; onOpenHistory(): void }) {
  const [collapsed, setCollapsed] = useState(() => localStorage.getItem(ACTIVITY_COLLAPSED) === "1");
  const open = steps.filter((s) => !s.ended);
  const doing = (s: ShownStep | undefined, fallback: string) =>
    !s ? fallback : s.step === "thinking" ? "正在思考" : s.step === "text" ? "正在写" : activityText(s.tool, s.input);
  const main = open.filter((s) => !s.parent);
  const mainText = phase?.phase === "starting" ? "正在启动"
    : phase?.phase === "requesting" && !main.length ? "等待模型响应"
    : doing(main.at(-1), "正在处理");
  const lines: { who: string; what: string }[] = [{ who: agent, what: mainText }];
  // Sub-agents, by the call that started them; named by what that call was asked to do.
  const parents = [...new Set(open.filter((s) => s.parent).map((s) => s.parent!))];
  for (const parent of parents) {
    const call = steps.find((s) => s.id === parent);
    const name = (call && partialString(call.input, "description")) || "子 agent";
    lines.push({ who: name, what: doing(open.filter((s) => s.parent === parent).at(-1), "正在处理") });
  }
  const shown = collapsed ? lines.slice(0, 1) : lines.slice(0, 3);
  const more = lines.length - shown.length;
  const toggle = () => {
    localStorage.setItem(ACTIVITY_COLLAPSED, collapsed ? "0" : "1");
    setCollapsed(!collapsed);
  };
  return (
    <div className="activity" data-collapsed={collapsed || undefined}>
      <button type="button" className="activity-lines" onClick={onOpenHistory} title="打开执行历史">
        {shown.map((l, i) => (
          <span key={i} className="activity-line">
            <span className="activity-pulse inline" aria-hidden="true" />
            <span className="activity-who">{l.who}</span>
            <span className="activity-what">{l.what}…</span>
          </span>
        ))}
      </button>
      <button type="button" className="activity-toggle" onClick={toggle} aria-label={collapsed ? "展开活动" : "收起为一行"}>
        {collapsed ? (more > 0 ? `+${more}` : <ChevronDown size={13} />) : <ChevronUp size={13} />}
      </button>
    </div>
  );
}
