// ember's own chat with a session, after Zork's: your messages sit right in a
// bubble with only their time; everyone else (people and the agent) gets an
// avatar, a name and the time over their words. Passages of earlier messages
// can be quoted with a comment, and files ride along as cards (images shown).
import { ArchiveNotice } from "./ArchiveNotice.tsx";
import { ArrowDown, ArrowUp, Bot, Brain, Chats, Close, Command, Edit, Info, Plus, Quote as QuoteIcon, Read, Received, Retry, Said, Search, Send, Sparks, Think, Trash, Web } from "./icons.tsx";
import { memo, useCallback, useContext, useEffect, useLayoutEffect, useMemo, useRef, useState, type CSSProperties, type MutableRefObject, type ReactNode, type RefObject } from "react";
import { useSearchParams } from "react-router";
import { useApi, useChatSend, type ChatTo, type Outgoing, type Activity as ActivityView, type AgentWait, type Attachment, type ChatMessage, type ChatView, type Live, type Maker, type Quote, type RuntimeKind, type Session, type Stamp, type Status } from "./api.ts";
import { Mark } from "./brand.tsx";
import { usePerson, useStation } from "./station.tsx";
import { Avatar, ModelLogo, Time, Tip, transitionTo } from "./ui.tsx";
import { ComposerSlot, useComposerHeight } from "./dock.tsx";
import { placeFiles, Prose } from "./Prose.tsx";
import { useShortcut } from "./keymap.ts";
import { chatImages, FileLink, FilePreview, fileSize, Gallery, isImage, kindOf, useFileShown, useNear } from "./FilePreview.tsx";
import { thumbhashRatio, thumbhashUrl } from "./thumbhash.ts";
import { OpenFile, VizFile } from "./Viz.tsx";
import { useStickToBottom } from "./scroll.ts";
import { DraftKey, useDraft, useDraftInbox, type Draft, type DraftQuote, type Pending } from "./draft.ts";
import * as nav from "./Sidebar.css.ts";
import * as sessionCss from "./styles/session.css.ts";
import * as chatCss2 from "./styles/chat.css.ts";
import * as conversationCss from "./styles/conversation.css.ts";
import * as css from "./Chat.css.ts";
import * as refCss from "./ChatRef.css.ts";
import { ChatRefMenu, markBefore, refAt, RefMirror, WithRefs, type ChatRef } from "./ChatRef.tsx";
import { refMark } from "./chatRefs.ts";
import { useMorph } from "./morph.ts";
import * as waitingCss from "./styles/waiting.css.ts";
import * as cloudCss from "./styles/cloud.css.ts";
import * as composerCss from "./styles/composer.css.ts";
import * as controlsCss from "./styles/controls.css.ts";
import * as dockCss from "./dock.css.ts";
import { toMadeChat as toMadeChatOf } from "./madeChat.ts";

/** Over the composer (dock.css.ts): where what a new chat's first message is drawn by on its way (madeChat.ts). */
export const OVER_DOCK = "4";

/**
 * From a new chat to the chat it made (madeChat.ts): its scene leaves, the composer moves to the chat's foot
 * (dock.tsx), and the words sent go up to where the chat has its first message.
 */
export function toMadeChat(go: () => void): void {
  toMadeChatOf(go, {
    scope: document,
    layer: () => document.querySelector<HTMLElement>(`.${dockCss.composerDock}`)?.offsetParent as HTMLElement | null,
    z: OVER_DOCK,
    list: () => document.querySelector<HTMLElement>(`.${css.chatMessages}`),
  });
}

/**
 * A chat's messages and its composer. Before its agent has a chat (`chat.thread` null) there are no messages, and
 * `ensureChat` makes the chat with the first message, which `onSent` then follows.
 */
export function ChatPanel({ chat, draftKey, lives, onOpenHistory, ensureChat, onSent, made }: {
  /** Whose draft the composer shows here. */
  chat: ChatView; draftKey: string; lives: ReadonlyMap<string, Live>; onOpenHistory(key: string, entry?: number): void;
  ensureChat?: () => Promise<{ key: string; thread: ChatTo }>; onSent?: (to: ChatTo) => void;
  /** The core's key of a chat made here (`chat.create`): sent to by it until its thread is known. */
  made?: string;
}) {
  const station = useStation();
  const list = useRef<HTMLDivElement>(null);
  const composerHeight = useComposerHeight();
  const floor = useRef<HTMLDivElement>(null);
  const api = useApi();
  const { thread, outbox } = chat;
  const id = thread?.id ?? null;
  const to: ChatTo | null = id ?? made ?? null;
  const [quotes, setQuotes] = useState<DraftQuote[]>([]);
  const [focusQuote, setFocusQuote] = useState<string | null>(null);
  const quoteFocused = useCallback(() => setFocusQuote(null), []);
  const rows = useMessageList(list, floor, chat, `${station.address}:${chat.thread?.id ?? chat.agents[0]?.session.key ?? ""}`, lives);
  // Files are kept in a session's workspace: what is sent here goes to the first agent's.
  const keeper = chat.agents[0]?.session.key ?? null;
  const ownerOf = (file: Attachment) => ownerIn(chat, file);
  // The messages are kept as they are while nothing they show changes (MessageRow): what they are handed stays the same
  // function, the latest one behind it, and `owners` says when whose files are whose has changed.
  const images = () => chatImages([...rows.messages, ...outbox.map((o) => ({ authorKind: "person", ...o }))], ownerOf);
  const latest = useRef({ ownerOf, onOpenHistory, images });
  latest.current = { ownerOf, onOpenHistory, images };
  const [stable] = useState(() => ({ owner: (file: Attachment) => latest.current.ownerOf(file), open: (key: string) => latest.current.onOpenHistory(key), images: () => latest.current.images() }));
  useShortcut("chat.latest", () => { list.current?.dispatchEvent(new Event("to-bottom")); });
  const askedFile = useAskedFile(list, rows.messages, ownerOf);
  // Selecting text inside one message offers to quote it.
  const quoting = useSelectionQuote(list, (q) => {
    const quote = { ...q, comment: "", id: `${Date.now()}` };
    setQuotes((all) => [...all, quote]);
    setFocusQuote(quote.id);
  });

  return (
    // The list runs on under the composer, frosted over it (its styles): its foot leaves the composer's height free.
    <section className={sessionCss.chat} aria-label="对话" data-under-composer="" data-avoid-previews="" style={{ "--composer-height": `${composerHeight}px` } as CSSProperties}>
      <div className={sessionCss.chatPane}>
      {rows.away && (
        <Tip label="跳到最新" shortcut="chat.latest" side="top">
        <button type="button" className={css.chatToBottom} aria-label="跳到最新"
          // Glides down, and follows new messages again (scroll.ts).
          onClick={() => list.current?.dispatchEvent(new Event("to-bottom"))}>
          <ArrowDown size={16} strokeWidth={2} />
        </button>
        </Tip>
      )}
      <Gallery.Provider value={stable.images}>
      <div className={`${sessionCss.chatList} ${css.chatMessages}`} ref={list} {...quoting.listProps}
        onClick={(e) => {
          const to = historyLinkClicked(e);
          // At the entry it names (else its start); opened, not toggled.
          if (to) { e.preventDefault(); onOpenHistory(to.key, to.entry); }
        }}>
        <DraftKey.Provider value={draftKey}>
          <ChatRows chat={chat} rows={rows} to={to} owners={ownersOf(chat)} owner={stable.owner} onOpenHistory={stable.open} />
        </DraftKey.Provider>
        <div ref={floor} className={chatCss2.chatFloor} aria-hidden="true" />
      </div>
      </Gallery.Provider>
      </div>
      {quoting.pop}
      {askedFile}
      {chat.archived && <ArchiveNotice className={css.offlineNotice} offline={chat.offline} restore={() => api.archive({ thread: id, session: keeper ?? "" }, false)} />}
      {chat.offline && <p className={css.offlineNotice} role="status">{station.name ? `「${station.name}」` : "这台 station "}离线了：这里是之前读到的内容，暂时不能发消息。</p>}
      {/* The one composer of the chat pages sits here (dock.tsx), kept as the page changes. */}
      <ComposerSlot variant="chat" station={station} draftKey={draftKey} thread={to} sessionKey={keeper} quotes={quotes} setQuotes={setQuotes} focusQuote={focusQuote} onFocused={quoteFocused}
        locked={chat.offline || !!chat.archived} placeholder={chat.archived ? "还原对话后才能发送" : "发消息"} {...(ensureChat ? { ensureChat } : {})} {...(onSent ? { onSent } : {})} />
    </section>
  );
}

/** The session of a chat that keeps a file: the agent whose workspace holds it, else the first (what is sent goes there). */
export function ownerIn(chat: ChatView, file: Attachment): string | null {
  return chat.agents.find((a) => file.path.startsWith(`${a.session.workspace}/`))?.session.key ?? chat.agents[0]?.session.key ?? null;
}

/** Whose files are whose in a chat, in a word: when it changes, its messages' files are drawn again. */
export function ownersOf(chat: ChatView): string {
  return `${chat.agents[0]?.session.key ?? ""} ${chat.agents.map((a) => `${a.session.key}=${a.session.workspace}`).join(" ")}`;
}

/**
 * What a chat's list holds, the same on both screens (this page; the phone's, mobile/Chat.tsx): older pages loading, its
 * messages with the unread line, what is sent from here on its way (`to`: where it goes), and its agents at work.
 * `owner` and `onOpenHistory` stay the same functions while the page lasts; `owners` says when whose files are whose
 * has changed.
 */
export function ChatRows({ chat, rows, to, owners, owner, onOpenHistory }: {
  chat: ChatView; rows: ReturnType<typeof useMessageList>; to: ChatTo | null; owners: string;
  owner: (file: Attachment) => string | null; onOpenHistory: (key: string) => void;
}) {
  const { messages, divider, shown, rowOf, poseOf } = rows;
  const here = (key: string | undefined) => key !== undefined && chat.agents.some((a) => a.session.key === key);
  return (
    <>
      {chat.more && <div className={css.chatOlder} aria-hidden="true"><span className={waitingCss.spinner} /></div>}
      {messages.length === 0 && chat.outbox.length === 0 && (
        <div className={css.chatEmpty}>
          <p>在这里发消息，这个对话里的 agent 会在这里回复。</p>
        </div>
      )}
      {messages.map((m) => {
        const line = m.seq === divider ? <div key={`new-${m.seq}`} className={css.chatUnreadLine} data-unread-line role="separator"><span>以下是新消息</span></div> : null;
        const { enter, emitted } = rowOf(m);
        return [line, (
          <MessageRow key={m.seq} message={m} enter={enter} emitted={emitted}
            agentHere={here(m.by.agent)} owners={owners} owner={owner} onOpenHistory={onOpenHistory} />
        )];
      })}
      {chat.outbox.map((o) => <OutboxRow key={o.id} o={o} to={to} locked={chat.offline || !!chat.archived} owner={owner} />)}
      {/* A reply comes whole, as a message: while an agent works, its activity (always the last thing in the chat) says what it does. */}
      {shown.map(({ agent, leaving }) => (
        <Activity key={agent.key} agent={agent} leaving={leaving} pose={poseOf(agent.key)} onOpen={() => onOpenHistory(agent.key)} />
      ))}
    </>
  );
}

/** A message sent from here that the chat does not show yet: on its way, or failed with a way to send it again or drop it. */
function OutboxRow({ o, to, locked, owner }: { o: Outgoing; to: ChatTo | null; locked: boolean; owner: (file: Attachment) => string | null }) {
  const sending = useChatSend();
  return (
    <MineMessage data-author="你" data-role="person" data-enter data-unsent={o.state === "failed" || undefined}>
      <MineWords message={o} owner={owner} />
      {o.state === "failed"
        // Not sent: said briefly, why in its tip; sending it again or dropping it right beside.
        ? <div className={css.msgUnsent}>
            <Tip label={o.error ? `没发出去：${o.error}` : "没发出去"}>
              <span className={css.msgUnsentNote}><Info size={12} strokeWidth={2} />未发送</span>
            </Tip>
            <button type="button" className={css.msgUnsentBtn} disabled={locked} onClick={() => void (to !== null && sending.retry(to, o.id).catch(() => {}))}><Retry size={12} strokeWidth={2} />重试</button>
            <button type="button" className={css.msgUnsentBtn} onClick={() => void (to !== null && sending.discard(to, o.id))}><Trash size={12} strokeWidth={2} />删除</button>
          </div>
        : <span className={`${conversationCss.msgTime} ${chatCss2.msgWaiting} ${chatCss2.msgSending}`}><span className={waitingCss.spinner} aria-hidden="true" />正在发送</span>}
    </MineMessage>
  );
}

/**
 * Selecting words inside one message of the list offers to quote them (`onQuote`), in a small button over the
 * selection. Answers what the list takes to watch the selection, and the button.
 */
export function useSelectionQuote(list: RefObject<HTMLElement | null>, onQuote: (quote: Omit<Quote, "comment">) => void) {
  const [picked, setPicked] = useState<{ quote: Omit<Quote, "comment">; x: number; y: number } | null>(null);
  const pick = () => {
    const selection = window.getSelection();
    const text = selection?.toString().trim();
    if (!selection || !text || selection.rangeCount === 0) return setPicked(null);
    const range = selection.getRangeAt(0);
    const node = range.commonAncestorContainer;
    const from = (node instanceof Element ? node : node.parentElement)?.closest<HTMLElement>("[data-author]");
    if (!from || !list.current?.contains(from)) return setPicked(null);
    const rect = range.getBoundingClientRect();
    const role = from.dataset.role === "agent" ? "agent" as const : "person" as const;
    setPicked({ quote: { author: from.dataset.author!, text, ...(from.dataset.ts ? { ts: from.dataset.ts } : {}), role }, x: rect.left + rect.width / 2, y: rect.top });
  };
  return {
    listProps: { onMouseUp: () => { setTimeout(pick, 0); }, onScroll: () => setPicked(null) },
    pop: picked && (
      <button type="button" className={css.quotePop} style={{ left: picked.x, top: picked.y }}
        onMouseDown={(e) => e.preventDefault()}
        onClick={() => { onQuote(picked.quote); setPicked(null); window.getSelection()?.removeAllRanges(); }}>
        <QuoteIcon size={12} strokeWidth={2.2} />引用
      </button>
    ),
  };
}

/** A click on a link to an agent's execution history in the list (`?history=<session>&entry=<n>`): which, or null. */
export function historyLinkClicked(e: React.MouseEvent): { key: string; entry: number } | null {
  // A chat going on with a session from a terminal starts with a note linking to it, where what was said before is.
  const anchor = (e.target as Element).closest?.("a[href]") as HTMLAnchorElement | null;
  return anchor ? historyLink(anchor.href) : null;
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
  useOlderOnScroll(list, chat.more, chat.messages[0]?.seq, older);
  useMarkRead(floor, chat, (seq) => (id === null ? Promise.resolve() : sending.read(id, seq)));
  useRememberPlace(list, place, messages.length > 0);
  const divider = useUnreadLine(list, chat, messages, mineOf, older);
  const away = useAwayFromBottom(list);
  // A message sent from here eases in once, from the outbox; its own copy that replaces it does not again.
  const sentHere = useRef(new Set<string>());
  for (const o of chat.outbox) sentHere.current.add(o.text);
  // Messages there when the chat opened (and older pages loaded later) show at once; newer ones ease in, except a reply that already streamed in place.
  const firstSeq = useRef<number | null>(null);
  if (firstSeq.current === null) firstSeq.current = messages.at(-1)?.seq ?? 0;
  // Only an agent that has taken a message and runs is at work: until then the message itself says it waits.
  const atWork: AgentAtWork[] = chat.agents.filter((a) => a.status === "running").map(({ session, since, wait }) => (
    { key: session.key, who: session.agentText, runtime: session.runtime, maker: session.maker, activity: lives.get(session.key)?.activity ?? null, since, wait }
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
 * no line, and the chat opens at its bottom or where it was left; something
 * unread takes it to the line even so. Answers the seq of the message
 * the line goes over.
 */
export function useUnreadLine(ref: RefObject<HTMLElement | null>, chat: ChatView, messages: ChatMessage[], mine: (m: ChatMessage) => boolean, older: () => Promise<unknown>): number | null {
  const [open] = useState(() => ({ read: chat.thread?.read ?? 0, at: Date.now() }));
  const unread = (m: ChatMessage) => m.seq > open.read && m.createdAt <= open.at && !mine(m);
  const first = messages[0]?.seq;
  // Those not loaded yet may hold it: the pages before are loaded first.
  const above = chat.more && first !== undefined && first > open.read + 1 && messages.some(unread);
  const target = above ? null : messages.find(unread)?.seq ?? null;
  const asked = useRef<number | undefined>(undefined);
  // Until something unread shows (it may come from the station a moment after opening), there is nothing to jump to.
  // Coming back to a chat with something unread goes to the line too, over where it was left (useRememberPlace).
  const jumped = useRef(false);
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
    // The line near the top, below what floats over the pane there (the phone's bar: its scroll padding), with about
    // four lines of what came before it still in view.
    const style = getComputedStyle(pane);
    const covered = parseFloat(style.scrollPaddingTop) || 0;
    const text = parseFloat(style.lineHeight) || 22;
    pane.scrollTop += line.getBoundingClientRect().top - pane.getBoundingClientRect().top - covered - 4 * text;
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
 * does not move it. The unread line, when there is one, goes over it (useUnreadLine).
 */
export function useRememberPlace(ref: RefObject<HTMLElement | null>, key: string, ready: boolean): void {
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
}

/**
 * Loads the page before what is shown (`more`: there is one; `first`: what is
 * shown first) when the reader comes near the top (or when what is loaded does
 * not fill the pane). What is on screen stays put: the pane keeps its distance
 * from the bottom as content grows above (scroll.ts).
 */
export function useOlderOnScroll(ref: RefObject<HTMLElement | null>, more: boolean, first: number | string | undefined, older: () => Promise<unknown>): void {
  // What was shown first when a page was asked before it: one request per page.
  const asked = useRef<number | string | undefined>(undefined);
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
        <MineWords message={m} owner={owner} />
        {/* Not taken by its agents yet: after a second it says it waits (the delay is the stylesheet's). */}
        {m.waiting
          ? <span className={`${conversationCss.msgTime} ${chatCss2.msgWaiting} ${css.msgWaitingLate}`}><span className={waitingCss.spinner} aria-hidden="true" />等待 agent 接收</span>
          : <Time className={conversationCss.msgTime} stamp={m.time?.createdAt} />}
      </MineMessage>
    );
  }
  // What ember itself says (a limit hit, a failure): a notice across the chat, not someone's message.
  if (m.system) return <SystemNotice text={m.text} time={m.time?.createdAt} ts={m.ts} enter={enter} />;
  const who = m.by.name;
  const agent = agentHere ? m.by.agent : undefined;
  return (
    <OthersMessage data-seq={m.seq} data-author={who} data-ts={m.ts} data-role={m.authorKind === "agent" ? "agent" : "person"}
      data-enter={enter} data-held={emitted === "held" || undefined} data-emitting={emitted === "emitting" || undefined} data-covered={emitted === "emitting" || undefined}
      avatar={<MessageAvatar message={m} name={who} />} time={m.time?.createdAt}
      name={agent
        ? <Tip label="打开或关闭执行历史"><button type="button" className={`${css.msgName} ${css.msgAgent}`} onClick={() => onOpenHistory(agent)}>{who}</button></Tip>
        : <span className={css.msgName}>{who}</span>}>
      <Quotes quotes={m.quotes} files={m.attachments} owner={owner} />
      {m.authorKind === "person"
        ? <>{m.text && <PersonWords text={m.text} />}<Files owner={owner} files={besideQuotes(m.quotes, m.attachments)} /></>
        : <ProseWithFiles owner={owner} text={m.text} files={besideQuotes(m.quotes, m.attachments)} />}
    </OthersMessage>
  );
}, (a, b) => a.enter === b.enter && a.emitted === b.emitted && a.agentHere === b.agentHere && a.owners === b.owners && sameMessage(a.message, b.message));

type Data = { [key: `data-${string}`]: string | number | boolean | undefined };

/** A viewer's own message as a chat draws it (on the right); its bubble is MineBubble. Also where else messages are shown so. */
export function MineMessage({ children, ...data }: Data & { children: ReactNode }) {
  return <div className={`${conversationCss.msg} ${chatCss2.msgMine}`} {...data}>{children}</div>;
}

/** What a viewer's own message says, its quotes and files with it: the same whether the station has it yet (a
 * MessageRow) or it is still on its way (an OutboxRow), so it does not change as the one takes the other's place. */
function MineWords({ message: m, owner }: { message: Pick<ChatMessage, "text" | "quotes" | "attachments">; owner: (file: Attachment) => string | null }) {
  return (
    <>
      <Quotes quotes={m.quotes} files={m.attachments} owner={owner} />
      <MineBubble text={m.text} />
      <Files owner={owner} files={besideQuotes(m.quotes, m.attachments)} />
    </>
  );
}

/** The words of a viewer's own message, in their bubble. */
export function MineBubble({ text }: { text: string }) {
  return text ? <div className={conversationCss.msgBubble}><PersonWords text={text} /></div> : null;
}

/** What a person wrote, as every message of a person's draws it (their own in its bubble, someone else's as it is):
 * plain text, its references to chats as chips. */
function PersonWords({ text }: { text: string }) {
  return <div className={chatCss2.msgPlain}><WithRefs text={text} /></div>;
}

/**
 * What ember itself says: a pill across the chat, in one line and no time. A click opens it: all its words, wrapped,
 * and its time under it. The station begins its failures with ⚠️ (Slack shows it so); here a failure is the pill in
 * red instead.
 */
function SystemNotice({ text, time, ts, enter }: { text: string; time: Stamp | undefined; ts: string | undefined; enter: true | undefined }) {
  const failed = /^⚠️\s*/u.exec(text);
  const words = failed ? text.slice(failed[0].length) : text;
  // A notice is a line of the UI, not prose: no 。 at its end (stations before 2026-09-30 wrote them as sentences).
  const said = words.replace(/。\s*$/u, "");
  const [open, setOpen] = useState(false);
  const toggle = () => setOpen((o) => !o);
  return (
    <div className={`${conversationCss.msg} ${css.msgSystem}`} data-ts={ts} data-role="system" data-enter={enter} role="note">
      <div className={css.msgSystemBox} data-failed={failed ? "" : undefined} data-open={open || undefined}
        role="button" tabIndex={0} aria-expanded={open}
        onClick={(e) => { if (!(e.target as Element).closest("a")) toggle(); }}
        onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); toggle(); } }}>
        <div className={conversationCss.markdown}><Prose>{said}</Prose></div>
      </div>
      {open && <Time className={conversationCss.msgTime} stamp={time} />}
    </div>
  );
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
function Quotes({ quotes, files, owner }: { quotes: Quote[] | undefined; files: Attachment[] | undefined; owner: (file: Attachment) => string | null }) {
  if (!quotes?.length) return null;
  // In the list the card is in: each screen's (and the phone's pages under the one on top) has its own.
  const jump = (from: Element, ts: string, text: string) => {
    const pane = from.closest<HTMLElement>(`.${css.chatMessages}`);
    const target = pane?.querySelector<HTMLElement>(`[data-ts="${CSS.escape(ts)}"]`);
    if (!pane || !target) return;
    // A reader's move: the pane lets it take the position.
    pane.dispatchEvent(new WheelEvent("wheel"));
    const range = findText(target, text);
    if (range && "highlights" in CSS) {
      const rect = range.getBoundingClientRect();
      pane.scrollTop += rect.top + rect.height / 2 - (pane.getBoundingClientRect().top + pane.clientHeight / 2);
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
      {quotes.map((q, i) => {
        const own = fileOf(q, files);
        return <QuoteCard key={i} quote={q} onJump={q.ts ? (from) => jump(from, q.ts!, q.text) : undefined}
          picture={own && <FileItem sessionKey={owner(own)} file={own} />} />;
      })}
    </div>
  );
}

/** The file among `files` that is a quote's own (a preview mark's screenshot, annotate/Marks.tsx), shown in its card. */
function fileOf<F extends { name: string }>(quote: Quote, files: F[] | undefined): F | undefined {
  return quote.file ? files?.find((f) => f.name === quote.file) : undefined;
}

/** A message's files but those shown in its quotes' cards. */
function besideQuotes<F extends { name: string }>(quotes: Quote[] | undefined, files: F[] | undefined): F[] | undefined {
  const own = new Set(quotes?.flatMap((q) => (q.file ? [q.file] : [])));
  return own.size && files ? files.filter((f) => !own.has(f.name)) : files;
}

/**
 * One quote: the passage with whose it is, its own picture (`picture`: a preview mark's screenshot), and the comment.
 * Also the composer's pending quote, with an editable comment.
 */
function QuoteCard({ quote, onJump, comment, onRemove, picture }: { quote: Quote; onJump?: ((from: Element) => void) | undefined; comment?: ReactNode; onRemove?: () => void; picture?: ReactNode }) {
  // A mark on a previewed page (annotate/Marks.tsx): its pin's number and what it is; where it is is for the agent.
  const pin = quote.role === "page" ? /(\d+)$/.exec(quote.author)?.[1] : undefined;
  return (
    <div className={css.quoteCard}>
      <Tip label={onJump ? "跳到原消息" : pin ? quote.text : undefined}><button type="button" className={css.quoteCardSource} onClick={onJump ? (e) => onJump(e.currentTarget) : undefined} disabled={!onJump}>
        {pin
          ? <span className={css.quoteCardText}><span className={css.quoteCardPin}>{pin}</span>{quote.text.split("\n")[0]}</span>
          : <span className={css.quoteCardText}><QuoteIcon size={11} strokeWidth={2.4} aria-hidden="true" /><span className={css.quoteCardWho}>{quote.author}：</span>{quote.text}</span>}
      </button></Tip>
      {picture && <div className={css.quoteCardPicture}>{picture}</div>}
      {comment ?? (quote.comment ? <div className={css.quoteCardComment}>{quote.comment}</div> : null)}
      {onRemove && <button type="button" className={css.quoteCardRemove} aria-label="移除引用" onClick={onRemove}><Close size={12} /></button>}
    </div>
  );
}

// ── files ───────────────────────────────────────────────────────────────

/** An agent's Markdown with its files: those its text names shown there, the rest below it. */
function ProseWithFiles({ owner, text, files }: { owner: (file: Attachment) => string | null; text: string; files: Attachment[] | undefined }) {
  const { placed, rest } = useMemo(() => placeFiles(text, files), [text, files]);
  return (
    <>
      <div className={conversationCss.markdown}>
        <Prose files={placed} file={(f, as, words) => as === "link" ? <FileLink sessionKey={owner(f)} file={f}>{words}</FileLink> : <PlacedFile sessionKey={owner(f)} file={f} />}>{text}</Prose>
      </div>
      <Files owner={owner} files={rest} />
    </>
  );
}

/**
 * A file the text places on a line of its own: an HTML one is a visualization, drawn there (Viz.tsx; how agents make
 * one is the ember-viz skill), any other shows as below the text.
 */
function PlacedFile({ sessionKey, file }: { sessionKey: string | null; file: Attachment }) {
  if (sessionKey !== null && kindOf(file.name).kind === "html") return <VizFile sessionKey={sessionKey} file={file} failed={<FileItem sessionKey={sessionKey} file={file} />} />;
  return <FileItem sessionKey={sessionKey} file={file} />;
}

/**
 * A link that names one of the chat's files (`?file=<name>`: what a post to Slack attached, which stays here): the
 * latest one of that name opens on its own (OpenFile: beside the chat, or over it on a phone), its message brought
 * into view. Anything else that name opens in a preview.
 */
export function useAskedFile(list: RefObject<HTMLDivElement | null>, messages: ChatMessage[], owner: (file: Attachment) => string | null): ReactNode {
  const [search, setSearch] = useSearchParams();
  const open = useContext(OpenFile);
  const asked = search.get("file");
  const found = useMemo(() => {
    if (!asked) return null;
    for (let i = messages.length - 1; i >= 0; i--) {
      const file = messages[i]!.attachments?.find((f) => f.name === asked);
      const key = file ? owner(file) : null;
      if (file && key !== null) return { file, key, ts: messages[i]!.ts };
    }
    return null;
  }, [asked, messages]); // eslint-disable-line react-hooks/exhaustive-deps
  const drawn = !!found && !!open && kindOf(found.file.name).kind === "html";
  const done = () => setSearch((now) => { now.delete("file"); return now; }, { replace: true });
  useEffect(() => {
    if (!found || !drawn) return;
    open!(found.key, found.file);
    list.current?.querySelector(`[data-ts="${CSS.escape(found.ts)}"]`)?.scrollIntoView({ block: "center" });
    done();
  }, [found, drawn]); // eslint-disable-line react-hooks/exhaustive-deps
  if (!found || drawn) return null;
  return <FilePreview open onClose={done} sessionKey={found.key} file={found.file} />;
}

/** A message's files; `owner` says which session of the chat keeps each (null: none can show it). */
function Files({ owner, files }: { owner: (file: Attachment) => string | null; files: Attachment[] | undefined }) {
  if (!files?.length) return null;
  return <div className={css.msgFiles}>{files.map((f) => <FileItem key={f.path} sessionKey={owner(f)} file={f} />)}</div>;
}

/** Images already brushed in on this page (session key and path): shown again, they just show. */
const revealed = new Set<string>();

/** Images and video stills load near the screen; other files are a card. Either opens in a preview. */
function FileItem({ sessionKey, file }: { sessionKey: string | null; file: Attachment }) {
  const image = isImage(file.name);
  const video = kindOf(file.name).kind === "video";
  const [videoFailed, setVideoFailed] = useState(false);
  const box = useRef<HTMLButtonElement>(null);
  const near = useNear(box, image || video);
  const { url, failed } = useFileShown(sessionKey ?? "", file, (image || video) && sessionKey !== null && near, !video);
  const [open, setOpen] = useState(false);
  // An image seen before, or that comes at once, just shows; one that takes a while is brushed in from the top.
  const born = useRef(performance.now());
  const [loaded, setLoaded] = useState<"instant" | "reveal" | null>(null);
  const shown = () => {
    const key = `${sessionKey}\n${file.path}`;
    setLoaded(revealed.has(key) || performance.now() - born.current < 150 ? "instant" : "reveal");
    revealed.add(key);
  };
  const preview = sessionKey !== null && <FilePreview open={open} onClose={() => setOpen(false)} sessionKey={sessionKey} file={file} />;
  if (video && sessionKey !== null) {
    return (
      <>
        <Tip label={file.name}><button ref={box} type="button" className={`${look.image} ${css.msgVideo}`} onClick={() => setOpen(true)} aria-label={`${videoFailed ? "查看" : "播放"} ${file.name}`} style={look.box(file)} data-unavailable={videoFailed || undefined}>
          {url && !videoFailed && <video src={url} muted playsInline preload="auto" aria-hidden="true" onError={() => setVideoFailed(true)} />}
          <span className={videoFailed ? css.msgVideoUnavailable : css.msgVideoPlay} aria-hidden="true">
            {videoFailed ? <><Read size={24} /><span>暂时无法预览</span><small>{fileSize(file.size)}</small></> : "▶"}
          </span>
          <span className={css.msgVideoName}>{file.name}</span>
        </button></Tip>
        {preview}
      </>
    );
  }
  if (image) {
    return (
      <>
        <button ref={box} type="button" className={look.image} onClick={() => (url || failed) && setOpen(true)} aria-label={`查看 ${file.name}`} style={look.box(file)}
          data-loaded={loaded ?? undefined} data-failed={failed || undefined}>
          {loaded !== "instant" && <Waiting hash={file.thumbhash} />}
          {failed && <span className={css.msgImageUnavailable} aria-hidden="true"><Read size={20} /><span>暂时无法预览</span></span>}
          {url && <img src={url} alt={file.name} onLoad={shown} />}
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

/** What an image's box shows until it loads: its ThumbHash drawn, sent with it; else the blots drifting. */
function Waiting({ hash }: { hash: string | undefined }) {
  const likeness = thumbhashUrl(hash);
  return likeness
    ? <span className={look.wait} style={{ backgroundImage: `url(${likeness})` }} data-likeness="" aria-hidden="true" />
    : <span className={look.wait} aria-hidden="true"><i /><i /><i /></span>;
}

/** How the chat draws a file: an image's button, the box it takes before it loads and what shows until then; a file's card and its button. */
const look = { image: css.msgImage, wait: css.msgImageWait, box: (f: Attachment) => imageBox(f), open: css.fileCardOpen, card: (f: Attachment) => <FileCard file={f} /> };

/**
 * The box an image takes in the chat, known before it loads: its own
 * proportions (sent with it, or read from its ThumbHash) within 360×300, or a
 * fixed box for images sent before sizes were recorded. A narrower chat shrinks it (max-width), the
 * proportions kept.
 */
export function imageBox(file: Attachment): { width: number; aspectRatio: string } {
  // No size sent, but a ThumbHash: its proportions, at the fixed box's height.
  const ratio = thumbhashRatio(file.thumbhash);
  const [w, h] = file.width && file.height ? [file.width, file.height] : ratio ? [Math.round(160 * ratio), 160] : [0, 0];
  if (!w || !h) return { width: 240, aspectRatio: "240 / 160" };
  const scale = Math.min(1, 360 / w, 300 / h);
  const width = Math.max(40, Math.round(w * scale)), height = Math.max(40, Math.round(h * scale));
  return { width, aspectRatio: `${width} / ${height}` };
}

function FileCard({ file, onRemove, pending, error }: { file: Pick<Attachment, "name" | "size"> & { path?: string }; onRemove?: () => void; pending?: boolean; error?: string | null }) {
  return (
    <Tip label={file.path ?? file.name}><span className={css.fileCard} data-error={error ? true : undefined}>
      {pending ? <span className={waitingCss.spinner} aria-hidden="true" /> : <Read size={16} aria-hidden="true" />}
      <span className={css.fileCardText}>
        <span className={css.fileCardName}>{file.name}</span>
        <span className={css.fileCardMeta}>{error ?? (pending ? "正在上传…" : fileSize(file.size))}</span>
      </span>
      {onRemove && <button type="button" className={css.fileCardRemove} aria-label={`移除 ${file.name}`} onClick={(e) => { e.stopPropagation(); onRemove(); }}><Close size={12} /></button>}
    </span></Tip>
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
  /**
   * The chat written to (its thread, or the core's key of one made here), and its session; both null for a new chat,
   * made by `ensureChat` with the first message.
   */
  thread: ChatTo | null;
  sessionKey: string | null;
  quotes?: DraftQuote[]; setQuotes?(update: (all: DraftQuote[]) => DraftQuote[]): void;
  /** A quote just added: its comment line takes the focus. */
  focusQuote?: string | null; onFocused?(): void;
  ensureChat?: () => Promise<{ key: string; thread: ChatTo }>;
  onSent?: (to: ChatTo) => void;
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
  const { text, files, add } = draft;
  const [dragging, setDragging] = useState(false);
  const input = useRef<HTMLTextAreaElement>(null);
  const picker = useRef<HTMLInputElement>(null);
  // Typing starts the session's runtime, so a cold start overlaps the writing.
  const warmed = useRef(0);
  const warm = () => {
    if (locked || !sessionKey || Date.now() - warmed.current < 60_000) return;
    warmed.current = Date.now();
    void api.warm(sessionKey).catch(() => {});
  };
  const send = async () => {
    const to = await sendDraft(draft, thread, ensureChat, onSending);
    if (to !== null) onSent?.(to);
  };
  // Switching to a chat puts the cursor in its composer (not on touch screens, where it would raise the keyboard),
  // before it is first drawn: it never shows unfocused first.
  useLayoutEffect(() => {
    if (window.matchMedia("(pointer: fine)").matches) input.current?.focus();
  }, [thread]);
  // Space with nothing that takes keys focused (the cursor lost to a click on the messages, a closed menu…) puts it
  // back in the composer, rather than scrolling the page.
  useShortcut("composer.focus", () => {
    const el = input.current;
    if (!el || el.disabled || !el.getClientRects().length) return false;
    el.focus();
  });
  useShortcut("composer.file", locked ? null : () => { picker.current?.click(); });
  const ready = draft.ready && !locked;
  const submit = () => {
    if (ready) void send();
  };
  const { menu, field } = useComposerText({ draft, input, draftKey, sessionKey, locked, placeholder, className: css.composerText, onType: warm, onSubmit: submit });
  // Capsule ⇄ box, in one motion (morph.ts); laid out for another page (a new chat's roomy box ⇄ a chat's foot), the
  // dock moves it (dock.tsx).
  const multiline = roomy || text.includes("\n") || text.length > 60 || files.length > 0 || quotes.length > 0;
  const box = useRef<HTMLFormElement>(null);
  // What it is laid out by: any change of it may change its height (a line more or less, capsule ⇄ box, files).
  useMorph(box, `${multiline}|${text}|${files.length}|${quotes.length}`, roomy);
  return (
    <div className={cloudCss.composerWrap}>
      {menu}
      <form ref={box} className={`${composerCss.composerBox} ${refCss.refHost}`} data-multiline={multiline || undefined} data-dragging={dragging || undefined}
        onSubmit={(e) => { e.preventDefault(); submit(); }} onClick={() => input.current?.focus()}
        // Locked (its station offline), no file is taken in.
        onDragOver={(e) => { if (e.dataTransfer.types.includes("Files") && !locked) { e.preventDefault(); setDragging(true); } }}
        onDragLeave={() => setDragging(false)}
        onDrop={(e) => { if (e.dataTransfer.files.length) { e.preventDefault(); setDragging(false); if (!locked) add(e.dataTransfer.files); } }}>
        <ComposerExtras draft={draft} focusQuote={focusQuote} onFocused={onFocused} onDone={() => input.current?.focus()} />
        {field}
        <div className={css.composerToolbar}>
          <input ref={picker} type="file" multiple hidden onChange={(e) => { if (e.target.files) add(e.target.files); e.target.value = ""; }} />
          <Tip label="发送文件" shortcut="composer.file">
            <button type="button" className={css.attachBtn} aria-label="发送文件" disabled={locked} onClick={(e) => { e.stopPropagation(); picker.current?.click(); }}>
              <Plus size={18} />
            </button>
          </Tip>
          {toolbar && <div className={css.composerChoices} onClick={(e) => e.stopPropagation()}>{toolbar}</div>}
          <Tip label={draft.uploading ? "文件还在上传" : "发送"}>
            <button type="submit" className={css.sendBtn} disabled={!ready} aria-label="发送" aria-busy={draft.starting || undefined}>
              {draft.starting ? <span className={waitingCss.spinner} aria-hidden="true" /> : <ArrowUp size={16} strokeWidth={2} />}
            </button>
          </Tip>
        </div>
      </form>
      {draft.error && <p className={`${controlsCss.fieldError} ${css.chatError}`} role="alert">{draft.error}</p>}
    </div>
  );
}

/**
 * Sends what a draft holds to a chat (`to`: its thread, or the core's key of one made here), as both screens' composers
 * do; with none yet (a new chat, or an agent's first message), `ensureChat` makes it first. Answers where it went, or
 * null when there was no chat to send into (the draft is back, and says why).
 */
export function sendDraft(draft: Draft, to: ChatTo | null, ensureChat: (() => Promise<{ thread: ChatTo }>) | undefined, onSending?: (text: string | null) => void): Promise<ChatTo | null> {
  return draft.send(async () => (to !== null ? to : (await ensureChat!()).thread), { first: to === null, ...(onSending ? { onSending } : {}) });
}

/**
 * The composer's text box, as both screens' composers have it (this page's Composer; the phone's capsule,
 * mobile/ChatHost.tsx), with `className` its look: it grows with the text up to `lines`, then scrolls, the lines it cuts
 * fading at its edges. `@` and a few letters offer the station's other chats, the one picked going in as a link, shown
 * as a chip; files pasted in go with the message; Enter sends (not with `enterSends` off: a touch keyboard's Enter
 * starts a line); with nothing typed, ↑ / ↓ go to the chat above or below. What a preview's marks offer the draft
 * `draftKey` comes in. Answers the box and the menu of chats (put over the composer), for the composer to place.
 */
export function useComposerText({ draft, input, draftKey, sessionKey, locked, placeholder, className, lines = 3, enterSends = true, onType, onSubmit }: {
  draft: Draft; input: RefObject<HTMLTextAreaElement | null>; draftKey: string | undefined; sessionKey: string | null; locked: boolean;
  placeholder: string; className: string; lines?: number; enterSends?: boolean; onType(): void; onSubmit(): void;
}): { menu: ReactNode; field: ReactNode } {
  const { text, setText, add } = draft;
  // `@` and a few letters: a menu of the station's other chats, the one chosen put in as a link (ChatRef.tsx).
  const [reference, setReference] = useState<{ start: number; query: string } | null>(null);
  const [active, setActive] = useState(0);
  const refItems = useRef<{ ref: ChatRef }[]>([]);
  // A reference in the text shows as a chip: a mirror of the text under it (see-through then) draws it.
  const mirror = useRef<HTMLDivElement>(null);
  const marked = /@\[[^\]\n]{1,120}\]/.test(text);
  const closedAt = useRef<number | null>(null);
  const lookForReference = (el: HTMLTextAreaElement) => {
    const at = el.selectionStart === el.selectionEnd ? refAt(el.value, el.selectionStart) : null;
    if (!at) closedAt.current = null;
    const next = at && at.start !== closedAt.current ? at : null;
    setReference((now) => (now?.start === next?.start && now?.query === next?.query ? now : next));
    if (next?.query !== reference?.query) setActive(0);
  };
  const pickReference = (ref: ChatRef) => {
    const el = input.current;
    if (!el || !reference) return;
    const link = refMark(ref.title, ref.link);
    const end = el.selectionStart;
    const next = `${text.slice(0, reference.start)}${link} ${text.slice(end)}`;
    const caret = reference.start + link.length + 1;
    caretAt.current = caret;
    setText(next);
    setReference(null);
  };
  // Where the caret goes once the text changed by hand is drawn (before anything more is typed).
  const caretAt = useRef<number | null>(null);
  useLayoutEffect(() => {
    const el = input.current, at = caretAt.current;
    if (!el || at === null) return;
    caretAt.current = null;
    el.focus();
    el.setSelectionRange(at, at);
  }, [text]);
  // A preview's marks beside the chat: their screenshot and a quote each, to say more about before sending.
  useDraftInbox(locked ? undefined : draftKey, ({ files: offered, quotes: added, text: words }) => {
    if (words) setText(text.trim() ? `${text.trimEnd()}\n${words}` : words);
    if (offered.length) add(offered);
    if (added.length) draft.setQuotes((all) => [...all, ...added]);
    input.current?.focus();
  });
  // Grow with the text up to its lines, then scroll; the frame is never resized by hand. Its width changing re-wraps
  // the text (or the placeholder), so it is measured again then; below the limit it never scrolls. Sized before it is
  // drawn (and before the composer's change of shape reads where things end up).
  useLayoutEffect(() => {
    const el = input.current;
    if (!el) return;
    // Measured on an unseen copy, so the text box itself is written only when its height changes: it was reset to
    // `auto` and back to measure it every frame its width changed (the composer moving between pages), and its caret
    // flickered as it moved.
    const probe = el.cloneNode() as HTMLTextAreaElement;
    probe.removeAttribute("aria-label");
    probe.setAttribute("aria-hidden", "true");
    probe.tabIndex = -1;
    probe.style.cssText = "position:absolute;visibility:hidden;pointer-events:none;height:auto;overflow-y:hidden;left:0;top:0;";
    el.after(probe);
    const fit = () => {
      const style = getComputedStyle(el);
      const limit = lines * parseFloat(style.lineHeight) + parseFloat(style.paddingTop) + parseFloat(style.paddingBottom);
      probe.style.width = `${el.clientWidth}px`;
      probe.placeholder = el.placeholder;
      probe.value = el.value;
      const height = `${Math.min(probe.scrollHeight, limit)}px`;
      const overflow = probe.scrollHeight > limit + 1 ? "auto" : "hidden";
      if (el.style.height !== height) el.style.height = height;
      if (el.style.overflowY !== overflow) el.style.overflowY = overflow;
      edges();
      over();
    };
    // Scrolling, the lines it cuts fade out at its edges (its styles) rather than stop at a hard line.
    // The mirror lies right over it, scrolled as it is.
    const over = () => {
      const m = mirror.current;
      if (!m) return;
      const host = el.offsetParent === m.offsetParent ? null : el.closest("form");
      const base = host?.getBoundingClientRect(), at = el.getBoundingClientRect();
      m.style.left = `${base ? at.left - base.left : el.offsetLeft}px`;
      m.style.top = `${base ? at.top - base.top : el.offsetTop}px`;
      m.style.width = `${el.offsetWidth}px`;
      m.style.height = `${el.offsetHeight}px`;
      m.scrollTop = el.scrollTop;
    };
    const edges = () => {
      const over = el.scrollHeight > el.clientHeight + 1;
      el.toggleAttribute("data-more-above", over && el.scrollTop > 1);
      el.toggleAttribute("data-more-below", over && el.scrollTop + el.clientHeight < el.scrollHeight - 1);
    };
    fit();
    let width = el.clientWidth;
    const resize = new ResizeObserver(() => { if (el.clientWidth !== width) { width = el.clientWidth; fit(); } });
    resize.observe(el);
    const scrolled = () => { edges(); over(); };
    el.addEventListener("scroll", scrolled);
    return () => { resize.disconnect(); el.removeEventListener("scroll", scrolled); probe.remove(); };
  }, [text]); // eslint-disable-line react-hooks/exhaustive-deps
  const menu = reference && !locked && (
    <div className={refCss.refAnchor}>
      <ChatRefMenu query={reference.query} here={sessionKey} active={active} onPick={pickReference} found={(items) => { refItems.current = items; }} />
    </div>
  );
  const field = (
    <>
      {marked && <RefMirror text={text} className={className} mirror={mirror} />}
      <textarea ref={input} className={`${className}${marked ? ` ${refCss.refTextSeeThrough}` : ""}`} rows={1} value={text} placeholder={placeholder} aria-label="消息"
        onChange={(e) => { setText(e.target.value); onType(); lookForReference(e.target); }}
        onSelect={(e) => lookForReference(e.currentTarget)}
        onBlur={() => setReference(null)}
        onPaste={(e) => { if (e.clipboardData.files.length) { e.preventDefault(); if (!locked) add(e.clipboardData.files); } }}
        onKeyDown={(e) => {
          if (reference && !e.nativeEvent.isComposing) {
            const n = refItems.current.length;
            if (e.key === "Escape") { e.preventDefault(); closedAt.current = reference.start; setReference(null); return; }
            if (n && (e.key === "ArrowDown" || e.key === "ArrowUp")) { e.preventDefault(); setActive((i) => (i + (e.key === "ArrowDown" ? 1 : n - 1)) % n); return; }
            if (n && (e.key === "Enter" || e.key === "Tab") && !e.shiftKey) { e.preventDefault(); pickReference(refItems.current[Math.min(active, n - 1)]!.ref); return; }
          }
          // A reference goes whole.
          const caret = e.currentTarget.selectionStart;
          const mark = e.key === "Backspace" && caret === e.currentTarget.selectionEnd ? markBefore(text, caret) : null;
          if (mark !== null) {
            e.preventDefault();
            caretAt.current = mark;
            setText(text.slice(0, mark) + text.slice(caret));
            return;
          }
          if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing && enterSends) { e.preventDefault(); onSubmit(); return; }
          // Nothing typed: ↑ / ↓ go to the chat above or below, as the sidebar lists them now.
          if ((e.key === "ArrowUp" || e.key === "ArrowDown") && !text && !e.nativeEvent.isComposing && !e.altKey && !e.metaKey && !e.ctrlKey && !e.shiftKey) {
            if (goToNeighbour(e.key === "ArrowUp" ? -1 : 1)) e.preventDefault();
          }
        }} />
    </>
  );
  return { menu, field };
}

/**
 * What waits to go with the message, as both screens' composers show it: the quotes, each with a line for a comment
 * (the one just added, `focusQuote`, takes the focus; Enter in it goes back to the text, `onDone`), then the files, an
 * image as its picture.
 */
export function ComposerExtras({ draft, focusQuote, onFocused, onDone }: { draft: Draft; focusQuote: string | null; onFocused(): void; onDone(): void }) {
  const { quotes, setQuotes, files } = draft;
  const rest = besideQuotes(quotes, files) ?? [];
  const quoteInputs = useRef(new Map<string, HTMLInputElement>());
  useEffect(() => {
    if (!focusQuote) return;
    quoteInputs.current.get(focusQuote)?.focus();
    onFocused();
  }, [focusQuote]); // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <>
      {quotes.length > 0 && (
        <div className={css.composerQuotes}>
          {quotes.map((q) => {
            const own = fileOf(q, files);
            return (
            <div key={q.id} className={css.composerQuote} onClick={(e) => e.stopPropagation()}>
              <QuoteCard quote={q} picture={own && <PendingFile file={own} />}
                onRemove={() => { setQuotes((all) => all.filter((x) => x.id !== q.id)); if (own) draft.remove(own.id); }} comment={
                <input ref={(el) => { if (el) quoteInputs.current.set(q.id, el); else quoteInputs.current.delete(q.id); }}
                  className={`${css.quoteCardComment} ${css.quoteCardInput}`} value={q.comment} placeholder="对这段说点什么（可以不写）" aria-label={`对 ${q.author} 这段的批注`}
                  onChange={(e) => { const v = e.target.value; setQuotes((all) => all.map((x) => (x.id === q.id ? { ...x, comment: v } : x))); }}
                  onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing) { e.preventDefault(); onDone(); } }} />
              } />
            </div>
            );
          })}
        </div>
      )}
      {rest.length > 0 && (
        <div className={css.composerFiles}>
          {rest.map((f) => <PendingFile key={f.id} file={f} onRemove={() => draft.remove(f.id)} />)}
        </div>
      )}
    </>
  );
}

/** A file waiting to go with the message: an image as its picture, anything else a card. */
function PendingFile({ file: f, onRemove }: { file: Pending; onRemove?: () => void }) {
  return f.preview ? (
    <Tip label={f.error ?? f.name}><span className={css.composerThumb} data-error={f.error ? true : undefined}>
      <img src={f.preview} alt={f.name} />
      {!f.done && !f.error && <span className={css.composerThumbBusy}><span className={waitingCss.spinner} aria-hidden="true" /></span>}
      {onRemove && <button type="button" className={css.composerThumbRemove} aria-label={`移除 ${f.name}`} onClick={(e) => { e.stopPropagation(); onRemove(); }}><Close size={12} /></button>}
    </span></Tip>
  ) : <FileCard file={f.done ?? f} pending={!f.done && !f.error} error={f.error} {...(onRemove ? { onRemove } : {})} />;
}

/** An agent in this chat that is at work: who it is, and what it does now. */
export interface AgentAtWork {
  key: string; who: string; runtime: RuntimeKind; maker: Maker | undefined;
  /** What it is doing, as the core says (null until its live view has come). */
  activity: ActivityView | null; since: number | undefined;
  /** While it waits on work it started (a station yet to update never says so): since when, at most how many seconds. */
  wait?: AgentWait | undefined;
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
 * nothing blinks. Until its turn a message waits folded to nothing. With reduced motion messages just appear, and so
 * do those no one watches come out: arriving while the page is hidden or the reader has scrolled up (scroll.ts), and
 * all still waiting when the page is hidden or the reader scrolls up (the browser barely runs timers for a hidden
 * page, so a queue would otherwise still be playing out long after).
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
  const [, rerender] = useState(0);
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

  // Everything waiting or coming out shows at once, where it is.
  const release = () => {
    if (!current && !queue.current.length) return;
    for (const q of queue.current) done.current.add(q.seq);
    if (current) done.current.add(current.seq);
    queue.current = [];
    flying.current?.remove();
    flying.current = null;
    setCurrent(null);
    rerender((n) => n + 1);
  };
  const watched = () => document.visibilityState === "visible" && !list.current?.hasAttribute("data-reading-up");
  useLayoutEffect(() => {
    if (!watched()) release();
    else if (!current && queue.current.length) nextAfter(null);
  });
  useEffect(() => {
    const pane = list.current;
    const change = () => { if (!watched()) release(); };
    document.addEventListener("visibilitychange", change);
    pane?.addEventListener("scroll", change, { passive: true });
    return () => {
      document.removeEventListener("visibilitychange", change);
      pane?.removeEventListener("scroll", change);
    };
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
        const emits = !reduced && watched() && m.seq > since && agent !== undefined && showing.has(agent);
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
function Activity({ agent, leaving, pose, onOpen }: { agent: AgentAtWork; leaving: boolean; pose: { folded: boolean; away: boolean }; onOpen(): void }) {
  const wait = agent.wait;
  const now = useSteady(wait ? { key: "wait", text: "等待中" } : agent.activity?.now ?? { key: "busy", text: "处理中" });
  return (
    <div className={`${conversationCss.msg} ${css.agentActivity}`} data-transient="" data-agent={agent.key} data-leaving={leaving || undefined} data-folded={pose.folded || undefined} data-away={pose.away || undefined} data-waiting={wait ? "" : undefined}>
      <Tip label="打开执行历史"><button type="button" className={css.activityLine} onClick={onOpen} aria-label={`${agent.who}：${now.current.text}`}>
        <span className={css.activityAvatar} aria-hidden="true"><span className={`${chatCss2.msgAvatar} ${css.msgAvatarAgent}`}><ModelLogo maker={agent.maker} runtime={agent.runtime} size={12} /></span></span>
        <span className={css.activityTail}>
          <span className={css.activityNow}>
            {now.previous && <span key={`was-${now.n - 1}`} className={css.activityNowText} data-out="">{now.previous.text}</span>}
            <span key={now.n} className={css.activityNowText} data-in={now.switched || undefined}>{now.current.text}</span>
          </span>
          {wait
            ? <span className={css.activityElapsed}><Waited since={wait.since} seconds={wait.seconds} /></span>
            : agent.since ? <span className={css.activityElapsed}><Elapsed since={agent.since} /></span> : null}
        </span>
      </button></Tip>
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

/** Seconds (then minutes) since a moment, ticking; at most `most` seconds. */
export function Elapsed({ since, most }: { since: number; most?: number }) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, []);
  const s = Math.max(0, Math.floor((now - since) / 1000));
  return <>{span(most === undefined ? s : Math.min(s, most))}</>;
}

/** How long a wait has gone on, ticking, at most its limit, with the limit: 1m 20s / 10m. */
export function Waited({ since, seconds }: { since: number; seconds?: number | undefined }) {
  return <><Elapsed since={since} {...(seconds ? { most: seconds } : {})} />{seconds ? ` / ${span(seconds)}` : ""}</>;
}

/** Seconds in short: 45s, 3m 20s, 1h 5m. */
function span(s: number): string {
  if (s < 60) return `${s}s`;
  if (s < 3600) return s % 60 ? `${Math.floor(s / 60)}m ${s % 60}s` : `${s / 60}m`;
  const m = Math.floor((s % 3600) / 60);
  return m ? `${Math.floor(s / 3600)}h ${m}m` : `${s / 3600}h`;
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
export function goToNeighbour(step: -1 | 1): boolean {
  // The list in view: the other one (全部 or 我参与的) sits beside it out of view, and a row of it is not a neighbour.
  const rows = [...document.querySelectorAll<HTMLAnchorElement>(`.${nav.sidebar} .${nav.navScroll}:not([inert]) a.${nav.navSession}`)];
  const at = rows.findIndex((row) => row.getAttribute("aria-current") === "page");
  const next = at < 0 ? null : rows[at + step];
  if (!next) return false;
  next.click();
  next.scrollIntoView({ block: "nearest" });
  return true;
}
