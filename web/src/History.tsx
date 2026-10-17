// Execution history, after Zork's: a readable account of what actually ran. The core puts it together
// (client/core-ts/src/history.ts): messages in and out, state marks and the agent's words stand alone; the tool calls and
// thinking between them fold into one group. Here it is only drawn: turn by turn (each prompt that woke the agent begins
// one, under a rule saying when and what it did), each event a mark in the gutter on the turn's rail and what it is beside
// it. What people were sent leads; the agent's own words, which reach no one, are a grey line.
import { PathSession } from "./Peeks.tsx";
import { failure, useToast } from "@stillfail/ui/toast.tsx";
import { DoingShown, useDoingState } from "./DoingMark.tsx";
import { Agent, Bell, CheckCircle, ChevronDown, ChevronRight, Command, Copy, Filter, Info, Said, Think, User, Wait, Received as ReceivedIcon, Send } from "@stillfail/ui/icons.tsx";
import { DropdownMenu } from "radix-ui";
import { createContext, memo, useCallback, useContext, useEffect, useLayoutEffect, useMemo, useRef, useState, type CSSProperties, type ReactNode } from "react";
import { flushSync } from "react-dom";
import { animate, EASE_OUT, reducedMotion, type AnimationPlaybackControls } from "@stillfail/ui/motion.ts";
import { useApi, useHistory, useHistoryDetail, useHistoryOlder, type HistoryGroup, type HistoryItem, type HistoryMark, type HistoryMessage, type HistoryStep, type HistoryTask, type HistoryTurn, type HistoryView, type Place } from "./api.ts";
import { ICON, IconButton, Pill, SlackLogo, Tip } from "./ui.tsx";
import { useCopyChatLink } from "./ChatRef.tsx";
import { useLink, useStation } from "./station.tsx";
import { Link } from "react-router";
import { MdView } from "./Prose.tsx";
import type { Md } from "./core/md.ts";
import { mdHead, mdLines, textHead, textLines } from "../../client/core-ts/src/mdHead.ts";
import { ToolCall, ToolResult } from "./ToolStep.tsx";
import * as toolCss from "./ToolStep.css.ts";
import { useLoadNear, Waited } from "./Chat.tsx";
import { KeepRow, useKeepRow, useRowKept, useVirtualList, useVirtualModel } from "./virtual/list.tsx";
import type { Item, Virtual } from "./virtual/model.ts";
import { Mark } from "./brand.tsx";
import * as css from "./History.css.ts";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import * as conversationCss from "./styles/conversation.css.ts";
import * as shellCss from "./styles/shell.css.ts";

import { NAME } from "./channel.ts";
import { t } from "./i18n.ts";
import { ReadWhole, useWhole } from "./brief.ts";

/** The room between two items of a history (History.css.ts `historyBody`). */
const GAP_PX = 14;

/** Whether a history shows only what came in and went out (and how turns ended), kept in this browser for every history. */
const ONLY_IO = "stillfail.history.onlyIo";
function readOnlyIo(): boolean {
  try { return localStorage.getItem(ONLY_IO) === "1"; } catch { return false; }
}
function keepOnlyIo(on: boolean): void {
  try { if (on) localStorage.setItem(ONLY_IO, "1"); else localStorage.removeItem(ONLY_IO); } catch { /* not kept */ }
}
/** What "只看收发" leaves out: the work (calls and thinking) and the agent's own words. */
const isWork = (item: HistoryItem) => item.body.kind === "group" || item.body.kind === "text";

/** About how many Latin letters a line of the pane holds: what a fold says it hides, of words it has not measured. */
const Per = createContext(70);

/**
 * The session as it ran: the main view of a session. `head` says what it runs on and `summary` what needs seeing to
 * (both in the head); `details` unfold under the head, open to begin with, from its switch there: the history's own,
 * not its tab's (a chat's agents each have a tab).
 * With its chat's `title`, each item offers its link (opening the history there), to paste into another chat.
 */
export function History({ station, sessionKey, head, summary, details, focusEntry = null, focusN = 0, title }: {
  station: string; sessionKey: string; head?: ReactNode; summary?: ReactNode; details?: ReactNode; title?: string | undefined;
  /** An entry to bring into view (`focusN` changes each time it is asked for); null: none. */
  focusEntry?: number | null; focusN?: number;
}) {
  const focus = focusEntry === null ? null : { entry: focusEntry, n: focusN };
  const history = useHistory(station, sessionKey).value;
  const paths = useMemo(() => ({ key: sessionKey, station }), [sessionKey, station]);
  const [usageOpen, setUsageOpen] = useState(true);
  const [onlyIo, setOnlyIo] = useState(readOnlyIo);
  const showIo = (on: boolean) => { setOnlyIo(on); keepOnlyIo(on); };
  // The steps' and thoughts' whole words: read only as one is opened (the core has them in brief till then).
  const detail = useHistoryDetail(station, sessionKey);
  const body = useRef<HTMLDivElement>(null);
  const loaded = history?.items ?? [];
  const all = onlyIo ? loaded.filter((item) => !isWork(item)) : loaded;
  const live = onlyIo ? [] : history?.live ?? [];
  // Only the items in and near the pane are made (virtual/list.tsx), the latest first: the pane follows new steps
  // while the reader is at its end and keeps their place when they scrolled up; the pages before load as they near
  // the top.
  // No room is held at its end: a text folded once it is measured only makes the history shorter.
  const made = useVirtualModel(`history ${station} ${sessionKey}`, GAP_PX, false);
  // About how many Latin letters a line of the pane holds (six pixels a letter or more): for how tall an item stands
  // before it is measured.
  const per = (made.model.paneWidth || 420) / 6;
  const list: Item[] = [];
  if (history && !history.empty) {
    list.push({ key: "edge", estimate: 18, place: false });
    // `tall` is the least an item stands: about that much more is what one stands on the whole, before any is measured.
    for (const item of all) list.push({ key: `h:${item.key}`, estimate: tall(item, per) * 1.4 });
    for (const s of live) list.push({ key: `l:${s.id}`, estimate: 20, place: false });
    if (history.phase) list.push({ key: "phase", estimate: 20, place: false });
  }
  // What came at the end since it was last drawn (not what it opens with): followed gliding, from its top.
  const last = all.at(-1)?.key;
  const was = useRef({ last, sessionKey });
  const came = was.current.sessionKey === sessionKey && was.current.last !== undefined && last !== undefined && last !== was.current.last;
  useEffect(() => { was.current = { last, sessionKey }; });
  const virtual = useVirtualList(body, made, list, { smooth: true, arrived: came ? `h:${last}` : null });
  const older = useHistoryOlder(station, sessionKey);
  useLoadNear(virtual, "top", history?.more ?? false, all[0]?.key, older);
  // Opened at an entry (an activity row): the item that draws it comes to the pane's middle, and says so for a moment.
  // One before what is loaded: the pages before come first; one "只看收发" leaves out: all of it shows again first.
  const focused = useRef<number | null>(null);
  useEffect(() => {
    if (!focus || focused.current === focus.n) return;
    const found = loaded.find((item) => (item.entries[0] ?? 0) <= focus.entry && focus.entry <= (item.entries[1] ?? -1));
    if (!found) {
      if (history?.more && focus.entry < (loaded[0]?.entries[0] ?? 0)) void older().catch(() => {});
      return;
    }
    if (onlyIo && isWork(found)) return showIo(false);
    focused.current = focus.n;
    virtual.goto(`h:${found.key}`, "center");
    // Its row made by then.
    const frame = requestAnimationFrame(() => requestAnimationFrame(() => {
      const el = body.current?.querySelector<HTMLElement>(`:scope > [data-vk="${CSS.escape(`h:${found.key}`)}"]`);
      if (!el) return;
      el.dataset.focus = "";
      setTimeout(() => delete el.dataset.focus, 1600);
    }));
    return () => cancelAnimationFrame(frame);
  }, [focus?.n, loaded[0]?.key, loaded.length > 0, onlyIo]); // eslint-disable-line react-hooks/exhaustive-deps
  // What was there when the history opened (and older pages loaded later) shows at once; only what comes later animates.
  const seen = useRef(Number.POSITIVE_INFINITY);
  if (seen.current === Number.POSITIVE_INFINITY && history?.loaded) seen.current = loaded.at(-1)?.entries[1] ?? -1;
  // An item eases in the first time its row is made only: made again as the reader scrolls back to it, it is there.
  const gone = useRef(new Set<string>());
  const rowsMade = useRef(new Set<string>());
  const nowMade = new Set(virtual.layout.rows.map((r) => r.key));
  for (const key of rowsMade.current) if (!nowMade.has(key)) gone.current.add(key);
  useEffect(() => { rowsMade.current = nowMade; });
  // What each item is: only those the list makes are drawn.
  const drawn = new Map<string, () => ReactNode>();
  if (history && !history.empty) {
    drawn.set("edge", () => <p key="edge" data-vk="edge" className={css.historyEdge}>{history.edge}</p>);
    // The turn's rail runs on from an item to the next unless the next begins a turn of its own; from the last, to what
    // is in flight.
    const going = live.length > 0 || history.phase != null;
    all.forEach((item, i) => {
      const next = all[i + 1];
      const rail = next ? next.turn == null : going;
      // Entries that arrive while watching ease in; a reply that streamed in place does not (it is already there).
      drawn.set(`h:${item.key}`, () => <HistoryRow key={item.key} item={item} rail={rail} enter={(item.entries[0] ?? 0) > seen.current && item.body.kind !== "text" && !gone.current.has(`h:${item.key}`)}
        station={station} session={sessionKey} title={title} keep={made.model} />);
    });
    // Only thinking and the reply stream here; a tool call shows once it is done, from the transcript.
    live.forEach((s, i) => drawn.set(`l:${s.id}`, () => (
      <div key={`l:${s.id}`} data-vk={`l:${s.id}`} className={css.hMain} data-rail={i < live.length - 1 || history.phase != null || undefined}>
        <Ev icon={<Think {...ICON} size={14} />}><div className={css.hLiveThinking}>{s.text}</div></Ev>
      </div>
    )));
    if (history.phase) { const phase = history.phase; drawn.set("phase", () => <PhaseLine key="phase" phase={phase} />); }
  }
  const usage = history?.usage;

  return (
    // The paths its agent writes are its session's files (Peeks.tsx).
    <PathSession.Provider value={paths}>
    <ReadWhole.Provider value={detail}>
    <Per.Provider value={per}>
    <section className={css.history} aria-label={t("web-main.history.label")}>
      <header className={css.historyHead}>
        <div className={css.historyIdentity}>{head}{summary}</div>
        <div className={css.historyTools}>
          <Tip label={t("web-main.history.onlyIoTip")}>
            <button type="button" className={`${controlsCss.textToggle} ${css.onlyIo}`} aria-pressed={onlyIo} onClick={() => showIo(!onlyIo)}>
              <Filter {...ICON} size={14} />{t("web-main.history.onlyIo")}
            </button>
          </Tip>
          {(usage || details) && (
            <button type="button" className={controlsCss.textToggle} aria-expanded={usageOpen} onClick={() => setUsageOpen(!usageOpen)}>
              {t("web-main.history.details")} <ChevronDown {...ICON} size={14} className={usageOpen ? css.flip : undefined} />
            </button>
          )}
        </div>
      </header>
      {usageOpen && details && <div className={css.historyDetails}>{details}</div>}
      {usageOpen && usage && !details && (
        <dl className={css.usage}>{usage.map((u) => <div key={u.label}><dt>{u.label}</dt><dd>{u.value}</dd></div>)}</dl>
      )}
      <div className={css.historyBody} ref={body}>
        {!history ? <p className={css.historyEdge}>{t("web-main.history.reading")}</p> : history.empty ? <p className={css.historyEdge}>{history.edge}</p> : (
          <>
            {virtual.layout.rows.flatMap((row, i) => [virtual.above(row, i === 0), drawn.get(row.key)?.()])}
            {virtual.after()}
          </>
        )}
      </div>
    </section>
    </Per.Provider>
    </ReadWhole.Provider>
    </PathSession.Provider>
  );
}

// An item's rows as History.css.ts draws them: an event's line (and a line of words), a line of a sent message's words,
// the switch under a folded text, the gap between two events of an item, a state's block, a turn's rule above its first.
const LINE_PX = 20;
const POST_LINE_PX = 23;
const SWITCH_PX = 20;
const EVENT_GAP_PX = 10;
const STATE_PX = 32;
const TURN_PX = 30;
/** The least `item` stands tall where a line holds `per` Latin letters: a message folded to its lines, the rest a line. */
function tall(item: HistoryItem, per: number): number {
  const folded = (lines: number, most: number, line: number) => (lines > most ? most * line + SWITCH_PX : lines * line);
  const events = (heights: number[]) => heights.reduce((sum, h) => sum + h, 0) + Math.max(0, heights.length - 1) * EVENT_GAP_PX;
  const body = item.body;
  const turn = item.turn ? TURN_PX : 0;
  switch (body.kind) {
    case "text": return turn + LINE_PX;
    case "post": return turn + events([LINE_PX + 20 + folded(mdLines(body.content.md as Md, per * 0.9, POST_LINES + 1), POST_LINES, POST_LINE_PX), ...(body.content.ends ? [STATE_PX] : [])]);
    case "received":
      return turn + events([
        ...(body.content.note ? [LINE_PX] : []),
        ...body.content.tasks.map((task) => LINE_PX + (task.md ? LINE_PX : 0)),
        ...body.content.messages.map((m) => LINE_PX + folded(textLines(m.text, per, WORDS_LINES + 1), WORDS_LINES, LINE_PX)),
      ]);
    case "mark": return turn + STATE_PX;
    case "group": return turn + LINE_PX + 8;
  }
}
/** The lines a sent message and a person's words show folded. */
const POST_LINES = 6;
const WORDS_LINES = 4;

/** An item and its link's button, drawn again only when the item changes (or its place in the list). */
const HistoryRow = memo(function HistoryRow({ item, rail, enter, station, session, title, keep }: {
  item: HistoryItem; enter: boolean; station: string; session: string;
  /** The turn's rail runs on below it, to the next item. */
  rail: boolean;
  /** The list's model: the row stays made while something the reader opened in it is open (its state is the row's). */
  keep: Virtual;
  /** Its chat's title: with it, the item offers its link (opening the history there), to paste into another chat. */
  title: string | undefined;
}) {
  const copyLink = useCopyChatLink(useToast());
  const entry = item.entries[0];
  const key = `h:${item.key}`;
  const hold = useRowKept(keep, key);
  return (
    <div className={css.hItem} data-vk={key} data-enter={enter || undefined}>
      {item.turn && <TurnRule turn={item.turn}>
        {title !== undefined && entry !== undefined && <IconButton className={css.hTurnLink} label={t("web-main.history.copyLink")} icon={Copy}
          onClick={() => copyLink({ station, session, id: session, title }, { key: session, entry })} />}
      </TurnRule>}
      <div className={css.hMain} data-rail={rail || undefined}>
        <KeepRow.Provider value={hold}><HistoryItemView item={item} /></KeepRow.Provider>
      </div>
    </div>
  );
});

/** Where a turn begins: when, and what it did (the core's words), on a rule; at its end, the turn's link to copy. */
function TurnRule({ turn, children }: { turn: HistoryTurn; children?: ReactNode }) {
  return <div className={css.hTurn}><span>{turn.time ? `${turn.time} · ${turn.text}` : turn.text}</span>{children}</div>;
}

/**
 * One event of an item: its mark in the gutter (on the turn's rail) and what it is beside it. `state`: how the turn
 * stands or ended, drawn as a block in its colour.
 */
function Ev({ icon, state, tone, children }: { icon: ReactNode; state?: string | undefined; tone?: "accent" | "red" | undefined; children: ReactNode }) {
  return (
    <div className={css.hEv} data-state={state} data-tone={tone}>
      <span className={css.hIcon}>{icon}</span>
      <div className={css.hEvBody}>{children}</div>
    </div>
  );
}

/** A place as its platform's mark and its name: a Slack thread opens in Slack; a still.fail chat, its agent's page. */
function Where({ place }: { place: Place }) {
  const link = useLink();
  const inner = <>{(place.surface === "ember" || place.surface === "stillfail") ? <Mark size={12} /> : <SlackLogo size={12} />}<span className={css.hPlaceName}>{place.name}</span></>;
  if (place.url) return <a className={css.hPlace} href={place.url} target="_blank" rel="noopener">{inner}</a>;
  return place.session
    ? <Link className={css.hPlace} to={link(`/chats/${encodeURIComponent(place.session)}`)}>{inner}</Link>
    : <span className={css.hPlace}>{inner}</span>;
}

const HistoryItemView = memo(function HistoryItemView({ item }: { item: HistoryItem }) {
  const body = item.body;
  switch (body.kind) {
    case "received":
      return (
        <>
          {body.content.note && <Reminder text={body.content.note} />}
          {body.content.tasks.map((task, i) => <Task key={i} task={task} />)}
          {body.content.messages.map((m) => (
            <Received key={m.key} message={m} place={m.place ? <Where place={m.place} /> : null}
              from={m.from.slackUser ? <SlackName user={m.from.slackUser} name={m.from.name} bound={m.from.bound} /> : m.notice === "stillfail" ? NAME : m.from.name} />
          ))}
        </>
      );
    case "text":
      // The agent's own words reach no one (only what it posts does): a grey line, whole as it is opened.
      return (
        <Ev icon={<Said {...ICON} size={14} />}>
          <OneLine lead={<span className={css.hTag}>{t(body.content.subagent ? "web-main.history.subagent" : "web-main.history.notSent")}</span>}
            line={firstLine(body.content.text)}>
            <div className={`${conversationCss.markdown} ${css.hNote}`}><MdView md={body.content.md as Md} /></div>
          </OneLine>
        </Ev>
      );
    case "post":
      return (
        <>
          <Ev icon={<Send {...ICON} size={14} />} tone={body.content.failed ? "red" : "accent"}>
            <div className={css.hLabel}>
              {t("web-main.history.sentTo")}{body.content.place ? <Where place={body.content.place} /> : <span className={css.hPlace}><SlackLogo size={12} />Slack</span>}
              {body.content.block && !body.content.ends && <Pill tone="blue">Block</Pill>}
              {body.content.failed && <Pill tone="red">{t("web-main.history.sendFailed")}</Pill>}
            </div>
            <div className={css.hCard} data-failed={body.content.failed}>
              <Fold className={conversationCss.markdown} of={body.content.md as Md} lines={POST_LINES} head={headOf(body.content.md as Md)}><MdView md={body.content.md as Md} /></Fold>
            </div>
          </Ev>
          {body.content.ends && <Ended ends={body.content.ends} text={t(body.content.ends === "human" ? "web-main.history.ends.human" : "web-main.history.ends.done")} />}
        </>
      );
    case "mark":
      return <MarkView mark={body.content} />;
    case "group":
      return <Group group={body.content} />;
  }
});

/** The first line of some words that has any: what a one-line event shows of them. */
function firstLine(text: string): string {
  return text.split("\n").find((l) => l.trim() !== "")?.trim() ?? "";
}

/**
 * An event in one line, its words cut at its end: opened, what `children` say in whole under it. Its lead (who, what
 * kind) stays; the line's words give way to the whole.
 */
function OneLine({ lead, line, failed, children }: { lead: ReactNode; line: string; failed?: boolean; children?: ReactNode }) {
  const [open, setOpen] = useState(false);
  useKeepRow(open);
  if (children == null) return <div className={css.hOne} data-failed={failed}>{lead}{line && <span className={css.hOneText}>{line}</span>}</div>;
  return (
    <>
      <button type="button" className={css.hOne} data-failed={failed} aria-expanded={open} onClick={() => setOpen(!open)}>
        {lead}{!open && line && <span className={css.hOneText}>{line}</span>}
        {open && <span className={css.hOneFold}>{t("web-main.fold")}</span>}
      </button>
      {open && <div className={css.hOneBody}>{children}</div>}
    </>
  );
}

/** A turn's state: waiting on work it started (counting on while it does, its bar filling toward the most it waits), done,
 * or waiting on a person; words the station no longer uses, a plain block. */
function MarkView({ mark }: { mark: HistoryMark }) {
  const wait = mark.wait;
  if (wait) {
    const still = wait.until == null;
    return (
      <Ev icon={<Wait {...ICON} size={14} />} state={still ? "waiting" : "waited"}>
        <div className={css.hStateLine}>
          {still
            ? <span className={css.hStateText}>{wait.what != null && <>{wait.what} · </>}{t("web-main.activity.waiting")} <Waited since={wait.since} seconds={wait.seconds} /></span>
            : <span className={css.hStateText}>{mark.text}</span>}
        </div>
        {still && wait.seconds != null && wait.seconds > 0 && <WaitBar since={wait.since} seconds={wait.seconds} />}
      </Ev>
    );
  }
  return <Ended ends={mark.ends} text={mark.text} />;
}

/** How a turn ended: done, or waiting on a person (or on work it started, from a transcript that did not say when; or
 * words of another state). */
function Ended({ ends, text }: { ends: string | undefined; text: string }) {
  const Icon = ends === "human" ? User : ends === "done" ? CheckCircle : ends === "waiting" ? Wait : Info;
  return (
    <Ev icon={<Icon {...ICON} size={14} />} state={ends === "human" ? "human" : ends === "done" ? "done" : ends === "waiting" ? "waited" : "other"}>
      <div className={css.hStateLine}><span className={css.hStateText}>{text}</span></div>
    </Ev>
  );
}

/** How much of the most it waits has gone: filled on the compositor, from where it stands when drawn to full at its end. */
function WaitBar({ since, seconds }: { since: number; seconds: number }) {
  const [gone] = useState(() => Math.max(0, (Date.now() - since) / 1000));
  return (
    <span className={css.hWaitBar} aria-hidden="true">
      <i style={{ animationDuration: `${seconds}s`, animationDelay: `-${Math.min(gone, seconds)}s` }} />
    </span>
  );
}

/**
 * A Slack user's name: "你" once the viewer said it is them. Clicking it offers "这是我" (the station then takes that
 * Slack user for the viewer), or "不是我" once it does.
 */
function SlackName({ user, name, bound }: { user: string; name: string; bound: boolean }) {
  const api = useApi();
  const toast = useToast();
  // Said to the station: the name turns until it answers; a red mark beside it a few seconds if that failed.
  const state = useDoingState("slack.identity", { station: useStation().address, user });
  const saying = state.running;
  return (
    <DropdownMenu.Root modal={false}>
      <DropdownMenu.Trigger className={css.hPerson} disabled={saying} aria-busy={saying || undefined}>
        {name}<DoingShown state={state} className={css.hPersonSpinner} size={11} />
      </DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content className={`${controlsCss.popover} ${controlsCss.menuList}`} align="start" sideOffset={4} collisionPadding={8}>
          <DropdownMenu.Item className={controlsCss.menuItem} onSelect={() => void api.slackIdentity(user, !bound).catch((error: unknown) => toast(t(bound ? "web-main.history.unbindFailed" : "web-main.history.bindFailed", { error: failure(error) })))}>{bound ? t("web-main.history.notMe") : t("web-main.history.isMe")}</DropdownMenu.Item>
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}

/** A message: who and where in a line, their words under it; a job's as it wrote them, in a monospaced font. */
function Received({ from, message, place }: { from: ReactNode; message: HistoryMessage; place?: ReactNode }) {
  const { text, notice } = message;
  return (
    <Ev icon={<ReceivedIcon {...ICON} size={14} />}>
      <div className={css.hLabel}>{t(notice === "job" ? "web-main.history.jobMessage.before" : "web-main.history.message.before")}<strong>{from}</strong>{t(notice === "job" ? "web-main.history.jobMessage.after" : "web-main.history.message.after")}{place && <> · {place}</>}</div>
      <Fold className={notice === "job" ? css.hOutput : css.hWords} of={text} lines={WORDS_LINES} head={textHead(text, HEAD_LINES)}>{text}</Fold>
    </Ev>
  );
}

/** still.fail's own words to the agent (its reminders, its notes around messages): a line, whole as it is opened. */
function Reminder({ text }: { text: string }) {
  return (
    <Ev icon={<Bell {...ICON} size={14} />}>
      <OneLine lead={<strong>{t("web-main.history.reminder", { name: NAME })}</strong>} line={firstLine(text)}>
        <div className={css.hNotePlain}>{text}</div>
      </OneLine>
    </Ev>
  );
}

/**
 * Work the agent started in the background, ended: a line saying how; what a sub-agent answered in a line under it,
 * whole as the line saying how is opened.
 */
function Task({ task }: { task: HistoryTask }) {
  const Icon = task.agent ? Agent : Command;
  const [open, setOpen] = useState(false);
  useKeepRow(open);
  const answer = task.md != null && task.result != null ? firstLine(task.result) : null;
  return (
    <Ev icon={<Icon {...ICON} size={14} />} tone={task.failed ? "red" : undefined}>
      {answer === null
        ? <div className={css.hOne} data-failed={task.failed}><span className={css.hOneText}>{task.text}</span></div>
        : <button type="button" className={css.hOne} data-failed={task.failed} aria-expanded={open} onClick={() => setOpen(!open)}>
            <span className={css.hOneText}>{task.text}</span>{open && <span className={css.hOneFold}>{t("web-main.fold")}</span>}
          </button>}
      {answer !== null && (open
        ? <div className={css.hOneBody}><div className={`${conversationCss.markdown} ${css.hNote}`}><MdView md={task.md as Md} /></div></div>
        : <div className={css.hOne}><span className={css.hOneText}>{answer}</span></div>)}
    </Ev>
  );
}

function Group({ group }: { group: HistoryGroup }) {
  const [open, setOpen] = useState(false);
  useKeepRow(open);
  const { rows, failures, pending } = group;
  const calls = rows.some((row) => row.kind === "step");
  return (
    <div className={`${css.hEv} ${css.hGroup}`} data-failed={failures > 0}>
      <Tip label={group.title || undefined}><button type="button" className={css.hGroupHead} aria-expanded={open} onClick={() => setOpen(!open)}>
        <span className={css.hIcon}>{open ? <ChevronDown {...ICON} size={14} /> : <ChevronRight {...ICON} size={14} />}</span>
        <span className={css.hGroupSummary}>{group.summary}</span>
        {failures > 0 && <Pill tone="red">{t("web-main.history.failures", { n: failures })}</Pill>}
        {pending > 0 && <Pill tone="accent">{t("web-main.history.pending", { n: pending })}</Pill>}
      </button></Tip>
      {open && (
        <div className={css.hSteps}>
          {rows.map((row, i) => row.kind === "thought" ? (calls ? (
            <Opened key={i} className={css.hStep} brief={row.content.brief} entries={row.content.entries}
              summary={<><span className={css.hStepName}>{t("web-main.history.thinking")}</span><span className={css.hStepHint}>{row.content.first}</span></>}>
              <div className={`${css.hStepBody} ${shellCss.muted}`}>{row.content.text}</div>
            </Opened>
          ) : (
            <Whole key={i} brief={row.content.brief} entries={row.content.entries}><div className={css.hThinking}>{row.content.text}</div></Whole>
          )) : (
            <Step key={i} step={row.content} />
          ))}
        </div>
      )}
    </div>
  );
}

function Step({ step }: { step: HistoryStep }) {
  return (
    <Opened className={css.hStep} failed={step.failed} brief={step.brief} entries={step.entries}
      summary={<>
        {step.said
          ? <span className={css.hStepSaid}>{step.said}</span>
          : <><span className={css.hStepName}>{step.name}</span><span className={css.hStepHint}>{step.hint}</span></>}
        <span className={css.hStepMeta}>{step.meta}</span>
      </>}>
      <div className={toolCss.body}>
        <div className={toolCss.section}><ToolCall name={step.name} call={step.call} said={step.said !== undefined} /></div>
        {step.result !== undefined && <ToolResult name={step.name} call={step.call} result={step.result} failed={step.failed} />}
      </div>
    </Opened>
  );
}

/**
 * A line of a group that opens to what is behind it. In brief (what is behind it not here: only what names it came), it
 * is read whole as it is opened.
 */
function Opened({ className, failed, brief, entries, summary, children }: {
  className: string; failed?: boolean; brief: boolean; entries: number[]; summary: ReactNode; children: ReactNode;
}) {
  const [open, setOpen] = useState(false);
  useKeepRow(open);
  return (
    <details className={className} data-failed={failed} onToggle={(e) => setOpen(e.currentTarget.open)}>
      <summary>{summary}</summary>
      {open && <Whole brief={brief} entries={entries}>{children}</Whole>}
    </details>
  );
}

/** What a step or thought holds, as it shows: in brief, read whole now, saying so till it comes (or why it did not). */
function Whole({ brief, entries, children }: { brief: boolean; entries: number[]; children: ReactNode }) {
  const reading = useWhole(brief, entries);
  if (reading === null) return <>{children}</>;
  return <div className={`${css.hStepBody} ${shellCss.muted}`}>{reading.error === null ? t("web-main.history.stepReading") : t("web-main.history.stepUnread", { error: reading.error })}</div>;
}

/** Each fold measured by the one observer: how it says it turned out long, and how many lines it shows folded. */
const folds = new Map<Element, { set: (more: number) => void; lines: number }>();
let watching: ResizeObserver | null = null;
function foldWatch(): ResizeObserver {
  return watching ??= new ResizeObserver((entries) => {
    const read = entries.flatMap(({ target }) => {
      const fold = folds.get(target);
      if (!fold) return [];
      const line = parseFloat(getComputedStyle(target).lineHeight) || 21;
      // The lines past those it shows (none: it is not long), what its height says.
      const past = (target.scrollHeight - line * fold.lines - 4) / line;
      return [[fold.set, past > 0 ? Math.max(1, Math.round(past)) : 0] as const];
    });
    if (read.length) flushSync(() => { for (const [set, more] of read) set(more); });
  });
}

// Words that surely fill more than a fold shows have only their beginning drawn while folded: these lines of them, a
// few past the most shown (mdHead counts no more lines than are drawn, however wide the panel).
const HEAD_LINES = 8;
/** How many lines a fold turned out to hide, as last measured (0: none, it is short). */
const longTrees = new WeakMap<Md, number>();
const longTexts = new Map<string, number>();
const heads = new WeakMap<Md, ReactNode>();
/** The beginning of `md` a fold draws while folded, the same one for the same tree; null for words that may be short. */
function headOf(md: Md): ReactNode {
  let head = heads.get(md);
  if (head === undefined) {
    const cut = mdHead(md, HEAD_LINES);
    heads.set(md, head = cut ? <MdView md={cut} /> : null);
  }
  return head;
}

/**
 * Long text in the history folds to `lines` lines, its last fading out; a button under it unfolds it, saying how many
 * lines it hides. Height is measured, so markdown (lists, code) folds the same way as plain text. Text known to be long
 * (`head`, its beginning) is folded as it comes, unmeasured, and only that beginning is drawn until it is unfolded: a
 * history coming in lays out the lines it shows, not all the words of its long entries (what it hides is then counted
 * from its words, about so many).
 */
function Fold({ children, of, lines = 5, head = null, className }: { children: ReactNode;
  /** What it folds (an entry's tree, a message's words): whether it turned out long is kept by it, so its row made
   *  again as the reader scrolls back (or the history opened again) is folded as it comes, not measured anew. */
  of: Md | string; lines?: number; head?: ReactNode; className?: string;
}) {
  const box = useRef<HTMLDivElement>(null);
  const per = useContext(Per);
  const cut = head != null;
  const [measured, setMeasured] = useState(() => (typeof of === "string" ? longTexts.get(of) : longTrees.get(of)) ?? 0);
  const setMore = useCallback((more: number) => {
    if (typeof of !== "string") longTrees.set(of, more);
    else {
      if (longTexts.size > 2000) longTexts.clear();
      longTexts.set(of, more);
    }
    setMeasured(more);
  }, [of]);
  const long = cut || measured > 0;
  const [open, setOpen] = useState(false);
  useKeepRow(open);
  // All of it drawn: unfolded, or on its way back to folded.
  const [whole, setWhole] = useState(false);
  const run = useRef<AnimationPlaybackControls | null>(null);
  // Measured before paint, so a long entry never shows at full height first: by the one observer all folds share, which
  // reads them once the page is laid out (its first report comes before the first paint) and folds the long ones
  // together. Read as each one mounted, a history coming in laid the whole page out in the middle of its commit.
  useLayoutEffect(() => {
    const el = box.current;
    if (!el || cut) return;
    folds.set(el, { set: setMore, lines });
    foldWatch().observe(el);
    return () => { folds.delete(el); foldWatch().unobserve(el); };
  }, [cut, setMore, lines]);
  useEffect(() => () => run.current?.stop(), []);
  // Only a reader's own click moves it (folding on arrival happens before the first paint): from the height it shows
  // (on its way, if clicked again) to the one it has now.
  const toggle = () => {
    const el = box.current!;
    const from = el.getBoundingClientRect().height;
    run.current?.stop();
    Object.assign(el.style, { height: "", maxHeight: "", overflow: "" });
    flushSync(() => { setOpen(!open); setWhole(true); });
    const to = el.getBoundingClientRect().height;
    if (reducedMotion() || Math.abs(to - from) < 1) return void (open && setWhole(false));
    // Its fold's height limit held off while it moves, what is past its height hidden.
    // Held at where it was until the motion takes it (from the next frame): the new height is never seen at once.
    Object.assign(el.style, { maxHeight: "none", overflow: "hidden", height: `${from}px` });
    const now = animate(el, { height: [`${from}px`, `${to}px`] }, { duration: 0.24, ease: EASE_OUT });
    run.current = now;
    void now.finished.then(() => { if (run.current === now) { Object.assign(el.style, { height: "", maxHeight: "", overflow: "" }); run.current = null; if (open) setWhole(false); } }, () => {});
  };
  // What it hides: measured, or (only its beginning drawn) counted from its words.
  const counted = cut && measured === 0;
  const more = counted ? Math.max(1, (typeof of === "string" ? textLines(of, per, 999) : mdLines(of, per, 999)) - lines) : measured;
  return (
    <div className={css.fold}>
      <div ref={box} className={`${css.foldBody}${className ? ` ${className}` : ""}`} style={{ "--fold-lines": lines } as CSSProperties}
        data-folded={long && !open ? true : undefined}>{cut && !whole ? head : children}</div>
      {long && <button type="button" className={`${controlsCss.textToggle} ${css.foldToggle}`} onClick={toggle}>
        {open ? t("web-main.fold") : t(counted ? "web-main.history.moreAbout" : "web-main.history.more", { n: more })}
      </button>}
    </div>
  );
}

/** The turn's state with the model (the core's words), with a running clock. */
function PhaseLine({ phase }: { phase: NonNullable<HistoryView["phase"]> }) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, []);
  const seconds = Math.max(0, Math.floor((now - phase.since) / 1000));
  return (
    <div className={`${css.hMain} ${css.hPhase}`} data-vk="phase" data-phase={phase.phase}>
      <Ev icon={<span className={conversationCss.activityPulse} aria-hidden="true" />}>
        <div className={css.hPhaseLine}>
          <span key={phase.phase} className={css.hPhaseText}>{phase.text}</span>
          <span className={css.hPhaseTime}>{seconds}s</span>
        </div>
      </Ev>
    </div>
  );
}
