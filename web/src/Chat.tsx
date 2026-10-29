import { chatPageAhead } from "./chatPaging.ts";
import { useLoadNear, usePagingEdges } from "./virtual/load.ts";
export { useLoadNear } from "./virtual/load.ts";
import { makePastedFile, pastedInfo, PASTE_THRESHOLD } from "./pastedText.ts";
// still.fail's own chat with a session, after Zork's: your messages sit right in a
// bubble with only their time; everyone else (people and the agent) gets an
// avatar, a name and the time over their words. Passages of earlier messages
// can be quoted with a comment, and files ride along as cards (images shown).
import { sentFileKey, sentImage, sentImageKey, uploadImageKey } from "./sentImages.ts";
import { ArchiveNotice } from "./ArchiveNotice.tsx";
import { CacheColdNotice } from "./CacheColdNotice.tsx";
import { ComposerNotice, ComposerNotices } from "./ComposerNotice.tsx";
import { StationInWords, StationNamedAt } from "./StationNamed.tsx";
import { ArrowDown, ArrowUp, Bell, Bot, Brain, Chats, Check, Close, Command, Edit, Folder, Info, Photo, PlayMark, Plus, Quote as QuoteIcon, Read, Received, Retry, Said, Search, Send, Sparks, Stop, Think, Trash, Unplug, Web } from "@stillfail/ui/icons.tsx";
import { createContext, Fragment, memo, useCallback, useContext, useEffect, useId, useLayoutEffect, useMemo, useRef, useState, type ClipboardEvent, type CSSProperties, type MutableRefObject, type ReactNode, type RefObject } from "react";
import { Link, useHref, useSearchParams } from "react-router";
import { useApi, useChat, useChatSend, useLives, type ChatTo, type Outgoing, type Activity as ActivityView, type AgentWait, type Attachment, type ChatItem, type ChatMessage, type ChatView, type Live, type Maker, type Quote, type RuntimeKind, type Session, type Stamp, type Status } from "./api.ts";
import { Mark } from "./brand.tsx";
import { scopeOf, stationBase, usePerson, useStation } from "./station.tsx";
import { chatOfLink } from "./chatRefs.ts";
import { pastedRefs } from "../../client/core-ts/src/refLinks.ts";
import { Hover, PathSession } from "./Peeks.tsx";
import { Avatar, Button, Chooser, ChooserItem, Dialog, ElsewhereLogo, ICON, ModelLogo, Pill, Progress, Segmented, Spinner, Switch, SlackLogo, Time, Tip, transitionTo } from "./ui.tsx";
import { ComposerSlot, useComposerHeight } from "./dock.tsx";
import { chatPage } from "./chatPage.ts";
import { Prose, withBareLinks } from "./Prose.tsx";
import type { Md } from "./core/md.ts";
import { placeFiles } from "../../client/core-ts/src/placed.ts";
import { shortcutOf, useKeymap, usePageKeysAvailable, useShortcut } from "./keymap.ts";
import { FileLink, FilePreview, fileHere, fileSize, Gallery, isImage, kindOf, storedName, useFileShown, useNear, useVideoStill } from "./FilePreview.tsx";
import { cancelDownload, retryDownload, useDownload } from "./chatDownloads.ts";
import { imageBox } from "./imageBox.ts";
import { thumbhashUrl } from "./thumbhash.ts";
import { OpenFile, VizFile } from "./Viz.tsx";
import { useVirtualList, useVirtualModel, type VirtualList } from "./virtual/list.tsx";
import type { Align, Item } from "./virtual/model.ts";
import { animate, arrive, EASE_OUT, ENTER, follower, glider, motionMs, moveState, type AnimationPlaybackControls, type Follower } from "@stillfail/ui/motion.ts";
import { motionValue, type MotionValue } from "motion";
import { flushSync } from "react-dom";
import { DraftKey, goingUp, MAX_FILE, offerToDraft, pathWords, useDraft, useDraftInbox, type Draft, type DraftQuote, type Pending } from "./draft.ts";
import { carriesDrive, droppedFrom, droppedOf, useDropOver } from "./drive/drag.ts";
import { useLanding } from "./drive/flight.ts";
import * as nav from "./Sidebar.css.ts";
import * as sessionCss from "./styles/session.css.ts";
import * as chatCss2 from "./styles/chat.css.ts";
import * as conversationCss from "./styles/conversation.css.ts";
import type { ChatAsk, ChatCcTo, ChatSentElsewhere, DownloadShown, NoticeShown, RuntimeInstall } from "./core/shapes.ts";
import * as partsCss from "@stillfail/ui/parts.css.ts";
import * as historyCss from "./History.css.ts";
import * as css from "./Chat.css.ts";
import { WaitingText } from "./ChatMark.tsx";
import { sampleMessages } from "./samples.ts";
import * as refCss from "./ChatRef.css.ts";
import { core, useCall } from "./core/react.ts";
import { ChatRefMenu, LinkedChats, markBefore, refAt, RefMirror, WithRefs } from "./ChatRef.tsx";
import { useOutsideShare } from "./OutsideShare.tsx";
import { useMorph } from "./morph.ts";
import * as cloudCss from "./styles/cloud.css.ts";
import * as composerCss from "./styles/composer.css.ts";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import * as dockCss from "./dock.css.ts";
import { sendingHere, sendingNow, sentAfter, toMadeChat as toMadeChatOf } from "./madeChat.ts";
import { after, claimReserved, growRow, listQueue, queueRow } from "./listQueue.ts";
import { thumbId } from "./viewerFlight.ts";
import { DoingShown, useDoingState } from "./DoingMark.tsx";
import { failure, useToast, useAct } from "@stillfail/ui/toast.tsx";
import { clock } from "@stillfail/ui/viewer/playing.ts";
import { MessageDecision } from "./Decisions.tsx";
import { Settles } from "./settling.tsx";
import { AgentHover, ChatAgentKeys, ChatAgents } from "./AgentCard.tsx";
import * as decisionsCss from "./Decisions.css.ts";
import { useDoing } from "./doing.ts";
import { useChatFind } from "./ChatFind.tsx";
import { placeStrokes, strokeLayer } from "@stillfail/ui/strokes.ts";
import { jumped, jumpTo, jumpWords, useJump } from "./jumpTo.ts";
import { t } from "./i18n.ts";
import { VaultAsk } from "./VaultAsk.tsx";

/** Over the composer (dock.css.ts): where what a new chat's first message is drawn by on its way (madeChat.ts). */
export const OVER_DOCK = "4";

// The composer's height, set on a chat (ChatPanel), as that element's own; the room it leaves the chat's list, a length
// worked out there and inherited (styles/session.css.ts): the composer growing (a line more, or its width changing as
// a side panel slides in) restyles the chat's every message only when the room it leaves does (past one line), not
// at each change of its height. As the phone's (mobile/ChatHost.tsx). A browser without registered properties inherits
// both as they are.
for (const property of [
  { name: "--composer-height", syntax: "<length>", inherits: false, initialValue: "0px" },
  { name: "--composer-room", syntax: "<length>", inherits: true, initialValue: "0px" },
]) {
  try { globalThis.CSS?.registerProperty?.(property); } catch { /* registered already (a module loaded again) */ }
}

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
 * A chat's messages and its composer, by the chat's key (its agent's session; `draftKey`: whose draft the composer
 * shows, the page's own key, which what is in it does the page's things by: chatPage.ts). Drawn again only when what it
 * is given changes, or the chat does.
 */
export const ChatPanel = memo(function ChatPanel({ session, draftKey, made }: {
  session: string; draftKey: string;
  /** What is sent to until its thread is known: the core's key of a chat made here (`chat.create`), or the agent's
   *  whose page it is (the core has the station make its chat behind what is sent). */
  made?: string | undefined;
}) {
  const chat = useChat(useStation().address, { session }).value;
  return chat ? <ChatShown chat={chat} session={session} draftKey={draftKey} made={made} /> : null;
});

function ChatShown({ chat, session, draftKey, made }: { chat: ChatView; session: string; draftKey: string; made: string | undefined }) {
  const station = useStation();
  const list = useRef<HTMLDivElement>(null);
  const composerHeight = useComposerHeight();
  const api = useApi();
  const { thread, outbox } = chat;
  const id = thread?.id ?? null;
  const to: ChatTo | null = id ?? made ?? null;
  const lives = useLives(station.address, chat.agents.map((a) => a.session.key));
  const rows = useMessageList(list, chat, `${station.address}:${chat.thread?.id ?? chat.agents[0]?.session.key ?? ""}`, lives, 28);
  // Files are kept in a session's workspace: what is sent here goes to the first agent's.
  const keeper = chat.agents[0]?.session.key ?? null;
  // An image opened here steps through the chat's (the core tells those beside it, as this page's chat names it).
  const gallery = useMemo(() => ({ chat: { session } }), [session]);
  useShortcut("chat.latest", rows.toEnd);
  // Its own find, in place of the browser's (ChatFind.tsx).
  const find = useChatFind(list, rows.virtual, id, rows.messages, composerHeight);
  useShortcut("chat.find", find.show);
  const askedFile = useAskedFile(list, rows.messages);
  // What waits to be decided here and does not show: a button over the list leads to it.
  const asks = useAsksShown(rows.virtual, chat);
  // Selecting text inside one message offers to quote it: into the chat's draft, its composer's (by its key).
  // Its turn shared as a picture from there, by the page open for it.
  const quoting = useSelectionQuote(list, (quote, file) => offerToDraft(draftKey, { files: [], quotes: [], quote, ...(file ? { quotedFile: file } : {}) }),
    (seq) => chatPage.share(draftKey, seq));

  return (
    // The list runs on under the composer, frosted over it (its styles): its foot leaves the composer's height free.
    <section className={sessionCss.chat} aria-label={t("web-main.chat.label")} data-under-composer="" data-avoid-previews="" style={{ "--composer-height": `${composerHeight}px`, ...askClear(chat, 44) } as CSSProperties}>
      <div className={sessionCss.chatPane}>
      {find.bar}
      {rows.away && <ToLatest station={station.address} thread={id} waiting={rows.waiting} onClick={rows.toEnd} />}
      {asks.length > 0 && id !== null && <ToAsk station={station.address} thread={id} asks={asks} above={rows.away} />}
      <Gallery.Provider value={gallery}>
      <div className={`${sessionCss.chatList} ${css.chatMessages}`} ref={list} {...quoting.listProps} {...sentAfter(chat)}
        onClick={(e) => {
          const to = historyLinkClicked(e);
          // At the entry it names (else its start); opened, not toggled. Another chat's agent's opens with its chat (ChatPage).
          if (to && chat.agents.some((a) => a.session.key === to.key)) { e.preventDefault(); chatPage.history(draftKey, to.key, to.entry); }
        }}>
        <DraftKey.Provider value={draftKey}>
          <ImageQuote.Provider value={quoting.images}><ChatRows chat={chat} rows={rows} to={to} /></ImageQuote.Provider>
        </DraftKey.Provider>
      </div>
      </Gallery.Provider>
      </div>
      {quoting.pop}
      {askedFile}
      {(chat.archived || chat.cacheCold || chat.offline) && <ComposerNotices className={css.offlineNotice}>
        {chat.archived && <ArchiveNotice offline={chat.offline} restore={() => api.archive({ thread: id, session: keeper ?? "" }, false)} />}
        {chat.cacheCold && !chat.archived && <CacheColdNotice cold={chat.cacheCold} offline={chat.offline} afresh={api.afresh} />}
        {chat.offline && <ComposerNotice mark={<Unplug size={16} />}><StationInWords station={station.address} text={chat.offlineNote ?? (station.name ? t("web-main.chat.offline.named", { name: station.name }) : t("web-main.chat.offline"))} /></ComposerNotice>}
      </ComposerNotices>}
      {/* The one composer of the chat pages sits here (dock.tsx), kept as the page changes. */}
      <ComposerSlot variant="chat" station={station} draftKey={draftKey} thread={to} sessionKey={keeper}
        toolbar={chat.cc?.length && id !== null ? <CcChooser station={station.address} thread={id} to={chat.cc} /> : undefined}
        locked={!!chat.archived} offline={chat.offline} placeholder={chat.archived ? t("web-main.chat.archivedPlaceholder") : t("web-main.composer.placeholder")} />
    </section>
  );
}

/**
 * In a chat whose agents are in Slack or Feishu threads: which of them what is sent is copied to too (`chat.cc`), each
 * thread's bot saying there who wrote it on still.fail. None until ticked; kept for the chat while the app runs. Where
 * it goes is said quietly by send (each mark and place), on one line and opened to write alike: it stays where it is as
 * the composer opens and shuts (said at the row's start once opened, it jumped across: docs/relay.md). Opened to write,
 * 抄送 just before it, opening a menu of the threads to tick: several stay open to tick in turn, one closes once ticked.
 */
function CcChooser({ station, thread, to }: { station: string; thread: number; to: ChatCcTo[] }) {
  const call = useCall();
  const act = useAct();
  const on = to.filter((o) => o.on);
  const where = (o: ChatCcTo) => <span key={o.thread} className={css.ccPlace}><ElsewhereLogo kind={o.via} size={14} />{o.place}</span>;
  return (
    <span className={css.ccTools}>
      <span className={css.ccSwitch}>
        <Chooser side="top" label={t("web-main.composer.ccLabel")}>
          {to.map((o) => (
            <ChooserItem key={o.thread} checked={o.on} stays={to.length > 1} checkEnd
              onSelect={() => act(call("chat.cc", { station, thread, to: o.thread, on: !o.on }), t("web-main.composer.cc", { place: o.place }))}>
              <ElsewhereLogo kind={o.via} size={14} />{o.place}
            </ChooserItem>
          ))}
        </Chooser>
      </span>
      {on.length > 0 && <span className={css.ccState} title={t("web-main.composer.ccOn", { place: on.map((o) => o.place).join("、") })}>{on.map(where)}</span>}
    </span>
  );
}

/**
 * 忽略 under a post that asks what no one has decided (the core's `asked`): the viewer lets it go (`decision.dismiss`:
 * their lists and the bell say nothing of it any more), fading where it is at once (settling.tsx: its room going once
 * out of sight) and back if that fails.
 */
function AskDismiss({ thread, seq, asked, answered }: { thread: number; seq: number; asked: boolean;
  /** Its post answered: pressed no more, faded where it is with the options staying (Decisions.tsx MessageDecision). */
  answered: boolean;
}) {
  const station = useStation().address;
  const call = useCall();
  const act = useAct();
  const [gone, setGone] = useState(false);
  return (
    <Settles shown={asked && !answered && !gone}>
      <button type="button" className={css.askDismiss} onClick={() => {
        setGone(true);
        act(call("decision.dismiss", { station, thread, seq }).catch((e: unknown) => { setGone(false); throw e; }), t("web-main.decisions.dismissWhat"));
      }}>{t("web-main.chat.asks.dismiss")}</button>
    </Settles>
  );
}

/**
 * The way to what waits to be decided in this chat (the core's `asks`: a card no one has answered, or what an agent
 * needs a person for) while its post does not show: a bell, no words, where the way to the chat's end is (over it when
 * both show: `above`). Pressed, the chat goes to the post (jumpTo.ts), then to the next one's the next time, round again.
 */
function ToAsk({ station, thread, asks, above }: { station: string; thread: number; asks: ChatAsk[]; above: boolean }) {
  const [turn, setTurn] = useState(0);
  const next = asks[turn % asks.length]!;
  return (
    <Tip label={t("web-main.chat.asks.go")} side="top">
      {/* Pressed with the cursor in the composer, it stays there. */}
      <button type="button" className={`${css.chatToBottom} ${css.chatToAsk}`} data-above={above || undefined} aria-label={t("web-main.chat.asks.go")}
        onMouseDown={(e) => e.preventDefault()} onClick={() => { jumpTo({ station, thread, seq: next.seq }); setTurn((n) => n + 1); }}>
        <Bell size={16} />
      </button>
    </Tip>
  );
}

const NO_ASKS: ChatAsk[] = [];

/** What waits to be decided in a chat (the core's `asks`): none in one archived or not made yet. */
export function asksOf(chat: ChatView): ChatAsk[] {
  return chat.archived || !chat.thread ? NO_ASKS : chat.asks ?? NO_ASKS;
}

/**
 * While something waits to be decided its bell (ToAsk) may float over the list's end: the end keeps clear of it
 * (`--ask-clear`, added to the list's padding), its last row as far over the bell as it is over the composer without
 * it, not under it (the time, 正在发送 under the viewer's own message, at the column's end where the bell is). `over`:
 * how far the bell's top is over the composer's room.
 */
export function askClear(chat: ChatView, over: number): CSSProperties {
  // (only for one not at the end itself, the core's `askClear`: that one shows whenever the end does, no bell over it)
  return asksOf(chat).length > 0 && chat.askClear ? ({ "--ask-clear": `${over}px` } as CSSProperties) : {};
}

/**
 * What waits to be decided in a chat whose post does not show, for the button that leads to it (ToAsk; the phone's,
 * mobile/Chat.tsx), both screens: the chat's `asks` (none in an archived one), and none at all while each one's post
 * shows in the pane. The pane says which posts do not show (out of it, or under the composer); one outside the window
 * of messages does not.
 */
export function useAsksShown(virtual: VirtualList, chat: ChatView): ChatAsk[] {
  const asks = asksOf(chat);
  const posts = asks.map((a) => a.seq).join(" ");
  const stateAsk = chat.stateAsk;
  const [shown, setShown] = useState(true);
  useEffect(() => {
    if (posts === "") return;
    const { model } = virtual;
    // Each one's post in the pane: among its items, and reaching into it (below what covers its top).
    const check = () => {
      const all = posts.split(" ").every((seq) => {
        // (what an agent needs: where the chat's end says it, its 忽略 under that line)
        const key = Number(seq) === stateAsk ? "state" : `m:${seq}`;
        const top = model.offsetOf(key);
        return top !== undefined && top < model.paneHeight && top + (model.sizes.get(key)?.height ?? 1) > model.covered;
      });
      setShown(all);
    };
    check();
    return virtual.watch(check);
  }, [virtual.model, posts, stateAsk, chat.messages.length]); // eslint-disable-line react-hooks/exhaustive-deps
  return asks.length > 0 && shown ? NO_ASKS : asks;
}

/** The session that keeps a file shown out of its chat (the decisions page), where the core does not say (`owner`). */
export const FileKeeper = createContext<string | null>(null);

/** The session whose workspace keeps a file, which its preview goes through: the core's word, else FileKeeper's. */
function useKeeper(): (file: Attachment) => string | null {
  const keeper = useContext(FileKeeper);
  return (file) => file.owner ?? keeper;
}

/**
 * What a chat's list holds, the same on both screens (this page; the phone's, mobile/Chat.tsx): older pages loading, its
 * messages with the unread line, what is sent from here on its way (`to`: where it goes), and its agents at work.
 * What is done from it (an agent's history or card opened, the chat archived) is done on the page by the chat's key
 * (chatPage.ts); what each message shows beside it (whether its agent is the chat's, 归档, what was sent to Slack after
 * it) the core says on the message.
 */
export function ChatRows({ chat, rows, to }: { chat: ChatView; rows: ReturnType<typeof useMessageList>; to: ChatTo | null }) {
  const { messages, shown, rowOf, caughtAgent, poseOf, virtual, olderPage, newerPage, canOlder, canNewer } = rows;
  // Where a decision's options answer: none while nothing can be sent.
  const thread = chat.offline || chat.archived ? null : chat.thread?.id ?? null;
  const locked = chat.offline || !!chat.archived;
  // What each item is: only those the list makes (virtual/list.tsx) are drawn.
  const visible = new Set(virtual.layout.rows.map((r) => r.key));
  const drawn = new Map<string, () => ReactNode>();
  const sent = (list: ChatSentElsewhere[] | undefined) => { for (const s of list ?? []) if (visible.has(`e:${s.key}`)) drawn.set(`e:${s.key}`, () => <SentElsewhere key={`e:${s.key}`} sent={s} />); };
  drawn.set("older", () => <div key="older" data-vk="older" className={css.chatOlder}>
    {olderPage.failed ? <button type="button" className={css.msgUnsentBtn} onClick={olderPage.retry} aria-label={t("common.retry")}><Retry size={16} />{t("common.retry")}</button> : <Spinner />}
  </div>);
  drawn.set("line", () => <div key="line" data-vk="line" className={css.chatUnreadLine} data-unread-line role="separator"><span>{t("web-main.chat.unreadLine")}</span></div>);
  sent(chat.elsewhere);
  for (const m of messages) {
    if (visible.has(`m:${m.seq}`)) drawn.set(`m:${m.seq}`, () => {
      const { enter, emitted, caught } = rowOf(m);
      return <LinkedChats.Provider key={`m:${m.seq}`} value={m.chats}><MessageRow message={m} enter={enter} emitted={emitted} caught={caught} thread={thread} /></LinkedChats.Provider>;
    });
    sent(m.elsewhere);
  }
  // The page after the window shown, while it is short of the chat's end (`chat.newer`), loading as the reader nears it.
  drawn.set("newer", () => <div key="newer" data-vk="newer" className={css.chatNewer}>
    {newerPage.failed ? <button type="button" className={css.msgUnsentBtn} onClick={newerPage.retry} aria-label={t("common.retry")}><Retry size={16} />{t("common.retry")}</button> : <Spinner />}
  </div>);
  for (const o of chat.outbox) drawn.set(`o:${o.id}`, () => <OutboxRow key={`o:${o.id}`} o={o} to={to} locked={locked} />);
  // Where it stands, as its row says it (the core's `stateText`), whole: done with nothing said, its word after the check.
  // What an agent needs a person for is let go right under the line that says it (the core's `stateAsk`).
  const state = chat.stateText;
  const stateAsk = chat.stateAsk;
  if (state) drawn.set("state", () => <div key="state" data-vk="state">
    <WaitingText text={state} lead={chat.stateLead} rest={chat.stateRest || (chat.stateLead === "done" ? t("web-main.status.done") : chat.stateRest)} className={css.chatState} slot />
    {stateAsk != null && thread !== null && <AskDismiss thread={thread} seq={stateAsk} asked answered={false} />}
  </div>);
  // A reply comes whole, as a message: while an agent works, its activity (always the last thing in the chat) says what it does.
  for (const { agent, leaving } of shown) {
    drawn.set(`a:${agent.key}`, () => <Activity key={`a:${agent.key}`} agent={agent} leaving={leaving} caught={caughtAgent(agent.key)} pose={poseOf(agent.key)} stoppable={chat.agents.length > 1} />);
  }
  const empty = messages.length === 0 && chat.outbox.length === 0 && !chat.elsewhere?.length && !canOlder && !canNewer;
  return (
    <ChatAgents.Provider value={chat.agents}>
    <ChatAgentKeys.Provider value={chat.agents.map((a) => a.session.key).join("\n")}>
      {empty && (
        <div className={css.chatEmpty}>
          <p>{t("web-main.chat.empty")}</p>
        </div>
      )}
      {virtual.layout.rows.flatMap((row, i) => [virtual.above(row, i === 0), drawn.get(row.key)?.()])}
      {virtual.after()}
    </ChatAgentKeys.Provider>
    </ChatAgents.Provider>
  );
}

/**
 * Over the list away from its end: glides down, and follows new messages again (virtual/model.ts); from a window short of the
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
        <DoingShown state={state} idle={<ArrowDown size={16} strokeWidth={2} />} bare />
        {waiting > 0 && <span>{t("web-main.chat.newMessages", { n: waiting })}</span>}
      </button>
    </Tip>
  );
}

const SENDING_SHOWS_MS = 800;

/** A message sent from here that the chat does not show yet: on its way, or failed with a way to send it again or drop it. */
function OutboxRow({ o, to, locked }: { o: Outgoing; to: ChatTo | null; locked: boolean }) {
  const sending = useChatSend();
  const station = useStation().address;
  const toast = useToast();
  const draftKey = useContext(DraftKey);
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
    <MineMessage data-vk={`o:${o.id}`} data-author={t("web-main.chat.you")} data-role="person" data-enter data-unsent={o.state === "failed" || undefined} data-joined={o.joined || undefined}>
      {/* (its images still going up among its files already, drawn from this device: the core's) */}
      <MineWords message={o} />
      {o.uploads?.map((f) => <FileCard key={f.id} file={f} pending={o.state !== "failed"} sent={f.sent} error={o.state === "failed" ? o.error ?? null : null} />)}
      {o.state === "failed"
        // Not sent: said briefly, why in its tip; sending it again or dropping it right beside.
        ? <div className={css.msgUnsent}>
            <Tip label={o.error ? t("web-main.draft.notSent", { error: o.error }) : t("web-main.chat.notSent")}>
              <span className={css.msgUnsentNote}><Info size={12} strokeWidth={2} />{o.final && o.error ? t("web-main.draft.notSent", { error: o.error }) : t("web-main.chat.unsent")}</span>
            </Tip>
            {o.final
              // Refused as it is (a file this station does not have): sent again it would be again. Its words go back to
              // the composer, to be sent anew.
              ? <button type="button" className={css.msgUnsentBtn} disabled={locked || busy || !draftKey}
                  onClick={() => {
                    if (to === null || !draftKey) return;
                    if (!offerToDraft(draftKey, { files: [], text: o.text, quotes: o.quotes.map((q, i) => ({ ...q, id: `${o.id}-${i}` })) })) return;
                    sending.discard(to, o.id).catch((e: unknown) => toast(t("web-main.chat.deleteFailed", { error: failure(e) })));
                  }}>
                  <Edit size={12} strokeWidth={2} />{t("common.edit")}</button>
              : <button type="button" className={css.msgUnsentBtn} disabled={locked || busy} aria-busy={retrying || undefined}
                  onClick={() => { if (to !== null) sending.retry(to, o.id).catch((e: unknown) => toast(t("web-main.chat.resendFailed", { error: failure(e) }))); }}>
                  <DoingShown state={retry} inline idle={<Retry size={12} strokeWidth={2} />} />{t("common.retry")}</button>}
            <button type="button" className={css.msgUnsentBtn} disabled={busy} aria-busy={dropping || undefined}
              onClick={() => { if (to !== null) sending.discard(to, o.id).catch((e: unknown) => toast(t("web-main.chat.deleteFailed", { error: failure(e) }))); }}>
              <DoingShown state={drop} inline idle={<Trash size={12} strokeWidth={2} />} />{t("common.delete")}</button>
          </div>
        // Another sent soon after it: that one says it is on its way.
        : o.followed ? null
        // The station took it: sent, its time under it as its message has it, until its message takes its place.
        : o.state === "sent" ? <Time className={conversationCss.msgTime} stamp={o.time?.createdAt} />
        : <span className={`${conversationCss.msgTime} ${chatCss2.msgWaiting} ${chatCss2.msgSending}`} data-shows-at={showsAt} style={{ animationDelay: delay }}><Spinner inline />{o.waits ?? t("web-main.chat.sending")}</span>}
    </MineMessage>
  );
}

/** How an image of a message in the list is quoted (useSelectionQuote's `images`): none outside a chat's list. */
export const ImageQuote = createContext<ImageQuoting | null>(null);
export interface ImageQuoting {
  /** The pointer over the image `file` (its box `at`): a button over its corner quotes it. */
  over(file: Attachment, at: Element): void;
  /** Off it, to `to`: the button goes, unless that is where it went. */
  off(to: EventTarget | null): void;
  /** Held there (a finger's long press): quoted at once. */
  hold(file: Attachment, at: Element): void;
}

/**
 * Selecting words inside one message of the list offers to quote them (`onQuote`), in a small button over the
 * selection, and beside it to share the message's turn as a picture (`onShare`, by its n); an image of one (`images`,
 * for its files' boxes), a button over its corner, or holding it, quotes the image (its file going again with the
 * message). Answers what the list takes to watch the selection, and the buttons.
 */
export function useSelectionQuote(list: RefObject<HTMLElement | null>, onQuote: (quote: Omit<Quote, "comment">, file?: Attachment) => void, onShare?: (seq: number) => void) {
  const [picked, setPicked] = useState<{ quote: Omit<Quote, "comment">; x: number; y: number; file?: Attachment; seq?: number } | null>(null);
  const latest = useRef(onQuote);
  latest.current = onQuote;
  const [images] = useState((): ImageQuoting => {
    // The image's message, as a quote names it; only one the station has (its ts).
    const of = (file: Attachment, at: Element): Omit<Quote, "comment"> | null => {
      const row = at.closest<HTMLElement>("[data-author][data-ts]");
      if (!row || !list.current?.contains(row)) return null;
      return { author: row.dataset.author!, text: file.name, ts: row.dataset.ts!, role: row.dataset.role === "agent" ? "agent" : "person", file: file.name };
    };
    return {
      over: (file, at) => {
        const quote = of(file, at);
        if (!quote) return;
        const box = at.getBoundingClientRect();
        setPicked({ quote, file, x: box.right - 6, y: box.top + 6 });
      },
      off: (to) => setPicked((p) => (p?.file && !(to instanceof Element && to.closest(`.${css.quoteImagePop}`)) ? null : p)),
      hold: (file, at) => {
        const quote = of(file, at);
        if (!quote) return;
        navigator.vibrate?.(10);
        latest.current(quote, file);
      },
    };
  });
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
    // (a message's row by its n: `m:<n>`; one not sent yet has none)
    const seq = /^m:(\d+)$/.exec(from.dataset.vk ?? "")?.[1];
    setPicked({ quote: { author: from.dataset.author!, text, ...(from.dataset.ts ? { ts: from.dataset.ts } : {}), role }, x: rect.left + rect.width / 2, y: rect.top, ...(seq ? { seq: Number(seq) } : {}) });
  };
  const quote = picked && (
    <button type="button" className={picked.file ? `${css.quotePop} ${css.quoteImagePop}` : css.quotePop} style={{ left: picked.x, top: picked.y }}
      onMouseDown={(e) => e.preventDefault()} onMouseLeave={picked.file ? (e) => images.off(e.relatedTarget) : undefined}
      onClick={() => { onQuote(picked.quote, picked.file); setPicked(null); if (!picked.file) window.getSelection()?.removeAllRanges(); }}>
      <QuoteIcon size={12} strokeWidth={2.2} />{t("web-main.chat.quote")}
    </button>
  );
  const seq = picked?.seq;
  return {
    listProps: { onMouseUp: () => { setTimeout(pick, 0); }, onScroll: () => setPicked(null) },
    images,
    pop: picked && !picked.file && seq !== undefined && onShare ? (
      <div className={css.quotePops} style={{ left: picked.x, top: picked.y }}>
        {quote}
        <button type="button" className={css.quotePop} onMouseDown={(e) => e.preventDefault()}
          onClick={() => { setPicked(null); window.getSelection()?.removeAllRanges(); onShare(seq); }}>
          <Photo size={12} />{t("web-main.chat.shareTurn")}
        </button>
      </div>
    ) : quote,
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
export function useMessageList(list: RefObject<HTMLDivElement | null>, chat: ChatView, place: string, lives: ReadonlyMap<string, Live>, gap: number, cover?: (lead: number) => number) {
  const sending = useChatSend();
  const station = useStation().address;
  const id = chat.thread?.id ?? null;
  const messages = chat.messages;
  // The window shown is short of the chat's end: its bottom is not the end, and what is said waits beyond it.
  const short = !!chat.newer;
  // Whose a message is, the core says.
  const mineOf = (m: ChatMessage) => m.mine;
  // Where the list is and which of its rows are made (virtual/model.ts): told where it opens before its rows are drawn.
  const made = useVirtualModel(place, gap);
  const { model } = made;
  // Where the reader leaves it, the core keeps too, on the device (it opens there next, while nothing is unread, also
  // after a reload): the message at the top of the pane and where its top is, or none at its end. A core from before
  // `chat.place` does not know it.
  const seqOf = useRef(new Map<string, number>());
  seqOf.current = useMemo(() => new Map(messages.map((m) => [m.ts, m.seq])), [messages]);
  const leave = (ts: string | null, offset: number | null) => {
    const seq = ts === null ? null : seqOf.current.get(ts);
    if (id !== null && seq !== undefined) void sending.place(id, seq, seq === null ? null : offset).catch(() => undefined);
  };
  // A message asked to be shown (jumpTo.ts) is where it opens this time, rather than the unread line; so is one its
  // link names (`?message=<seq>`, a notification's: docs/notifications.md), asked for once the link is read.
  const asked = useRef(false);
  const [search, setSearch] = useSearchParams();
  const named = Number(search.get("message"));
  const linked = id !== null && Number.isSafeInteger(named) && named > 0 ? named : null;
  if (useJump(station, id) !== null || linked !== null) asked.current = true;
  useEffect(() => {
    if (linked === null || id === null) return;
    jumpTo({ station, thread: id, seq: linked });
    setSearch((now) => { now.delete("message"); return now; }, { replace: true });
  }, [linked, id, station, setSearch]);
  const divider = chat.unreadLine ?? null;
  // Where it opens, said once its messages are there: where it was left here (`leftAt`), else where the core says it
  // was left (`at`: that message at the top, or where its top was, `atOffset`, when it is the very entry left there);
  // left at its end with nothing new since, at its end, followed. Not for a message asked to be shown.
  const opened = useRef<string | null>(null);
  if (opened.current !== place && messages.length > 0) {
    opened.current = place;
    const saved = leftAt.get(place);
    const core = chat.unreadLine == null && chat.at != null ? messages.find((m) => m.seq >= chat.at!) ?? null : null;
    if (asked.current) { /* useJumpTo takes it there */ }
    else if (saved) {
      const seq = seqOf.current.get(saved.ts);
      if (!(saved.bottom !== null && messages.at(-1)?.ts === saved.bottom) && seq !== undefined) model.goto(`m:${seq}`, "at", saved.offset);
    } else if (core) model.goto(`m:${core.seq}`, core.seq === chat.at && chat.atOffset != null ? "at" : "start", core.seq === chat.at ? chat.atOffset ?? 0 : 0);
  }
  // Something unread, the first time it shows (it may come from the station a moment after opening): the line near the
  // top, with about four lines of what came before it still in view; over where it was left. Opened at a message asked
  // to be shown, the line is drawn and the pane not moved to it.
  const lined = useRef<string | null>(null);
  if (lined.current !== place && divider !== null) {
    lined.current = place;
    if (!asked.current) model.goto("line", "start", 4 * 23);
  }
  // A message sent from here eases in once, from the outbox; its own copy that replaces it does not again.
  const sentHere = useRef(new Set<string>());
  for (const o of chat.outbox) sentHere.current.add(o.text);
  // Only what is said while the chat shows comes in, and an activity only for an agent seen starting meanwhile: the
  // core decides both (attend.ts: `said`, `started`); the rest is there at once.
  const said = useMemo(() => new Set(messages.filter((m) => m.said).map((m) => m.seq)), [messages]);
  const saidHere = (seq: number) => said.has(seq);
  // Only an agent that has taken a message and runs is at work: until then the message itself says it waits.
  const atWork: AgentAtWork[] = chat.agents.filter((a) => a.status === "running").map(({ session, since, wait }) => (
    { key: session.key, who: session.agentText, runtime: session.runtime, maker: session.maker, activity: lives.get(session.key)?.activity ?? null, since, wait }
  ));
  const started = new Set(chat.agents.filter((a) => a.started).map((a) => a.session.key));
  const emissions = useEmissions(list, () => model.mode.kind === "follow");
  const shown = useLinger(atWork, emissions.keeps);
  emissions.take(messages, saidHere, new Set(shown.map((s) => s.agent.key)));

  const emptyWindow = messages.length === 0 && !chat.elsewhere?.length;
  const { older: canOlder, newer: canNewer } = usePagingEdges(emptyWindow, !!chat.more, short, place);

  // The list's items, in order: each a row of its own.
  const heights = useMemo(() => new Map(messages.map((m) => [m.seq, tallOf(m)])), [messages]);
  const items: Item[] = [];
  if (canOlder) items.push({ key: "older", estimate: 30, place: false });
  for (const s of chat.elsewhere ?? []) items.push({ key: `e:${s.key}`, estimate: 64 });
  for (const m of messages) {
    if (m.seq === divider) items.push({ key: "line", estimate: 20 });
    // One waiting to come out of its avatar takes no room, not even the gap before it (the list measures it so): known,
    // not guessed, so that nothing below it moves for a guess and back for the fact.
    items.push(emissions.stateOf(m.seq) === "held" ? { key: `m:${m.seq}`, estimate: 0, exact: -gap } : { key: `m:${m.seq}`, estimate: heights.get(m.seq)! });
    for (const s of m.elsewhere ?? []) items.push({ key: `e:${s.key}`, estimate: 64 });
  }
  if (canNewer) items.push({ key: "newer", estimate: 30, place: false });
  for (const o of chat.outbox) items.push({ key: `o:${o.id}`, estimate: 44 });
  // Where it stands, said only at its end (none while an agent works).
  if (!canNewer && chat.stateText) items.push({ key: "state", estimate: 20 });
  for (const { agent } of shown) items.push({ key: `a:${agent.key}`, estimate: 24, place: false });

  // What changed since it was last drawn: messages gone from an end as the core's window moved along the chat (their
  // room is not held), and messages come at its end (said as the reader watches: followed gliding, the last from its
  // top; caught up on, history read in or missed while the link was down: taken at once).
  const first = messages[0]?.seq;
  const last = messages.at(-1)?.seq;
  const was = useRef({ first, last, place, keys: new Set<string>() });
  const before = was.current.place === place ? was.current : { first: undefined, last: undefined };
  useEffect(() => { was.current = { first, last, place, keys: new Set(items.map((item) => item.key)) }; });
  const trimmed = (before.first !== undefined && first !== undefined && first > before.first) || (before.last !== undefined && last !== undefined && last < before.last);
  const came = before.last !== undefined && last !== undefined && last > before.last ? messages.filter((m) => m.seq > before.last!) : [];
  const smooth = came.length === 0 || came.some((m) => saidHere(m.seq));
  // What came at the list's end is followed from the top of the last of it: a row is come at the end when all that
  // stands after it came with it or is an agent's activity (always the last thing in the chat). A long message come
  // alone is so read from its start; come with its agent's activity after it (a message sent, the agent starting on
  // it), the pane goes on to the end, where the activity is. Not what a chat opens with.
  const had = before === was.current ? was.current.keys : null;
  let arrived: string | null = null;
  if (had && smooth) {
    for (let i = items.length - 1; i >= 0; i--) {
      const key = items[i]!.key;
      const added = !had.has(key);
      if (added) { arrived = key; break; }
      if (!key.startsWith("a:")) break;
    }
  }
  const virtual = useVirtualList(list, made, items, { short, trimmed, smooth, arrived, ...(cover ? { cover } : {}) });
  useQueuedEntries(list);

  usePlace(virtual, place, messages, short, leave);
  // Without a chat there is nothing older (or newer) to load.
  const older = () => (id === null ? Promise.resolve() : sending.older(id));
  // Loaded as far as entries go, not messages: a page of what is not a message here (letters, edits) moves it too.
  const ahead = (edge: "top" | "bottom") => {
    const showing = model.showing();
    const visible = showing ? Array.from({ length: showing.last - showing.first + 1 }, (_, i) => model.keyAt(showing.first + i)!) : [];
    return chatPageAhead(edge, chat.firstEntry, chat.lastEntry, visible);
  };
  const olderPage = useLoadNear(virtual, "top", canOlder, chat.firstEntry ?? chat.messages[0]?.seq, older, () => ahead("top"));
  useJumpTo(list, virtual, station, id, messages, chat.more, older);
  const newer = () => (id === null ? Promise.resolve() : sending.newer(id));
  const newerPage = useLoadNear(virtual, "bottom", canNewer, chat.lastEntry ?? chat.messages.at(-1)?.seq, newer, () => ahead("bottom"));
  useShowing(virtual, station, chat, (seq) => (id === null ? Promise.resolve() : sending.read(id, seq)));
  const away = useAwayFromBottom(virtual);
  const toEnd = useToEnd(list, virtual, chat, () => (id === null ? Promise.resolve() : sending.latest(id)));
  useActivityGlide(list, virtual);
  // The list's own way to one of its messages, for what is drawn in it (a quote's card, a file asked for).
  useEffect(() => {
    const el = list.current;
    if (!el) return;
    lists.set(el, { goto: (ts, align, pad) => { const seq = seqOf.current.get(ts); return seq !== undefined && virtual.goto(`m:${seq}`, align, pad); } });
    return () => { lists.delete(el); };
  }, [list, virtual]);

  // A message comes in (`enter`) only the first time its row is made: made again as the reader scrolls back to it, it
  // is there.
  const gone = useRef(new Set<number>());
  const rowsMade = useRef(new Set<number>());
  const nowMade = new Set(virtual.layout.rows.flatMap((r) => (r.key.startsWith("m:") ? [Number(r.key.slice(2))] : [])));
  for (const seq of rowsMade.current) if (!nowMade.has(seq)) gone.current.add(seq);
  useEffect(() => { rowsMade.current = nowMade; });
  const rowOf = (m: ChatMessage): RowState => {
    const mine = mineOf(m);
    const told = !mine && !m.system;
    const fresh = saidHere(m.seq) && !gone.current.has(m.seq);
    const enter = fresh && !(mine && sentHere.current.has(m.text)) && !(told && emissions.emits(m.seq)) ? true : undefined;
    return { enter, emitted: told ? emissions.stateOf(m.seq) : null, caught: fresh ? undefined : true };
  };
  const caughtAgent = (key: string) => (started.has(key) ? undefined : true);
  // Short of the end, the way there shows wherever the reader is, with how many wait there.
  const waiting = short ? chat.thread?.unread ?? 0 : 0;
  return { olderPage, newerPage, canOlder, canNewer, messages, away: away || short, waiting, toEnd, shown, rowOf, caughtAgent, poseOf: emissions.poseOf, virtual };
}

/**
 * A message come in (eased in: `[data-enter]`, not one sent from here nor one out of its agent's avatar, which take
 * their turns themselves) comes in its turn among what changes the list's height (listQueue.ts): its room not taken
 * till then, it eases in as it takes it.
 */
function useQueuedEntries(list: RefObject<HTMLElement | null>) {
  const seen = useRef(new WeakSet<Element>());
  useLayoutEffect(() => {
    const pane = list.current;
    if (!pane) return;
    // (An outbox row takes the turn what sent it took: words sent from the composer fly into it, madeChat.ts sendingHere;
    // an option picked, Decisions.tsx. One sent otherwise comes in like any other.)
    for (const el of pane.querySelectorAll<HTMLElement>(":scope > [data-enter]")) {
      if (seen.current.has(el)) continue;
      seen.current.add(el);
      // (words flying in from the composer open their own room as they fly: there whole)
      if (el.dataset.vk?.startsWith("o:") && sendingNow()) { el.dataset.grown = ""; continue; }
      if (el.dataset.vk?.startsWith("o:") && claimReserved(el)) { growRow(el); continue; }
      queueRow(el, () => after(motionMs(ENTER.duration)));
    }
  });
}

/** A list's way to one of its messages (by `ts`), by its pane: what is drawn in it finds it there. */
const lists = new WeakMap<HTMLElement, { goto(ts: string, align: Align, pad?: number): boolean }>();

/** About how tall a message stands before it is measured: its lines of words, and what it carries. */
function tallOf(m: ChatMessage): number {
  let breaks = 0;
  for (let i = m.text.indexOf("\n"); i >= 0 && breaks < 60; i = m.text.indexOf("\n", i + 1)) breaks++;
  const lines = Math.min(60, Math.ceil(m.text.length / 48) + breaks);
  return (m.mine ? 44 : 30) + lines * 23 + (m.attachments?.length ?? 0) * 72 + (m.quotes?.length ?? 0) * 56;
}

/**
 * The way to a chat's end, from the button over the list or its shortcut: down the list, gliding, as always; from a
 * window short of the end (`chat.newer`), its latest page in its place first (`latest`), then straight to its bottom,
 * with nothing gliding or coming in. A message sent from such a window takes the reader there the same way (the core
 * does not move the window as it sends: the list asks for the latest page itself); sent from up the list, straight to
 * its bottom.
 */
function useToEnd(list: RefObject<HTMLElement | null>, virtual: VirtualList, chat: ChatView, latest: () => Promise<unknown>): () => void {
  const toast = useToast();
  const short = !!chat.newer;
  // Going to the end: once the latest page is in, the list goes to its bottom.
  const going = useRef(false);
  const isShort = useRef(short);
  isShort.current = short;
  useLayoutEffect(() => {
    if (short || !going.current) return;
    going.current = false;
    virtual.toEnd(true);
  });
  const toLatest = useRef(() => {});
  toLatest.current = () => {
    going.current = true;
    latest().catch((e: unknown) => { going.current = false; toast(t("web-main.chat.toLatestFailed", { error: failure(e) })); });
  };
  // A message sent (the composer says so as it sends, `sent`, rather than the outbox growing: on a quick link the
  // station has it before the outbox ever shows it): from up the list, to its bottom at once, following again; from a
  // window short of the end, its latest page first. Left waiting for the reader to load the rest, the list jumped to
  // the end at once whenever a page they scrolled to reached it.
  useEffect(() => {
    const el = list.current;
    if (!el) return;
    const sent = () => {
      if (isShort.current) toLatest.current();
      else if (virtual.model.mode.kind !== "follow") virtual.toEnd(true);
    };
    el.addEventListener("sent", sent);
    return () => el.removeEventListener("sent", sent);
  }, [list, virtual]);
  return () => {
    if (!short) virtual.toEnd();
    else toLatest.current();
  };
}

/**
 * A message asked to be shown (jumpTo.ts: a row's state line pressed): once it is in the list, scrolled to the top
 * (below what floats there, as the unread line) and flashed, after the list has been put where it opens (the unread
 * line, where it was left). Older than the window: older pages load until it is in; not there at all (a letter, which
 * the chat does not show), nothing.
 */
function useJumpTo(list: RefObject<HTMLDivElement | null>, virtual: VirtualList, station: string, thread: number | null, messages: ChatMessage[], more: boolean | undefined, older: () => Promise<unknown>) {
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
    // Its top near the pane's, below what floats over it there (the phone's bar), as the unread line; then, its row
    // made, flashed (or the words a search found in it marked).
    let frame = requestAnimationFrame(() => {
      const words = jumpWords();
      jumped();
      virtual.goto(`m:${seq}`, "start", 12);
      frame = requestAnimationFrame(() => {
        const pane = list.current;
        const target = pane?.querySelector<HTMLElement>(`.${conversationCss.msg}[data-ts="${CSS.escape(message.ts)}"]`);
        if (!pane || !target) return;
        // Opened from a search: the words found marked in it (kept until the chat is left), the first in view.
        if (words?.length && markWords(target, words)) {
          const first = searchHits[0]!.getBoundingClientRect();
          const box = pane.getBoundingClientRect();
          if (first.bottom > box.bottom) virtual.goto(`m:${seq}`, "at", box.height / 2 - (first.top + first.height / 2 - target.getBoundingClientRect().top));
          return;
        }
        target.classList.remove(css.msgFlash);
        void target.offsetWidth;
        target.classList.add(css.msgFlash);
      });
    });
    return () => cancelAnimationFrame(frame);
  }, [seq, messages, more]); // eslint-disable-line react-hooks/exhaustive-deps
  // The words a search marked go when the chat does.
  useEffect(() => () => unmarkWords(), [station, thread]);
}

/** Where the words a search found are marked in the message it opened: bold (CSS custom highlights: `search-hit`), and
 *  a hand-drawn stroke under each, drawn in left to right one word after another (`[data-search-marks]`, global.css.ts). */
let searchHits: Range[] = [];
let searchStrokes: { layer: HTMLElement; observer: ResizeObserver } | null = null;

/** The strokes under `ranges`, in a layer over `root` (its box, so they move with it); laid out again as it resizes. */
function drawStrokes(root: HTMLElement, ranges: Range[]): void {
  const layer = strokeLayer(root);
  const place = () => placeStrokes(layer, root, ranges);
  place();
  // Laid out again (the pane resized): drawn where the words are now, not drawn in again.
  let first = true;
  const observer = new ResizeObserver(() => {
    if (first) { first = false; return; }
    layer.dataset.settled = "";
    place();
  });
  observer.observe(root);
  searchStrokes = { layer, observer };
}

/** Marks each of `words` (case aside) in the text of `root`; false when none is in it (or the browser cannot). */
function markWords(root: Element, words: string[]): boolean {
  unmarkWords();
  if (!("highlights" in CSS)) return false;
  const wanted = words.map((w) => w.toLowerCase()).filter((w) => w !== "");
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  const ranges: Range[] = [];
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    const node = n as Text;
    const lower = node.data.toLowerCase();
    if (lower.length !== node.data.length) continue;
    for (const w of wanted) {
      for (let at = lower.indexOf(w); at >= 0; at = lower.indexOf(w, at + w.length)) {
        const range = document.createRange();
        range.setStart(node, at);
        range.setEnd(node, at + w.length);
        ranges.push(range);
      }
    }
  }
  if (!ranges.length) return false;
  ranges.sort((a, b) => a.compareBoundaryPoints(Range.START_TO_START, b));
  searchHits = ranges;
  const highlights = (CSS as unknown as { highlights: Map<string, unknown> }).highlights;
  const Highlight = (window as unknown as { Highlight: new (...r: Range[]) => unknown }).Highlight;
  highlights.set("search-hit", new Highlight(...ranges));
  if (root instanceof HTMLElement) drawStrokes(root, ranges);
  return true;
}

function unmarkWords(): void {
  searchHits = [];
  searchStrokes?.observer.disconnect();
  searchStrokes?.layer.remove();
  searchStrokes = null;
  if ("highlights" in CSS) (CSS as unknown as { highlights: Map<string, unknown> }).highlights.delete("search-hit");
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
/** Whether the reader is scrolled up, away from the newest messages (more than a screenful's corner). */
export function useAwayFromBottom(virtual: VirtualList): boolean {
  const [away, setAway] = useState(false);
  useEffect(() => {
    const check = () => setAway(virtual.model.toEnd > 120);
    check();
    return virtual.watch(check);
  }, [virtual.model]); // eslint-disable-line react-hooks/exhaustive-deps
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
function usePlace(virtual: VirtualList, key: string, messages: ChatMessage[], short: boolean, onLeave: (ts: string | null, offset: number | null) => void): void {
  const latest = useRef({ short, onLeave, messages });
  latest.current = { short, onLeave, messages };
  const { model } = virtual;
  /** Where the reader is: the first message showing and where its top is, and the last message if at the end. */
  const where = useCallback(() => {
    const { messages, short } = latest.current;
    const showing = model.showing();
    if (!showing) return null;
    const tsOf = new Map(messages.map((m) => [`m:${m.seq}`, m.ts]));
    for (let i = showing.first; i <= showing.last; i++) {
      const item = model.keyAt(i);
      const ts = item === undefined ? undefined : tsOf.get(item);
      if (ts === undefined) continue;
      const end = !short && model.mode.kind === "follow";
      return { ts, offset: model.offsetOf(item!)!, bottom: end ? messages.at(-1)?.ts ?? null : null };
    }
    return null;
  }, [model]);
  /** What was last told (`onLeave`), so the same is not told again. */
  const told = useRef<string | null>(null);
  const tell = useCallback((at: { ts: string; offset: number; bottom: string | null }) => {
    const ts = at.bottom !== null ? null : at.ts;
    const offset = ts === null ? null : Math.round(at.offset * 10) / 10;
    const said = JSON.stringify([ts, offset]);
    if (said === told.current) return;
    told.current = said;
    latest.current.onLeave(ts, offset);
  }, []);
  useEffect(() => {
    // Told once the pane comes to rest, where the reader put it (not where it opened).
    let rest: ReturnType<typeof setTimeout> | undefined;
    let at = model.layout().scrollTop;
    const stop = virtual.watch(() => {
      const now = model.layout().scrollTop;
      if (now === at) return;
      at = now;
      clearTimeout(rest);
      rest = setTimeout(() => {
        const here = where();
        if (here) { leftAt.set(key, here); tell(here); }
      }, REST_MS);
    });
    // Told as the page goes: the model says where it was.
    return () => {
      stop();
      clearTimeout(rest);
      const here = where();
      if (here) { leftAt.set(key, here); tell(here); }
      else if (!latest.current.short) latest.current.onLeave(null, null);
    };
  }, [model, key, where, tell]); // eslint-disable-line react-hooks/exhaustive-deps
}

/** How long the pane stays still before where the reader is gets told (`useRememberPlace`). */
const REST_MS = 400;

/**
 * Tells the core this page shows the chat, and whether its end (`floor`) is in view: what is read, where the unread
 * line goes and which notices are not shown follow from it there (client/core-ts/src/attend.ts).
 */
export function useShowing(virtual: VirtualList, station: string, chat: ChatView, read: (seq: number) => Promise<unknown>): void {
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
    const { model } = virtual;
    const of = { station, thread, session };
    const tell = () => void core().focus({ chat: { ...of, end: old.current.end && !short.current } }).catch((e: unknown) => {
      if ((e as { code?: string }).code === "unknown_call") { old.current.on = true; readHere(); }
    });
    tell();
    // Its end in view: the pane within a few pixels of the last of what it scrolls.
    const stop = virtual.watch(() => {
      const end = model.paneHeight > 0 && model.toEnd <= 4;
      if (end === old.current.end) return;
      old.current.end = end;
      if (old.current.on) readHere(); else tell();
    });
    document.addEventListener("visibilitychange", readHere);
    return () => {
      stop();
      document.removeEventListener("visibilitychange", readHere);
      void core().focus({ left: of }).catch(() => undefined);
    };
  }, [virtual.model, station, thread, session, readHere]); // eslint-disable-line react-hooks/exhaustive-deps
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
const MessageRow = memo(function MessageRow({ message: m, enter, emitted, caught, thread, options = true }: {
  message: ChatMessage; enter: true | undefined; emitted: "held" | "emitting" | null; caught: true | undefined;
  /** Its chat's thread, where a decision's options answer (Decisions.tsx); null while nothing can be sent there. */
  thread: number | null;
  /** A decision's options under it (the decisions page has them at its foot instead). */
  options?: boolean;
}) {
  const chat = useContext(DraftKey);
  if (m.mine) {
    return (
      <MineMessage data-vk={`m:${m.seq}`} data-outgoing={m.outgoing} data-author={t("web-main.chat.you")} data-ts={m.ts} data-role="person" data-enter={enter} data-caught={caught} data-joined={m.joined || undefined}>
        <MineWords message={m} />
        {/* Not taken by its agents yet: after a second it says it waits (the delay is the stylesheet's). Their next
            message soon after: under that one instead, close under this. */}
        {m.followed ? null : m.blocked && m.blocked.state !== "installed" ? <BlockedLine install={m.blocked} /> : m.waiting
          ? <span className={`${conversationCss.msgTime} ${chatCss2.msgWaiting} ${css.msgWaitingLate}`}><Spinner inline />{t("web-main.chat.waitingAgent")}</span>
          : <Time className={conversationCss.msgTime} stamp={m.time?.createdAt} />}
      </MineMessage>
    );
  }
  // What still.fail itself says (a limit hit, a failure): a notice across the chat, not someone's message.
  if (m.system) return <SystemNotice vk={`m:${m.seq}`} notice={m.notice ?? { failed: false, words: m.text }} profile={m.profile} install={m.install} report={m.reportable ? { thread: m.thread, seq: m.seq } : undefined} time={m.time?.createdAt} ts={m.ts} enter={enter} caught={caught} />;
  const who = m.by.name;
  const agent = m.by.here ? m.by.agent : undefined;
  const ask = m.card?.vaultAsk;
  return (
    <OthersMessage data-vk={`m:${m.seq}`} data-seq={m.seq} data-author={who} data-ts={m.ts} data-role={m.authorKind === "agent" ? "agent" : "person"}
      data-enter={enter} data-caught={caught} data-held={emitted === "held" || undefined} data-emitting={emitted === "emitting" || undefined} data-covered={emitted === "emitting" || undefined}
      avatar={<MessageAvatar message={m} name={who} agent={agent} />} time={m.time?.createdAt}
      name={agent
        ? <AgentHover agent={agent}><button type="button" className={`${css.msgName} ${css.msgAgent}`} onClick={() => { if (chat) chatPage.agent(chat, agent); }}>{who}</button></AgentHover>
        // Another chat's agent: its name opens that chat (its link, as the chat pages open still.fail's links).
        : m.by.from ? <a href={m.by.from} className={`${css.msgName} ${css.msgAgent}`}>{who}</a>
        : <span className={css.msgName}>{who}</span>}>
      <Quotes quotes={m.quotes} files={m.attachments} />
      {/* An agent's request about a vault item, as its card says it (VaultAsk.tsx): the card in place of its words,
          answered or turned down on it (nothing to set aside: once decided it is a line). */}
      {ask
        ? <VaultAsk message={m} ask={ask} rows={options} />
        : m.authorKind === "person"
        ? <>{m.text && <PersonWords text={m.text} />}<Files files={besideQuotes(m.quotes, m.attachments)} /></>
        : <ProseWithFiles text={m.text} md={m.md as Md | undefined} files={besideQuotes(m.quotes, m.attachments)} session={m.by.agent ?? null} from={m.by.from} />}
      {/* An agent's post asking to decide: its options right under it, or how it was settled (Decisions.tsx). */}
      {/* It asks what no one has decided (the core's `asked`): letting it go, right under it, closing with its options. */}
      {ask ? null : options && (m.card || m.options?.length) && !(m.card?.type === "login" && m.card.login)
        ? <MessageDecision message={m} thread={thread}>{thread !== null && <AskDismiss thread={thread} seq={m.seq} asked={!!m.asked} answered={!!(m.decision?.resolved || m.decision?.dismissed)} />}</MessageDecision>
        : <>
          {options && (m.card || m.options) && <MessageDecision message={m} thread={thread} />}
          {options && thread !== null && <AskDismiss thread={thread} seq={m.seq} asked={!!m.asked} answered={false} />}
        </>}
    </OthersMessage>
  );
}, (a, b) => a.enter === b.enter && a.emitted === b.emitted && a.thread === b.thread && a.options === b.options && sameMessage(a.message, b.message));

/**
 * What an agent of the chat said in Slack rather than here, or a person's Slack message it was given (the core reads
 * them from its transcript; the chat does not keep them): drawn as a message of theirs, Slack's mark on the avatar and
 * where it went or came from after its name telling it apart.
 */
const SentElsewhere = memo(function SentElsewhere({ sent: s }: { sent: ChatSentElsewhere }) {
  const chat = useContext(DraftKey);
  const agent = s.by.here ? s.by.agent : undefined;
  const received = s.received === true;
  const kind = s.place?.surface;
  const place = s.place
    ? <><ElsewhereLogo kind={kind} size={12} /><span className={historyCss.hPlaceName}>{s.place.name}</span></>
    : <><SlackLogo size={12} /><span className={historyCss.hPlaceName}>Slack</span></>;
  return (
    <OthersMessage data-vk={`e:${s.key}`} data-role={received ? "person" : "agent"} data-author={s.by.name} data-elsewhere="" time={s.time?.createdAt}
      avatar={received
        ? <span className={`${chatCss2.msgAvatar} ${css.msgAvatarSlackHolder}`} data-slack="">{s.by.picture ? <img className={css.msgAvatarSlackPicture} src={s.by.picture} alt="" width={18} height={18} referrerPolicy="no-referrer" /> : <Avatar id={s.by.name} name={s.by.name} size={18} />}<span className={css.msgAvatarSlack}><ElsewhereLogo kind={kind} size={9} /></span></span>
        : <AgentAvatar maker={s.by.maker} runtime={s.by.runtime} slack={kind === "feishu" ? "feishu" : true} agent={agent} />}
      name={agent
        ? <AgentHover agent={agent}><button type="button" className={`${css.msgName} ${css.msgAgent}`} onClick={() => { if (chat) chatPage.agent(chat, agent); }}>{s.by.name}</button></AgentHover>
        : <span className={css.msgName}>{s.by.name}</span>}
      route={
        <span className={css.msgRoute}>
          {received ? <Received {...ICON} size={14} /> : <Send {...ICON} size={14} />}
          {t(received ? "web-main.chat.fromSlack" : "web-main.history.sentTo")}
          {s.place?.url
            ? <a className={historyCss.hPlace} href={s.place.url} target="_blank" rel="noopener">{place}</a>
            : <span className={historyCss.hPlace}>{place}</span>}
          {s.failed && <Pill tone="red">{t("web-main.history.sendFailed")}</Pill>}
        </span>
      }>
      <div className={conversationCss.markdown}><Prose>{s.text}</Prose></div>
      <Files files={s.attachments} />
    </OthersMessage>
  );
}, (a, b) => JSON.stringify(a.sent) === JSON.stringify(b.sent));

/** A message as a chat draws it, out of its chat (the decisions page): still, its name plain, no options under it. */
export function StaticMessage({ message, keeper }: { message: ChatMessage; /** The session that keeps its files. */ keeper: string }) {
  return (
    <FileKeeper.Provider value={keeper}>
      <LinkedChats.Provider value={message.chats}><MessageRow message={message} enter={undefined} emitted={null} caught={undefined} thread={null} options={false} /></LinkedChats.Provider>
    </FileKeeper.Provider>
  );
}

/**
 * A chat's messages made up, for what its page shows while it is read (in their bones), as its list draws them: in a
 * list of `className` (the wide screen's, unless said).
 */
export function ChatSample({ className = `${sessionCss.chatList} ${css.chatMessages}` }: { className?: string }) {
  return <div className={className}>{SAMPLE_MESSAGES.map((m) => <StaticMessage key={m.seq} message={m} keeper="" />)}</div>;
}
const SAMPLE_MESSAGES = sampleMessages();

type Data = { [key: `data-${string}`]: string | number | boolean | undefined };

/** A viewer's own message as a chat draws it (on the right); its bubble is MineBubble. Also where else messages are shown so. */
export function MineMessage({ children, ...data }: Data & { children: ReactNode }) {
  return <div className={`${conversationCss.msg} ${chatCss2.msgMine}`} {...data}>{children}</div>;
}

/** What a viewer's own message says, its quotes and files with it: the same whether the station has it yet (a
 * MessageRow) or it is still on its way (an OutboxRow), so it does not change as the one takes the other's place. */
function MineWords({ message: m }: { message: Pick<ChatMessage, "text" | "quotes" | "attachments"> }) {
  return (
    <>
      <Quotes quotes={m.quotes} files={m.attachments} />
      <MineBubble text={m.text} />
      <Files files={besideQuotes(m.quotes, m.attachments)} />
    </>
  );
}

/** The words of a viewer's own message, in their bubble. */
export function MineBubble({ text }: { text: string }) {
  return text ? <div className={conversationCss.msgBubble}><PersonWords text={text} /></div> : null;
}

/** What a person wrote, as every message of a person's draws it (their own in its bubble, someone else's as it is):
 * plain text, its references to chats as chips and its web addresses as links. */
export function PersonWords({ text }: { text: string }) {
  return <div className={chatCss2.msgPlain}><WithRefs text={text} words={withBareLinks} /></div>;
}

/**
 * What still.fail itself says: a pill across the chat, in one line and no time. A click opens it: all its words, wrapped,
 * and its time under it. The station begins its failures with ⚠️ (Slack shows it so); here a failure is the pill in
 * red instead. In one about a profile (its sign-in failed), what went wrong (after its ：) links to that profile's page.
 * One saying the station does not have the chat's runtime, with none of the viewer's messages waiting for it (those say
 * it under them: BlockedLine), ends in installing it.
 */
function SystemNotice({ notice, profile, install, report, time, ts, enter, caught, vk }: { notice: NoticeShown; profile: string | undefined; install: RuntimeInstall | undefined; /** A failure the viewer may report (core `reportable`): its entry. */ report?: { thread: number; seq: number } | undefined; time: Stamp | undefined; ts: string | undefined; enter: true | undefined; caught: true | undefined; /** Its item's key in a list (virtual/list.tsx). */ vk?: string }) {
  const station = useStation();
  // As the core says it (notice.ts): a line of the UI, a failure's ⚠️ taken for its red, where a profile's link begins.
  const { failed, words: said, linkAt } = notice;
  const [open, setOpen] = useState(false);
  const toggle = () => setOpen((o) => !o);
  return (
    <div className={`${conversationCss.msg} ${css.msgSystem}`} data-vk={vk} data-ts={ts} data-role="system" data-enter={enter} data-caught={caught} role="note">
      <div className={css.msgSystemBox} data-failed={failed ? "" : undefined} data-open={open || undefined}
        role="button" tabIndex={0} aria-expanded={open}
        onClick={(e) => { if (!(e.target as Element).closest("a, button")) toggle(); }}
        onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); toggle(); } }}>
        <div className={css.msgSystemLine}>
          <div className={conversationCss.markdown}>
            {profile && linkAt !== undefined
              ? <p>{said.slice(0, linkAt)}<Link className={css.msgSystemLink} to={`${stationBase(station.address)}/settings/accounts/${encodeURIComponent(profile)}`}>{said.slice(linkAt)}</Link></p>
              : install ? <p>{said}<InstallAction install={install} /></p> : <Prose md={notice.md as Md | undefined}>{said}</Prose>}
          </div>
          {report && <ReportAction thread={report.thread} seq={report.seq} />}
        </div>
      </div>
      {open && <Time className={conversationCss.msgTime} stamp={time} />}
    </div>
  );
}

/**
 * Under the viewer's message that waits for a runtime the station does not have (core `blocked`), in place of its
 * waiting: how that stands, in red while nothing is under way, and installing it. The whole line is what installs it
 * (as a message not delivered is sent again from its line), so it is as big to press as it is wide. Once installed it
 * waits again.
 */
function BlockedLine({ install }: { install: RuntimeInstall }) {
  const stuck = install.state === "missing" || install.state === "failed";
  const { busy, run } = useInstall(install);
  const words = (
    <>
      {install.state === "installing" ? <Spinner inline /> : stuck && <span className={partsCss.failedMark} style={{ width: 12, height: 12, fontSize: 8 }} aria-hidden>!</span>}
      <span className={css.blockedWords}>{install.title}{install.state === "installing" && install.percent != null && ` ${install.percent}%`}</span>
      {install.note && !install.action && <><span className={css.blockedDot} aria-hidden>·</span><span className={css.blockedWords}>{install.note}</span></>}
      {install.action && <><span className={css.blockedDot} aria-hidden>·</span><span className={css.blockedAction}>{install.action}</span></>}
    </>
  );
  const className = `${conversationCss.msgTime} ${css.blocked}`;
  return install.action
    ? <button type="button" className={className} data-stuck={stuck || undefined} title={install.detail} disabled={busy} aria-busy={busy || undefined} onClick={run}>{words}</button>
    : <span className={className} data-stuck={stuck || undefined} title={install.detail ?? install.note}>{words}</span>;
}

/** Installing a notice's runtime: whether it is under way here, and doing it (software.update; a manager's: `action`). */
function useInstall(install: RuntimeInstall) {
  const station = useStation().address;
  const busy = useDoing("software.update", { station, id: install.runtime });
  const api = useApi();
  const act = useAct();
  return { busy, run: () => { if (install.action) act(api.updateSoftware(install.runtime), install.action); } };
}

/** Installing a runtime the station does not have, a word at the end of a notice that says so. */
function InstallAction({ install }: { install: RuntimeInstall }) {
  const { busy, run } = useInstall(install);
  if (!install.action) return null;
  return <><span className={css.blockedDot} aria-hidden>·</span><button type="button" className={css.blockedAction} disabled={busy} aria-busy={busy || undefined} onClick={run}>{install.action}</button></>;
}

/** Sending a failure notice to the still.fail team, a word at its end (out of its words, so a long one cut short keeps
 * it): asked first, saying when to and what goes; what it was filed as is said once sent. */
function ReportAction({ thread, seq }: { thread: number; seq: number }) {
  const station = useStation().address;
  const busy = useDoing("chat.report", { station, thread, seq });
  const call = useCall();
  const toast = useToast();
  const act = useAct();
  const [asking, setAsking] = useState(false);
  const action = t("common.report.action");
  const run = () => {
    setAsking(false);
    act(call("chat.report", { station, thread, seq }).then((a) => {
      const answer = a as { number?: number; duplicate?: boolean } | null;
      toast(t(answer?.duplicate ? "common.report.again" : "common.report.done", { number: answer?.number ?? "?" }));
    }), action);
  };
  return (
    <span className={css.msgSystemEnd}>
      <span className={css.blockedDot} aria-hidden>·</span>
      <button type="button" className={css.blockedAction} disabled={busy} aria-busy={busy || undefined} onClick={() => setAsking(true)}>{action}</button>
      <Dialog open={asking} title={t("common.report.title")} description={t("common.report.lead")} onClose={() => setAsking(false)}
        footer={<><Button variant="ghost" onClick={() => setAsking(false)}>{t("common.cancel")}</Button><Button variant="primary" onClick={run}>{action}</Button></>}>
        <p className={css.reportSends}>{t("common.report.sends")}</p>
      </Dialog>
    </span>
  );
}

/** Someone else's message as a chat draws it: `avatar`, then `name` and `time` over what it says; `route` (where it
 * went or came from, when not here) between the two. */
export function OthersMessage({ avatar, name, route, time, children, ...data }: Data & { avatar: ReactNode; name: ReactNode; route?: ReactNode; time: Stamp | undefined; children: ReactNode }) {
  return (
    <div className={`${conversationCss.msg} ${css.msgRow}`} {...data}>
      {avatar}
      <div className={css.msgMain}>
        <div className={conversationCss.msgHead}>
          {name}
          {route}
          <Time className={conversationCss.msgTime} stamp={time} />
        </div>
        {children}
      </div>
    </div>
  );
}

/** An agent's picture in a chat: its model's maker, in the agents' ground. One of the chat's (`agent`, its session's key)
 * has its card while it is pointed at (AgentCard.tsx). */
export function AgentAvatar({ maker, runtime, slack, agent }: { maker: Maker | null | undefined; runtime: RuntimeKind | null | undefined; slack?: boolean | "feishu"; agent?: string | undefined }) {
  return (
    <AgentHover agent={agent}>
      <span className={`${chatCss2.msgAvatar} ${css.msgAvatarAgent}`} data-slack={slack || undefined}>
        {maker || runtime ? <ModelLogo maker={maker} runtime={runtime ?? "claude"} size={12} /> : <Mark size={12} />}
        {/* What it said went to Slack, not here: Slack's mark on its corner. */}
        {slack && <span className={css.msgAvatarSlack}><ElsewhereLogo kind={slack === "feishu" ? "feishu" : "slack"} size={9} /></span>}
      </span>
    </AgentHover>
  );
}

/** An agent's words as a chat draws them (Markdown). */
export function AgentWords({ text }: { text: string }) {
  return <div className={conversationCss.markdown}><Prose>{text}</Prose></div>;
}

/** An agent's name over its message. */
export function MessageName({ children }: { children: ReactNode }) {
  return <span className={css.msgName}>{children}</span>;
}

function MessageAvatar({ message, name, agent }: { message: ChatMessage; name: string; agent: string | undefined }) {
  if (message.authorKind === "agent") return <AgentAvatar maker={message.by.maker} runtime={message.by.runtime} agent={agent} />;
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
function Quotes({ quotes, files }: { quotes: Quote[] | undefined; files: Attachment[] | undefined }) {
  const owner = useKeeper();
  if (!quotes?.length) return null;
  // In the list the card is in: each screen's (and the phone's pages under the one on top) has its own.
  const jump = (from: Element, ts: string, text: string) => {
    const pane = from.closest<HTMLElement>(`.${css.chatMessages}`);
    const way = pane ? lists.get(pane) : undefined;
    // Its message's middle at the pane's, by the list (its row made if it was not); then, its row there, the quoted
    // words at the middle and flashed, or the whole message.
    if (!pane || !way?.goto(ts, "center")) return;
    requestAnimationFrame(() => {
      const target = pane.querySelector<HTMLElement>(`[data-ts="${CSS.escape(ts)}"]`);
      if (!target) return;
      const range = findText(target, text);
      if (range) {
        const rect = range.getBoundingClientRect();
        const box = pane.getBoundingClientRect();
        way.goto(ts, "at", box.height / 2 - (rect.top + rect.height / 2 - target.getBoundingClientRect().top));
        flashRange(range);
        return;
      }
      target.classList.remove(css.msgFlash);
      void target.offsetWidth;
      target.classList.add(css.msgFlash);
    });
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
function ProseWithFiles({ text, md, files, session = null, from }: {
  text: string;
  /** `text` as the core read it (the message's `md`). */ md?: Md | undefined;
  files: Attachment[] | undefined;
  /** Its agent's: the files its paths name are that session's (Peeks.tsx). */ session?: string | null;
  /** Another chat's agent wrote it (session_send): its link, whose session (and station) the paths are of. */ from?: string | undefined;
}) {
  const { placed, rest } = useMemo(() => placeFiles(text, files), [text, files]);
  const here = useStation().address;
  const paths = useMemo(() => {
    if (session !== null) return { key: session };
    const of = from ? chatOfLink(from) : null;
    // A local page knows only its own station: the link's station is taken to be it.
    return of ? { key: of.id, ...(here.includes("/") && of.station !== here ? { station: of.station } : {}) } : null;
  }, [session, from, here]);
  // The same function while the keeper is: a new one each render would have Prose parse the text again whenever this
  // draws (its station's context changing draws every message's).
  const keeper = useContext(FileKeeper);
  const file = useCallback((f: Attachment, as: "shown" | "link", words?: ReactNode) => as === "link" ? <FileLink sessionKey={f.owner ?? keeper} file={f}>{words}</FileLink> : <PlacedFile sessionKey={f.owner ?? keeper} file={f} />, [keeper]);
  return (
    <>
      <div className={conversationCss.markdown}>
        <PathSession.Provider value={paths}><Prose md={md} files={placed} file={file}>{text}</Prose></PathSession.Provider>
      </div>
      <Files files={rest} />
    </>
  );
}

/**
 * A file the text places on a line of its own: an HTML one is a visualization, drawn there (Viz.tsx; how agents make
 * one is the ember-viz skill), any other shows as below the text.
 */
function PlacedFile({ sessionKey, file }: { sessionKey: string | null; file: Attachment }) {
  const tick = useContext(FileTick);
  if (tick) return tick(file, sessionKey);
  if (sessionKey !== null && kindOf(file.name).kind === "html") return <VizFile sessionKey={sessionKey} file={file} failed={<FileItem sessionKey={sessionKey} file={file} />} />;
  return <FileItem sessionKey={sessionKey} file={file} />;
}

/**
 * In a picture being made of the chat (Publish.tsx): what its messages' files are drawn as, each to tick (as it looks
 * in the chat, FileLook), in place of each to open.
 */
export const FileTick = createContext<((file: Attachment, sessionKey: string | null) => ReactNode) | null>(null);

/**
 * A link that names one of the chat's files (`?file=<name>`: what a post to Slack attached, which stays here): the
 * latest one of that name opens on its own (OpenFile: beside the chat, or over it on a phone), its message brought
 * into view. Anything else that name opens in a preview.
 */
export function useAskedFile(list: RefObject<HTMLDivElement | null>, messages: ChatMessage[]): ReactNode {
  const [search, setSearch] = useSearchParams();
  const open = useContext(OpenFile);
  const asked = search.get("file");
  const found = useMemo(() => {
    if (!asked) return null;
    for (let i = messages.length - 1; i >= 0; i--) {
      const file = messages[i]!.attachments?.find((f) => f.name === asked);
      const key = file?.owner ?? null;
      if (file && key !== null) return { file, key, ts: messages[i]!.ts };
    }
    return null;
  }, [asked, messages]);
  const drawn = !!found && !!open && kindOf(found.file.name).kind === "html";
  const done = () => setSearch((now) => { now.delete("file"); return now; }, { replace: true });
  useEffect(() => {
    if (!found || !drawn) return;
    open!(found.key, found.file);
    if (list.current) lists.get(list.current)?.goto(found.ts, "center");
    done();
  }, [found, drawn]); // eslint-disable-line react-hooks/exhaustive-deps
  if (!found || drawn) return null;
  return <FilePreview open onClose={done} sessionKey={found.key} file={found.file} />;
}

/** A message's files, each through the session that keeps it (none: it cannot show). */
function Files({ files }: { files: Attachment[] | undefined }) {
  const owner = useKeeper();
  if (!files?.length) return null;
  // One still going up is on no station yet: drawn from this device alone.
  const tick = useContext(FileTick);
  return <div className={css.msgFiles}>{files.map((f) => {
    const sessionKey = f.upload && f.path === uploadImageKey(f.upload) ? null : owner(f);
    return tick ? <Fragment key={f.upload ?? f.path}>{tick(f, sessionKey)}</Fragment> : <FileItem key={f.upload ?? f.path} sessionKey={sessionKey} file={f} />;
  })}</div>;
}

/** Images already brushed in on this page (session key and path): shown again, they just show. */
const revealed = new Set<string>();

/**
 * Images and video stills load near the screen; other files are a card. Either opens in a preview, an image's whether
 * its thumbnail has come or not (the preview fetches the image itself, showing how far it has come).
 */
function FileItem({ sessionKey, file }: { sessionKey: string | null; file: Attachment }) {
  const station = useStation();
  const quoting = useContext(ImageQuote);
  // Held to quote it: the tap the finger's lifting makes does not open it too.
  const held = useRef(false);
  const image = isImage(file.name);
  const video = kindOf(file.name).kind === "video";
  const [videoFailed, setVideoFailed] = useState(false);
  const box = useRef<HTMLButtonElement>(null);
  const near = useNear(box, image || video);
  // One here already is drawn at once, near the screen or not yet known to be (its row just made again).
  const [here] = useState(() => image && sessionKey !== null && fileHere(station.address, sessionKey, file, true));
  const fetched = useFileShown(sessionKey ?? "", file, image && sessionKey !== null && (near || here), true);
  const still = useVideoStill(sessionKey ?? "", file, video && sessionKey !== null && near);
  const [local] = useState(() => image ? sentImage(station.address, sentFileKey(file)) : undefined);
  const url = local ?? fetched.url;
  const failed = !local && fetched.failed;
  const [open, setOpen] = useState(false);
  // Downloaded by the core (asked from its preview, chatDownloads.ts): how far, on its card (✕ calls it off, ↻ asks a
  // failed one again) or a video's block.
  const download = useDownload(station.address, image ? null : sessionKey, storedName(file));
  // An image seen before, or that comes at once, just shows; one that takes a while is brushed in from the top.
  const born = useRef(performance.now());
  const key = `${sessionKey}\n${file.path}`;
  const [loaded, setLoaded] = useState<"instant" | "reveal" | null>(local || (url && revealed.has(key)) ? "instant" : null);
  const shown = () => {
    setLoaded(local || revealed.has(key) || performance.now() - born.current < 150 ? "instant" : "reveal");
    revealed.add(key);
  };
  // Its picture already decoded (the same URL drawn before): shown before this frame is painted, not after its load
  // event, a frame or more later, the placeholder showing meanwhile.
  const img = useRef<HTMLImageElement>(null);
  useLayoutEffect(() => {
    if (loaded === null && img.current?.complete && img.current.naturalWidth > 0) shown();
  }, [url]); // eslint-disable-line react-hooks/exhaustive-deps
  const preview = sessionKey !== null && <FilePreview open={open} onClose={() => setOpen(false)} sessionKey={sessionKey} file={file} />;
  const { letterbox, ...size } = look.box(file, video ? 96 : undefined);
  // (one still going up: on no station yet, its play mark on black alone, opening nothing)
  if (video) {
    return (
      <>
        <Tip label={file.name}><button ref={box} type="button" className={`${look.image} ${css.msgVideo}`} data-viewer-thumb={sessionKey !== null ? thumbId(station.address, sessionKey, file.path) : undefined} onClick={() => { if (sessionKey !== null) setOpen(true); }} aria-label={t(videoFailed ? "web-main.file.view" : "web-main.file.play", { name: file.name })} style={size} data-letterbox={letterbox ? "" : undefined} data-unavailable={videoFailed || undefined}
          data-loaded={still.poster ? "instant" : undefined}>
          {still.url && !videoFailed && (still.poster
            ? <img src={still.url} alt="" aria-hidden="true" />
            : <video src={still.url} muted playsInline preload="auto" aria-hidden="true" onError={() => setVideoFailed(true)} />)}
          <span className={videoFailed ? css.msgVideoUnavailable : css.msgVideoPlay} aria-hidden="true">
            {videoFailed ? <><Read size={24} /><span>{t("web-main.file.noPreview")}</span><small>{fileSize(file.size)}</small></> : <PlayMark size={26} />}
          </span>
          <span className={css.msgVideoName}>{download?.active
            ? <>{download.statusText}<Progress part={download.progress} label={download.statusText} className={css.msgVideoBar} /></>
            : <span className={css.msgVideoLine}><span>{file.name}</span>{file.duration ? <span>{clock(file.duration / 1000)}</span> : null}</span>}</span>
        </button></Tip>
        {preview}
      </>
    );
  }
  if (image) {
    return (
      <>
        <button ref={box} type="button" className={look.image} data-send-image={sentFileKey(file)} onClick={() => { if (held.current) held.current = false; else setOpen(true); }} aria-label={t("web-main.file.view", { name: file.name })} style={size} data-letterbox={letterbox ? "" : undefined}
          // In a chat's list, one the station has can be quoted: a button over its corner as a mouse comes over it, or held.
          {...(quoting && sessionKey !== null ? {
            onPointerDown: () => { held.current = false; },
            onMouseEnter: (e: React.MouseEvent<HTMLElement>) => quoting.over(file, e.currentTarget),
            onMouseLeave: (e: React.MouseEvent<HTMLElement>) => quoting.off(e.relatedTarget),
            onContextMenu: (e: React.MouseEvent<HTMLElement>) => {
              if ((e.nativeEvent as Partial<PointerEvent>).pointerType !== "touch" && !matchMedia("(hover: none)").matches) return;
              e.preventDefault();
              held.current = true;
              quoting.hold(file, e.currentTarget);
            },
          } : {})}
          data-viewer-thumb={url && sessionKey !== null ? thumbId(station.address, sessionKey, file.path) : undefined}
          data-loaded={loaded ?? undefined} data-failed={failed || undefined} data-near={near || undefined}>
          {loaded !== "instant" && <Waiting hash={file.thumbhash} fit={letterbox} />}
          {failed && <span className={css.msgImageUnavailable} aria-hidden="true"><Read size={20} /><span>{t("web-main.file.noPreview")}</span></span>}
          {url && <img ref={img} src={url} alt={file.name} onLoad={() => { if (loaded === null) shown(); }} />}
        </button>
        {preview}
      </>
    );
  }
  if (sessionKey === null) return look.card(file);
  return (
    <>
      <MessageFileCard file={file} download={download} onOpen={() => setOpen(true)}
        onCancel={cancelDownload} onRetry={retryDownload} />
      {preview}
    </>
  );
}

/**
 * A message's file as a card, opened by a press; while the core downloads it (`download`, chatDownloads.ts) a button
 * of its own at its end calls that off (✕), once that failed asks it again (↻): beside the button that opens it, laid
 * over the room the card keeps for it (a button holds no button).
 */
export function MessageFileCard({ file, download, onOpen, onCancel, onRetry }: {
  file: Pick<Attachment, "name" | "size" | "path">; download: DownloadShown | null; onOpen: () => void; onCancel: (id: string) => void; onRetry: (id: string) => void;
}) {
  const act = download === null ? null
    : download.active ? { label: t("web-main.file.cancelDownload"), icon: <Close size={12} />, run: () => onCancel(download.id) }
    : download.state === "failed" ? { label: t("web-main.file.retryDownload"), icon: <Retry size={13} />, run: () => onRetry(download.id) }
    : null;
  return (
    <span className={css.fileCardHold}>
      <button type="button" className={look.open} onClick={onOpen} aria-label={t("web-main.file.view", { name: file.name })}>{look.card(file, download, act !== null)}</button>
      {act && <Tip label={act.label}><button type="button" className={`${css.fileCardRemove} ${css.fileCardAction}`} aria-label={act.label} onClick={act.run}>{act.icon}</button></Tip>}
    </span>
  );
}

/** An image of a message quoted, waiting in the composer: a small picture of the station's (none: its likeness). */
function QuotedThumb({ sessionKey, file }: { sessionKey: string; file: Attachment }) {
  const fetched = useFileShown(sessionKey, file, isImage(file.name), true);
  const likeness = !fetched.url && file.thumbhash ? thumbhashUrl(file.thumbhash) : null;
  return <span className={css.quoteThumb}>{(fetched.url ?? likeness) && <img src={fetched.url ?? likeness!} alt={file.name} />}</span>;
}

/**
 * A file drawn as the chat draws it, but still: an image's box (fetched at once), else its card; nothing opens from it.
 * A published chat's preview (Publish.tsx), where a tap ticks the file instead.
 */
export function FileLook({ sessionKey, file }: { sessionKey: string | null; file: Attachment }) {
  const image = isImage(file.name);
  const fetched = useFileShown(sessionKey ?? "", file, image && sessionKey !== null, true);
  if (!image || sessionKey === null) return look.card(file);
  const { letterbox, ...size } = look.box(file);
  return (
    <span className={look.image} style={size} data-letterbox={letterbox ? "" : undefined} data-loaded={fetched.url ? "instant" : undefined} data-failed={fetched.failed || undefined}>
      {!fetched.url && <Waiting hash={file.thumbhash} fit={letterbox} />}
      {fetched.failed && <span className={css.msgImageUnavailable} aria-hidden="true"><Read size={20} /><span>{t("web-main.file.noPreview")}</span></span>}
      {fetched.url && <img src={fetched.url} alt={file.name} />}
    </span>
  );
}

/** What an image's box shows until it loads: its ThumbHash drawn, sent with it; else the blots drifting. */
/** `fit`: a letterboxed image's share of its box, all the placeholder takes. */
function Waiting({ hash, fit }: { hash: string | undefined; fit?: { width: string; height: string } | undefined }) {
  const likeness = thumbhashUrl(hash);
  return likeness
    ? <span className={look.wait} style={{ ...fit, backgroundImage: `url(${likeness})` }} data-likeness="" aria-hidden="true" />
    : <span className={look.wait} style={fit} aria-hidden="true"><i /><i /><i /></span>;
}

/** How the chat draws a file: an image's button, the box it takes before it loads and what shows until then; a file's card and its button. */
const look = { image: css.msgImage, wait: css.msgImageWait, box: (f: Attachment, least?: number) => imageBox(f, least), open: css.fileCardOpen, card: (f: Pick<Attachment, "name" | "size" | "path">, download?: DownloadShown | null, slot?: boolean) => <FileCard file={f} download={download} slot={slot} /> };

const NO_MARK = { current: null };

/** A file's name as its card shows it: what is cut is the middle of its name, never its extension. */
function FileName({ name }: { name: string }) {
  const dot = name.lastIndexOf(".");
  const [stem, ext] = dot > 0 && name.length - dot <= 8 ? [name.slice(0, dot), name.slice(dot)] : [name, ""];
  return <span className={css.fileCardName}><span className={css.fileCardStem}>{stem}</span>{ext && <span className={css.fileCardExt}>{ext}</span>}</span>;
}

/**
 * What a file is, at a glance: a sheet with its extension on it (a folder its own shape), drawn in the text's colour.
 * One going up fills from the bottom as it goes; one that failed has its extension in red.
 */
export function FileTile({ name, dir = false, progress, error = false, land = false, style }: {
  name: string; dir?: boolean; progress?: number | undefined; error?: boolean;
  /** A card's in the composer: where a mark dropped on the chat lands (drive/flight.ts). */
  land?: boolean; style?: CSSProperties;
}) {
  const own = useRef<SVGSVGElement>(null);
  useLanding(land ? own : NO_MARK);
  const dot = name.lastIndexOf(".");
  const ext = dot > 0 && name.length - dot <= 6 ? name.slice(dot + 1).toUpperCase() : "";
  const id = useId();
  return (
    <svg ref={own} className={css.fileTile} width="30" height="36" viewBox="0 0 30 36" aria-hidden="true" data-error={error || undefined} style={style}>
      {dir ? (
        <path d="M2.75 8.5Q2.75 5.75 5.5 5.75H11.5L14.5 9H24.5Q27.25 9 27.25 11.75V28.5Q27.25 31.25 24.5 31.25H5.5Q2.75 31.25 2.75 28.5Z"/>
      ) : (
        <>
          {progress !== undefined && (
            <>
              <clipPath id={id}><path d="M6 1.75H19L26.25 9V31Q26.25 34.25 23 34.25H6Q2.75 34.25 2.75 31V5Q2.75 1.75 6 1.75Z" /></clipPath>
              <rect className={css.fileTileFill} x="0" width="30" y={36 - 36 * Math.max(0, Math.min(1, progress))} height="36" clipPath={`url(#${id})`} />
            </>
          )}
          <path d="M6 1.75H19L26.25 9V31Q26.25 34.25 23 34.25H6Q2.75 34.25 2.75 31V5Q2.75 1.75 6 1.75Z"/>
          <path d="M19 1.75V6.5Q19 9 21.5 9H26.25" />
          {ext
            ? <text x="14.5" y="27" textAnchor="middle" className={css.fileTileExt} textLength={ext.length >= 3 ? 17 : undefined} lengthAdjust="spacingAndGlyphs">{ext}</text>
            : <path d="M8.5 19H20.5M8.5 23.5H17" />}
        </>
      )}
    </svg>
  );
}

/** `download`: the core's of it (chatDownloads.ts), how far in its size's place and filling its sheet as an upload does;
 * failed, why, as an upload's failure. `slot`: room at its end for a button of its own laid over it (a message's
 * ✕ or ↻, beside the button that opens it). */
export function FileCard({ file, onRemove, onRetry, pending, sent, error, download, slot }: { file: Pick<Attachment, "name" | "size"> & { path?: string }; onRemove?: () => void; onRetry?: (() => void) | undefined; pending?: boolean; sent?: number | undefined; error?: string | null; download?: DownloadShown | null | undefined; slot?: boolean | undefined }) {
  // How far it has gone, once that is known.
  const going = pending && sent !== undefined && file.size > 0
    ? t("web-main.file.uploadingPart", { percent: Math.floor((sent / file.size) * 100), size: fileSize(file.size) })
    : t("common.uploading");
  const coming = download?.active ? download : null;
  const failed = error ?? (download?.state === "failed" ? download.statusText : null);
  return (
    <Tip label={file.path ?? file.name} cut={!file.path}><span className={css.fileCard} data-card="" data-error={failed ? true : undefined}>
      <FileTile name={file.name} progress={pending ? (sent ?? 0) / Math.max(1, file.size) : coming?.progress} error={!!failed} land={!!onRemove} />
      <span className={css.fileCardText}>
        <FileName name={file.name} />
        <span className={css.fileCardMeta}>{failed ?? (pending ? going : coming ? coming.statusText : fileSize(file.size))}</span>
      </span>
      {onRetry && <Tip label={t("web-main.composer.retryUpload")}><button type="button" className={css.fileCardRemove} aria-label={t("web-main.composer.retryUpload")} onClick={(e) => { e.stopPropagation(); onRetry(); }}><Retry size={13} /></button></Tip>}
      {onRemove && <button type="button" className={css.fileCardRemove} aria-label={t("web-main.file.remove", { name: file.name })} onClick={(e) => { e.stopPropagation(); onRemove(); }}><Close size={12} /></button>}
      {slot && <span className={css.fileCardSlot} aria-hidden="true" />}
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
  /** A quote just added: its comment line takes the focus (the draft's own, where not given). */
  focusQuote?: string | null; onFocused?(): void;
  ensureChat?: () => Promise<{ key: string; thread: ChatTo }>;
  onSent?: (to: ChatTo) => void;
  /** A new chat's first message leaving the composer (null: it came back, the chat not made). */
  onSending?: (text: string | null) => void;
  /** Choices shown in the toolbar, between attach and send (a new chat's station, model and effort). */
  toolbar?: ReactNode;
  /** Said right on top of the box. */
  above?: ReactNode;
  placeholder?: string;
  /** While true (a new chat being made) nothing can be sent. */
  locked?: boolean;
  /** Its station taken for down: what is written waits in the outbox until it is reached, and no file is taken in
   * (files go up to the station first). */
  offline?: boolean;
  /** Text above, toolbar below, even for one line (a new chat, whose toolbar holds choices). */
  roomy?: boolean;
  /** Whose draft it shows: changing it keeps what is typed for the one before and brings back the next one's. */
  draftKey?: string;
  /** A key whose draft goes on from what is typed now, instead of its own (a new chat becoming its chat). */
  carry?: MutableRefObject<string | null>;
}

export function Composer(props: ComposerProps) {
  const api = useApi();
  const { draftKey, carry } = props;
  // Its quotes are its draft's: a passage selected in the chat is offered to it by its key (useDraftInbox).
  const draft = useDraft({ key: draftKey, ...(carry ? { carry } : {}) });
  return <ComposerView {...props} draft={draft} />;
}

/** How long the composer stays a box after it loses the cursor, for the cursor to come back without it shrinking. */
const LET_GO_MS = 300;

/** The chat's composer, also used where a page sends its draft as a reply to a decision. */
export function ComposerView({ draft, submitDraft, thread, sessionKey, focusQuote = draft.focusQuote, onFocused = draft.quoteFocused, ensureChat, onSent, onSending, toolbar, above, placeholder = t("web-main.composer.placeholder"), locked = false, offline = false, roomy = false, draftKey }: ComposerProps & {
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
    if (locked || offline || !sessionKey || Date.now() - warmed.current < 60_000) return;
    warmed.current = Date.now();
    void api.warm(sessionKey).catch(() => {});
  };
  const station = useStation().address;
  // Files dragged over its chat's page (ChatPage.tsx useChatDrop).
  const pageOver = useDropOver();
  const outside = useOutsideShare();
  const send = async () => {
    if (submitDraft) { submitDraft(draft); return; }
    // Chats of other workspaces it refers to: shared with this one first, as the viewer says (OutsideShare.tsx).
    if (!(await outside.ask(station, draft.text))) return;
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
  const noFiles = locked || offline;
  useShortcut("composer.file", noFiles ? null : () => { picker.current?.click(); });
  const ready = draft.ready && !locked;
  const submit = () => {
    if (ready) void send();
  };
  const multiline = roomy || focused || text !== "" || files.length > 0 || quotes.length > 0;
  const { menu, field } = useComposerText({ draft, input, draftKey, sessionKey, locked, noFiles, placeholder: hint ?? placeholder, className: css.composerText, layout: multiline, onType: warm, onSubmit: submit });
  // Capsule ⇄ box, in one motion (morph.ts); laid out for another page (a new chat's roomy box ⇄ a chat's foot), the
  // dock moves it (dock.tsx).
  const box = useRef<HTMLFormElement>(null);
  // What it is laid out by: any change of it may change its height (a line more or less, capsule ⇄ box, files).
  useMorph(box, `${multiline}|${text}|${files.length}|${quotes.length}`, roomy);
  // A box while it has the cursor; lost, a capsule a moment later, so that a cursor gone and back at once (a click
  // that hands it back) does not shrink and grow it.
  const letGo = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  useEffect(() => () => clearTimeout(letGo.current), []);
  return (
    <div className={cloudCss.composerWrap}>
      {outside.node}
      {menu}
      {above && <div className={css.composerAbove}>{above}</div>}
      <form ref={box} className={`${composerCss.composerBox} ${refCss.refHost}`} data-multiline={multiline || undefined} data-dragging={dragging || undefined}
        onFocus={() => { clearTimeout(letGo.current); setFocused(true); }}
        onBlur={(e) => {
          if (e.currentTarget.contains(e.relatedTarget)) return;
          clearTimeout(letGo.current);
          letGo.current = setTimeout(() => setFocused(false), LET_GO_MS);
        }}
        onSubmit={(e) => { e.preventDefault(); submit(); }} onClick={() => input.current?.focus()}
        // Locked, or its station down, no file is taken in.
        // Over a chat's page the page shows where they go (ChatPage.tsx useChatDrop); the composer is not marked then.
        onDragOver={(e) => { if ((e.dataTransfer.types.includes("Files") || carriesDrive(e.dataTransfer)) && !noFiles) { e.preventDefault(); if (pageOver === null) setDragging(true); } }}
        onDragLeave={() => setDragging(false)}
        onDrop={(e) => {
          // Dropped on a chat's page, the page takes it (ChatPage.tsx useChatDrop: its marks fly here).
          if (pageOver !== null) return;
          // A station's files (the chat's 文件 tab): named by their path there, until switched to files.
          if (carriesDrive(e.dataTransfer)) { e.preventDefault(); setDragging(false); if (!noFiles) draft.addDropped(droppedOf(e.dataTransfer).map(droppedFrom)); return; }
          if (e.dataTransfer.files.length) {
            e.preventDefault(); setDragging(false);
            if (noFiles) return;
            add(e.dataTransfer.files);
          }
        }}>
        <ComposerExtras draft={draft} focusQuote={focusQuote} onFocused={onFocused} onDone={() => input.current?.focus()} />
        {field}
        <input ref={picker} type="file" multiple hidden onChange={(e) => { if (e.target.files) add(e.target.files); e.target.value = ""; }} />
        <ComposerTools picker={picker} locked={noFiles} toolbar={toolbar} ready={ready} starting={draft.starting} />
      </form>
      {draft.error && <p className={`${controlsCss.fieldError} ${css.chatError}`} role="alert">{draft.error}</p>}
    </div>
  );
}

/**
 * The composer's foot: a file to send, what the page puts there (`toolbar`), and send. Drawn again only when what it
 * shows changes, not at every key typed.
 */
const ComposerTools = memo(function ComposerTools({ picker, locked, toolbar, ready, starting }: {
  /** The composer's file field, which the attach button opens. */
  picker: RefObject<HTMLInputElement | null>; locked: boolean; toolbar: ReactNode; ready: boolean; starting: boolean;
}) {
  return (
    <div className={css.composerToolbar}>
      <Tip label={t("web-main.composer.attach")} shortcut="composer.file">
        <button type="button" className={css.attachBtn} aria-label={t("web-main.composer.attach")} disabled={locked} onClick={(e) => { e.stopPropagation(); picker.current?.click(); }}>
          <Plus size={18} />
        </button>
      </Tip>
      {toolbar && <div className={css.composerChoices} onClick={(e) => e.stopPropagation()}>{toolbar}</div>}
      <Tip label={t("web-main.composer.send")}>
        <button type="submit" className={css.sendBtn} disabled={!ready} aria-label={t("web-main.composer.send")} aria-busy={starting || undefined}>
          {starting ? <Spinner /> : <ArrowUp size={16} strokeWidth={2} />}
        </button>
      </Tip>
    </div>
  );
});

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
export function useComposerText({ draft, input, draftKey, sessionKey, locked, noFiles = locked, placeholder, className, lines, layout, enterSends = true, onType, onSubmit }: {
  draft: Draft; input: RefObject<HTMLTextAreaElement | null>; draftKey: string | undefined; sessionKey: string | null; locked: boolean;
  /** No file is taken in (pasted), though it may be written: its station down. Locked, none is. */
  noFiles?: boolean;
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
    // One of another workspace's: its link kept for this workspace's messages too (`into`).
    void core().call("chat.ref", { station: item.station, id: item.id, title: item.title, base, into: scopeOf(here) }).then((answer) => {
      const { mark } = answer as { mark: string };
      const now = input.current?.value ?? "";
      if (now[start] !== "@") return;
      caretAt.current = start + mark.length + 1;
      setText(`${now.slice(0, start)}${mark} ${now.slice(end)}`);
    }, (e: unknown) => toast(t("web-main.composer.refFailed", { title: item.title, error: failure(e) })));
  };
  // A chat's link pasted (copied from its row's menu: `[its title](its link)`) goes in as a reference, as one picked
  // with `@` does, when the chat is of this workspace; the rest of what is pasted as it is.
  const here = useStation().address;
  const pasteReferences = (e: ClipboardEvent<HTMLTextAreaElement>) => {
    const pasted = e.clipboardData.getData("text/plain");
    // (the core's reading of what is pasted: refLinks.ts pastedRefs)
    const found = pastedRefs(pasted, here);
    if (found.length === 0) return;
    e.preventDefault();
    const el = e.currentTarget;
    const [start, end, before] = [el.selectionStart, el.selectionEnd, el.value];
    const marks = found.map(async (chat) => {
      try {
        const { mark } = (await core().call("chat.ref", { station: chat.station, id: chat.id, title: chat.title, base })) as { mark: string };
        // A link to its execution history: the mark kept as that link, not the chat's.
        if (chat.history) {
          const at = chat.station.indexOf("/");
          const page = `${base}/w/${chat.station.slice(0, at)}/s/${chat.station.slice(at + 1)}/chats/${encodeURIComponent(chat.id)}${chat.history}`;
          await core().call("chat.refs", { links: [[mark.slice(2, -1), page]] });
        }
        return mark;
      } catch {
        return pasted.slice(chat.start, chat.end);
      }
    });
    void Promise.all(marks).then((made) => {
      let text = "", at = 0;
      found.forEach((r, i) => { text += pasted.slice(at, r.start) + made[i]; at = r.end; });
      text += pasted.slice(at);
      // Typed on meanwhile: at the end.
      const now = input.current?.value ?? "";
      const [from, to] = now === before ? [start, end] : [now.length, now.length];
      caretAt.current = from + text.length;
      setText(`${now.slice(0, from)}${text}${now.slice(to)}`);
      onType();
    });
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
  useDraftInbox(locked ? undefined : draftKey, (offer) => {
    const { files: offered, quotes: added, text: words, quote, dropped } = offer;
    if (words) setText(text.trim() ? `${text.trimEnd()}\n${words}` : words);
    if (offered.length) add(offered);
    if (dropped?.length) draft.addDropped(dropped);
    if (added.length) draft.addQuotes(added);
    // A passage selected in the chat (or an image of it): its comment line takes the focus.
    if (quote) draft.quote(quote, offer.quotedFile);
    else input.current?.focus();
  });
  const fitInput = useRef<(() => void) | null>(null);
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
      const limit = lines === undefined
        ? Math.max(parseFloat(style.lineHeight), Math.min(480, window.innerHeight * 0.4))
        : lines * parseFloat(style.lineHeight) + parseFloat(style.paddingTop) + parseFloat(style.paddingBottom);
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
    fitInput.current = fit;
    fit();
    let width = el.clientWidth;
    const resize = new ResizeObserver(() => { if (el.clientWidth !== width) { width = el.clientWidth; fit(); } });
    resize.observe(el);
    // What is above it changing (a file or quote added or gone, a picture loaded) moves it down or up, its text the
    // same: the mirror follows. Its box's size changes with it.
    const moved = new ResizeObserver(() => over());
    const box = el.closest("form");
    if (box) moved.observe(box);
    const scrolled = () => { edges(); over(); };
    el.addEventListener("scroll", scrolled);
    window.addEventListener("resize", fit);
    return () => { fitInput.current = null; resize.disconnect(); moved.disconnect(); window.removeEventListener("resize", fit); el.removeEventListener("scroll", scrolled); probe.remove(); };
  }, [lines, layout]); // eslint-disable-line react-hooks/exhaustive-deps
  // Typing reuses the measure and its observers; only the text and the resulting size change.
  useLayoutEffect(() => { fitInput.current?.(); }, [text]);
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
        onPaste={(e) => {
          if (draft.starting) return;
          if (e.clipboardData.files.length) { e.preventDefault(); if (!noFiles) add(e.clipboardData.files); return; }
          const pasted = e.clipboardData.getData("text/plain");
          if (!noFiles && pasted.length >= PASTE_THRESHOLD) {
            e.preventDefault();
            add([makePastedFile(pasted)], pastedInfo(pasted));
            onType();
          } else pasteReferences(e);
        }}
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
 * What waits to go with the message, as both screens' composers show it: the quotes, each with its picture and a line
 * for a comment (the one just added, `focusQuote`, takes the focus; Enter in it goes back to the text, `onDone`), then
 * the files, an image as its picture.
 */
export function ComposerExtras({ draft, focusQuote, onFocused, onDone, onRef }: {
  draft: Draft; focusQuote: string | null; onFocused(): void; onDone(): void;
  /** A station's file's card tapped, where there is no hover (a phone's: mobile/StationFiles.tsx RefSheet). */
  onRef?: ((f: Pending) => void) | undefined;
}) {
  const { quotes, files } = draft;
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
            const own = q.own;
            // An image of a message quoted is the station's already (none of this device's): a small picture of it.
            const kept = own?.done && !own.preview ? own.done : undefined;
            return (
            <div key={q.id} className={css.composerQuote} onClick={(e) => e.stopPropagation()}>
              <QuoteCard quote={q} picture={own && (kept?.owner ? <QuotedThumb sessionKey={kept.owner} file={kept} /> : <PendingFile file={own} />)}
                onRemove={() => draft.unquote(q.id)} comment={
                <input ref={(el) => { if (el) quoteInputs.current.set(q.id, el); else quoteInputs.current.delete(q.id); }}
                  className={`${css.quoteCardComment} ${css.quoteCardInput}`} value={q.comment} placeholder={t("web-main.quote.commentPlaceholder")} aria-label={t("web-main.quote.commentLabel", { author: q.author })}
                  onChange={(e) => draft.comment(q.id, e.target.value)}
                  onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing) { e.preventDefault(); onDone(); } }} />
              } />
            </div>
            );
          })}
        </div>
      )}
      {files.length > 0 && (
        <div className={css.composerFiles}>
          {files.map((f) => f.link ? <LinkCard key={f.id} file={f} onRemove={() => draft.remove(f.id)} /> : f.ref ? <RefCard key={f.id} file={f} draft={draft} onRemove={() => draft.remove(f.id)} onTap={onRef && (() => onRef(f))} /> : <PendingFile key={f.id} file={f} onRemove={() => draft.remove(f.id)}
            onRetry={!f.error ? undefined : f.pastedFile ? () => { draft.remove(f.id); draft.add([f.pastedFile!], f.pasted); } : f.pasted || f.size > MAX_FILE ? undefined : () => draft.retry(f.id)}
            onRestore={f.pasted?.text === undefined || draft.starting ? undefined : () => {
              draft.setText(draft.text ? `${draft.text}\n${f.pasted!.text}` : f.pasted!.text!);
              draft.remove(f.id);
              onDone();
            }} />)}
        </div>
      )}
    </>
  );
}

/**
 * A file or folder dragged in from where it is: named by its path (which station has it, and where), or sent as a file
 * (a folder of the chat's own station as a zip). Hovered, the card says all of it, and switches it there; as it does
 * whether this chat takes what is dragged in as files.
 */
function RefCard({ file: f, draft, onRemove, onTap }: { file: Pending; draft: Draft; onRemove: () => void; onTap?: (() => void) | undefined }) {
  const ref = f.ref!;
  const station = useStation();
  const asFile = ref.mode === "file";
  const pending = asFile && goingUp(f);
  const going = f.sent !== undefined && f.size > 0
    ? t("web-main.file.uploadingPart", { percent: Math.floor((f.sent / f.size) * 100), size: fileSize(f.size) })
    : t("common.uploading");
  // A folder goes as a zip only from the chat's own station (zipped there).
  const zips = ref.dir && ref.station === station.address;
  const meta = asFile ? f.error ?? (pending ? going : fileSize(f.done?.size ?? f.size)) : `${ref.stationName} · ${t("web-main.file.modePath")}`;
  // Hovered: its name, where it is (its station, its folder), how it goes (a path, the file, a folder as a zip), and how
  // this chat takes what is dragged in; each switched there.
  const where = ref.path.slice(0, Math.max(ref.path.lastIndexOf("/"), ref.path.lastIndexOf("\\"))) || ref.path;
  const info = (
    <div className={css.refInfo}>
      <div className={css.refInfoHead}>
        <span className={css.refInfoText}>
          <span className={css.refInfoName}>{f.name}</span>
          <span className={css.refInfoPath} title={ref.path}><bdi><StationNamedAt station={ref.station} name={ref.stationName} /> · {where}</bdi></span>
        </span>
        {(!ref.dir || zips) && (
          <Segmented className={css.refInfoMode} label={t("web-main.file.sendAs")} value={ref.mode} onChange={(mode) => draft.setMode(f.id, mode)}
            options={[{ value: "path", label: t("web-main.file.modePath") }, { value: "file", label: t(ref.dir ? "web-main.file.modeZip" : "web-main.file.modeFile") }]} />
        )}
      </div>
      <label className={css.refInfoChat}>
        <span>{t("web-main.file.chatAsFiles")}</span>
        <Switch small checked={draft.asFiles} onChange={draft.setAsFiles} label={t("web-main.file.chatAsFiles")} />
      </label>
    </div>
  );
  const card = (
    <span className={css.fileCard} data-card="" data-error={asFile && f.error ? true : undefined} data-named={!asFile || undefined}
      {...(onTap ? { role: "button", tabIndex: 0, onClick: onTap, onKeyDown: (e: React.KeyboardEvent) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); onTap(); } } } : {})}>
      <FileTile land name={asFile && ref.dir ? `${f.name}.zip` : f.name} dir={ref.dir && !asFile} progress={pending ? (f.sent ?? 0) / Math.max(1, f.size) : undefined} error={asFile && !!f.error} />
      <span className={css.fileCardText}>
        <FileName name={asFile && ref.dir ? `${f.name}.zip` : f.name} />
        <span className={css.fileCardMeta}>{meta}</span>
      </span>
      <button type="button" className={css.fileCardRemove} aria-label={t("web-main.file.remove", { name: f.name })} onClick={(e) => { e.stopPropagation(); onRemove(); }}><Close size={12} /></button>
    </span>
  );
  // Where nothing hovers, a tap says all of it (`onTap`); else hovered.
  return onTap ? card : <Hover tile content={info}>{card}</Hover>;
}

/**
 * A link shared in (docs/share-in.md), waiting to go with the message as words: a card as a file's, a globe where a
 * file's sheet is, its title (cut short) over its site. Nothing goes up: it is never under way, and it does not hold
 * the message back.
 */
function LinkCard({ file: f, onRemove }: { file: Pending; onRemove: () => void }) {
  const link = f.link!;
  const title = link.title || link.url;
  return (
    <Tip label={link.url}><span className={css.fileCard} data-card="" data-link="">
      <LinkTile />
      <span className={css.fileCardText}>
        <span className={css.fileCardName}><span className={css.fileCardStem}>{title}</span></span>
        <span className={css.fileCardMeta}>{link.site ?? hostOf(link.url)}</span>
      </span>
      <button type="button" className={css.fileCardRemove} aria-label={t("web-main.file.remove", { name: title })} onClick={(e) => { e.stopPropagation(); onRemove(); }}><Close size={12} /></button>
    </span></Tip>
  );
}

/** A link's host (`www.youtube.com`), or the link itself where it has none. */
function hostOf(url: string): string {
  try { return new URL(url).host || url; } catch { return url; }
}

/** What a link is, where a file's sheet stands (FileTile's box and lines): a globe. */
function LinkTile() {
  return (
    <svg className={css.fileTile} width="30" height="36" viewBox="0 0 30 36" aria-hidden="true">
      <circle cx="15" cy="18" r="11.25" />
      <path d="M3.75 18H26.25M15 6.75C11.75 10 10.25 14 10.25 18S11.75 26 15 29.25M15 6.75C18.25 10 19.75 14 19.75 18S18.25 26 15 29.25" />
    </svg>
  );
}

/** A file waiting to go with the message: an image as its picture (clicked, shown whole), anything else a card. */
function PendingFile({ file: f, onRemove, onRestore, onRetry }: { file: Pending; onRemove?: () => void; onRestore?: (() => void) | undefined; onRetry?: (() => void) | undefined }) {
  const station = useStation();
  // A picture dropped on the chat: its mark lands here (drive/flight.ts).
  const thumb = useRef<HTMLSpanElement>(null);
  useLanding(thumb);
  const [open, setOpen] = useState(false);
  // Not sent yet: no session keeps it, it is shown from this device.
  const shown: Attachment = { name: f.name, path: `draft:${f.id}`, size: f.size };
  if (f.pasted) {
    // Cut short (a failure said at length), all of it on hover.
    const meta = f.error ?? (goingUp(f) ? t("common.uploading") : t("web-main.composer.pasteAttachment", { count: f.pasted.characters.toLocaleString("en-US") }));
    return <><span className={css.fileCard} data-card="" data-error={f.error ? true : undefined}>
      <FileTile name={f.name} progress={goingUp(f) ? (f.sent ?? 0) / Math.max(1, f.size) : undefined} error={!!f.error} />
      <span className={css.fileCardText}>
        <button type="button" className={css.pasteCardTitle} onClick={(e) => { e.stopPropagation(); setOpen(true); }}>{f.pasted.preview || t("web-main.composer.pastedText")}</button>
        <Tip label={meta} cut><span className={`${css.fileCardMeta} ${css.pasteCardMeta}`}>{meta}</span></Tip>
      </span>
      <span className={css.pasteCardActions}>
        {onRetry && <Tip label={t("web-main.composer.retryPaste")}><button type="button" className={css.fileCardRemove} aria-label={t("web-main.composer.retryPaste")} onClick={(e) => { e.stopPropagation(); onRetry(); }}><Retry size={13} /></button></Tip>}
        {onRestore && <Tip label={t("web-main.composer.expandPaste")}><button type="button" className={css.fileCardRemove} aria-label={t("web-main.composer.expandPaste")} onClick={(e) => { e.stopPropagation(); onRestore(); }}><Edit size={13} /></button></Tip>}
        {onRemove && <button type="button" className={css.fileCardRemove} aria-label={t("web-main.composer.removePaste")} onClick={(e) => { e.stopPropagation(); onRemove(); }}><Close size={12} /></button>}
      </span>
    </span>{f.pastedFile && f.preview && <FilePreview open={open} onClose={() => setOpen(false)} sessionKey="" file={shown} local={{ blob: f.pastedFile, url: f.preview }} />}</>;
  }
  return f.preview ? (
    <Tip label={f.error ?? f.name}><span ref={thumb} data-card="" className={css.composerThumb} data-send-image={f.done ? sentImageKey(f.done.path) : f.error ? undefined : uploadImageKey(f.id)} data-error={f.error ? true : undefined}>
      <button type="button" className={css.composerThumbOpen} aria-label={t("web-main.file.view", { name: f.name })} data-viewer-thumb={thumbId(station.address, "", shown.path)}
        onClick={(e) => { e.stopPropagation(); setOpen(true); }}>
        <img src={f.preview} alt={f.name} />
      </button>
      {f.image && <FilePreview open={open} onClose={() => setOpen(false)} sessionKey="" file={shown} local={{ blob: f.image, url: f.preview }} />}
      {goingUp(f) && <span className={css.composerThumbBusy}><Spinner /></span>}
      {f.error && onRetry && <button type="button" className={css.composerThumbRetry} aria-label={t("web-main.composer.retryUpload")} onClick={(e) => { e.stopPropagation(); onRetry(); }}><Retry size={18} /></button>}
      {onRemove && <button type="button" className={css.composerThumbRemove} aria-label={t("web-main.file.remove", { name: f.name })} onClick={(e) => { e.stopPropagation(); onRemove(); }}><Close size={12} /></button>}
    </span></Tip>
  ) : <FileCard file={f.done ?? f} pending={goingUp(f)} sent={f.sent} error={f.error} onRetry={onRetry} {...(onRemove ? { onRemove } : {})} />;
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
    const at = now - s.stopped < HOLD_MS ? s.stopped + HOLD_MS : s.stopped + HOLD_MS + motionMs(FADE_MS);
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
 * avatar, an image loading): it glides from where it showed to where it is laid out now, by the pane's own law
 * (motion.ts glider), so that it and the pane gliding to the end move together, one way; a change while it is on its
 * way goes on from where it is. What the pane's width lays out anew is taken at once.
 */
/** How long after the pane's width last changed its rows may still come to stand as they wrap now. */
const REWRAP_MS = 200;

function useActivityGlide(list: RefObject<HTMLDivElement | null>, virtual: VirtualList) {
  useEffect(() => {
    const pane = list.current;
    if (!pane) return;
    const { model } = virtual;
    // `at`: where it is laid out in the pane's content; `closed`: how much shorter what is above it has got as things
    // closed in it (model.ts `closedBefore`), which it simply went along with, as every row below does; `y`: how far
    // it is drawn from where it is laid out, gliding to nothing after a move at once.
    const rows = new Map<string, { el: HTMLElement; at: number; closed: number; y: Follower }>();
    let width = model.paneWidth;
    let rewrapped = -Infinity;
    let pending = false;
    // How far the list has moved the pane at once to keep its place (rows above measured, an older page come in): by
    // as much, an activity is elsewhere in the pane's content and nowhere else on screen: not a move to glide.
    let kept = virtual.kept();
    // Judged as the list says anything changed, from where it says each activity stands: nothing of the page is read.
    const check = () => {
      // The pane as wide as it was? While it changes (a side panel sliding), and until its rows are measured as they
      // wrap now, what moves an activity is the page laid out anew: taken at once.
      if (model.paneWidth !== width) { width = model.paneWidth; rewrapped = performance.now(); pending = true; }
      const shift = virtual.kept() - kept;
      kept += shift;
      if (shift) for (const row of rows.values()) row.at += shift;
      const layout = model.layout();
      // A row just made stands at a guessed height until the page reports it: what moves an activity is taken as the
      // pane takes it, the guess and then the fact (below).
      const anew = pending || performance.now() - rewrapped < REWRAP_MS;
      pending = false;
      const seen = new Set<string>();
      for (const { key } of layout.rows) {
        if (!key.startsWith("a:")) continue;
        const el = pane.querySelector<HTMLElement>(`:scope > [data-vk="${CSS.escape(key)}"]`);
        if (!el) continue;
        seen.add(key);
        // Where it stands in the pane's content.
        const at = model.offsetOf(key)! + layout.scrollTop;
        const closed = model.closedBefore(key);
        let row = rows.get(key);
        if (row && row.el !== el) { row.y.stop(); rows.delete(key); row = undefined; }
        if (!row) {
          rows.set(key, { el, at, closed, y: glider(0, (v) => { el.style.transform = Math.abs(v) < 0.01 ? "" : `translateY(${v}px)`; }) });
          continue;
        }
        // What closes above it as it closes moves it as it moves every row below: not a move of its own.
        const moved = at - row.at + (closed - row.closed);
        row.at = at;
        row.closed = closed;
        if (Math.abs(moved) < 0.01) continue;
        // One folded to its avatar, out flying, shows nothing: it is where it is laid out, for the avatar to fly to.
        // Moved as the pane is not gliding (it took the change at once, or the reader holds it): where it is laid out.
        if (anew || !model.glides || document.visibilityState !== "visible" || el.hasAttribute("data-away")) row.y.jump(0);
        else {
          // Laid out elsewhere at once as the pane glides, it is drawn where it was, and glides from there with it.
          row.y.jump(row.y.value - moved);
          row.y.to(0);
        }
      }
      for (const [key, row] of rows) if (!seen.has(key)) { row.y.stop(); rows.delete(key); }
    };
    check();
    const stop = virtual.watch(check);
    return () => {
      stop();
      for (const row of rows.values()) row.y.stop();
    };
  }, [list, virtual.model]); // eslint-disable-line react-hooks/exhaustive-deps
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
 * out: arriving while the page is hidden or the reader has scrolled up (virtual/model.ts), and all still waiting when the page
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

export function useEmissions(list: RefObject<HTMLDivElement | null>, following: () => boolean = () => true) {
  const decided = useRef(new Map<number, boolean>());
  const done = useRef(new Set<number>());
  // `at`: when it began waiting; its agent's activity folds to its avatar from then.
  const queue = useRef<{ seq: number; agent: string; at: number }[]>([]);
  // `chain`: on from the message before it, the same agent's, without going home between.
  const [current, setCurrent] = useState<{ seq: number; agent: string; pose: Pose; at: number; chain?: boolean } | null>(null);
  const flight = useRef<{ el: HTMLElement; x: Follower; y: Follower; s: MotionValue<number>; sx: MotionValue<number>; sy: MotionValue<number> } | null>(null);
  const [, rerender] = useState(0);

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
    // Its ring stepping as the real one does (the copy's would start over): they hand over to each other unmoved.
    const ring = (n: Element) => n.getAnimations({ subtree: true }).filter((x): x is CSSAnimation => x instanceof CSSAnimation);
    const turning = ring(avatar);
    for (const copied of ring(el)) {
      const real = turning.find((x) => x.animationName === copied.animationName);
      if (real) copied.currentTime = real.currentTime;
    }
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
  // Their turn among what changes the list's height (listQueue.ts): taken as the first sets out, kept while one after
  // another comes out, given back once none is left.
  const slot = useRef<{ granted: boolean; out(): void; over(): void } | null>(null);
  const giveBack = () => {
    const s = slot.current;
    slot.current = null;
    if (s?.granted) s.over();
    else s?.out();
  };
  const nextAfter = (agent: string | null) => {
    if (queue.current.length && !slot.current?.granted) {
      // Not its turn yet: asked for once, and on from here when it comes (drawn again then).
      if (!slot.current && list.current) {
        const s = { granted: false, out: () => {}, over: () => {} };
        slot.current = s;
        s.out = listQueue(list.current).take(() => new Promise<void>((resolve) => { s.granted = true; s.over = resolve; rerender((n) => n + 1); }));
      }
      if (!slot.current?.granted) return;
    }
    const next = queue.current.shift();
    if (!next) giveBack();
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
      giveBack();
    }
    rerender((n) => n + 1);
  };
  const watched = () => document.visibilityState === "visible" && following();
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
    if (pose === "fold") timer = setTimeout(() => go("float"), Math.max(0, motionMs(FOLD_MS) - (performance.now() - current.at)));
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
      }, motionMs(SPIT_MS));
    }
    if (pose === "return") {
      if (!flight.current) { finish(seq, agent, false); return; }
      follow(() => home(avatar), () => finish(seq, agent));
    }
    return () => { clearTimeout(timer); cancelAnimationFrame(frame); hop?.stop(); };
  }, [current?.seq, current?.pose]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => () => { land(); giveBack(); }, []); // eslint-disable-line react-hooks/exhaustive-deps

  return {
    /** Agents whose activity must stay while their messages come out. */
    keeps: new Set([...queue.current.map((q) => q.agent), ...(current ? [current.agent] : [])]),
    /** Messages seen for the first time: an agent's, new, while its activity shows, waits its turn to come out of it. */
    take(messages: ChatMessage[], saidHere: (seq: number) => boolean, showing: ReadonlySet<string>) {
      for (const m of messages) {
        if (decided.current.has(m.seq)) continue;
        const agent = m.authorKind === "agent" ? m.by.agent : undefined;
        const emits = watched() && saidHere(m.seq) && agent !== undefined && showing.has(agent);
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
function Activity({ agent, leaving, caught, pose, stoppable }: { agent: AgentAtWork; leaving: boolean; caught: true | undefined; pose: { folded: boolean; away: boolean };
  /** Stopped alone, from its row (the chat has other agents). */
  stoppable: boolean;
}) {
  const chat = useContext(DraftKey);
  const api = useApi();
  const act = useAct();
  const wait = agent.wait;
  const now = useSteady(wait ? { key: "wait", text: wait.text ?? t("web-main.activity.waiting") } : agent.activity?.now ?? { key: "busy", text: t("web-main.activity.busy") });
  const row = useRef<HTMLDivElement>(null);
  const line = useRef<HTMLButtonElement>(null);
  const tail = useRef<HTMLSpanElement>(null);
  // One there when the chat opened is there at once. One that starts comes in its turn among what changes the list's
  // height (listQueue.ts): after the reader's message on its way from the composer has landed, under it, not first and
  // then pushed down by it.
  useLayoutEffect(() => {
    if (caught) return;
    const el = row.current!;
    const move = { duration: FADE_MS / 1000, ease: EASE_OUT };
    return queueRow(el, () => {
      arrive([[el, { "grid-template-rows": "0px", opacity: "0" }], [line.current!, { transform: "scale(0.5)" }]], move);
      return after(motionMs(FADE_MS));
    });
  }, []); // eslint-disable-line react-hooks/exhaustive-deps
  // Set here, not by React: the change is made where what shows before it can be read.
  const was = useRef({ leaving: false, folded: false });
  useLayoutEffect(() => {
    const el = row.current!;
    if (leaving !== was.current.leaving) {
      // Reading where it goes lays the list out with its room folded for a moment, shorter than the pane scrolled to its
      // end: the browser pulls the pane up then, and moveState puts it back (the list is held where it was as it folds).
      void moveState([[el, ["grid-template-rows", "opacity"]]], () => el.toggleAttribute("data-leaving", leaving), { duration: FADE_MS / 1000, ease: EASE_OUT });
    }
    if (pose.folded !== was.current.folded) {
      void moveState([[tail.current!, ["width", "opacity"]]], () => el.toggleAttribute("data-folded", pose.folded), { duration: FOLD_MS / 1000, ease: EASE_OUT });
    }
    was.current = { leaving, folded: pose.folded };
  });
  return (
    <div ref={row} className={`${conversationCss.msg} ${css.agentActivity}`} data-vk={`a:${agent.key}`} data-transient="" data-agent={agent.key} data-caught={caught} data-away={pose.away || undefined} data-waiting={wait ? "" : undefined}>
      <div className={css.activityRow}>
      <button ref={line} type="button" className={css.activityLine} onClick={() => { if (chat) chatPage.history(chat, agent.key); }} aria-label={`${agent.who}：${now.current.text}`}>
        <span className={css.activityAvatar} aria-hidden="true"><span className={`${chatCss2.msgAvatar} ${css.msgAvatarAgent}`}><ModelLogo maker={agent.maker} runtime={agent.runtime} size={12} /></span><span className={css.activityRing} data-spokes="" /></span>
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
      {stoppable && (
        <Tip label={t("web-main.activity.stop", { who: agent.who })}>
          <button type="button" className={css.activityStop} aria-label={t("web-main.activity.stop", { who: agent.who })} onClick={() => act(api.stop(agent.key), t("web-pages.chat.stop"), t("web-pages.chat.stopAsked"))}><Stop size={12} fill="currentColor" /></button>
        </Tip>
      )}
      </div>
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
    const timer = setTimeout(() => setState((s) => ({ ...s, previous: null })), motionMs(CROSS_MS));
    return () => clearTimeout(timer);
  }, [state.previous]);
  return state;
}

/** Seconds (then minutes) since a moment, ticking; at most `most` seconds. */
export function Elapsed({ since, most }: { since: number; most?: number }) {
  const shown = () => {
    const s = Math.max(0, Math.floor((Date.now() - since) / 1000));
    return span(most === undefined ? s : Math.min(s, most));
  };
  // Its words changed in place each second, not drawn by React: nothing around it is drawn again, and the lists that
  // watch what changes in them pass over it (`data-ticking`).
  const [first] = useState(shown);
  const el = useRef<HTMLSpanElement>(null);
  useLayoutEffect(() => {
    const tick = () => {
      const words = el.current?.firstChild;
      const now = shown();
      if (words && words.nodeValue !== now) words.nodeValue = now;
    };
    tick();
    const timer = setInterval(tick, 1000);
    return () => clearInterval(timer);
  }, [since, most]); // eslint-disable-line react-hooks/exhaustive-deps
  return <span ref={el} data-ticking="">{first}</span>;
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
  const h = Math.floor(s / 3600);
  return m ? `${h}h ${m}m` : `${h}h`;
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

let passageMarks: { host: HTMLElement; layer: HTMLElement; timer: ReturnType<typeof setTimeout> } | null = null;
/**
 * Marks a range for a moment, as Android's TextMark: a rounded ground behind each of its lines, as tall as its words, a
 * little past their ends; in, held, and faded (`[data-passage-marks]`, global.css.ts). The layer is in the block the
 * words are in, below them and above its ground (your bubble's).
 */
function flashRange(range: Range): void {
  unmarkPassage();
  const common = range.commonAncestorContainer;
  const at = common instanceof HTMLElement ? common : common.parentElement;
  const host = at?.closest<HTMLElement>(`p, li, td, th, h1, h2, h3, h4, h5, h6, blockquote, .${conversationCss.msgBubble}`) ?? at;
  if (!host) return;
  host.dataset.passageHost = "";
  const layer = document.createElement("span");
  layer.dataset.passageMarks = "";
  layer.setAttribute("aria-hidden", "true");
  host.append(layer);
  // One ground a line: a range's rects may be one per element it crosses (code, a link) on the same line.
  const lines: { left: number; top: number; right: number; bottom: number }[] = [];
  for (const r of range.getClientRects()) {
    if (r.width < 1) continue;
    const line = lines.find((l) => r.top < l.bottom && r.bottom > l.top && Math.abs((r.top + r.bottom) - (l.top + l.bottom)) < r.height);
    if (line) Object.assign(line, { left: Math.min(line.left, r.left), top: Math.min(line.top, r.top), right: Math.max(line.right, r.right), bottom: Math.max(line.bottom, r.bottom) });
    else lines.push({ left: r.left, top: r.top, right: r.right, bottom: r.bottom });
  }
  const box = host.getBoundingClientRect();
  const x = box.left + host.clientLeft, y = box.top + host.clientTop;
  layer.replaceChildren(...lines.map((l) => {
    const ground = document.createElement("span");
    Object.assign(ground.style, { left: `${l.left - x - 3}px`, top: `${l.top - y - 1}px`, width: `${l.right - l.left + 6}px`, height: `${l.bottom - l.top + 2}px` });
    return ground;
  }));
  passageMarks = { host, layer, timer: setTimeout(unmarkPassage, 2400) };
}

function unmarkPassage(): void {
  if (!passageMarks) return;
  clearTimeout(passageMarks.timer);
  passageMarks.layer.remove();
  delete passageMarks.host.dataset.passageHost;
  passageMarks = null;
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
