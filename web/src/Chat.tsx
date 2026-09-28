// ember's own chat with a session, after Zork's: your messages sit right in a
// bubble with only their time; everyone else (people and the agent) gets an
// avatar, a name and the time over their words. Passages of earlier messages
// can be quoted with a comment, and files ride along as cards (images shown).
import { ArrowDown, ArrowUp, Bot, Brain, Chats, Close, Command, Edit, Info, Plus, Quote as QuoteIcon, Read, Received, Retry, Said, Search, Send, Sparks, Think, Trash, Web } from "./icons.tsx";
import { memo, useEffect, useLayoutEffect, useMemo, useRef, useState, type CSSProperties, type MutableRefObject, type ReactNode, type RefObject } from "react";
import { useApi, useChatSend, type Activity as ActivityView, type Attachment, type ChatMessage, type ChatView, type Live, type Maker, type Quote, type RuntimeKind, type Session, type Stamp, type Status } from "./api.ts";
import { Mark } from "./brand.tsx";
import { usePerson, useStation } from "./station.tsx";
import { Avatar, ModelLogo, Time, Tip, transitionTo } from "./ui.tsx";
import { ComposerSlot, useComposerHeight } from "./dock.tsx";
import { placeFiles, Prose } from "./Prose.tsx";
import { chatImages, FileLink, FilePreview, fileSize, Gallery, isImage, useFileUrl, useNear } from "./FilePreview.tsx";
import { useStickToBottom } from "./scroll.ts";
import { useDraft, type DraftQuote } from "./draft.ts";
import * as nav from "./Sidebar.css.ts";
import * as sessionCss from "./styles/session.css.ts";
import * as chatCss from "./mobile/styles/chat.css.ts";
import * as chatCss2 from "./styles/chat.css.ts";
import * as conversationCss from "./styles/conversation.css.ts";
import * as css from "./Chat.css.ts";
import * as waitingCss from "./styles/waiting.css.ts";
import * as cloudCss from "./styles/cloud.css.ts";
import * as composerCss from "./styles/composer.css.ts";
import * as controlsCss from "./styles/controls.css.ts";

/** An agent of this chat as its messages and activity show it: who it is, and its execution history as it runs. */
interface AgentHere { key: string; who: string; runtime: RuntimeKind; maker: Maker | undefined; session: Session; status: Status; live: Live | undefined; since: number | undefined }

/**
 * A chat's messages and its composer. Before its agent has a chat (`chat.thread` null) there are no messages, and
 * `ensureChat` makes the chat with the first message, which `onSent` then follows.
 */
/**
 * From a new chat, whose page already looks like the chat (its first messages on their way), to the chat itself: the
 * page is kept until the chat shows them, then gives way at once.
 */
export function toMadeChat(go: () => void): void {
  void transitionTo(go, () => document.querySelector(`:is(.${sessionCss.chatList}, .${chatCss.mMessages}) :is(.${chatCss2.msgMine}, .${chatCss.mMine})`) !== null, true);
}

export function ChatPanel({ chat, draftKey, lives, onOpenHistory, ensureChat, onSent }: {
  /** Whose draft the composer shows here. */
  chat: ChatView; draftKey: string; lives: ReadonlyMap<string, Live>; onOpenHistory(key: string, entry?: number): void;
  ensureChat?: () => Promise<{ key: string; thread: number }>; onSent?: (thread: number) => void;
}) {
  const station = useStation();
  const list = useRef<HTMLDivElement>(null);
  const composerHeight = useComposerHeight();
  const floor = useRef<HTMLDivElement>(null);
  const sending = useChatSend();
  const { thread, outbox } = chat;
  const id = thread?.id ?? null;
  const [quotes, setQuotes] = useState<DraftQuote[]>([]);
  const [focusQuote, setFocusQuote] = useState<string | null>(null);
  const [picked, setPicked] = useState<{ quote: DraftQuote; at: { x: number; y: number } } | null>(null);
  const { messages, divider, away, shown, rowOf, poseOf } = useMessageList(list, floor, chat, `${station.address}:${chat.thread?.id ?? chat.agents[0]?.session.key ?? ""}`, lives);
  const agents: AgentHere[] = chat.agents.map(({ session, status, since }) => (
    { key: session.key, who: session.agentText, runtime: session.runtime, maker: session.maker, session, status, live: lives.get(session.key), since }
  ));
  const agentOf = (key: string) => agents.find((a) => a.key === key);
  // Where agents post to reach this chat.
  const address = thread ? `${thread.channel}/${thread.threadTs}` : null;
  // Files are kept in a session's workspace: what is sent here goes to the first agent's.
  const keeper = agents[0]?.key ?? null;
  const ownerOf = (file: Attachment) => agents.find((a) => file.path.startsWith(`${a.session.workspace}/`))?.key ?? keeper;
  // The messages are kept as they are while nothing they show changes (MessageRow): what they are handed stays the same
  // function, the latest one behind it, and `owners` says when whose files are whose has changed.
  const images = () => chatImages([...messages, ...outbox.map((o) => ({ authorKind: "person", ...o }))], ownerOf);
  const latest = useRef({ ownerOf, onOpenHistory, images });
  latest.current = { ownerOf, onOpenHistory, images };
  const [stable] = useState(() => ({ owner: (file: Attachment) => latest.current.ownerOf(file), open: (key: string) => latest.current.onOpenHistory(key), images: () => latest.current.images() }));
  const owners = `${keeper ?? ""} ${agents.map((a) => `${a.key}=${a.session.workspace}`).join(" ")}`;

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
    // The list runs on under the composer, frosted over it (its styles): its foot leaves the composer's height free.
    <section className={sessionCss.chat} aria-label="对话" data-under-composer="" style={{ "--composer-height": `${composerHeight}px` } as CSSProperties}>
      <div className={sessionCss.chatPane}>
      {away && (
        <button type="button" className={css.chatToBottom} aria-label="跳到最新"
          // Glides down, and follows new messages again (scroll.ts).
          onClick={() => list.current?.dispatchEvent(new Event("to-bottom"))}>
          <ArrowDown size={16} strokeWidth={2} />
        </button>
      )}
      <Gallery.Provider value={stable.images}>
      <div className={sessionCss.chatList} ref={list} onMouseUp={() => setTimeout(onSelect, 0)} onScroll={() => setPicked(null)}
        onClick={(e) => {
          // `?history=<session>&entry=<n>`: that agent's execution history (a chat going on with a session from a terminal starts
          // with a note linking to it, where what was said before is).
          const anchor = (e.target as Element).closest?.("a[href]") as HTMLAnchorElement | null;
          const to = anchor ? historyLink(anchor.href) : null;
          // At the entry it names (else its start); opened, not toggled.
          if (to) { e.preventDefault(); onOpenHistory(to.key, to.entry); }
        }}>
        {chat.more && <div className={css.chatOlder} aria-hidden="true"><span className={waitingCss.spinner} /></div>}
        {messages.length === 0 && (
          <div className={css.chatEmpty}>
            <p>在这里发消息，这个对话里的 agent 会在这里回复。</p>
          </div>
        )}
        {messages.map((m) => {
          const line = m.seq === divider ? <div key={`new-${m.seq}`} className={css.chatUnreadLine} data-unread-line role="separator"><span>以下是新消息</span></div> : null;
          const { enter, emitted } = rowOf(m);
          return [line, (
            <MessageRow key={m.seq} message={m} enter={enter} emitted={emitted}
              agentHere={m.by.agent ? agentOf(m.by.agent) !== undefined : false} owners={owners} owner={stable.owner} onOpenHistory={stable.open} />
          )];
        })}
        {outbox.map((o) => (
          <div key={o.id} className={`${conversationCss.msg} ${chatCss2.msgMine}`} data-author="你" data-role="person" data-enter data-unsent={o.state === "failed" || undefined}>
            <Quotes quotes={o.quotes} />
            {o.text && <div className={conversationCss.msgBubble}><div className={chatCss2.msgPlain}>{o.text}</div></div>}
            <Files owner={ownerOf} files={o.attachments} look={look} />
            {o.state === "failed"
              // Not sent: said briefly, why in its tip; sending it again or dropping it right beside.
              ? <div className={css.msgUnsent}>
                  <Tip label={o.error ? `没发出去：${o.error}` : "没发出去"}>
                    <span className={css.msgUnsentNote}><Info size={12} strokeWidth={2} />未发送</span>
                  </Tip>
                  <button type="button" className={css.msgUnsentBtn} onClick={() => void (id !== null && sending.retry(id, o.id).catch(() => {}))}><Retry size={12} strokeWidth={2} />重试</button>
                  <button type="button" className={css.msgUnsentBtn} onClick={() => void (id !== null && sending.discard(id, o.id))}><Trash size={12} strokeWidth={2} />删除</button>
                </div>
              : <span className={`${conversationCss.msgTime} ${chatCss2.msgWaiting} ${chatCss2.msgSending}`}><span className={waitingCss.spinner} aria-hidden="true" />正在发送</span>}
          </div>
        ))}
        {/* A reply comes whole, as a message: while an agent works, its activity (always the last thing in the chat) says what it does. */}
        {shown.map(({ agent, leaving }) => (
          <Activity key={agent.key} agent={agent} leaving={leaving} pose={poseOf(agent.key)} onOpen={() => onOpenHistory(agent.key)} />
        ))}
        <div ref={floor} className={chatCss2.chatFloor} aria-hidden="true" />
      </div>
      </Gallery.Provider>
      </div>
      {picked && (
        <button type="button" className={css.quotePop} style={{ left: picked.at.x, top: picked.at.y }}
          onMouseDown={(e) => e.preventDefault()}
          onClick={() => { setQuotes((all) => [...all, picked.quote]); setFocusQuote(picked.quote.id); setPicked(null); window.getSelection()?.removeAllRanges(); }}>
          <QuoteIcon size={12} strokeWidth={2.2} />引用
        </button>
      )}
      {chat.offline && <p className={css.offlineNotice} role="status">{station.name ? `「${station.name}」` : "这台 station "}离线了：这里是之前读到的内容，暂时不能发消息。</p>}
      {/* The one composer of the chat pages sits here (dock.tsx), kept as the page changes. */}
      <ComposerSlot variant="chat" station={station} draftKey={draftKey} thread={id} sessionKey={keeper} quotes={quotes} setQuotes={setQuotes} focusQuote={focusQuote} onFocused={() => setFocusQuote(null)}
        locked={chat.offline} {...(ensureChat ? { ensureChat } : {})} {...(onSent ? { onSent } : {})} />
    </section>
  );
}

/** The session and entry a link to an agent's execution history names (`?history=<session>&entry=<n>`), or null when it
 * is not one. */
export function historyLink(href: string): { key: string; entry: number } | null {
  let url: URL;
  try { url = new URL(href, location.href); } catch { return null; }
  const key = url.searchParams.get("history");
  const entry = Number(url.searchParams.get("entry") ?? 0);
  return key ? { key, entry: Number.isInteger(entry) && entry >= 0 ? entry : 0 } : null;
}

/** How a message of the list comes in: easing in (`enter`), or held in its agent's activity and sent out of it (`emitted`). */
export interface RowState { enter: true | undefined; emitted: "held" | "emitting" | null }

/**
 * A chat's list as both screens run it (this page, and the phone's, mobile/Chat.tsx): it follows its bottom, loads
 * older pages near its top, records what is read, keeps the reader's place (`place`: whose it is), draws the unread
 * line, and shows its agents at work, their replies coming out of their activity. Answers what the list shows: its
 * messages, where the unread line goes, whether the reader is away from the bottom, the agents at work, and how each
 * message comes in.
 */
export function useMessageList(list: RefObject<HTMLDivElement | null>, floor: RefObject<HTMLDivElement | null>, chat: ChatView, place: string, lives: ReadonlyMap<string, Live>) {
  const sending = useChatSend();
  const id = chat.thread?.id ?? null;
  const messages = chat.messages;
  // Whose a message is, the core says.
  const mineOf = (m: ChatMessage) => m.mine;
  useStickToBottom(list, `.${conversationCss.msg}`, floor);
  // Without a chat there is nothing older to load and nothing to read.
  const older = () => (id === null ? Promise.resolve() : sending.older(id));
  useOlderOnScroll(list, chat, older);
  useMarkRead(floor, chat, (seq) => (id === null ? Promise.resolve() : sending.read(id, seq)));
  const returning = useRememberPlace(list, place, messages.length > 0);
  const divider = useUnreadLine(list, chat, messages, mineOf, older, returning);
  const away = useAwayFromBottom(list);
  // A message sent from here eases in once, from the outbox; its own copy that replaces it does not again.
  const sentHere = useRef(new Set<string>());
  for (const o of chat.outbox) sentHere.current.add(o.text);
  // Messages there when the chat opened (and older pages loaded later) show at once; newer ones ease in, except a reply that already streamed in place.
  const firstSeq = useRef<number | null>(null);
  if (firstSeq.current === null) firstSeq.current = messages.at(-1)?.seq ?? 0;
  // Only an agent that has taken a message and runs is at work: until then the message itself says it waits.
  const atWork: AgentAtWork[] = chat.agents.filter((a) => a.status === "running").map(({ session, since }) => (
    { key: session.key, who: session.agentText, runtime: session.runtime, maker: session.maker, activity: lives.get(session.key)?.activity ?? null, since }
  ));
  const emissions = useEmissions(list);
  const shown = useLinger(atWork, emissions.keeps);
  emissions.take(messages, firstSeq.current, new Set(shown.map((s) => s.agent.key)));
  const rowOf = (m: ChatMessage): RowState => {
    const mine = mineOf(m);
    const told = !mine && !m.system;
    const enter = m.seq > firstSeq.current! && !(mine && sentHere.current.has(m.text)) && !(told && emissions.emits(m.seq)) ? true : undefined;
    return { enter, emitted: told ? emissions.stateOf(m.seq) : null };
  };
  return { messages, divider, away, shown, rowOf, poseOf: emissions.poseOf };
}

/** The core hands the chat over anew as it changes: a message is the same one if all it holds is (its times in words too). */
export function sameMessage(a: ChatMessage, b: ChatMessage): boolean {
  return a === b || JSON.stringify(a) === JSON.stringify(b);
}

/**
 * The line over the first message the viewer had not read when the chat
 * opened (not their own), and the jump to it: the read position is taken as
 * the chat opens and does not move during the visit, so the line stays put as
 * the chat is read. A chat opens from what the device kept, so messages said
 * before it opened may still arrive from the station: the line goes over the
 * first of them wherever it came from; what is said during the visit gets
 * none. Older pages are loaded first when it lies above them. Nothing unread:
 * no line, and the chat opens at its bottom. Answers the seq of the message
 * the line goes over.
 */
export function useUnreadLine(ref: RefObject<HTMLElement | null>, chat: ChatView, messages: ChatMessage[], mine: (m: ChatMessage) => boolean, older: () => Promise<unknown>, returning = false): number | null {
  const [open] = useState(() => ({ read: chat.thread?.read ?? 0, at: Date.now() }));
  const unread = (m: ChatMessage) => m.seq > open.read && m.createdAt <= open.at && !mine(m);
  const first = messages[0]?.seq;
  // Those not loaded yet may hold it: the pages before are loaded first.
  const above = chat.more && first !== undefined && first > open.read + 1 && messages.some(unread);
  const target = above ? null : messages.find(unread)?.seq ?? null;
  const asked = useRef<number | undefined>(undefined);
  // Until something unread shows (it may come from the station a moment after opening), there is nothing to jump to.
  // Coming back to a chat goes back to where it was left (useRememberPlace), not to the line.
  const jumped = useRef(returning);
  const load = useRef(older);
  load.current = older;
  useEffect(() => {
    if (!above || asked.current === first) return;
    asked.current = first;
    void load.current().catch(() => { asked.current = undefined; });
  }, [above, first]);
  useEffect(() => {
    if (jumped.current || above || target === null) return;
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

/** Whether the reader is scrolled up, away from the newest messages (more than a screenful's corner). */
export function useAwayFromBottom(ref: RefObject<HTMLElement | null>): boolean {
  const [away, setAway] = useState(false);
  useEffect(() => {
    const pane = ref.current;
    if (!pane) return;
    const check = () => setAway(pane.scrollHeight - pane.scrollTop - pane.clientHeight > 120);
    check();
    pane.addEventListener("scroll", check, { passive: true });
    const resize = new ResizeObserver(check);
    resize.observe(pane);
    return () => {
      pane.removeEventListener("scroll", check);
      resize.disconnect();
    };
  }, [ref]);
  return away;
}

/** Where each chat was left: the message at the top of its pane, and how far below the pane's top it sat. */
const leftAt = new Map<string, { ts: string; offset: number }>();

/**
 * Remembers where the reader was in a chat and takes them back there when
 * they return, instead of opening it from the bottom again. The place is kept
 * as the message at the top and its offset, so what arrived meanwhile below
 * does not move it. Answers whether this is a return to a known place.
 */
export function useRememberPlace(ref: RefObject<HTMLElement | null>, key: string, ready: boolean): boolean {
  const [saved] = useState(() => leftAt.get(key));
  const restored = useRef(false);
  useEffect(() => {
    const pane = ref.current;
    if (!pane) return;
    const record = () => {
      const top = pane.getBoundingClientRect().top;
      const first = [...pane.querySelectorAll<HTMLElement>(`.${conversationCss.msg}[data-ts]`)].find((m) => m.getBoundingClientRect().bottom > top);
      if (first) leftAt.set(key, { ts: first.dataset.ts!, offset: first.getBoundingClientRect().top - top });
    };
    pane.addEventListener("scroll", record, { passive: true });
    return () => {
      record();
      pane.removeEventListener("scroll", record);
    };
  }, [ref, key]);
  useEffect(() => {
    if (!saved || !ready || restored.current) return;
    restored.current = true;
    const pane = ref.current;
    const at = pane?.querySelector<HTMLElement>(`.${conversationCss.msg}[data-ts="${saved.ts}"]`);
    if (!pane || !at) return;
    // A reader's move: the pane keeps it rather than holding its bottom.
    pane.dispatchEvent(new WheelEvent("wheel"));
    pane.scrollTop += at.getBoundingClientRect().top - pane.getBoundingClientRect().top - saved.offset;
  }, [ref, saved, ready]);
  return saved !== undefined;
}

/**
 * Loads the page of messages before those shown when the reader comes near
 * the top (or when what is loaded does not fill the pane). What is on screen
 * stays put: the pane keeps its distance from the bottom as content grows
 * above (scroll.ts).
 */
export function useOlderOnScroll(ref: RefObject<HTMLElement | null>, chat: ChatView, older: () => Promise<unknown>): void {
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
export function useMarkRead(floor: RefObject<HTMLElement | null>, chat: ChatView, read: (seq: number) => Promise<unknown>): void {
  const newest = chat.messages.at(-1)?.seq ?? 0;
  const known = chat.thread?.read ?? 0;
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

/**
 * One message of the chat. It is drawn again only when something it shows changes: an agent at work makes the chat
 * draw again many times a second (its activity), and every message's Markdown would be laid out anew each time.
 */
const MessageRow = memo(function MessageRow({ message: m, enter, emitted, agentHere, owner, onOpenHistory }: {
  message: ChatMessage; enter: true | undefined; emitted: "held" | "emitting" | null; agentHere: boolean;
  /** Whose files are whose, in a word: when it changes, the files are drawn again. */
  owners: string;
  owner: (file: Attachment) => string | null; onOpenHistory: (key: string) => void;
}) {
  if (m.mine) {
    return (
      <MineMessage data-author="你" data-ts={m.ts} data-role="person" data-enter={enter}>
        <Quotes quotes={m.quotes} />
        <MineBubble text={m.text} />
        <Files owner={owner} files={m.attachments} look={look} />
        {/* Not taken by its agents yet: after a second it says it waits (the delay is the stylesheet's). */}
        {m.waiting
          ? <span className={`${conversationCss.msgTime} ${chatCss2.msgWaiting} ${css.msgWaitingLate}`}><span className={waitingCss.spinner} aria-hidden="true" />等待 agent 接收</span>
          : <Time className={conversationCss.msgTime} stamp={m.time?.createdAt} />}
      </MineMessage>
    );
  }
  // What ember itself says (a limit hit, a failure): a notice across the chat, not someone's message.
  if (m.system) {
    return (
      <div className={`${conversationCss.msg} ${css.msgSystem}`} data-ts={m.ts} data-role="system" data-enter={enter} role="note">
        <div className={css.msgSystemBox}>
          <Mark size={14} />
          <div className={conversationCss.markdown}><Prose>{m.text}</Prose></div>
          <Time className={conversationCss.msgTime} stamp={m.time?.createdAt} />
        </div>
      </div>
    );
  }
  const who = m.by.name;
  const agent = agentHere ? m.by.agent : undefined;
  return (
    <OthersMessage data-seq={m.seq} data-author={who} data-ts={m.ts} data-role={m.authorKind === "agent" ? "agent" : "person"}
      data-enter={enter} data-held={emitted === "held" || undefined} data-emitting={emitted === "emitting" || undefined} data-covered={emitted === "emitting" || undefined}
      avatar={<MessageAvatar message={m} name={who} />} time={m.time?.createdAt}
      name={agent
        ? <button type="button" className={`${css.msgName} ${css.msgAgent}`} onClick={() => onOpenHistory(agent)} title="打开或关闭执行历史">{who}</button>
        : <span className={css.msgName}>{who}</span>}>
      <Quotes quotes={m.quotes} />
      {m.authorKind === "person"
        ? <>{m.text && <div className={chatCss2.msgPlain}>{m.text}</div>}<Files owner={owner} files={m.attachments} look={look} /></>
        : <ProseWithFiles owner={owner} text={m.text} files={m.attachments} look={look} className={conversationCss.markdown} />}
    </OthersMessage>
  );
}, (a, b) => a.enter === b.enter && a.emitted === b.emitted && a.agentHere === b.agentHere && a.owners === b.owners && sameMessage(a.message, b.message));

type Data = { [key: `data-${string}`]: string | number | boolean | undefined };

/** A viewer's own message as a chat draws it (on the right); its bubble is MineBubble. Also where else messages are shown so. */
export function MineMessage({ children, ...data }: Data & { children: ReactNode }) {
  return <div className={`${conversationCss.msg} ${chatCss2.msgMine}`} {...data}>{children}</div>;
}

/** The words of a viewer's own message, in their bubble. */
export function MineBubble({ text }: { text: string }) {
  return text ? <div className={conversationCss.msgBubble}><div className={chatCss2.msgPlain}>{text}</div></div> : null;
}

/** Someone else's message as a chat draws it: `avatar`, then `name` and `time` over what it says. */
export function OthersMessage({ avatar, name, time, children, ...data }: Data & { avatar: ReactNode; name: ReactNode; time: Stamp | undefined; children: ReactNode }) {
  return (
    <div className={`${conversationCss.msg} ${css.msgRow}`} {...data}>
      {avatar}
      <div className={css.msgMain}>
        <div className={conversationCss.msgHead}>
          {name}
          <Time className={conversationCss.msgTime} stamp={time} />
        </div>
        {children}
      </div>
    </div>
  );
}

/** An agent's picture in a chat: its model's maker, in the agents' ground. */
export function AgentAvatar({ maker, runtime }: { maker: Maker | null | undefined; runtime: RuntimeKind | null | undefined }) {
  return <span className={`${chatCss2.msgAvatar} ${css.msgAvatarAgent}`}>{runtime ? <ModelLogo maker={maker} runtime={runtime} size={12} /> : <Mark size={12} />}</span>;
}

/** An agent's words as a chat draws them (Markdown). */
export function AgentWords({ text }: { text: string }) {
  return <div className={conversationCss.markdown}><Prose>{text}</Prose></div>;
}

/** An agent's name over its message. */
export function MessageName({ children }: { children: ReactNode }) {
  return <span className={css.msgName}>{children}</span>;
}

function MessageAvatar({ message, name }: { message: ChatMessage; name: string }) {
  if (message.authorKind === "agent") return <AgentAvatar maker={message.by.maker} runtime={message.by.runtime} />;
  if (message.authorKind === "ember") return <span className={`${chatCss2.msgAvatar} ${css.msgAvatarAgent}`}><Mark size={12} /></span>;
  const picture = message.by.picture;
  return picture
    ? <img className={chatCss2.msgAvatar} src={picture} alt="" width={18} height={18} referrerPolicy="no-referrer" />
    : <span className={chatCss2.msgAvatar}><Avatar id={message.author} name={name} size={18} /></span>;
}

/**
 * Quotes as sent, each a card of its own ahead of the message: the quoted
 * part on a warm ground (whose message, the passage) leading back to it, then
 * what was said about it.
 */
function Quotes({ quotes }: { quotes: Quote[] | undefined }) {
  if (!quotes?.length) return null;
  const jump = (ts: string | undefined, text: string) => {
    const target = ts ? document.querySelector<HTMLElement>(`.${sessionCss.chatList} [data-ts="${ts}"]`) : null;
    if (!target) return;
    // A reader's move: the pane lets it take the position.
    target.closest(`.${sessionCss.chatList}`)?.dispatchEvent(new WheelEvent("wheel"));
    const range = findText(target, text);
    if (range && "highlights" in CSS) {
      const rect = range.getBoundingClientRect();
      const pane = target.closest<HTMLElement>(`.${sessionCss.chatList}`);
      if (pane) pane.scrollTop += rect.top + rect.height / 2 - (pane.getBoundingClientRect().top + pane.clientHeight / 2);
      flashRange(range);
      return;
    }
    target.scrollIntoView({ block: "center" });
    target.classList.remove(css.msgFlash);
    void target.offsetWidth;
    target.classList.add(css.msgFlash);
  };
  return (
    <div className={css.quoteCards}>
      {quotes.map((q, i) => <QuoteCard key={i} quote={q} onJump={q.ts ? () => jump(q.ts, q.text) : undefined} />)}
    </div>
  );
}

/** One quote: the passage with whose it is, and the comment. Also the composer's pending quote, with an editable comment. */
function QuoteCard({ quote, onJump, comment, onRemove }: { quote: Quote; onJump?: (() => void) | undefined; comment?: ReactNode; onRemove?: () => void }) {
  return (
    <div className={css.quoteCard}>
      <button type="button" className={css.quoteCardSource} onClick={onJump} disabled={!onJump} title={onJump ? "跳到原消息" : undefined}>
        <span className={css.quoteCardText}><QuoteIcon size={11} strokeWidth={2.4} aria-hidden="true" /><span className={css.quoteCardWho}>{quote.author}：</span>{quote.text}</span>
      </button>
      {comment ?? (quote.comment ? <div className={css.quoteCardComment}>{quote.comment}</div> : null)}
      {onRemove && <button type="button" className={css.quoteCardRemove} aria-label="移除引用" onClick={onRemove}><Close size={12} /></button>}
    </div>
  );
}

// ── files ───────────────────────────────────────────────────────────────

/** How a screen draws a message's files (this page's `look`; the phone's, mobile/Chat.tsx): what differs is only the look. */
export interface FileLook {
  /** The list of a message's files. */
  files: string;
  /** An image's button, and the box it takes before it loads. */
  image: string; box(file: Attachment): CSSProperties;
  /** What an image shows until it loads; without it, its button is disabled until then. */
  wait?: string;
  /** A file's button, around its card. */
  open: string; card(file: Attachment): ReactNode;
}

/** An agent's Markdown with its files: those its text names shown there, the rest below it. */
export function ProseWithFiles({ owner, text, files, look, className, prose, markdown }: {
  owner: (file: Attachment) => string | null; text: string; files: Attachment[] | undefined; look: FileLook;
  /** Around the Markdown; `prose`, what else it holds (a long-press on the phone); `markdown`, a frame of its own inside. */
  className: string; prose?: React.HTMLAttributes<HTMLDivElement> & Record<`data-${string}`, unknown>; markdown?: string;
}) {
  const { placed, rest } = useMemo(() => placeFiles(text, files), [text, files]);
  const words = <Prose files={placed} file={(f, as, words) => as === "link" ? <FileLink sessionKey={owner(f)} file={f}>{words}</FileLink> : <FileItem sessionKey={owner(f)} file={f} look={look} />}>{text}</Prose>;
  return (
    <>
      <div className={className} {...prose}>{markdown ? <div className={markdown}>{words}</div> : words}</div>
      <Files owner={owner} files={rest} look={look} />
    </>
  );
}

/** A message's files; `owner` says which session of the chat keeps each (null: none can show it). */
export function Files({ owner, files, look }: { owner: (file: Attachment) => string | null; files: Attachment[] | undefined; look: FileLook }) {
  if (!files?.length) return null;
  return <div className={look.files}>{files.map((f) => <FileItem key={f.path} sessionKey={owner(f)} file={f} look={look} />)}</div>;
}

/** Images show themselves at their own proportions, fetched as they come near the screen; other files are a card. Either opens in a preview. */
function FileItem({ sessionKey, file, look }: { sessionKey: string | null; file: Attachment; look: FileLook }) {
  const image = isImage(file.name);
  const box = useRef<HTMLButtonElement>(null);
  const near = useNear(box, image);
  const url = useFileUrl(sessionKey ?? "", file, image && sessionKey !== null && near);
  const [open, setOpen] = useState(false);
  const preview = sessionKey !== null && <FilePreview open={open} onClose={() => setOpen(false)} sessionKey={sessionKey} file={file} />;
  if (image) {
    return (
      <>
        <button ref={box} type="button" className={look.image} onClick={() => url && setOpen(true)} title={file.path} aria-label={`查看 ${file.name}`} style={look.box(file)}
          disabled={look.wait === undefined && !url}>
          {url ? <img src={url} alt={file.name} /> : look.wait !== undefined && <span className={look.wait} />}
        </button>
        {preview}
      </>
    );
  }
  if (sessionKey === null) return look.card(file);
  return (
    <>
      <button type="button" className={look.open} onClick={() => setOpen(true)} aria-label={`查看 ${file.name}`}>{look.card(file)}</button>
      {preview}
    </>
  );
}

const look: FileLook = { files: css.msgFiles, image: css.msgImage, wait: css.msgImageWait, box: (f) => imageBox(f), open: css.fileCardOpen, card: (f) => <FileCard file={f} /> };

/**
 * The box an image takes in the chat, known before it loads: its own
 * proportions (sent with it) within 360×300, or a fixed box for images sent
 * before sizes were recorded. A narrower chat shrinks it (max-width), the
 * proportions kept.
 */
export function imageBox(file: Attachment): { width: number; aspectRatio: string } {
  if (!file.width || !file.height) return { width: 240, aspectRatio: "240 / 160" };
  const scale = Math.min(1, 360 / file.width, 300 / file.height);
  const width = Math.max(40, Math.round(file.width * scale)), height = Math.max(40, Math.round(file.height * scale));
  return { width, aspectRatio: `${width} / ${height}` };
}

function FileCard({ file, onRemove, pending, error }: { file: Pick<Attachment, "name" | "size"> & { path?: string }; onRemove?: () => void; pending?: boolean; error?: string | null }) {
  return (
    <span className={css.fileCard} title={file.path ?? file.name} data-error={error ? true : undefined}>
      {pending ? <span className={waitingCss.spinner} aria-hidden="true" /> : <Read size={16} aria-hidden="true" />}
      <span className={css.fileCardText}>
        <span className={css.fileCardName}>{file.name}</span>
        <span className={css.fileCardMeta}>{error ?? (pending ? "正在上传…" : fileSize(file.size))}</span>
      </span>
      {onRemove && <button type="button" className={css.fileCardRemove} aria-label={`移除 ${file.name}`} onClick={(e) => { e.stopPropagation(); onRemove(); }}><Close size={12} /></button>}
    </span>
  );
}

// ── composer ────────────────────────────────────────────────────────────

/**
 * Where people write to a chat; a new chat is made by the first message or
 * file. Zork's composer: a soft frame that grows with the text, a round send
 * button, the files and quotes waiting to go above it. Files (picked, pasted
 * or dropped) go to the workspace of a session in the chat on the station as
 * soon as they are added.
 */
/** What the composer writes to, and how it shows. */
export interface ComposerProps {
  /** The chat written to, and its session; both null for a new chat, made by `ensureChat` with the first message. */
  thread: number | null;
  sessionKey: string | null;
  quotes?: DraftQuote[]; setQuotes?(update: (all: DraftQuote[]) => DraftQuote[]): void;
  /** A quote just added: its comment line takes the focus. */
  focusQuote?: string | null; onFocused?(): void;
  ensureChat?: () => Promise<{ key: string; thread: number }>;
  onSent?: (thread: number) => void;
  /** A new chat's first message leaving the composer (null: it came back, the chat not made). */
  onSending?: (text: string | null) => void;
  /** Choices shown in the toolbar, between attach and send (a new chat's station, model and effort). */
  toolbar?: ReactNode;
  placeholder?: string;
  /** While true (a new chat being made) nothing can be sent. */
  locked?: boolean;
  /** Text above, toolbar below, even for one line (a new chat, whose toolbar holds choices). */
  roomy?: boolean;
  /** Whose draft it shows: changing it keeps what is typed for the one before and brings back the next one's. */
  draftKey?: string;
  /** A key whose draft goes on from what is typed now, instead of its own (a new chat becoming its chat). */
  carry?: MutableRefObject<string | null>;
}

export function Composer({ thread, sessionKey, quotes = [], setQuotes = () => {}, focusQuote = null, onFocused = () => {}, ensureChat, onSent, onSending, toolbar, placeholder = "发消息", locked = false, roomy = false, draftKey, carry }: ComposerProps) {
  const api = useApi();
  const draft = useDraft({ key: draftKey, ...(carry ? { carry } : {}), upload: (file) => api.uploadFile(file), quotes: [quotes, setQuotes] });
  const { text, setText, files, add, uploading, starting } = draft;
  const [dragging, setDragging] = useState(false);
  const input = useRef<HTMLTextAreaElement>(null);
  const picker = useRef<HTMLInputElement>(null);
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
  const send = async () => {
    const to = await draft.send(async () => (thread !== null ? thread : (await ensureChat!()).thread), { first: thread === null, ...(onSending ? { onSending } : {}) });
    if (to !== null) onSent?.(to);
  };
  // Switching to a chat puts the cursor in its composer (not on touch screens, where it would raise the keyboard),
  // before it is first drawn: it never shows unfocused first.
  useLayoutEffect(() => {
    if (window.matchMedia("(pointer: fine)").matches) input.current?.focus();
  }, [thread]);
  // Grow with the text up to three lines, then scroll; the frame is never resized by hand. Its width changing re-wraps
  // the text (or the placeholder), so it is measured again then; below the limit it never scrolls.
  useEffect(() => {
    const el = input.current;
    if (!el) return;
    const fit = () => {
      const style = getComputedStyle(el);
      const limit = 3 * parseFloat(style.lineHeight) + parseFloat(style.paddingTop) + parseFloat(style.paddingBottom);
      el.style.height = "auto";
      el.style.height = `${Math.min(el.scrollHeight, limit)}px`;
      el.style.overflowY = el.scrollHeight > limit + 1 ? "auto" : "hidden";
      edges();
    };
    // Scrolling, the lines it cuts fade out at its edges (its styles) rather than stop at a hard line.
    const edges = () => {
      const over = el.scrollHeight > el.clientHeight + 1;
      el.toggleAttribute("data-more-above", over && el.scrollTop > 1);
      el.toggleAttribute("data-more-below", over && el.scrollTop + el.clientHeight < el.scrollHeight - 1);
    };
    fit();
    let width = el.clientWidth;
    const resize = new ResizeObserver(() => { if (el.clientWidth !== width) { width = el.clientWidth; fit(); } });
    resize.observe(el);
    el.addEventListener("scroll", edges);
    return () => { resize.disconnect(); el.removeEventListener("scroll", edges); };
  }, [text]);
  const ready = draft.ready && !locked;
  const submit = () => {
    if (ready) void send();
  };
  return (
    <div className={cloudCss.composerWrap}>
      <form className={composerCss.composerBox} data-multiline={roomy || text.includes("\n") || text.length > 60 || files.length > 0 || quotes.length > 0 || undefined} data-dragging={dragging || undefined}
        onSubmit={(e) => { e.preventDefault(); submit(); }} onClick={() => input.current?.focus()}
        // Locked (its station offline), no file is taken in.
        onDragOver={(e) => { if (e.dataTransfer.types.includes("Files") && !locked) { e.preventDefault(); setDragging(true); } }}
        onDragLeave={() => setDragging(false)}
        onDrop={(e) => { if (e.dataTransfer.files.length) { e.preventDefault(); setDragging(false); if (!locked) add(e.dataTransfer.files); } }}>
        {quotes.length > 0 && (
          <div className={css.composerQuotes}>
            {quotes.map((q) => (
              <div key={q.id} className={css.composerQuote} onClick={(e) => e.stopPropagation()}>
                <QuoteCard quote={q} onRemove={() => setQuotes((all) => all.filter((x) => x.id !== q.id))} comment={
                  <input ref={(el) => { if (el) quoteInputs.current.set(q.id, el); else quoteInputs.current.delete(q.id); }}
                    className={`${css.quoteCardComment} ${css.quoteCardInput}`} value={q.comment} placeholder="对这段说点什么（可以不写）" aria-label={`对 ${q.author} 这段的批注`}
                    onChange={(e) => { const v = e.target.value; setQuotes((all) => all.map((x) => (x.id === q.id ? { ...x, comment: v } : x))); }}
                    onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing) { e.preventDefault(); input.current?.focus(); } }} />
                } />
              </div>
            ))}
          </div>
        )}
        {files.length > 0 && (
          <div className={css.composerFiles}>
            {files.map((f) => {
              const remove = () => draft.remove(f.id);
              return f.preview ? (
                <span key={f.id} className={css.composerThumb} title={f.error ?? f.name} data-error={f.error ? true : undefined}>
                  <img src={f.preview} alt={f.name} />
                  {!f.done && !f.error && <span className={css.composerThumbBusy}><span className={waitingCss.spinner} aria-hidden="true" /></span>}
                  <button type="button" className={css.composerThumbRemove} aria-label={`移除 ${f.name}`} onClick={(e) => { e.stopPropagation(); remove(); }}><Close size={11} /></button>
                </span>
              ) : <FileCard key={f.id} file={f.done ?? f} pending={!f.done && !f.error} error={f.error} onRemove={remove} />;
            })}
          </div>
        )}
        <textarea ref={input} className={css.composerText} rows={1} value={text} placeholder={placeholder} aria-label="消息"
          onChange={(e) => { setText(e.target.value); warm(); }}
          onPaste={(e) => { if (e.clipboardData.files.length) { e.preventDefault(); if (!locked) add(e.clipboardData.files); } }}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) { e.preventDefault(); submit(); return; }
            // Nothing typed: ↑ / ↓ go to the chat above or below, as the sidebar lists them now.
            if ((e.key === "ArrowUp" || e.key === "ArrowDown") && !text && !e.nativeEvent.isComposing && !e.altKey && !e.metaKey && !e.ctrlKey && !e.shiftKey) {
              if (goToNeighbour(e.key === "ArrowUp" ? -1 : 1)) e.preventDefault();
            }
          }} />
        <div className={css.composerToolbar}>
          <input ref={picker} type="file" multiple hidden onChange={(e) => { if (e.target.files) add(e.target.files); e.target.value = ""; }} />
          <Tip label="发送文件">
            <button type="button" className={css.attachBtn} aria-label="发送文件" disabled={locked} onClick={(e) => { e.stopPropagation(); picker.current?.click(); }}>
              <Plus size={18} />
            </button>
          </Tip>
          {toolbar && <div className={css.composerChoices} onClick={(e) => e.stopPropagation()}>{toolbar}</div>}
          <Tip label={uploading ? "文件还在上传" : "发送"}>
            <button type="submit" className={css.sendBtn} disabled={!ready} aria-label="发送" aria-busy={starting || undefined}>
              {starting ? <span className={waitingCss.spinner} aria-hidden="true" /> : <ArrowUp size={16} strokeWidth={2} />}
            </button>
          </Tip>
        </div>
      </form>
      {draft.error && <p className={`${controlsCss.fieldError} ${css.chatError}`} role="alert">{draft.error}</p>}
    </div>
  );
}

/** An agent in this chat that is at work: who it is, and what it does now. */
export interface AgentAtWork {
  key: string; who: string; runtime: RuntimeKind; maker: Maker | undefined;
  /** What it is doing, as the core says (null until its live view has come). */
  activity: ActivityView | null; since: number | undefined;
}

/** How long an activity stays once its agent stops (a turn ending and the next starting leave a moment between), then how long it takes to fade and fold away. */
const HOLD_MS = 600;
const FADE_MS = 220;

/**
 * The activities on screen: every agent at work, and each one that stopped for a moment more (HOLD_MS, then FADE_MS
 * to fold away), each on its own. `keep` holds those whose message is still coming out of their avatar.
 */
export function useLinger(atWork: AgentAtWork[], keep: ReadonlySet<string>): { agent: AgentAtWork; leaving: boolean }[] {
  const [, rerender] = useState(0);
  const shown = useRef(new Map<string, { agent: AgentAtWork; stopped: number | null }>());
  const now = Date.now();
  for (const a of atWork) shown.current.set(a.key, { agent: a, stopped: null });
  let next: number | null = null;
  for (const [key, s] of shown.current) {
    if (atWork.some((a) => a.key === key) || keep.has(key)) s.stopped = null;
    else if (s.stopped === null) s.stopped = now;
    if (s.stopped === null) continue;
    const at = now - s.stopped < HOLD_MS ? s.stopped + HOLD_MS : s.stopped + HOLD_MS + FADE_MS;
    if (at <= now) shown.current.delete(key);
    else next = Math.min(next ?? at, at);
  }
  useEffect(() => {
    if (next === null) return;
    const timer = setTimeout(() => rerender((n) => n + 1), next - Date.now());
    return () => clearTimeout(timer);
  });
  return [...shown.current.values()].map((s) => ({ agent: s.agent, leaving: s.stopped !== null && now - s.stopped >= HOLD_MS }));
}

/**
 * A message an agent posts while its activity shows comes out of the activity's avatar, one at a time:
 * the activity folds to its avatar (fold), the avatar floats to where the message goes (float), the message comes out
 * of it, growing into its place (spit), and the avatar goes on down to where the activity now is, which unfolds again
 * (return). The message's own avatar is where the flying one leaves it, the same picture in the same place, so
 * nothing blinks. Until its turn a message waits folded to nothing. With reduced motion messages just appear.
 */
type Pose = "fold" | "float" | "spit" | "return";
const FOLD_MS = 170;
const FLOAT_MS = 240;
const SPIT_MS = 380;
const RETURN_MS = 320;

export function useEmissions(list: RefObject<HTMLDivElement | null>) {
  const decided = useRef(new Map<number, boolean>());
  const done = useRef(new Set<number>());
  const queue = useRef<{ seq: number; agent: string }[]>([]);
  const [current, setCurrent] = useState<{ seq: number; agent: string; pose: Pose } | null>(null);
  const flying = useRef<HTMLElement | null>(null);
  const reduced = useMemo(() => window.matchMedia("(prefers-reduced-motion: reduce)").matches, []);

  // Where an element sits in the list's content, by layout: what the flying avatar moves in (scrolling does not move
  // it), and unmoved by the message's own growing scale.
  const spot = (el: Element) => {
    const pane = list.current!;
    let x = 0;
    let y = 0;
    for (let n: HTMLElement | null = el as HTMLElement; n && n !== pane; n = n.offsetParent as HTMLElement | null) {
      x += n.offsetLeft;
      y += n.offsetTop;
    }
    return { x, y };
  };
  const nextAfter = (agent: string | null) => {
    const next = queue.current.shift();
    // The same agent's next message goes straight on: its activity is folded already.
    setCurrent(next ? { ...next, pose: next.agent === agent ? "float" : "fold" } : null);
  };
  const finish = (seq: number, agent: string) => {
    flying.current?.remove();
    flying.current = null;
    done.current.add(seq);
    nextAfter(agent);
  };

  useLayoutEffect(() => {
    if (!current && queue.current.length) nextAfter(null);
  });
  useLayoutEffect(() => {
    if (!current) return;
    const { seq, agent, pose } = current;
    const pane = list.current;
    const avatar = pane?.querySelector(`.${css.agentActivity}[data-agent="${CSS.escape(agent)}"] .${css.activityAvatar}`);
    const message = pane?.querySelector(`.${conversationCss.msg}[data-seq="${seq}"]`);
    const landing = message?.querySelector(`:scope > .${chatCss2.msgAvatar}`);
    if (!pane || !avatar || !message || !landing) { finish(seq, agent); return; }
    let timer: ReturnType<typeof setTimeout> | undefined;
    let frame = 0;
    const go = (to: Pose | null, ms: number) => { timer = setTimeout(() => (to ? setCurrent({ seq, agent, pose: to }) : finish(seq, agent)), ms); };
    // Each frame the avatar is put between where it set out and where it is going, both read anew: the message growing
    // moves the one, the activity pushed down the other.
    const move = (from: () => { x: number; y: number }, to: () => { x: number; y: number }, ms: number, swell = 0) => {
      const el = flying.current;
      if (!el) return;
      const start = from();
      const begun = performance.now();
      const step = () => {
        const t = Math.min(1, (performance.now() - begun) / ms);
        const e = 1 - (1 - t) ** 3;
        const end = to();
        const scale = 1 + swell * Math.sin(Math.PI * Math.min(1, t / 0.6));
        el.style.transform = `translate(${start.x + (end.x - start.x) * e}px, ${start.y + (end.y - start.y) * e}px) scale(${scale})`;
        if (t < 1) frame = requestAnimationFrame(step);
      };
      step();
    };
    if (pose === "fold") go("float", FOLD_MS);
    if (pose === "float") {
      const el = avatar.cloneNode(true) as HTMLElement;
      el.classList.add(css.avatarFlying);
      Object.assign(el.style, { left: "0", top: "0", width: `${(avatar as HTMLElement).offsetWidth}px`, height: `${(avatar as HTMLElement).offsetHeight}px` });
      pane.append(el);
      flying.current = el;
      move(() => spot(avatar), () => spot(landing), FLOAT_MS);
      go("spit", FLOAT_MS);
    }
    // A small swell as it lets the message out, staying on the message's avatar as the message grows.
    if (pose === "spit") {
      move(() => spot(landing), () => spot(landing), SPIT_MS, 0.16);
      go("return", SPIT_MS);
    }
    if (pose === "return") {
      move(() => spot(landing), () => spot(avatar), RETURN_MS);
      go(null, RETURN_MS);
    }
    return () => { clearTimeout(timer); cancelAnimationFrame(frame); };
  }, [current?.seq, current?.pose]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => () => flying.current?.remove(), []);

  return {
    /** Agents whose activity must stay while their messages come out. */
    keeps: new Set([...queue.current.map((q) => q.agent), ...(current ? [current.agent] : [])]),
    /** Messages seen for the first time: an agent's, new, while its activity shows, waits its turn to come out of it. */
    take(messages: ChatMessage[], since: number, showing: ReadonlySet<string>) {
      for (const m of messages) {
        if (decided.current.has(m.seq)) continue;
        const agent = m.authorKind === "agent" ? m.by.agent : undefined;
        const emits = !reduced && m.seq > since && agent !== undefined && showing.has(agent);
        decided.current.set(m.seq, emits);
        if (emits) queue.current.push({ seq: m.seq, agent: agent! });
      }
    },
    /** Whether a message comes (or came) out of an avatar: it never eases in as others do. */
    emits: (seq: number) => decided.current.get(seq) === true,
    /** A message's part in it: waiting folded, coming out, or none (shown as any other). */
    stateOf(seq: number): "held" | "emitting" | null {
      if (!decided.current.get(seq) || done.current.has(seq)) return null;
      if (current?.seq === seq && current.pose === "spit") return "emitting";
      if (current?.seq === seq && current.pose === "return") return null;
      return "held";
    },
    /** How an agent's activity stands: folded to its avatar, and whether the avatar is away flying. */
    poseOf(agent: string): { folded: boolean; away: boolean } {
      if (current?.agent !== agent) return { folded: false, away: false };
      return { folded: true, away: current.pose !== "fold" };
    },
  };
}

/**
 * An agent at work, in one line: its avatar, ringed while it works, and what it does now (as the core says), with how
 * long its turn has run. No name: the avatar says whose. What it does changes by crossfading, and each thing stays a
 * moment, so a passing 请求中 does not flicker by. The line opens its history.
 */
export function Activity({ agent, leaving, pose, onOpen, mark, className }: {
  agent: AgentAtWork; leaving: boolean; pose: { folded: boolean; away: boolean }; onOpen(): void;
  /** Its avatar, drawn as the agent's messages draw theirs (a message comes out of it onto theirs); the pane's class. */
  mark?: ReactNode; className?: string;
}) {
  const now = useSteady(agent.activity?.now ?? { key: "busy", text: "处理中" });
  return (
    <div className={`${conversationCss.msg} ${css.agentActivity}${className ? ` ${className}` : ""}`} data-transient="" data-agent={agent.key} data-leaving={leaving || undefined} data-folded={pose.folded || undefined} data-away={pose.away || undefined}>
      <button type="button" className={css.activityLine} onClick={onOpen} title="打开执行历史" aria-label={`${agent.who}：${now.current.text}`}>
        <span className={css.activityAvatar} aria-hidden="true">{mark ?? <span className={`${chatCss2.msgAvatar} ${css.msgAvatarAgent}`}><ModelLogo maker={agent.maker} runtime={agent.runtime} size={12} /></span>}</span>
        <span className={css.activityTail}>
          <span className={css.activityNow}>
            {now.previous && <span key={`was-${now.n - 1}`} className={css.activityNowText} data-out="">{now.previous.text}</span>}
            <span key={now.n} className={css.activityNowText} data-in={now.switched || undefined}>{now.current.text}</span>
          </span>
          {agent.since ? <span className={css.activityElapsed}><Elapsed since={agent.since} /></span> : null}
        </span>
      </button>
    </div>
  );
}

/** Each thing shown at least this long before the next replaces it; how long the crossfade takes. */
const DWELL_MS = 700;
const CROSS_MS = 240;

/**
 * What an activity shows now, steadied: a new thing (another key) replaces the shown one after it has stayed DWELL_MS,
 * with the one it replaces kept for the crossfade; the same thing's new words (its rate) show at once.
 */
export function useSteady(now: { key: string; text: string }) {
  type Shown = { key: string; text: string };
  // `n` counts the crossfades: what shows is known by it, so words changing in place (a rate, or another thing saying
  // the same) do not make it come in again.
  const [state, setState] = useState<{ current: Shown; previous: Shown | null; at: number; switched: boolean; n: number }>(
    () => ({ current: now, previous: null, at: 0, switched: false, n: 0 }),
  );
  const latest = useRef(now);
  latest.current = now;
  useEffect(() => {
    // The same thing, or another saying the same words: nothing to fade, the words change at once.
    if (now.key === state.current.key || now.text === state.current.text) {
      if (now.key !== state.current.key || now.text !== state.current.text) setState((s) => ({ ...s, current: now }));
      return;
    }
    const timer = setTimeout(() => setState((s) => {
      const next = latest.current;
      // Back to what shows while it stayed (请求中, a moment of 思考中, 请求中 again): nothing changes.
      if (next.text === s.current.text) return { ...s, current: next };
      return { current: next, previous: s.current, at: Date.now(), switched: true, n: s.n + 1 };
    }), Math.max(0, state.at + DWELL_MS - Date.now()));
    return () => clearTimeout(timer);
  }, [now.key, now.text, state.current.key, state.current.text]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    if (!state.previous) return;
    const timer = setTimeout(() => setState((s) => ({ ...s, previous: null })), CROSS_MS);
    return () => clearTimeout(timer);
  }, [state.previous]);
  return state;
}

/** Seconds (then minutes) since a moment, ticking. */
export function Elapsed({ since }: { since: number }) {
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

/** Opens the chat `step` rows above (-1) or below (1) the open one in the sidebar; false when there is none. */
function goToNeighbour(step: -1 | 1): boolean {
  // The list in view: the other one (全部 or 我参与的) sits beside it out of view, and a row of it is not a neighbour.
  const rows = [...document.querySelectorAll<HTMLAnchorElement>(`.${nav.sidebar} .${nav.navScroll}:not([inert]) a.${nav.navSession}`)];
  const at = rows.findIndex((row) => row.getAttribute("aria-current") === "page");
  const next = at < 0 ? null : rows[at + step];
  if (!next) return false;
  next.click();
  next.scrollIntoView({ block: "nearest" });
  return true;
}
