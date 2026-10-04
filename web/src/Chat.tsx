// still.fail's own chat with a session, after Zork's: your messages sit right in a
// bubble with only their time; everyone else (people and the agent) gets an
// avatar, a name and the time over their words. Passages of earlier messages
// can be quoted with a comment, and files ride along as cards (images shown).
import { sentImage, sentImageKey } from "./sentImages.ts";
import { ArchiveNotice } from "./ArchiveNotice.tsx";
import { ArrowDown, ArrowUp, Bot, Brain, Chats, Close, Command, Edit, Info, Plus, Quote as QuoteIcon, Read, Received, Retry, Said, Search, Send, Sparks, Think, Trash, Web } from "./icons.tsx";
import { Fragment, memo, useCallback, useContext, useEffect, useLayoutEffect, useMemo, useRef, useState, type CSSProperties, type MutableRefObject, type ReactNode, type RefObject } from "react";
import { Link, useHref, useSearchParams } from "react-router";
import { useApi, useChatSend, type ChatTo, type Outgoing, type Activity as ActivityView, type AgentWait, type Attachment, type ChatItem, type ChatMessage, type ChatView, type Live, type Maker, type Quote, type RuntimeKind, type Session, type Stamp, type Status } from "./api.ts";
import { Mark } from "./brand.tsx";
import { stationBase, usePerson, useStation } from "./station.tsx";
import { Avatar, ModelLogo, Time, Tip, transitionTo } from "./ui.tsx";
import { ComposerSlot, useComposerHeight } from "./dock.tsx";
import { placeFiles, Prose } from "./Prose.tsx";
import { shortcutOf, takesKeys, useKeymap, usePageKeysAvailable, useShortcut } from "./keymap.ts";
import { chatImages, FileLink, FilePreview, fileSize, Gallery, isImage, kindOf, useFileShown, useNear } from "./FilePreview.tsx";
import { thumbhashRatio, thumbhashUrl } from "./thumbhash.ts";
import { OpenFile, VizFile } from "./Viz.tsx";
import { useStickToBottom } from "./scroll.ts";
import { animate, arrive, EASE_OUT, follower, moveState, type AnimationPlaybackControls, type Follower } from "./motion.ts";
import { motionValue, type MotionValue } from "motion";
import { flushSync } from "react-dom";
import { DraftKey, useDraft, useDraftInbox, type Draft, type DraftQuote, type Pending } from "./draft.ts";
import * as nav from "./Sidebar.css.ts";
import * as sessionCss from "./styles/session.css.ts";
import * as chatCss2 from "./styles/chat.css.ts";
import * as conversationCss from "./styles/conversation.css.ts";
import type { ArchiveCheck } from "./core/shapes.ts";
import * as css from "./Chat.css.ts";
import * as refCss from "./ChatRef.css.ts";
import { core } from "./core/react.ts";
import { ChatRefMenu, markBefore, refAt, RefMirror, WithRefs } from "./ChatRef.tsx";
import { useMorph } from "./morph.ts";
import * as waitingCss from "./styles/waiting.css.ts";
import * as cloudCss from "./styles/cloud.css.ts";
import * as composerCss from "./styles/composer.css.ts";
import * as controlsCss from "./styles/controls.css.ts";
import * as dockCss from "./dock.css.ts";
import { sendingHere, toMadeChat as toMadeChatOf } from "./madeChat.ts";
import { thumbId } from "./viewerFlight.ts";
import { DoingShown, useDoingState } from "./DoingMark.tsx";
import { failure, useToast, useAct } from "./toast.tsx";
import { MessageDecision } from "./Decisions.tsx";
import * as decisionsCss from "./Decisions.css.ts";
import { useDoing } from "./doing.ts";
import { jumped, useJump } from "./jumpTo.ts";
import { t } from "./i18n.ts";

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
export function ChatPanel({ chat, draftKey, lives, onOpenHistory, ensureChat, onSent, made, onArchive }: {
  /** Whose draft the composer shows here. */
  chat: ChatView; draftKey: string; lives: ReadonlyMap<string, Live>; onOpenHistory(key: string, entry?: number): void;
  ensureChat?: () => Promise<{ key: string; thread: ChatTo }>; onSent?: (to: ChatTo) => void;
  /** What is sent to until its thread is known: the core's key of a chat made here (`chat.create`), or the agent's
   *  whose page it is (the core has the station make its chat behind what is sent). */
  made?: string;
  /** Archives the chat, as its bar's 归档 does: offered under the agent's last post once it is all done (ChatRows). */
  onArchive?: (() => void) | undefined;
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
  const latest = useRef({ ownerOf, onOpenHistory, images, onArchive });
  latest.current = { ownerOf, onOpenHistory, images, onArchive };
  const [stable] = useState(() => ({ owner: (file: Attachment) => latest.current.ownerOf(file), open: (key: string) => latest.current.onOpenHistory(key), images: () => latest.current.images(),
    archive: () => latest.current.onArchive?.() }));
  useShortcut("chat.latest", rows.toEnd);
  const askedFile = useAskedFile(list, rows.messages, ownerOf);
  // Selecting text inside one message offers to quote it.
  const quoting = useSelectionQuote(list, (q) => {
    const quote = { ...q, comment: "", id: `${Date.now()}` };
    setQuotes((all) => [...all, quote]);
    setFocusQuote(quote.id);
  });

  return (
    // The list runs on under the composer, frosted over it (its styles): its foot leaves the composer's height free.
    <section className={sessionCss.chat} aria-label={t("web-main.chat.label")} data-under-composer="" data-avoid-previews="" style={{ "--composer-height": `${composerHeight}px` } as CSSProperties}>
      <div className={sessionCss.chatPane}>
      {rows.away && <ToLatest station={station.address} thread={id} waiting={rows.waiting} onClick={rows.toEnd} />}
      <Gallery.Provider value={stable.images}>
      <div className={`${sessionCss.chatList} ${css.chatMessages}`} ref={list} {...quoting.listProps}
        onClick={(e) => {
          const to = historyLinkClicked(e);
          // At the entry it names (else its start); opened, not toggled.
          if (to) { e.preventDefault(); onOpenHistory(to.key, to.entry); }
        }}>
        <DraftKey.Provider value={draftKey}>
          <ChatRows chat={chat} rows={rows} to={to} owners={ownersOf(chat)} owner={stable.owner} onOpenHistory={stable.open} onArchive={onArchive ? stable.archive : undefined} />
        </DraftKey.Provider>
        <div ref={floor} className={chatCss2.chatFloor} aria-hidden="true" />
      </div>
      </Gallery.Provider>
      </div>
      {quoting.pop}
      {askedFile}
      {chat.archived && <ArchiveNotice className={css.offlineNotice} offline={chat.offline} restore={() => api.archive({ thread: id, session: keeper ?? "" }, false)} />}
      {chat.offline && <p className={css.offlineNotice} role="status">{station.name ? t("web-main.chat.offline.named", { name: station.name }) : t("web-main.chat.offline")}</p>}
      {/* The one composer of the chat pages sits here (dock.tsx), kept as the page changes. */}
      <ComposerSlot variant="chat" station={station} draftKey={draftKey} thread={to} sessionKey={keeper} quotes={quotes} setQuotes={setQuotes} focusQuote={focusQuote} onFocused={quoteFocused}
        locked={chat.offline || !!chat.archived} placeholder={chat.archived ? t("web-main.chat.archivedPlaceholder") : t("web-main.composer.placeholder")} {...(ensureChat ? { ensureChat } : {})} {...(onSent ? { onSent } : {})} />
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
export function ChatRows({ chat, rows, to, owners, owner, onOpenHistory, onArchive }: {
  chat: ChatView; rows: ReturnType<typeof useMessageList>; to: ChatTo | null; owners: string;
  owner: (file: Attachment) => string | null; onOpenHistory: (key: string) => void;
  /** Archives the chat (its page's 归档). */
  onArchive?: (() => void) | undefined;
}) {
  const { messages, divider, shown, rowOf, caughtAgent, poseOf } = rows;
  const here = (key: string | undefined) => key !== undefined && chat.agents.some((a) => a.session.key === key);
  // Where a decision's options answer: none while nothing can be sent.
  const thread = chat.offline || chat.archived ? null : chat.thread?.id ?? null;
  // Nothing left in it (the core's `archivable`) and its agent's last post said it is all done: 归档 right under that
  // post, as a decision's options are (only at the chat's end, not in an older window).
  const last = chat.newer ? undefined : messages.findLast((m) => m.authorKind === "agent" && !m.system);
  const archiveAt = onArchive && chat.archivable && !chat.offline && last?.ending === "all_done" ? last.seq : null;
  // What the archive check made of it, under the same post (in words: the option it picked and what came of it).
  const checkAt = chat.archiveCheck && last?.ending === "all_done" ? last.seq : null;
  return (
    <>
      {chat.more && <div className={css.chatOlder} aria-hidden="true"><span className={waitingCss.spinner} /></div>}
      {messages.length === 0 && chat.outbox.length === 0 && (
        <div className={css.chatEmpty}>
          <p>{t("web-main.chat.empty")}</p>
        </div>
      )}
      {messages.map((m) => {
        const line = m.seq === divider ? <div className={css.chatUnreadLine} data-unread-line role="separator"><span>{t("web-main.chat.unreadLine")}</span></div> : null;
        const { enter, emitted, caught } = rowOf(m);
        // Keyed as a whole: a bare [line, row] pair is placed by its index, and an older page coming in above would
        // shift every index and draw every message anew.
        return (
          <Fragment key={m.seq}>
            {line}
            <MessageRow message={m} focus={chat.focusLast === true && m.seq === messages.at(-1)?.seq} enter={enter} emitted={emitted} caught={caught} thread={thread}
              agentHere={here(m.by.agent)} owners={owners} owner={owner} onOpenHistory={onOpenHistory}
              {...(archiveAt === m.seq ? { archive: onArchive } : {})} {...(checkAt === m.seq ? { check: chat.archiveCheck } : {})} />
          </Fragment>
        );
      })}
      {/* The page after the window shown, while it is short of the chat's end (`chat.newer`), loading as the reader nears it. */}
      {chat.newer && <div className={css.chatNewer} aria-hidden="true"><span className={waitingCss.spinner} /></div>}
      {chat.outbox.map((o) => <OutboxRow key={o.id} o={o} to={to} locked={chat.offline || !!chat.archived} owner={owner} />)}
      {/* A reply comes whole, as a message: while an agent works, its activity (always the last thing in the chat) says what it does. */}
      {shown.map(({ agent, leaving }) => (
        <Activity key={agent.key} agent={agent} leaving={leaving} caught={caughtAgent(agent.key)} pose={poseOf(agent.key)} onOpen={() => onOpenHistory(agent.key)} />
      ))}
    </>
  );
}

/**
 * Over the list away from its end: glides down, and follows new messages again (scroll.ts); from a window short of the
 * end, goes there at once, turning while the latest page comes (`chat.latest`), not pressed again meanwhile.
 */
function ToLatest({ station, thread, waiting, onClick }: { station: string; thread: number | null; waiting: number; onClick(): void }) {
  // Failed: a red mark in the arrow's place a few seconds, the tip saying why.
  const asked = useDoingState("chat.latest", { station, thread: thread ?? "" });
  const state = thread === null ? { running: false } : asked;
  const coming = state.running;
  return (
    <Tip label={state.error ?? t("web-main.chat.toLatest")} shortcut="chat.latest" side="top">
      <button type="button" className={css.chatToBottom} aria-label={t("web-main.chat.toLatest")} data-count={waiting > 0 || undefined}
        disabled={coming} aria-busy={coming || undefined} onClick={onClick}>
        <DoingShown state={state} className={controlsCss.iconSpinner} size={16} idle={<ArrowDown size={16} strokeWidth={2} />} bare />
        {waiting > 0 && <span>{t("web-main.chat.newMessages", { n: waiting })}</span>}
      </button>
    </Tip>
  );
}

const SENDING_SHOWS_MS = 800;

/** A message sent from here that the chat does not show yet: on its way, or failed with a way to send it again or drop it. */
function OutboxRow({ o, to, locked, owner }: { o: Outgoing; to: ChatTo | null; locked: boolean; owner: (file: Attachment) => string | null }) {
  const sending = useChatSend();
  const station = useStation().address;
  const toast = useToast();
  // Each turns in its icon's place while it goes; failed, a red mark there a few seconds, why on hover.
  const retry = useDoingState("chat.retry", { station, id: o.id });
  const drop = useDoingState("chat.discard", { station, id: o.id });
  const retrying = retry.running;
  const dropping = drop.running;
  const busy = retrying || dropping;
  // "正在发送" shows once it has been on its way a while, counted from when it was sent: the row is drawn anew as a chat
  // made here takes the page, and copies of it fly in (madeChat.ts, by `data-shows-at`), all showing it at one time.
  const showsAt = o.createdAt + SENDING_SHOWS_MS;
  const [delay] = useState(() => `${Math.max(0, showsAt - Date.now())}ms`);
  return (
    <MineMessage data-author={t("web-main.chat.you")} data-role="person" data-enter data-unsent={o.state === "failed" || undefined}>
      <MineWords message={o} owner={owner} />
      {o.state === "failed"
        // Not sent: said briefly, why in its tip; sending it again or dropping it right beside.
        ? <div className={css.msgUnsent}>
            <Tip label={o.error ? t("web-main.draft.notSent", { error: o.error }) : t("web-main.chat.notSent")}>
              <span className={css.msgUnsentNote}><Info size={12} strokeWidth={2} />{t("web-main.chat.unsent")}</span>
            </Tip>
            <button type="button" className={css.msgUnsentBtn} disabled={locked || busy} aria-busy={retrying || undefined}
              onClick={() => { if (to !== null) sending.retry(to, o.id).catch((e: unknown) => toast(t("web-main.chat.resendFailed", { error: failure(e) }))); }}>
              <DoingShown state={retry} className={css.msgUnsentSpinner} idle={<Retry size={12} strokeWidth={2} />} />{t("common.retry")}</button>
            <button type="button" className={css.msgUnsentBtn} disabled={busy} aria-busy={dropping || undefined}
              onClick={() => { if (to !== null) sending.discard(to, o.id).catch((e: unknown) => toast(t("web-main.chat.deleteFailed", { error: failure(e) }))); }}>
              <DoingShown state={drop} className={css.msgUnsentSpinner} idle={<Trash size={12} strokeWidth={2} />} />{t("common.delete")}</button>
          </div>
        : <span className={`${conversationCss.msgTime} ${chatCss2.msgWaiting} ${chatCss2.msgSending}`} data-shows-at={showsAt} style={{ animationDelay: delay }}><span className={waitingCss.spinner} aria-hidden="true" />{t("web-main.chat.sending")}</span>}
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
        <QuoteIcon size={12} strokeWidth={2.2} />{t("web-main.chat.quote")}
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

/**
 * How a message of the list comes in: easing in (`enter`), or held in its agent's activity and sent out of it
 * (`emitted`); or not at all, there when the chat opened or caught up on since (`caught`: the list goes to it at once).
 */
export interface RowState { enter: true | undefined; emitted: "held" | "emitting" | null; caught: true | undefined }

/**
 * A chat's list as both screens run it (this page, and the phone's, mobile/Chat.tsx): it follows its bottom, loads
 * older pages near its top and newer ones near its bottom (the core holds a window of the chat, `chat.newer` while it
 * is short of the end), records what is read, keeps the reader's place (`place`: whose it is), draws the unread
 * line, and shows its agents at work, their replies coming out of their activity. Answers what the list shows: its
 * messages, where the unread line goes, whether to offer the way to the end (`away`, with what waits there:
 * `waiting`; `toEnd` takes it), the agents at work, and how each message comes in.
 */
export function useMessageList(list: RefObject<HTMLDivElement | null>, floor: RefObject<HTMLDivElement | null>, chat: ChatView, place: string, lives: ReadonlyMap<string, Live>) {
  const sending = useChatSend();
  const station = useStation().address;
  const id = chat.thread?.id ?? null;
  const messages = chat.messages;
  // The window shown is short of the chat's end: its bottom is not the end, and what is said waits beyond it.
  const short = !!chat.newer;
  // Whose a message is, the core says.
  const mineOf = (m: ChatMessage) => m.mine;
  useStickToBottom(list, `.${conversationCss.msg}`, floor, short);
  useWindowMoves(list, messages);
  useHistoryFade(list, messages);
  useAtScrollEnd(list, messages, place);
  // Where the reader leaves it, the core keeps too, on the device (it opens there next, while nothing is unread, also
  // after a reload): the message at the top of the pane and where its top is, or none at its end. A core from before
  // `chat.place` does not know it.
  const seqOf = useRef(new Map<string, number>());
  seqOf.current = new Map(messages.map((m) => [m.ts, m.seq]));
  const leave = (ts: string | null, offset: number | null) => {
    const seq = ts === null ? null : seqOf.current.get(ts);
    if (id !== null && seq !== undefined) void sending.place(id, seq, seq === null ? null : offset).catch(() => undefined);
  };
  // Taken to where it was left or to the unread line before anything loads by where the pane is.
  // With nothing unread, the core may open it short of its end where it was left (`at`): that message goes at the top,
  // or where its top was (`atOffset`) when it is the very entry left there.
  const opened = chat.unreadLine == null && chat.at != null ? messages.find((m) => m.seq >= chat.at!) ?? null : null;
  const at = opened ? { ts: opened.ts, offset: opened.seq === chat.at ? chat.atOffset ?? null : null } : null;
  useRememberPlace(list, place, messages.length > 0, short, leave, at);
  const divider = useUnreadLine(list, chat);
  // Without a chat there is nothing older (or newer) to load.
  const older = () => (id === null ? Promise.resolve() : sending.older(id));
  useOlderOnScroll(list, chat.more, chat.messages[0]?.seq, older);
  useJumpTo(list, station, id, messages, chat.more, older);
  const newer = () => (id === null ? Promise.resolve() : sending.newer(id));
  useNewerOnScroll(list, short, chat.messages.at(-1)?.seq, newer);
  useShowing(floor, station, chat, (seq) => (id === null ? Promise.resolve() : sending.read(id, seq)));
  const away = useAwayFromBottom(list);
  const toEnd = useToEnd(list, chat, () => (id === null ? Promise.resolve() : sending.latest(id)));
  // A message sent from here eases in once, from the outbox; its own copy that replaces it does not again.
  const sentHere = useRef(new Set<string>());
  for (const o of chat.outbox) sentHere.current.add(o.text);
  // Only what is said while the chat shows comes in, and an activity only for an agent seen starting meanwhile: the
  // core decides both (attend.ts: `said`, `started`); the rest is there at once.
  const said = new Set(messages.filter((m) => m.said).map((m) => m.seq));
  const saidHere = (seq: number) => said.has(seq);
  // Only an agent that has taken a message and runs is at work: until then the message itself says it waits.
  const atWork: AgentAtWork[] = chat.agents.filter((a) => a.status === "running").map(({ session, since, wait }) => (
    { key: session.key, who: session.agentText, runtime: session.runtime, maker: session.maker, activity: lives.get(session.key)?.activity ?? null, since, wait }
  ));
  const started = new Set(chat.agents.filter((a) => a.started).map((a) => a.session.key));
  const emissions = useEmissions(list);
  useActivityGlide(list);
  const shown = useLinger(atWork, emissions.keeps);
  emissions.take(messages, saidHere, new Set(shown.map((s) => s.agent.key)));
  const rowOf = (m: ChatMessage): RowState => {
    const mine = mineOf(m);
    const told = !mine && !m.system;
    const enter = saidHere(m.seq) && !(mine && sentHere.current.has(m.text)) && !(told && emissions.emits(m.seq)) ? true : undefined;
    return { enter, emitted: told ? emissions.stateOf(m.seq) : null, caught: saidHere(m.seq) ? undefined : true };
  };
  const caughtAgent = (key: string) => (started.has(key) ? undefined : true);
  // Short of the end, the way there shows wherever the reader is, with how many wait there.
  const waiting = short ? chat.thread?.unread ?? 0 : 0;
  return { messages, divider, away: away || short, waiting, toEnd, shown, rowOf, caughtAgent, poseOf: emissions.poseOf };
}

/**
 * The way to a chat's end, from the button over the list or its shortcut: down the list, gliding, as always; from a
 * window short of the end (`chat.newer`), its latest page in its place first (`latest`), then straight to its bottom,
 * with nothing gliding or coming in. A message sent from such a window takes the reader there the same way (the core
 * puts the latest page in place as it sends); sent from up the list, straight to its bottom.
 */
function useToEnd(list: RefObject<HTMLElement | null>, chat: ChatView, latest: () => Promise<unknown>): () => void {
  const toast = useToast();
  const short = !!chat.newer;
  // Going to the end: once the latest page is in, the list goes to its bottom.
  const going = useRef(false);
  const isShort = useRef(short);
  isShort.current = short;
  useLayoutEffect(() => {
    if (short || !going.current) return;
    going.current = false;
    list.current?.dispatchEvent(new CustomEvent("to-bottom", { detail: "at-once" }));
  });
  // A message sent (the composer says so as it sends, `sent`, rather than the outbox growing: on a quick link the
  // station has it before the outbox ever shows it): from up the list, to its bottom at once, following again.
  useEffect(() => {
    const el = list.current;
    if (!el) return;
    const sent = () => {
      if (isShort.current) going.current = true;
      else if (el.hasAttribute("data-reading-up")) el.dispatchEvent(new CustomEvent("to-bottom", { detail: "at-once" }));
    };
    el.addEventListener("sent", sent);
    return () => el.removeEventListener("sent", sent);
  }, [list]);
  return () => {
    if (!short) {
      list.current?.dispatchEvent(new Event("to-bottom"));
      return;
    }
    going.current = true;
    latest().catch((e: unknown) => { going.current = false; toast(t("web-main.chat.toLatestFailed", { error: failure(e) })); });
  };
}

/** New historical rows share one short opacity fade; existing rows never replay when their status changes. */
function useHistoryFade(list: RefObject<HTMLElement | null>, messages: ChatMessage[]): void {
  const seen = useRef(new WeakSet<HTMLElement>());
  useLayoutEffect(() => {
    for (const row of list.current?.querySelectorAll<HTMLElement>(":scope > [data-ts]") ?? []) {
      if (seen.current.has(row)) continue;
      seen.current.add(row);
      if (row.hasAttribute("data-caught") && document.visibilityState === "visible") row.dataset.historyFade = "";
    }
  }, [list, messages]);
}

/**
 * Tells the list (scroll.ts) when messages leave its ends as the core's window moves along the chat (a page in at one
 * end, as many out at the other): it lets go of the room it held at its foot. Told as the change is laid out, before
 * the list puts the reader's message back in place.
 */
function useWindowMoves(list: RefObject<HTMLElement | null>, messages: ChatMessage[]): void {
  const first = messages[0]?.seq;
  const last = messages.at(-1)?.seq;
  const was = useRef({ first, last });
  useLayoutEffect(() => {
    const before = was.current;
    was.current = { first, last };
    const moved = (before.first !== undefined && first !== undefined && first > before.first)
      || (before.last !== undefined && last !== undefined && last < before.last);
    if (moved) list.current?.dispatchEvent(new Event("trimmed"));
  }, [list, first, last]);
}

/**
 * A message asked to be shown (jumpTo.ts: a row's state line pressed): once it is in the list, scrolled to the middle
 * and flashed, after the list has been put where it opens (the unread line, where it was left). Older than the window:
 * older pages load until it is in; not there at all, nothing.
 */
function useJumpTo(list: RefObject<HTMLDivElement | null>, station: string, thread: number | null, messages: ChatMessage[], more: boolean | undefined, older: () => Promise<unknown>) {
  const seq = useJump(station, thread);
  const loading = useRef(false);
  useEffect(() => {
    if (seq === null || !messages.length || loading.current) return;
    const message = messages.find((m) => m.seq === seq);
    if (!message) {
      if (more && seq < messages[0]!.seq) {
        loading.current = true;
        void older().catch(() => jumped()).finally(() => { loading.current = false; });
      } else jumped();
      return;
    }
    // A frame later: after the list has been put where it opens.
    const frame = requestAnimationFrame(() => {
      jumped();
      const pane = list.current;
      const target = pane?.querySelector<HTMLElement>(`.${conversationCss.msg}[data-ts="${CSS.escape(message.ts)}"]`);
      if (!pane || !target) return;
      // A reader's move: the pane keeps it rather than holding its bottom.
      pane.dispatchEvent(new WheelEvent("wheel"));
      target.scrollIntoView({ block: "center" });
      target.classList.remove(css.msgFlash);
      void target.offsetWidth;
      target.classList.add(css.msgFlash);
    });
    return () => cancelAnimationFrame(frame);
  }, [seq, messages, more]); // eslint-disable-line react-hooks/exhaustive-deps
}

/** The core hands the chat over anew as it changes: a message is the same one if all it holds is (its times in words too). */
export function sameMessage(a: ChatMessage, b: ChatMessage): boolean {
  return a === b || JSON.stringify(a) === JSON.stringify(b);
}

/**
 * The jump to the unread line (the core says where it goes: over the first message the viewer had not read when the
 * chat was opened, not their own; it stays put for the visit, and the core loads older pages first when it lies above
 * them). Nothing unread: no line, and the chat opens at its bottom or where it was left; something unread takes it to
 * the line even so. Answers the seq of the message the line goes over.
 */
export function useUnreadLine(ref: RefObject<HTMLElement | null>, chat: ChatView): number | null {
  const target = chat.unreadLine ?? null;
  // Until something unread shows (it may come from the station a moment after opening), there is nothing to jump to.
  // Coming back to a chat with something unread goes to the line too, over where it was left (useRememberPlace).
  const jumped = useRef(false);
  useEffect(() => {
    if (jumped.current || target === null) return;
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
  }, [ref, target]);
  return target;
}

/** Exact scroll end, separate from the 120px threshold for the jump button and the following animation. */
function useAtScrollEnd(ref: RefObject<HTMLElement | null>, messages: ChatMessage[], place: string): void {
  // Opening/restoring the pane is already in its final appearance. Only the reader's scrolling enables fades.
  useEffect(() => {
    const pane = ref.current;
    if (!pane) return;
    const enable = () => pane.setAttribute("data-focus-motion", "");
    const key = (event: KeyboardEvent) => {
      if (!takesKeys(event.target instanceof Element ? event.target : null) && ["ArrowUp", "ArrowDown", "PageUp", "PageDown", "Home", "End", " "].includes(event.key)) enable();
    };
    pane.addEventListener("wheel", enable, { passive: true });
    pane.addEventListener("touchmove", enable, { passive: true });
    pane.addEventListener("pointerdown", enable, { passive: true });
    pane.addEventListener("keydown", key);
    return () => {
      pane.removeEventListener("wheel", enable);
      pane.removeEventListener("touchmove", enable);
      pane.removeEventListener("pointerdown", enable);
      pane.removeEventListener("keydown", key);
      pane.removeAttribute("data-focus-motion");
    };
  }, [ref, place]);
  useLayoutEffect(() => {
    const pane = ref.current;
    if (!pane) return;
    const check = () => pane.toggleAttribute("data-at-end", pane.scrollHeight - pane.scrollTop - pane.clientHeight <= 2);
    check();
    pane.addEventListener("scroll", check, { passive: true });
    const resize = new ResizeObserver(check);
    resize.observe(pane);
    for (const child of pane.children) resize.observe(child);
    return () => { pane.removeEventListener("scroll", check); resize.disconnect(); pane.removeAttribute("data-at-end"); };
  }, [ref, messages]);
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

/**
 * Where each chat was left: the message at the top of its pane, and how far below the pane's top it sat; and, if it
 * was left at its end (the bottom of a pane not short of it), the last message then (`bottom`).
 */
const leftAt = new Map<string, { ts: string; offset: number; bottom: string | null }>();

/**
 * Remembers where the reader was in a chat and takes them back there when
 * they return, instead of opening it from the bottom again. The place is kept
 * as the message at the top and its offset, so what arrived meanwhile below
 * does not move it. The unread line, when there is one, goes over it (useUnreadLine).
 * With no place of its own here, a chat the core opened short of its end
 * (`opensAt`: the message at the entry it opened at, where it was left) shows
 * that message at the top (or where its top was: `offset`). `short`: the pane
 * shows a window short of the chat's end, so its bottom is not the end.
 * `onLeave` is told where the reader is, as the pane is: the message at its
 * top (its `ts`) and its top's offset, or none at the end (the core opens the
 * chat there next, `chat.place`, and keeps it on the device). Told as the page
 * goes, and as the reader comes to rest too: a page that is reloaded or closed
 * is not left that way.
 */
export function useRememberPlace(ref: RefObject<HTMLElement | null>, key: string, ready: boolean, short = false, onLeave?: (ts: string | null, offset: number | null) => void, opensAt: { ts: string; offset: number | null } | null = null): void {
  const [saved] = useState(() => leftAt.get(key));
  const restored = useRef(false);
  const latest = useRef({ short, onLeave });
  latest.current = { short, onLeave };
  /** Where the reader is: the message at the pane's top and its offset, and the last message if at the end. */
  const where = useCallback((pane: HTMLElement) => {
    const top = pane.getBoundingClientRect().top;
    const first = [...pane.querySelectorAll<HTMLElement>(`.${conversationCss.msg}[data-ts]`)].find((m) => m.getBoundingClientRect().bottom > top);
    const end = !latest.current.short && pane.scrollHeight - pane.scrollTop - pane.clientHeight <= 2;
    return first ? { ts: first.dataset.ts!, offset: first.getBoundingClientRect().top - top, bottom: end ? lastTs(pane) : null } : null;
  }, []);
  /** What was last told (`onLeave`), so the same is not told again. */
  const told = useRef<string | null>(null);
  const tell = useCallback((at: { ts: string; offset: number; bottom: string | null }) => {
    const ts = at.bottom !== null ? null : at.ts;
    const offset = ts === null ? null : Math.round(at.offset * 10) / 10;
    const said = JSON.stringify([ts, offset]);
    if (said === told.current) return;
    told.current = said;
    latest.current.onLeave?.(ts, offset);
  }, []);
  useEffect(() => {
    const pane = ref.current;
    if (!pane) return;
    // Told once the pane comes to rest, after it has been put where it was left (before that, it is not the reader's).
    let rest: ReturnType<typeof setTimeout> | undefined;
    const record = () => {
      const at = where(pane);
      if (at) leftAt.set(key, at);
      clearTimeout(rest);
      rest = setTimeout(() => {
        const now = restored.current && pane.isConnected ? where(pane) : null;
        if (now) tell(now);
      }, REST_MS);
    };
    pane.addEventListener("scroll", record, { passive: true });
    return () => {
      clearTimeout(rest);
      pane.removeEventListener("scroll", record);
    };
  }, [ref, key, where, tell]);
  // Told as the page goes, while the pane is still laid out (a layout effect's cleanup runs before it is taken away).
  useLayoutEffect(() => {
    const pane = ref.current;
    if (!pane) return;
    return () => {
      if (!pane.isConnected) return;
      const at = where(pane);
      if (at) leftAt.set(key, at);
      if (at) tell(at);
      else if (!latest.current.short) latest.current.onLeave?.(null, null);
    };
  }, [ref, key, where, tell]);
  const opensTs = opensAt?.ts ?? null;
  const opensOffset = opensAt?.offset ?? null;
  useEffect(() => {
    if (!ready || restored.current) return;
    restored.current = true;
    const pane = ref.current;
    if (!pane) return;
    if (!saved) {
      // Opened where it was left (the core keeps it: the page since reloaded, or this page's place long let go): that
      // message where its top was, when the core says, else at the top, below what floats over the pane there (the
      // phone's bar: its scroll padding).
      const at = opensTs === null ? null : pane.querySelector<HTMLElement>(`.${conversationCss.msg}[data-ts="${opensTs}"]`);
      if (!at) return;
      pane.dispatchEvent(new WheelEvent("wheel"));
      const offset = opensOffset ?? (parseFloat(getComputedStyle(pane).scrollPaddingTop) || 0);
      pane.scrollTop += at.getBoundingClientRect().top - pane.getBoundingClientRect().top - offset;
      return;
    }
    // Left at the bottom with nothing new since: it opens at the bottom, following it (the top message's offset would
    // not land there once what is below it is laid out otherwise: images still loading, an activity come or gone).
    if (saved.bottom !== null && lastTs(pane) === saved.bottom) return;
    const at = pane.querySelector<HTMLElement>(`.${conversationCss.msg}[data-ts="${saved.ts}"]`);
    if (!at) return;
    // A reader's move: the pane keeps it rather than holding its bottom.
    pane.dispatchEvent(new WheelEvent("wheel"));
    pane.scrollTop += at.getBoundingClientRect().top - pane.getBoundingClientRect().top - saved.offset;
  }, [ref, saved, ready, opensTs, opensOffset]);
}

/** How long the pane stays still before where the reader is gets told (`useRememberPlace`). */
const REST_MS = 400;

/** The last message's `ts` in a pane. */
function lastTs(pane: HTMLElement): string | null {
  return [...pane.querySelectorAll<HTMLElement>(`.${conversationCss.msg}[data-ts]`)].at(-1)?.dataset.ts ?? null;
}

/**
 * Loads the page before what is shown (`more`: there is one; `first`: what is
 * shown first) when the reader comes within about a screenful of the top (or
 * when what is loaded does not fill the pane). What is on screen stays put: the
 * pane keeps the reader's message in place as content grows above (scroll.ts).
 */
export function useOlderOnScroll(ref: RefObject<HTMLElement | null>, more: boolean, first: number | string | undefined, older: () => Promise<unknown>): void {
  useLoadNear(ref, "top", more, first, older);
}

/**
 * Loads the page after what is shown while the chat shows a window short of its end (`newer`; `last`: what is shown
 * last) when the reader comes within about a screenful of its bottom (or when what is loaded does not fill the pane).
 * What is on screen stays put as it comes in below and as many messages leave above (scroll.ts).
 */
export function useNewerOnScroll(ref: RefObject<HTMLElement | null>, newer: boolean, last: number | string | undefined, load: () => Promise<unknown>): void {
  useLoadNear(ref, "bottom", newer, last, load);
}

/**
 * One page per approach to an edge of the pane: a page is asked when the reader is within a screenful of `edge`
 * (`can`: there is one; `at`: what is shown at that edge, asked after once). The pane is judged as the reader
 * scrolls, not as the page comes in: until the pane has put the reader's message back (scroll.ts, as it is laid out),
 * it still looks near the edge, and would ask for another page at once. So after a page, nothing is asked until a
 * frame after it is in, and then only as the reader scrolls (or while what is loaded does not fill the pane).
 */
function useLoadNear(ref: RefObject<HTMLElement | null>, edge: "top" | "bottom", can: boolean, at: number | string | undefined, load: () => Promise<unknown>): void {
  const latest = useRef({ load, at });
  latest.current = { load, at };
  const asked = useRef<number | string | undefined>(undefined);
  /** Judges the pane now; set while it is up. */
  const fill = useRef<(() => void) | null>(null);
  useEffect(() => {
    const el = ref.current;
    if (!el || !can) return;
    let live = true;
    let busy = false;
    const near = () => (edge === "top" ? el.scrollTop : el.scrollHeight - el.scrollTop - el.clientHeight) <= el.clientHeight;
    const check = () => {
      const { load, at } = latest.current;
      if (busy || asked.current === at || !near()) return;
      asked.current = at;
      busy = true;
      // Two frames on, the page is laid out and the reader's place put back (or the page never came: asked again).
      const settle = () => requestAnimationFrame(() => requestAnimationFrame(() => {
        busy = false;
        if (live && el.scrollHeight <= el.clientHeight) check();
      }));
      void load().then(settle, () => { asked.current = undefined; settle(); });
    };
    fill.current = () => { if (el.scrollHeight <= el.clientHeight) check(); };
    check();
    el.addEventListener("scroll", check, { passive: true });
    return () => {
      live = false;
      fill.current = null;
      el.removeEventListener("scroll", check);
    };
  }, [ref, can, edge]);
  // A page in that does not fill the pane leaves nothing to scroll: the next is asked without waiting for the reader.
  useEffect(() => fill.current?.(), [at]);
}

/**
 * Tells the core this page shows the chat, and whether its end (`floor`) is in view: what is read, where the unread
 * line goes and which notices are not shown follow from it there (client/core-ts/src/attend.ts).
 */
export function useShowing(floor: RefObject<HTMLElement | null>, station: string, chat: ChatView, read: (seq: number) => Promise<unknown>): void {
  const thread = chat.thread?.id ?? null;
  const session = chat.key ?? chat.agents[0]?.session.key ?? null;
  // A core from before `client.focus` (an older desktop app's) reads nothing itself: the page records what is read, as
  // it did, up to the newest message whenever the end is in view on a visible page.
  const old = useRef({ on: false, end: false, sent: 0 });
  const newest = chat.messages.at(-1)?.seq ?? 0;
  const known = chat.thread?.read ?? 0;
  const latest = useRef({ newest, known, read });
  latest.current = { newest, known, read };
  // The end of a window short of the chat's end is not its end: nothing past it has shown.
  const short = useRef(false);
  short.current = chat.newer === true;
  const readHere = useCallback(() => {
    const { newest, known, read } = latest.current;
    const o = old.current;
    if (!o.on || !o.end || short.current || document.visibilityState !== "visible" || newest <= known || o.sent >= newest) return;
    o.sent = newest;
    void read(newest).catch(() => { o.sent = 0; });
  }, []);
  useEffect(readHere, [readHere, newest, known]);
  useEffect(() => {
    const el = floor.current;
    const of = { station, thread, session };
    const tell = () => void core().focus({ chat: { ...of, end: old.current.end && !short.current } }).catch((e: unknown) => {
      if ((e as { code?: string }).code === "unknown_call") { old.current.on = true; readHere(); }
    });
    tell();
    const observer = el && new IntersectionObserver((entries) => {
      old.current.end = entries.some((e) => e.isIntersecting);
      if (old.current.on) readHere(); else tell();
    });
    if (el) observer?.observe(el);
    document.addEventListener("visibilitychange", readHere);
    return () => {
      observer?.disconnect();
      document.removeEventListener("visibilitychange", readHere);
      void core().focus({ left: of }).catch(() => undefined);
    };
  }, [floor, station, thread, session, readHere]);
  // The window reaching the chat's end with its end in view, or leaving it: said again.
  const isShort = chat.newer === true;
  const told = useRef(isShort);
  useEffect(() => {
    if (told.current === isShort) return;
    told.current = isShort;
    if (old.current.on) return readHere();
    void core().focus({ chat: { station, thread, session, end: old.current.end && !isShort } }).catch(() => undefined);
  }, [isShort, station, thread, session, readHere]);
}

/**
 * One message of the chat. It is drawn again only when something it shows changes: an agent at work makes the chat
 * draw again many times a second (its activity), and every message's Markdown would be laid out anew each time.
 */
const MessageRow = memo(function MessageRow({ message: m, enter, emitted, caught, agentHere, owner, onOpenHistory, thread, options = true, archive, check, focus }: {
  focus?: boolean;
  message: ChatMessage; enter: true | undefined; emitted: "held" | "emitting" | null; caught: true | undefined; agentHere: boolean;
  /** Its chat's thread, where a decision's options answer (Decisions.tsx); null while nothing can be sent there. */
  thread: number | null;
  /** A decision's options under it (the decisions page has them at its foot instead). */
  options?: boolean;
  /** Whose files are whose, in a word: when it changes, the files are drawn again. */
  owners: string;
  owner: (file: Attachment) => string | null; onOpenHistory: (key: string) => void;
  /** Its chat is all done: 归档 under it (ArchiveOption). */
  archive?: (() => void) | undefined;
  /** What the archive check made of its chat, under its all-done post. */
  check?: ArchiveCheck | undefined;
}) {
  if (m.mine) {
    return (
      <MineMessage data-author={t("web-main.chat.you")} data-ts={m.ts} data-role="person" data-enter={enter} data-caught={caught}>
        <MineWords message={m} owner={owner} />
        {/* Not taken by its agents yet: after a second it says it waits (the delay is the stylesheet's). */}
        {m.waiting
          ? <span className={`${conversationCss.msgTime} ${chatCss2.msgWaiting} ${css.msgWaitingLate}`}><span className={waitingCss.spinner} aria-hidden="true" />{t("web-main.chat.waitingAgent")}</span>
          : <Time className={conversationCss.msgTime} stamp={m.time?.createdAt} />}
      </MineMessage>
    );
  }
  // What still.fail itself says (a limit hit, a failure): a notice across the chat, not someone's message.
  if (m.system) return <SystemNotice text={m.text} profile={m.profile} time={m.time?.createdAt} ts={m.ts} enter={enter} caught={caught} />;
  const who = m.by.name;
  const agent = agentHere ? m.by.agent : undefined;
  return (
    <OthersMessage data-focus={focus || undefined} data-seq={m.seq} data-author={who} data-ts={m.ts} data-role={m.authorKind === "agent" ? "agent" : "person"}
      data-enter={enter} data-caught={caught} data-held={emitted === "held" || undefined} data-emitting={emitted === "emitting" || undefined} data-covered={emitted === "emitting" || undefined}
      avatar={<MessageAvatar message={m} name={who} />} time={m.time?.createdAt}
      name={agent
        ? <button type="button" className={`${css.msgName} ${css.msgAgent}`} onClick={() => onOpenHistory(agent)}>{who}</button>
        // Another chat's agent: its name opens that chat (its link, as the chat pages open still.fail's links).
        : m.by.from ? <a href={m.by.from} className={`${css.msgName} ${css.msgAgent}`}>{who}</a>
        : <span className={css.msgName}>{who}</span>}>
      <Quotes quotes={m.quotes} files={m.attachments} owner={owner} />
      {m.authorKind === "person"
        ? <>{m.text && <PersonWords text={m.text} />}<Files owner={owner} files={besideQuotes(m.quotes, m.attachments)} /></>
        : <ProseWithFiles owner={owner} text={m.text} files={besideQuotes(m.quotes, m.attachments)} />}
      {/* An agent's post asking to decide: its options right under it, or how it was settled (Decisions.tsx). */}
      {options && (m.card || m.options) && <MessageDecision message={m} thread={thread} />}
      {check && <p className={css.archiveCheck} data-failed={check.failed || undefined}>{check.text}</p>}
      {archive && <ArchiveOption thread={m.thread} onArchive={archive} />}
    </OthersMessage>
  );
}, (a, b) => a.enter === b.enter && a.emitted === b.emitted && a.agentHere === b.agentHere && a.owners === b.owners && a.thread === b.thread
  && a.options === b.options && a.archive === b.archive && a.check?.text === b.check?.text && a.check?.failed === b.check?.failed && a.focus === b.focus && sameMessage(a.message, b.message));

/**
 * 归档这个 chat, under the agent's post that said it is all done, while nothing is left in the chat: as wide as the
 * message, in the accent as a decision's recommended option is. Turns while the archive is under way (doing.ts).
 */
function ArchiveOption({ thread, onArchive }: { thread: number; onArchive: () => void }) {
  const station = useStation().address;
  const busy = useDoing("chat.archive", { station, thread, archived: true });
  const keepState = useDoingState("chat.keep", { station, thread });
  const keeping = keepState.running;
  const api = useApi();
  const act = useAct();
  return (
    <div className={decisionsCss.archiveOptions}>
      <button type="button" className={decisionsCss.option} data-busy={keeping || undefined} disabled={busy || keeping}
        aria-busy={keeping || undefined} onClick={() => act(api.keepChat(thread), t("web-main.chat.keep.what"), t("web-main.chat.keep.done"))}>
        <span className={decisionsCss.optionLabel}>{t("web-main.chat.keep")}</span>
        <DoingShown state={keepState} className={decisionsCss.optionSpinner} />
      </button>
      <button type="button" className={decisionsCss.option} data-recommended="" data-busy={busy || undefined} disabled={busy || keeping}
        aria-busy={busy || undefined} onClick={onArchive}>
        <span className={decisionsCss.optionLabel}>{t("web-main.chat.archiveThis")}</span>
        {busy && <span className={`${waitingCss.spinner} ${decisionsCss.optionSpinner}`} aria-hidden="true" />}
      </button>
    </div>
  );
}

/** A message as a chat draws it, out of its chat (the decisions page): still, its name plain, no options under it. */
export function StaticMessage({ message, owner }: { message: ChatMessage; owner: (file: Attachment) => string | null }) {
  return <MessageRow message={message} enter={undefined} emitted={null} caught={undefined} agentHere={false} thread={null} options={false}
    owners="" owner={owner} onOpenHistory={noHistory} />;
}
const noHistory = () => {};

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
export function PersonWords({ text }: { text: string }) {
  return <div className={chatCss2.msgPlain}><WithRefs text={text} /></div>;
}

/**
 * What still.fail itself says: a pill across the chat, in one line and no time. A click opens it: all its words, wrapped,
 * and its time under it. The station begins its failures with ⚠️ (Slack shows it so); here a failure is the pill in
 * red instead. In one about a profile (its sign-in failed), what went wrong (after its ：) links to that profile's page.
 */
function SystemNotice({ text, profile, time, ts, enter, caught }: { text: string; profile: string | undefined; time: Stamp | undefined; ts: string | undefined; enter: true | undefined; caught: true | undefined }) {
  const station = useStation();
  const failed = /^⚠️\s*/u.exec(text);
  const words = failed ? text.slice(failed[0].length) : text;
  // A notice is a line of the UI, not prose: no 。 at its end (stations before 2026-09-30 wrote them as sentences).
  const said = words.replace(/。\s*$/u, "");
  const colon = profile ? said.indexOf("：") : -1;
  const [open, setOpen] = useState(false);
  const toggle = () => setOpen((o) => !o);
  return (
    <div className={`${conversationCss.msg} ${css.msgSystem}`} data-ts={ts} data-role="system" data-enter={enter} data-caught={caught} role="note">
      <div className={css.msgSystemBox} data-failed={failed ? "" : undefined} data-open={open || undefined}
        role="button" tabIndex={0} aria-expanded={open}
        onClick={(e) => { if (!(e.target as Element).closest("a")) toggle(); }}
        onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); toggle(); } }}>
        <div className={conversationCss.markdown}>
          {profile && colon >= 0
            ? <p>{said.slice(0, colon + 1)}<Link className={css.msgSystemLink} to={`${stationBase(station.address)}/settings/accounts/${encodeURIComponent(profile)}`}>{said.slice(colon + 1)}</Link></p>
            : <Prose>{said}</Prose>}
        </div>
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
  if ((message.authorKind === "ember" || message.authorKind === "stillfail")) return <span className={`${chatCss2.msgAvatar} ${css.msgAvatarAgent}`}><Mark size={12} /></span>;
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
  // A mark on a previewed page (annotate/Marks.tsx) or an image (annotate/ImageMarks.tsx): its pin's number and what
  // it is; where it is is for the agent.
  const pin = quote.role === "page" || quote.role === "image" ? /(\d+)$/.exec(quote.author)?.[1] : undefined;
  return (
    <div className={css.quoteCard}>
      <Tip label={onJump ? t("web-main.quote.jump") : pin ? quote.text : undefined}><button type="button" className={css.quoteCardSource} onClick={onJump ? (e) => onJump(e.currentTarget) : undefined} disabled={!onJump}>
        {pin
          ? <span className={css.quoteCardText}><span className={css.quoteCardPin}>{pin}</span>{quote.text.split("\n")[0]}</span>
          : <span className={css.quoteCardText}><QuoteIcon size={11} strokeWidth={2.4} aria-hidden="true" /><span className={css.quoteCardWho}>{t("web-main.quote.author", { author: quote.author })}</span>{quote.text}</span>}
      </button></Tip>
      {picture && <div className={css.quoteCardPicture}>{picture}</div>}
      {comment ?? (quote.comment ? <div className={css.quoteCardComment}>{quote.comment}</div> : null)}
      {onRemove && <button type="button" className={css.quoteCardRemove} aria-label={t("web-main.quote.remove")} onClick={onRemove}><Close size={12} /></button>}
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
  const station = useStation();
  const image = isImage(file.name);
  const video = kindOf(file.name).kind === "video";
  const [videoFailed, setVideoFailed] = useState(false);
  const box = useRef<HTMLButtonElement>(null);
  const near = useNear(box, image || video);
  const fetched = useFileShown(sessionKey ?? "", file, (image || video) && sessionKey !== null && near, !video);
  const [local] = useState(() => image ? sentImage(station.address, file.path) : undefined);
  const url = local ?? fetched.url;
  const failed = !local && fetched.failed;
  const [open, setOpen] = useState(false);
  // An image seen before, or that comes at once, just shows; one that takes a while is brushed in from the top.
  const born = useRef(performance.now());
  const [loaded, setLoaded] = useState<"instant" | "reveal" | null>(local ? "instant" : null);
  const shown = () => {
    const key = `${sessionKey}\n${file.path}`;
    setLoaded(local || revealed.has(key) || performance.now() - born.current < 150 ? "instant" : "reveal");
    revealed.add(key);
  };
  const preview = sessionKey !== null && <FilePreview open={open} onClose={() => setOpen(false)} sessionKey={sessionKey} file={file} />;
  if (video && sessionKey !== null) {
    return (
      <>
        <Tip label={file.name}><button ref={box} type="button" className={`${look.image} ${css.msgVideo}`} data-viewer-thumb={thumbId(station.address, sessionKey, file.path)} onClick={() => setOpen(true)} aria-label={t(videoFailed ? "web-main.file.view" : "web-main.file.play", { name: file.name })} style={look.box(file)} data-unavailable={videoFailed || undefined}>
          {url && !videoFailed && <video src={url} muted playsInline preload="auto" aria-hidden="true" onError={() => setVideoFailed(true)} />}
          <span className={videoFailed ? css.msgVideoUnavailable : css.msgVideoPlay} aria-hidden="true">
            {videoFailed ? <><Read size={24} /><span>{t("web-main.file.noPreview")}</span><small>{fileSize(file.size)}</small></> : "▶"}
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
        <button ref={box} type="button" className={look.image} data-send-image={sentImageKey(file.path)} onClick={() => (url || failed) && setOpen(true)} aria-label={t("web-main.file.view", { name: file.name })} style={look.box(file)}
          data-viewer-thumb={url && sessionKey !== null ? thumbId(station.address, sessionKey, file.path) : undefined}
          data-loaded={loaded ?? undefined} data-failed={failed || undefined}>
          {loaded !== "instant" && <Waiting hash={file.thumbhash} />}
          {failed && <span className={css.msgImageUnavailable} aria-hidden="true"><Read size={20} /><span>{t("web-main.file.noPreview")}</span></span>}
          {url && <img src={url} alt={file.name} onLoad={shown} />}
        </button>
        {preview}
      </>
    );
  }
  if (sessionKey === null) return look.card(file);
  return (
    <>
      <button type="button" className={look.open} onClick={() => setOpen(true)} aria-label={t("web-main.file.view", { name: file.name })}>{look.card(file)}</button>
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
    <Tip label={file.path ?? file.name} cut={!file.path}><span className={css.fileCard} data-error={error ? true : undefined}>
      {pending ? <span className={waitingCss.spinner} aria-hidden="true" /> : <Read size={16} aria-hidden="true" />}
      <span className={css.fileCardText}>
        <span className={css.fileCardName}>{file.name}</span>
        <span className={css.fileCardMeta}>{error ?? (pending ? t("web-main.file.uploading") : fileSize(file.size))}</span>
      </span>
      {onRemove && <button type="button" className={css.fileCardRemove} aria-label={t("web-main.file.remove", { name: file.name })} onClick={(e) => { e.stopPropagation(); onRemove(); }}><Close size={12} /></button>}
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

export function Composer(props: ComposerProps) {
  const api = useApi();
  const { draftKey, carry, quotes = [], setQuotes = () => {} } = props;
  const draft = useDraft({ key: draftKey, ...(carry ? { carry } : {}), upload: (file) => api.uploadFile(file), quotes: [quotes, setQuotes] });
  return <ComposerView {...props} draft={draft} />;
}

/** The chat's composer, also used where a page sends its draft as a reply to a decision. */
export function ComposerView({ draft, submitDraft, thread, sessionKey, focusQuote = null, onFocused = () => {}, ensureChat, onSent, onSending, toolbar, placeholder = t("web-main.composer.placeholder"), locked = false, roomy = false, draftKey }: ComposerProps & {
  draft: Draft; submitDraft?: (draft: Draft) => void;
}) {
  const api = useApi();
  const quotes = draft.quotes;
  const { text, files, add } = draft;
  const [dragging, setDragging] = useState(false);
  const [focused, setFocused] = useState(false);
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
    if (submitDraft) { submitDraft(draft); return; }
    // In a chat (not a new one's first message, onSending's): its words stay where they were typed until its row is in
    // the list, then go there (madeChat.ts), over the dock.
    const field = input.current;
    const dock = field?.closest<HTMLElement>(`.${dockCss.composerDock}`);
    const layer = dock?.offsetParent;
    const list = document.querySelector<HTMLElement>(`.${css.chatMessages}`);
    list?.dispatchEvent(new Event("sent"));
    if (!onSending && field && list && layer instanceof HTMLElement) sendingHere(field, draft.text, { layer, z: OVER_DOCK, list });
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
  // Nothing focused, the box says which key brings the cursor back (its key changed here, or none).
  useKeymap();
  const hint = useSpaceHint(locked);
  useShortcut("composer.file", locked ? null : () => { picker.current?.click(); });
  const ready = draft.ready && !locked;
  const submit = () => {
    if (ready) void send();
  };
  const multiline = roomy || focused || text !== "" || files.length > 0 || quotes.length > 0;
  const { menu, field } = useComposerText({ draft, input, draftKey, sessionKey, locked, placeholder: hint ?? placeholder, className: css.composerText, layout: multiline, onType: warm, onSubmit: submit });
  // Capsule ⇄ box, in one motion (morph.ts); laid out for another page (a new chat's roomy box ⇄ a chat's foot), the
  // dock moves it (dock.tsx).
  const box = useRef<HTMLFormElement>(null);
  // What it is laid out by: any change of it may change its height (a line more or less, capsule ⇄ box, files).
  useMorph(box, `${multiline}|${text}|${files.length}|${quotes.length}`, roomy);
  return (
    <div className={cloudCss.composerWrap}>
      {menu}
      <form ref={box} className={`${composerCss.composerBox} ${refCss.refHost}`} data-multiline={multiline || undefined} data-dragging={dragging || undefined}
        onFocus={() => setFocused(true)}
        onBlur={(e) => { if (!e.currentTarget.contains(e.relatedTarget)) setFocused(false); }}
        onSubmit={(e) => { e.preventDefault(); submit(); }} onClick={() => input.current?.focus()}
        // Locked (its station offline), no file is taken in.
        onDragOver={(e) => { if (e.dataTransfer.types.includes("Files") && !locked) { e.preventDefault(); setDragging(true); } }}
        onDragLeave={() => setDragging(false)}
        onDrop={(e) => { if (e.dataTransfer.files.length) { e.preventDefault(); setDragging(false); if (!locked) add(e.dataTransfer.files); } }}>
        <ComposerExtras draft={draft} focusQuote={focusQuote} onFocused={onFocused} onDone={() => input.current?.focus()} />
        {field}
        <div className={css.composerToolbar}>
          <input ref={picker} type="file" multiple hidden onChange={(e) => { if (e.target.files) add(e.target.files); e.target.value = ""; }} />
          <Tip label={t("web-main.composer.attach")} shortcut="composer.file">
            <button type="button" className={css.attachBtn} aria-label={t("web-main.composer.attach")} disabled={locked} onClick={(e) => { e.stopPropagation(); picker.current?.click(); }}>
              <Plus size={18} />
            </button>
          </Tip>
          {toolbar && <div className={css.composerChoices} onClick={(e) => e.stopPropagation()}>{toolbar}</div>}
          <Tip label={draft.uploading ? t("web-main.composer.stillUploading") : t("web-main.composer.send")}>
            <button type="submit" className={css.sendBtn} disabled={!ready} aria-label={t("web-main.composer.send")} aria-busy={draft.starting || undefined}>
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
 * With a mouse, and nothing that takes keys focused, what the composer's box says instead of its placeholder: that
 * "composer.focus"'s key puts the cursor there. Null while it has the cursor (or another field or button has).
 */
function useSpaceHint(locked: boolean): string | null {
  const available = usePageKeysAvailable();
  const key = shortcutOf("composer.focus");
  if (!available || locked || !key || !window.matchMedia("(pointer: fine)").matches) return null;
  return t(/^[\u4e00-\u9fff]+$/.test(key) ? "web-main.composer.pressToTypeCjk" : "web-main.composer.pressToType", { key });
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
export function useComposerText({ draft, input, draftKey, sessionKey, locked, placeholder, className, lines = 3, layout, enterSends = true, onType, onSubmit }: {
  draft: Draft; input: RefObject<HTMLTextAreaElement | null>; draftKey: string | undefined; sessionKey: string | null; locked: boolean;
  placeholder: string; className: string; lines?: number; layout?: unknown; enterSends?: boolean; onType(): void; onSubmit(): void;
}): { menu: ReactNode; field: ReactNode } {
  const { text, setText, add } = draft;
  const toast = useToast();
  // `@` and a few letters: a menu of the station's other chats, the one chosen put in as a link (ChatRef.tsx).
  const [reference, setReference] = useState<{ start: number; query: string } | null>(null);
  const [active, setActive] = useState(0);
  const refItems = useRef<ChatItem[]>([]);
  // Where this page's links start: a reference is a link to the chat's page here.
  const base = `${/^https?:$/.test(location.protocol) ? location.origin : ""}${useHref("/").replace(/\/$/, "")}`;
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
  const pickReference = (item: ChatItem) => {
    const el = input.current;
    if (!el || !reference) return;
    const { start } = reference;
    const end = el.selectionStart;
    setReference(null);
    // Its mark, from the core, which keeps its link until it is sent; in its place if the `@words` are still there.
    void core().call("chat.ref", { station: item.station, id: item.id, title: item.title, base }).then((answer) => {
      const { mark } = answer as { mark: string };
      const now = input.current?.value ?? "";
      if (now[start] !== "@") return;
      caretAt.current = start + mark.length + 1;
      setText(`${now.slice(0, start)}${mark} ${now.slice(end)}`);
    }, (e: unknown) => toast(t("web-main.composer.refFailed", { title: item.title, error: failure(e) })));
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
  }, [text, lines, layout]); // eslint-disable-line react-hooks/exhaustive-deps
  const menu = reference && !locked && (
    <div className={refCss.refAnchor}>
      <ChatRefMenu query={reference.query} here={sessionKey} active={active} onPick={pickReference} found={(items) => { refItems.current = items; }} />
    </div>
  );
  const field = (
    <>
      {marked && <RefMirror text={text} className={className} mirror={mirror} />}
      <textarea ref={input} className={`${className}${marked ? ` ${refCss.refTextSeeThrough}` : ""}`} rows={1} value={text} placeholder={placeholder} aria-label={t("web-main.composer.label")} readOnly={draft.starting}
        onChange={(e) => { setText(e.target.value); onType(); lookForReference(e.target); }}
        onSelect={(e) => lookForReference(e.currentTarget)}
        onBlur={() => setReference(null)}
        onPaste={(e) => { if (e.clipboardData.files.length) { e.preventDefault(); if (!locked) add(e.clipboardData.files); } }}
        onKeyDown={(e) => {
          if (reference && !e.nativeEvent.isComposing) {
            const n = refItems.current.length;
            if (e.key === "Escape") { e.preventDefault(); closedAt.current = reference.start; setReference(null); return; }
            if (n && (e.key === "ArrowDown" || e.key === "ArrowUp")) { e.preventDefault(); setActive((i) => (i + (e.key === "ArrowDown" ? 1 : n - 1)) % n); return; }
            if (n && (e.key === "Enter" || e.key === "Tab") && !e.shiftKey) { e.preventDefault(); pickReference(refItems.current[Math.min(active, n - 1)]!); return; }
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
                  className={`${css.quoteCardComment} ${css.quoteCardInput}`} value={q.comment} placeholder={t("web-main.quote.commentPlaceholder")} aria-label={t("web-main.quote.commentLabel", { author: q.author })}
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
    <Tip label={f.error ?? f.name}><span className={css.composerThumb} data-send-image={f.done ? sentImageKey(f.done.path) : undefined} data-error={f.error ? true : undefined}>
      <img src={f.preview} alt={f.name} />
      {!f.done && !f.error && <span className={css.composerThumbBusy}><span className={waitingCss.spinner} aria-hidden="true" /></span>}
      {onRemove && <button type="button" className={css.composerThumbRemove} aria-label={t("web-main.file.remove", { name: f.name })} onClick={(e) => { e.stopPropagation(); onRemove(); }}><Close size={12} /></button>}
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
 * An activity keeps its place on screen as what is above it changes at once (a message arriving, one coming out of an
 * avatar, an image loading): it glides from where it showed to where it is laid out now, and a change while it is on
 * its way goes on from where it is and the speed it has. What the pane's width lays out anew is taken at once.
 */
const GLIDE = { type: "spring", visualDuration: 0.3, bounce: 0 } as const;

function useActivityGlide(list: RefObject<HTMLDivElement | null>) {
  useEffect(() => {
    const pane = list.current;
    if (!pane) return;
    const rows = new Map<HTMLElement, { top: number; y: Follower }>();
    const contentWidth = () => {
      const style = getComputedStyle(pane);
      return pane.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
    };
    let width = contentWidth();
    const check = () => {
      const now = contentWidth();
      const rewrapped = now !== width;
      width = now;
      const seen = new Set<HTMLElement>();
      for (const el of pane.querySelectorAll<HTMLElement>(`:scope > .${css.agentActivity}`)) {
        seen.add(el);
        const top = layoutSpot(pane, el).y;
        const row = rows.get(el);
        if (!row) {
          const made = { top, y: follower(top, (v) => { el.style.transform = Math.abs(v - made.top) < 0.01 ? "" : `translateY(${v - made.top}px)`; }) };
          rows.set(el, made);
          continue;
        }
        if (top === row.top) continue;
        row.top = top;
        // One folded to its avatar, out flying, shows nothing: it is where it is laid out, for the avatar to fly to.
        if (rewrapped || document.visibilityState !== "visible" || el.hasAttribute("data-away")) row.y.jump(top);
        else {
          row.y.to(top, GLIDE);
          // Laid out elsewhere, it is drawn where it was until the glide takes it.
          el.style.transform = `translateY(${row.y.value - top}px)`;
        }
      }
      for (const [el, row] of rows) if (!seen.has(el)) { row.y.stop(); rows.delete(el); }
    };
    const resize = new ResizeObserver(check);
    const watch = () => { resize.disconnect(); resize.observe(pane); for (const child of pane.children) resize.observe(child); };
    const mutations = new MutationObserver(() => { watch(); check(); });
    mutations.observe(pane, { childList: true, subtree: true, characterData: true });
    watch();
    check();
    return () => {
      resize.disconnect();
      mutations.disconnect();
      for (const row of rows.values()) row.y.stop();
    };
  }, [list]);
}

/** Where an element sits in the pane's content, by layout: scrolling does not move it, nor does a transform. */
function layoutSpot(pane: HTMLElement, el: Element) {
  let x = 0;
  let y = 0;
  for (let n: HTMLElement | null = el as HTMLElement; n && n !== pane; n = n.offsetParent as HTMLElement | null) {
    x += n.offsetLeft;
    y += n.offsetTop;
  }
  return { x, y };
}

/**
 * A message an agent posts while its activity shows comes out of the activity's avatar, one at a time:
 * the activity folds to its avatar (fold), the avatar hops to where the message's avatar goes (float: up, slowing, then
 * falling faster and faster, stopping dead there), the message comes out of it as it lands, carried on by the fall,
 * growing down into its place (spit), and the avatar goes on down to where the activity now is, which unfolds again
 * (return). The avatar that flies is a copy over the list, put exactly where the real one is (and the real one hidden)
 * as it sets out, and let go of only once it has come to rest exactly where the real one is, so nothing blinks or
 * jumps; where it goes is read anew each frame (the message growing, the activity gliding down), and going home it is
 * on springs, from the speed it has. The message's own avatar is where it lands, the same picture in the same place. Until its turn
 * a message waits folded to nothing. With reduced motion messages just appear, and so do those no one watches come
 * out: arriving while the page is hidden or the reader has scrolled up (scroll.ts), and all still waiting when the page
 * is hidden or the reader scrolls up (the browser barely runs timers for a hidden page, so a queue would otherwise
 * still be playing out long after); an avatar then on its way goes home from where it is.
 */
type Pose = "fold" | "float" | "spit" | "return";
const FOLD_MS = 170;
const SPIT_MS = 380;
/** The hop: how long, how high above the higher of its two ends it goes, and the share of it spent going up. */
const HOP_MS = 440;
const HOP_PX = 34;
const RISE = 0.42;
/** The same agent's next message, waiting as one comes out: the avatar drops on to it, no hop (how long). */
const DROP_MS = 280;
const FLY = { type: "spring", visualDuration: 0.26, bounce: 0 } as const;

export function useEmissions(list: RefObject<HTMLDivElement | null>) {
  const decided = useRef(new Map<number, boolean>());
  const done = useRef(new Set<number>());
  // `at`: when it began waiting; its agent's activity folds to its avatar from then.
  const queue = useRef<{ seq: number; agent: string; at: number }[]>([]);
  // `chain`: on from the message before it, the same agent's, without going home between.
  const [current, setCurrent] = useState<{ seq: number; agent: string; pose: Pose; at: number; chain?: boolean } | null>(null);
  const flight = useRef<{ el: HTMLElement; x: Follower; y: Follower; s: MotionValue<number>; sx: MotionValue<number>; sy: MotionValue<number> } | null>(null);
  const [, rerender] = useState(0);
  const reduced = useMemo(() => window.matchMedia("(prefers-reduced-motion: reduce)").matches, []);

  // Where the avatar of an agent's activity shows: where it is laid out, and how far its row is from there, gliding.
  const home = (avatar: HTMLElement) => {
    const at = layoutSpot(list.current!, avatar);
    const row = avatar.closest<HTMLElement>(`.${css.agentActivity}`);
    return { x: at.x, y: at.y + (row ? new DOMMatrixReadOnly(getComputedStyle(row).transform).m42 : 0) };
  };
  const launch = (pane: HTMLElement, avatar: HTMLElement) => {
    const el = avatar.cloneNode(true) as HTMLElement;
    el.classList.add(css.avatarFlying);
    Object.assign(el.style, { left: "0", top: "0", width: `${avatar.offsetWidth}px`, height: `${avatar.offsetHeight}px` });
    pane.append(el);
    // Its ring turning as the real one does (the copy's would start over): they hand over to each other unmoved.
    const ring = (n: Element) => n.getAnimations({ subtree: true }).find((x) => (x.effect as KeyframeEffect | null)?.pseudoElement === "::after");
    const turning = ring(avatar);
    const copied = ring(el);
    if (turning && copied) copied.currentTime = turning.currentTime;
    // Squashed and stretched (sx, sy) from its foot; swelling (s) from its middle.
    const at = { ...home(avatar), s: 1, sx: 1, sy: 1 };
    const h = avatar.offsetHeight;
    const draw = () => {
      el.style.transform = `translate(${at.x}px, ${at.y + (h * (1 - at.sy)) / 2}px) scale(${at.s * at.sx}, ${at.s * at.sy})`;
    };
    const s = motionValue(1);
    const sx = motionValue(1);
    const sy = motionValue(1);
    s.on("change", (v) => { at.s = v; draw(); });
    sx.on("change", (v) => { at.sx = v; draw(); });
    sy.on("change", (v) => { at.sy = v; draw(); });
    draw();
    return { el, s, sx, sy, x: follower(at.x, (v) => { at.x = v; draw(); }), y: follower(at.y, (v) => { at.y = v; draw(); }) };
  };
  const land = () => {
    const f = flight.current;
    if (!f) return;
    f.x.stop();
    f.y.stop();
    f.s.destroy();
    f.sx.destroy();
    f.sy.destroy();
    f.el.remove();
    flight.current = null;
  };
  const nextAfter = (agent: string | null) => {
    const next = queue.current.shift();
    // The same agent's next message goes straight on: its activity is folded already, and its avatar out.
    setCurrent(next ? { ...next, pose: next.agent === agent ? "float" : "fold" } : null);
  };
  // Done: the copy let go of in the same frame as the real avatar shows again (or kept, flying on to the next message).
  const finish = (seq: number, agent: string, sync = true) => {
    done.current.add(seq);
    if (queue.current[0]?.agent !== agent || !sync) land();
    if (sync) flushSync(() => nextAfter(agent));
    else nextAfter(agent);
  };

  // Everything waiting or coming out shows at once, where it is; an avatar on its way goes home from there.
  const release = () => {
    if (!queue.current.length && (!current || done.current.has(current.seq))) return;
    for (const q of queue.current) done.current.add(q.seq);
    queue.current = [];
    if (current) done.current.add(current.seq);
    if (current && flight.current && document.visibilityState === "visible") {
      if (current.pose !== "return") setCurrent({ ...current, pose: "return" });
    } else {
      land();
      setCurrent(null);
    }
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
    const avatar = pane?.querySelector<HTMLElement>(`.${css.agentActivity}[data-agent="${CSS.escape(agent)}"] .${css.activityAvatar}`);
    const message = pane?.querySelector(`.${conversationCss.msg}[data-seq="${seq}"]`);
    const landing = message?.querySelector(`:scope > .${chatCss2.msgAvatar}`);
    // Going home needs only its activity (the message may show already).
    if (!pane || !avatar || (pose !== "return" && !landing)) { finish(seq, agent, false); return; }
    let timer: ReturnType<typeof setTimeout> | undefined;
    let frame = 0;
    const go = (to: Pose) => setCurrent({ ...current, pose: to, chain: false });
    // Where the message's avatar is once the message is out: waiting, the message takes back the list's gap above it.
    const landed = () => {
      const at = layoutSpot(pane, landing!);
      return message!.hasAttribute("data-held") ? { x: at.x, y: at.y - parseFloat(getComputedStyle(message!).marginTop) } : at;
    };
    // Each frame the avatar is sent on to where it goes, read anew; `arrived`, once it is there (put exactly there).
    const follow = (to: () => { x: number; y: number }, arrived?: () => void) => {
      const step = () => {
        const f = flight.current;
        if (!f) return;
        const goal = to();
        f.x.to(goal.x, FLY);
        f.y.to(goal.y, FLY);
        if (arrived && Math.abs(f.x.value - goal.x) < 0.5 && Math.abs(f.y.value - goal.y) < 0.5) {
          f.x.jump(goal.x);
          f.y.jump(goal.y);
          arrived();
          return;
        }
        frame = requestAnimationFrame(step);
      };
      step();
    };
    // Folding since it began waiting: on once folded.
    if (pose === "fold") timer = setTimeout(() => go("float"), Math.max(0, FOLD_MS - (performance.now() - current.at)));
    let hop: AnimationPlaybackControls | undefined;
    if (pose === "float") {
      const f = (flight.current ??= launch(pane, avatar));
      const from = { x: f.x.value, y: f.y.value };
      // Thrown up: it shoots off and slows to the top, hangs there a moment, then drops ever faster (stretching as it
      // goes) onto where it goes. Across, it eases out and in. On from the message before it, it only drops.
      const rise = current.chain ? 0 : RISE;
      hop = animate(0, 1, {
        duration: (current.chain ? DROP_MS : HOP_MS) / 1000, ease: "linear",
        onUpdate: (t) => {
          const to = landed();
          const top = current.chain ? from.y : Math.min(from.y, to.y) - HOP_PX;
          const up = rise ? t / rise : 1;
          const down = (t - rise) / (1 - rise);
          const y = t < rise ? from.y + (top - from.y) * (1 - (1 - up) ** 2.5) : top + (to.y - top) * down ** 2.5;
          const across = t < 0.5 ? 4 * t ** 3 : 1 - (-2 * t + 2) ** 3 / 2;
          f.x.jump(from.x + (to.x - from.x) * across);
          f.y.jump(y);
          const stretch = t < rise ? 0.07 * Math.sin(Math.PI * up) : 0.14 * down ** 2;
          f.sx.jump(1 - stretch * 0.6);
          f.sy.jump(1 + stretch);
        },
        onComplete: () => go("spit"),
      });
    }
    // A small swell as it lets the message out, staying on the message's avatar as the message grows.
    if (pose === "spit") {
      const f = flight.current;
      if (f) {
        // Landing: flattened by the fall, it springs back up as the message comes out.
        f.sx.jump(1.16);
        f.sy.jump(0.8);
        animate(f.sx, 1, { type: "spring", stiffness: 520, damping: 14 });
        animate(f.sy, 1, { type: "spring", stiffness: 520, damping: 14 });
        animate(f.s, [1, 1.12, 1], { duration: SPIT_MS / 1000, times: [0, 0.4, 0.75], ease: "easeInOut" });
      }
      follow(landed);
      timer = setTimeout(() => {
        const next = queue.current[0];
        if (next?.agent !== agent || !flight.current) return go("return");
        // The same agent's next message is waiting: the avatar drops on to it from here, not going home to hop again.
        queue.current.shift();
        done.current.add(seq);
        setCurrent({ ...next, pose: "float", chain: true });
      }, SPIT_MS);
    }
    if (pose === "return") {
      if (!flight.current) { finish(seq, agent, false); return; }
      follow(() => home(avatar), () => finish(seq, agent));
    }
    return () => { clearTimeout(timer); cancelAnimationFrame(frame); hop?.stop(); };
  }, [current?.seq, current?.pose]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => land, []); // eslint-disable-line react-hooks/exhaustive-deps

  return {
    /** Agents whose activity must stay while their messages come out. */
    keeps: new Set([...queue.current.map((q) => q.agent), ...(current ? [current.agent] : [])]),
    /** Messages seen for the first time: an agent's, new, while its activity shows, waits its turn to come out of it. */
    take(messages: ChatMessage[], saidHere: (seq: number) => boolean, showing: ReadonlySet<string>) {
      for (const m of messages) {
        if (decided.current.has(m.seq)) continue;
        const agent = m.authorKind === "agent" ? m.by.agent : undefined;
        const emits = !reduced && watched() && saidHere(m.seq) && agent !== undefined && showing.has(agent);
        decided.current.set(m.seq, emits);
        if (emits) queue.current.push({ seq: m.seq, agent: agent!, at: performance.now() });
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
    // Folded from when its first message begins waiting until its last is out: with others' messages coming out in
    // between, it does not unfold and fold again each time.
    poseOf(agent: string): { folded: boolean; away: boolean } {
      const mine = current?.agent === agent;
      return { folded: mine || queue.current.some((q) => q.agent === agent), away: mine && current!.pose !== "fold" };
    },
  };
}

/**
 * An agent at work, in one line: its avatar, ringed while it works, and what it does now (as the core says), with how
 * long its turn has run. No name: the avatar says whose. What it does changes by crossfading, and each thing stays a
 * moment, so a passing 请求中 does not flicker by. The line opens its history. It comes in opening its room as it fades
 * in, the line growing from its avatar; it leaves fading and folding its room away; for a message to come out of its
 * avatar the line folds to the avatar. Each of these goes from wherever it shows, cut off by the next or not.
 */
function Activity({ agent, leaving, caught, pose, onOpen }: { agent: AgentAtWork; leaving: boolean; caught: true | undefined; pose: { folded: boolean; away: boolean }; onOpen(): void }) {
  const wait = agent.wait;
  const now = useSteady(wait ? { key: "wait", text: wait.text ?? t("web-main.activity.waiting") } : agent.activity?.now ?? { key: "busy", text: t("web-main.activity.busy") });
  const row = useRef<HTMLDivElement>(null);
  const line = useRef<HTMLButtonElement>(null);
  const tail = useRef<HTMLSpanElement>(null);
  // One there when the chat opened is there at once.
  useLayoutEffect(() => {
    if (caught) return;
    const move = { duration: FADE_MS / 1000, ease: EASE_OUT };
    arrive([[row.current!, { "grid-template-rows": "0px", opacity: "0" }], [line.current!, { transform: "scale(0.5)" }]], move);
  }, []); // eslint-disable-line react-hooks/exhaustive-deps
  // Set here, not by React: the change is made where what shows before it can be read.
  const was = useRef({ leaving: false, folded: false });
  useLayoutEffect(() => {
    const el = row.current!;
    if (leaving !== was.current.leaving) {
      // Reading where it goes lays the list out with its room folded for a moment, shorter than the pane scrolled to its
      // end: the browser pulls the pane up then, and it is put back (the list is held where it was while it folds).
      const pane = el.parentElement;
      const top = pane?.scrollTop ?? 0;
      moveState([[el, ["grid-template-rows", "opacity"]]], () => el.toggleAttribute("data-leaving", leaving), { duration: FADE_MS / 1000, ease: EASE_OUT });
      if (pane && pane.scrollTop !== top) pane.scrollTop = top;
    }
    if (pose.folded !== was.current.folded) {
      moveState([[tail.current!, ["width", "opacity"]]], () => el.toggleAttribute("data-folded", pose.folded), { duration: FOLD_MS / 1000, ease: EASE_OUT });
    }
    was.current = { leaving, folded: pose.folded };
  });
  return (
    <div ref={row} className={`${conversationCss.msg} ${css.agentActivity}`} data-transient="" data-agent={agent.key} data-caught={caught} data-away={pose.away || undefined} data-waiting={wait ? "" : undefined}>
      <button ref={line} type="button" className={css.activityLine} onClick={onOpen} aria-label={`${agent.who}：${now.current.text}`}>
        <span className={css.activityAvatar} aria-hidden="true"><span className={`${chatCss2.msgAvatar} ${css.msgAvatarAgent}`}><ModelLogo maker={agent.maker} runtime={agent.runtime} size={12} /></span></span>
        <span ref={tail} className={css.activityTail}>
          <span className={css.activityNow}>
            {now.previous && <span key={`was-${now.n - 1}`} className={css.activityNowText} data-out="">{now.previous.text}</span>}
            <span key={now.n} className={css.activityNowText} data-in={now.switched || undefined}>{now.current.text}</span>
          </span>
          {wait
            ? <span className={css.activityElapsed}><Waited since={wait.since} seconds={wait.seconds} /></span>
            : agent.since ? <span className={css.activityElapsed}><Elapsed since={agent.since} /></span> : null}
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
  const rows = [...document.querySelectorAll<HTMLAnchorElement>(`.${nav.sidebar} .${nav.navScroll}:not([inert]) [data-flip]:not([data-leaving]) a.${nav.navSession}`)];
  // From the row on its way to be the current one (clicked, its page not there yet), else the current one.
  const going = rows.findIndex((row) => row.dataset.going === "here");
  const at = going >= 0 ? going : rows.findIndex((row) => row.getAttribute("aria-current") === "page");
  const next = at < 0 ? null : rows[at + step];
  if (!next) return false;
  next.click();
  next.scrollIntoView({ block: "nearest" });
  return true;
}
