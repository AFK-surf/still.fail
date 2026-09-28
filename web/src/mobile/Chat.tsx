// An item's page on a narrow screen, as the Android app has it (apps/android/…/screens/Chat.kt): its chat's messages
// (none before its agent has a chat), the composer, and each agent's execution history as a sheet opened from its mark
// or name. Your messages sit right in a bubble; everyone else gets a face, a name and the time over their words.
// Long-press quotes or copies a message; ＋ adds files. The list's behaviour (following its end, older pages, what is
// read, the unread line, where it was left, messages coming out of an agent's avatar) is the desktop's (../Chat.tsx).
import { memo, useEffect, useLayoutEffect, useRef, useState, type ReactNode, type RefObject } from "react";
import { useLocation, useParams } from "react-router";
import { useApi, useChat, useChatSend, useLives, useStationCall, type Attachment, type ChatMessage, type ChatThread, type ChatView, type Maker, type Outgoing, type Quote, type RuntimeKind } from "../api.ts";
import { useHost, type HostComposer } from "./ChatHost.tsx";
import type { Draft as SharedDraft } from "../draft.ts";
import { chatImages, fileSize, Gallery } from "../FilePreview.tsx";
import { Activity, Files, ProseWithFiles, sameMessage, useMessageList, type FileLook } from "../Chat.tsx";
import { ArrowDown, ArrowUp, Camera, ChevronLeft, ChevronRight, Close, Copy, File, More, Photo, Plus, Quote as QuoteIcon, Stop, Web } from "../icons.tsx";
import { Prose } from "../Prose.tsx";
import { stationBase, useStation } from "../station.tsx";
import { ask } from "./sheets.tsx";
import { SheetGrab, SheetHead, useApp, type MobileApp } from "./app.tsx";
import { openHistory } from "./History.tsx";
import { Avatar, GroupLabel, InfoList, InfoRow, Mark, ModelMark, NavButton, PeopleStack, Seg, SlackMark, Spinner, stateOf } from "./parts.tsx";
import { ago, alarmOf, clock, isCurrent, isService, JobDot, metaOf, sorted, toneOf, useJobLog, useNow, useStopJob, type Tone } from "../Jobs.tsx";
import { emberLinkClicked } from "../emberLink.ts";
import type { Job } from "../core/shapes.ts";
import * as chatCss from "./styles/chat.css.ts";
import * as css from "./Chat.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as conversationCss from "../styles/conversation.css.ts";
import * as chatCss2 from "../styles/chat.css.ts";
import * as barsCss from "./styles/bars.css.ts";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as homeCss from "./styles/home.css.ts";
import * as listsCss from "./styles/lists.css.ts";

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
      <div className={chatCss.mChat}>
        <BarFrame title="" more={false} />
        <div className={`${css.mCenter} ${partsCss.mMuted}`}>{chat.error ? `读不到这个对话：${chat.error.message}` : null}</div>
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
    <div className={chatCss.mChat}>
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
        <button key={a.session.key} type="button" className={css.mBarAgent} onClick={() => openHistory(app, here.station, here.key, a.session.key)} aria-label={`${a.session.agentText} 的执行历史`}>
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
    <header className={`${css.mChatBar} ${pagesCss.mGlass}`}>
      <button type="button" className={css.mChatBack} onClick={app.pop} aria-label="返回"><ChevronLeft size={22} /></button>
      <span className={css.mChatBarTitle}><b>{title}</b>{children}</span>
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
  const thread = view.thread;
  const { messages, divider, away, shown, rowOf, poseOf } = useMessageList(list, floor, view, `${here.station}:${thread?.id ?? here.key}`, lives);
  const agentOf = (key: string | undefined) => view.agents.find((a) => a.session.key === key);
  const images = () => chatImages([...messages, ...view.outbox.map((o) => ({ authorKind: "person", ...o }))], (f) => ownerOf(here, f));
  // The messages are kept as they are while nothing they show changes (Said): what they are handed stays the same
  // function, the latest one behind it, and `owners` says when whose files are whose has changed.
  const latest = useRef({ here, draft, images });
  latest.current = { here, draft, images };
  const [act] = useState<Act>(() => ({ owner: (file) => ownerOf(latest.current.here, file), quote: (q) => latest.current.draft.quote(q) }));
  const [gallery] = useState(() => () => latest.current.images());
  const owners = view.agents.map((a) => `${a.session.key}=${a.session.workspace}`).join(" ");
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
        <button type="button" className={css.mQuotePop} style={{ left: picked.x, top: picked.y }} onMouseDown={(e) => e.preventDefault()}
          onClick={() => { draft.quote(picked.quote); setPicked(null); window.getSelection()?.removeAllRanges(); }}>
          <QuoteIcon size={12} strokeWidth={2.2} />引用
        </button>
      )}
      <Gallery.Provider value={gallery}>
      <div className={chatCss.mMessages} ref={list} onClick={onLink} onMouseUp={() => setTimeout(() => setPicked(selectedQuote(list.current)), 0)} onScroll={() => setPicked(null)}>
        {view.more && <div className={css.mOlder}><Spinner size={16} /></div>}
        {messages.length === 0 && view.outbox.length === 0 && <p className={css.mChatEmpty}>在这里发消息，这个对话里的 agent 会在这里回复。</p>}
        {messages.map((m) => {
          const { enter, emitted: state } = rowOf(m);
          const agent = agentOf(m.by.agent)?.session;
          return [
            m.seq === divider ? <UnreadLine key={`line-${m.seq}`} /> : null,
            <div key={m.seq} className={`${conversationCss.msg} ${css.mRow}`} data-seq={m.seq} data-ts={m.ts} data-enter={enter}
              data-author={m.mine ? "你" : m.by.name} data-role={m.authorKind === "agent" ? "agent" : "person"}
              data-held={state === "held" || undefined} data-emitting={state === "emitting" || undefined} data-covered={state === "emitting" || undefined}>
              <Said m={m} agent={agent ? { key: agent.key, maker: agent.maker, runtime: agent.runtime } : undefined} station={here.station} sessionKey={here.key} owners={owners} act={act} list={list} />
            </div>,
          ];
        })}
        {view.outbox.map((o) => <div key={o.id} className={`${conversationCss.msg} ${css.mRow}`} data-enter><Out o={o} here={here} /></div>)}
        {shown.map(({ agent, leaving }) => (
          <Activity key={agent.key} agent={agent} leaving={leaving} pose={poseOf(agent.key)} className={css.mActivity}
            mark={<ModelMark maker={agent.maker} runtime={agent.runtime} size={20} />} onOpen={() => openHistory(app, here.station, here.key, agent.key)} />
        ))}
        <div ref={floor} className={chatCss2.chatFloor} aria-hidden="true" />
      </div>
      </Gallery.Provider>
      {/* Over the send button, in line with it; it comes up growing and goes the way it came. */}
      <button type="button" className={`${css.mJump} ${pagesCss.mFloating}`} data-shown={away || undefined} aria-label="跳到最新"
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
  return <div className={css.mUnreadLine} data-unread-line role="separator"><i /><span>以下是新消息</span><i /></div>;
}

/** A message's words as read, without markdown's marks: what a quote carries. */
function plain(text: string): string {
  return text.replace(/[`*#>]/g, "").replace(/\s+/g, " ").trim();
}

/** Long-press on a message: quote it, or copy it. While its menu is open the message is marked. */
function useHold(text: string, who: string, ts: string | undefined, role: "agent" | "person", quote: Act["quote"]) {
  const app = useApp();
  const [pressed, setPressed] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const open = (el: HTMLElement) => {
    setPressed(true);
    app.menu({
      anchor: el.getBoundingClientRect(),
      items: [
        { label: "引用", icon: <QuoteIcon size={16} />, action: () => quote({ author: who, text: plain(text), ...(ts ? { ts } : {}), role }) },
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

/** What a message does from its page: whose files are whose, and quoting it (the same functions while the page lasts). */
interface Act { owner(file: Attachment): string | null; quote(q: Omit<Quote, "comment">): void }

/** An agent of the chat, as its messages show it. */
interface SaidBy { key: string; maker: Maker | undefined; runtime: RuntimeKind }

/**
 * One message. It is drawn again only when something it shows changes: an agent at work makes the chat draw again
 * many times a second (its activity), and every message's Markdown would be laid out anew each time.
 */
const Said = memo(function Said({ m, agent, station, sessionKey, act, list }: {
  m: ChatMessage; agent: SaidBy | undefined; station: string; sessionKey: string;
  /** Whose files are whose, in a word: when it changes, the files are drawn again. */
  owners: string;
  act: Act; list: RefObject<HTMLDivElement | null>;
}) {
  const app = useApp();
  const jump = (ts: string) => {
    const target = list.current?.querySelector<HTMLElement>(`[data-ts="${ts}"]`);
    if (!target) return;
    list.current!.dispatchEvent(new WheelEvent("wheel"));
    list.current!.scrollTop += target.getBoundingClientRect().top - list.current!.getBoundingClientRect().top - 80;
  };
  const who = m.by.name;
  const hold = useHold(m.text, m.mine ? "你" : who, m.ts, m.authorKind === "agent" ? "agent" : "person", act.quote);
  // What ember itself says: a notice across the chat, apart from people's and agents' messages.
  if (m.system) {
    return <div className={css.mSystem}><Mark size={14} /><div className={`${chatCss.mMarkdown} ${css.mMd14}`}><Prose>{m.text}</Prose></div></div>;
  }
  if (m.mine) {
    return (
      <div className={chatCss.mMine}>
        {m.quotes.map((q, i) => <QuoteCard key={i} q={q} onJump={jump} />)}
        {m.text && <div className={chatCss.mBubble} data-pressed={hold.pressed || undefined} {...hold.props}>{m.text}</div>}
        <Files owner={act.owner} files={m.attachments} look={look} />
        {m.waiting
          ? <span className={`${chatCss.mMeta} ${chatCss.mWaiting}`}><Spinner size={10} />等待 agent 接收</span>
          : <span className={chatCss.mMeta}>{m.time?.createdAt?.ago ?? ""}</span>}
      </div>
    );
  }
  return (
    <div className={css.mSaid}>
      <div className={`${conversationCss.msgHead} ${css.mSaidHead}`}>
        {agent ? (
          <button type="button" className={css.mAgentHead} onClick={() => openHistory(app, station, sessionKey, agent.key)}>
            <span className={chatCss2.msgAvatar}><ModelMark maker={agent.maker} runtime={agent.runtime} size={20} /></span>
            <b>{who}</b>
          </button>
        ) : (
          <span className={css.mAgentHead}>
            <span className={chatCss2.msgAvatar}>{m.authorKind === "agent" || m.authorKind === "ember" ? <Mark size={18} /> : <Avatar id={m.author} name={who} size={18} picture={m.by.picture} />}</span>
            <b>{who}</b>
          </span>
        )}
        <span className={chatCss.mMeta}>{m.time?.createdAt?.ago ?? ""}</span>
      </div>
      {m.quotes.map((q, i) => <QuoteCard key={i} q={q} onJump={jump} />)}
      {m.authorKind === "person"
        ? <>
            <div className={css.mSaidBody} data-pressed={hold.pressed || undefined} {...hold.props}>{m.text && <p className={chatCss.mPlain}>{m.text}</p>}</div>
            <Files owner={act.owner} files={m.attachments} look={look} />
          </>
        : <ProseWithFiles owner={act.owner} text={m.text} files={m.attachments} look={look}
            className={css.mSaidBody} prose={{ "data-pressed": hold.pressed || undefined, ...hold.props }} markdown={chatCss.mMarkdown} />}
    </div>
  );
}, (a, b) => a.station === b.station && a.sessionKey === b.sessionKey && a.owners === b.owners && a.act === b.act && a.list === b.list
  && JSON.stringify(a.agent) === JSON.stringify(b.agent) && sameMessage(a.m, b.m));

/** A message sent from here that the chat does not show yet: on its way, or failed with a way to send it again or drop it. */
function Out({ o, here }: { o: Outgoing; here: Here }) {
  const app = useApp();
  const sending = useChatSend();
  const thread = here.view.thread;
  return (
    <div className={chatCss.mMine} data-unsent={o.state === "failed" || undefined}>
      {o.quotes.map((q, i) => <QuoteCard key={i} q={q} />)}
      {o.text && <div className={chatCss.mBubble}>{o.text}</div>}
      <Files owner={(f) => ownerOf(here, f)} files={o.attachments} look={look} />
      {o.state === "failed" ? (
        // Not sent: said briefly (a tap says why); sending it again or dropping it right beside.
        <div className={css.mUnsent}>
          <button type="button" className={css.mUnsentNote} onClick={() => app.toast(o.error ? `没发出去：${o.error}` : "没发出去")}>未发送</button>
          <button type="button" className={css.mUnsentBtn} disabled={here.view.offline || !!here.view.archived} onClick={() => void (thread && sending.retry(thread.id, o.id).catch(() => {}))}>重试</button>
          <button type="button" className={css.mUnsentBtn} onClick={() => void (thread && sending.discard(thread.id, o.id))}>删除</button>
        </div>
      ) : <span className={`${chatCss.mMeta} ${chatCss.mWaiting}`}><Spinner size={10} />正在发送</span>}
    </div>
  );
}

/** A quote as sent: the quoted part on a warm ground (whose message, the passage) leading back to it, then what was said about it. */
function QuoteCard({ q, onJump }: { q: Quote; onJump?: (ts: string) => void }) {
  const ts = q.ts;
  return (
    <div className={css.mQuote}>
      <button type="button" className={css.mQuoteSource} disabled={!ts || !onJump} onClick={() => ts && onJump?.(ts)}>
        <QuoteIcon size={11} strokeWidth={2.4} />
        <span><b>{q.author}：</b>{q.text}</span>
      </button>
      {q.comment && <div className={css.mQuoteComment}>{q.comment}</div>}
    </div>
  );
}

// ── the running turn ───────────────────────────────────────────────────

// ── files ──────────────────────────────────────────────────────────────

/** The session a file is kept by: the agent whose workspace holds it, else the first. */
function ownerOf(here: Here, file: Attachment): string | null {
  return here.view.agents.find((a) => file.path.startsWith(`${a.session.workspace}/`))?.session.key ?? here.view.agents[0]?.session.key ?? null;
}

/** Files as the phone draws them (../Chat.tsx's `Files`): images at their own proportions within 240×200, known before they load; a tap shows one whole. */
const look: FileLook = {
  files: css.mFiles, image: css.mImage, open: css.mFileOpen,
  box: (file) => (file.width && file.height
    ? (() => { const scale = Math.min(1, 240 / file.width, 200 / file.height); return { width: Math.max(40, file.width * scale), height: Math.max(40, file.height * scale) }; })()
    : { width: 170, height: 120 }),
  card: (file) => <FileCard name={file.name} size={file.size} />,
};

function FileCard({ name, size, note, busy = false, onRemove, inComposer = false }: { name: string; size: number; note?: string | null | undefined; busy?: boolean; onRemove?: () => void; inComposer?: boolean }) {
  return (
    <span className={css.mFile} data-composer={inComposer || undefined}>
      {busy ? <Spinner size={16} /> : <File size={18} />}
      <span className={css.mFileText}><span>{name}</span><small data-error={note && !busy ? true : undefined}>{note ?? fileSize(size)}</small></span>
      {onRemove && <button type="button" className={css.mFileRemove} onClick={onRemove} aria-label={`移除 ${name}`}><Close size={12} /></button>}
    </span>
  );
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

/** What waits to go with the message: the quotes (each with a line for a comment), then the files. */
export function DraftExtras({ draft }: { draft: Draft }) {
  return (
    <>
      {draft.quotes.map((q) => (
        <div key={q.id} className={css.mDraftQuote}>
          <div className={css.mDraftQuoteSource}>
            <QuoteIcon size={12} strokeWidth={2.4} />
            <span><b>{q.author}：</b>{q.text}</span>
            <button type="button" onClick={() => draft.setQuotes((all) => all.filter((x) => x.id !== q.id))} aria-label="移除引用"><Close size={13} /></button>
          </div>
          <QuoteComment draft={draft} q={q} />
        </div>
      ))}
      {draft.files.length > 0 && (
        <div className={css.mDraftFiles}>
          {draft.files.map((f) => {
            const remove = () => draft.remove(f.id);
            return f.preview ? (
              <span key={f.id} className={css.mDraftThumb}>
                <img src={f.preview} alt={f.name} />
                {!f.done && <span className={css.mDraftThumbWait} data-error={f.error ? true : undefined}>{f.error ? "失败" : <Spinner size={16} color="#fff" />}</span>}
                <button type="button" onClick={remove} aria-label={`移除 ${f.name}`}><Close size={10} /></button>
              </span>
            ) : <FileCard key={f.id} name={f.done?.name ?? f.name} size={f.done?.size ?? f.size} note={f.error ?? (f.done ? null : "正在上传…")} busy={!f.done && !f.error} onRemove={remove} inComposer />;
          })}
        </div>
      )}
    </>
  );
}

function QuoteComment({ draft, q }: { draft: Draft; q: Draft["quotes"][number] }) {
  const input = useRef<HTMLInputElement>(null);
  useEffect(() => {
    if (draft.focusQuote !== q.id) return;
    input.current?.focus();
    draft.quoteFocused();
  }, [draft.focusQuote]); // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <input ref={input} className={css.mDraftQuoteComment} value={q.comment} placeholder="对这段说点什么（可以不写）"
      onChange={(e) => draft.setQuotes((all) => all.map((x) => (x.id === q.id ? { ...x, comment: e.target.value } : x)))}
      onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); draft.bumpFocus(); } }} />
  );
}

/** The bar, inside a floating capsule that is its frame: ＋, a field that grows with the text, and a round send button (a spinner while a new chat is made). */
export function ComposerBar({ draft, placeholder, locked = false, onPlus, onType, onSend }: { draft: Draft; placeholder: string; locked?: boolean; onPlus: () => void; onType: () => void; onSend: () => void }) {
  const field = useRef<HTMLTextAreaElement>(null);
  const ready = draft.ready && !locked;
  useEffect(() => { if (draft.focus > 0) field.current?.focus(); }, [draft.focus]);
  // The field grows with what is typed, up to six lines.
  useLayoutEffect(() => {
    const el = field.current;
    if (!el) return;
    el.style.height = "0px";
    el.style.height = `${Math.min(el.scrollHeight, 21 * 6)}px`;
  }, [draft.text]);
  return (
    <div className={css.mComposerBar}>
      <button type="button" className={css.mPlus} onClick={onPlus} disabled={locked} aria-label="添加文件"><Plus size={18} /></button>
      <textarea ref={field} className={css.mComposerField} rows={1} value={draft.text} placeholder={placeholder}
        onChange={(e) => { draft.setText(e.target.value); onType(); }}
        onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing && window.matchMedia("(hover: hover)").matches) { e.preventDefault(); if (ready) onSend(); } }} />
      <button type="button" className={css.mSend} data-ready={ready || undefined} disabled={!ready} onClick={onSend} aria-label="发送">
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
  const keeper = view.agents[0]?.session.key ?? null;
  const warmed = useRef(0);
  const send = (draft: Draft) => {
    if (view.offline || view.archived) return;
    // Before the agent has a chat, the message makes one.
    const thread = view.thread?.id;
    void draft.send(async () => thread ?? (await call.request<{ id: number }>("POST", "/threads", { session: here.key })).id, { first: thread === undefined });
  };
  useLayoutEffect(() => use({
    station: here.station, placeholder: view.archived ? "还原对话后才能发送" : "发消息", offline: view.offline, archived: !!view.archived, send,
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

/** The chat's agents' services and background jobs: those that matter now first, what is over faded and last. */
function jobsOf(view: ChatView) {
  return sorted(view.agents.flatMap((a) => a.jobs ?? []));
}

/** The bar's button for the chat's services and jobs, with a dot when one died lately (red) or a service restarts (amber). */
function JobsButton({ here, jobs }: { here: Here; jobs: Job[] }) {
  const app = useApp();
  const alarm = alarmOf(jobs, useNow(30_000));
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
      <div className={`${sheetsCss.mSheetScroll} ${partsCss.mPad18}`}>
        {jobs.length === 0 && <div className={css.mJobsEmpty}><b>还没有服务或后台任务</b><span>agent 开网页、或挂上长期盯着的任务时，会列在这里。</span></div>}
        {jobs.length > 0 && shown.length === 0 && <p className={homeCss.mNote}>眼下没有在跑的服务或任务。</p>}
        <JobGroups here={here} view={view} jobs={shown} now={now} notes />
        {hidden > 0 && (
          <button type="button" className={css.mJobsAll} onClick={() => setAll(!all)}>
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
      <span className={css.mJob} data-off={tone === "off" || undefined}>
        <JobDot tone={tone} />
        <span className={`${partsCss.mGrow} ${css.mJobText}`}><b>{job.name}</b><span>{metaOf(job, now)}</span></span>
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
  if (!job) return <><SheetGrab /><SheetHead title="任务" /><p className={homeCss.mNote}>这个任务已经不在了。</p></>;
  const lastAt = last?.outputAt ?? job.outputAt;
  return (
    <>
      <SheetGrab />
      <div className={css.mJobHead}>
        <JobDot tone={toneOf(job)} />
        <span className={partsCss.mGrow}><b>{job.name}</b><span>{metaOf(job, now)}</span></span>
      </div>
      <div className={`${partsCss.mPad18} ${css.mJobBody}`}>
        {job.command && <div className={css.mJobCommand}>{job.command}</div>}
        {!service && <Seg options={["通知", "输出"]} selected={tab} onSelect={setTab} fill height={34} />}
        {tab === 0
          ? (
            <div className={css.mJobNotices}>
              {(job.notices ?? []).length === 0 && <p className={homeCss.mNote}>还没有通知。</p>}
              {(job.notices ?? []).map((n, i) => <p key={`${n.at}-${i}`}><time>{clock(n.at, now)}</time><span>{n.text}</span></p>)}
            </div>
          )
          : <JobOutput station={station} job={job} />}
        {tab === 0 && (lastAt || last?.text) && <div className={css.mJobLast}><span>最后输出{lastAt ? ` · ${ago(lastAt, now)}` : ""}</span>{last?.text && <code>{last.text.trim()}</code>}</div>}
        {running && <button type="button" className={css.mJobStop} onClick={() => stop(job)}><Stop size={16} />停止</button>}
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
  const now = useNow();
  const view = useChat(here.station, { session: here.key }).value ?? here.view;
  const thread = view.thread ?? first;
  return (
    <>
      <SheetGrab />
      <SheetHead title="对话信息" />
      <div className={`${sheetsCss.mSheetScroll} ${partsCss.mPad18}`}>
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
            <InfoList><a className={listsCss.mInfoRow} href={view.slackUrl} target="_blank" rel="noopener"><SlackMark size={16} /><span className={partsCss.mGrow}>在 Slack 中打开</span><ChevronRight size={14} className={partsCss.mSubtle} /></a></InfoList>
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
                    <span className={`${partsCss.mGrow} ${css.mInfoAgent}`}>
                      <b>{s.agentText}</b>
                      <span>{a.connect && <SlackMark size={11} />}{[a.connect?.name, s.processText, s.time?.lastActiveAt?.ago].filter(Boolean).join(" · ")}</span>
                    </span>
                    <ChevronRight size={14} className={partsCss.mSubtle} />
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
  return <InfoRow><span className={css.mInfoLabel}>{label}</span>{extra}<span className={partsCss.mGrow}>{value}</span></InfoRow>;
}
