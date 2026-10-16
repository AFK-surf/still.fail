// Execution history, after Zork's: a readable account of what actually ran. The core puts it together
// (client/core-ts/src/history.ts): messages in and out, state marks and the agent's words stand alone; the tool calls and
// thinking between them fold into one group. Here it is only drawn.
import { PathSession } from "./Peeks.tsx";
import { failure, useToast } from "@stillfail/ui/toast.tsx";
import { DoingShown, useDoingState } from "./DoingMark.tsx";
import { Agent, ChevronDown, ChevronRight, Command, Copy, Wait, Received as ReceivedIcon, Send } from "@stillfail/ui/icons.tsx";
import { DropdownMenu } from "radix-ui";
import { memo, useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { flushSync } from "react-dom";
import { animate, EASE_OUT, reducedMotion, type AnimationPlaybackControls } from "@stillfail/ui/motion.ts";
import { useApi, useHistory, useHistoryDetail, useHistoryOlder, type HistoryGroup, type HistoryItem, type HistoryStep, type HistoryTask, type HistoryView, type Place } from "./api.ts";
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
import * as additionsCss from "./styles/additions.css.ts";

import { NAME } from "./channel.ts";
import { t } from "./i18n.ts";
import { ReadWhole, useWhole } from "./brief.ts";

/** How many of a history's latest items are drawn when it opens, and how many more each time the reader nears its top. */
/** The room between two items of a history (History.css.ts `historyBody`). */
const GAP_PX = 14;

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
  // The steps' and thoughts' whole words: read only as one is opened (the core has them in brief till then).
  const detail = useHistoryDetail(station, sessionKey);
  const body = useRef<HTMLDivElement>(null);
  const all = history?.items ?? [];
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
    for (const s of history.live) list.push({ key: `l:${s.id}`, estimate: 40, place: false });
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
  // One before what is loaded: the pages before come first.
  const focused = useRef<number | null>(null);
  useEffect(() => {
    if (!focus || focused.current === focus.n) return;
    const found = all.find((item) => (item.entries[0] ?? 0) <= focus.entry && focus.entry <= (item.entries[1] ?? -1));
    if (!found) {
      if (history?.more && focus.entry < (all[0]?.entries[0] ?? 0)) void older().catch(() => {});
      return;
    }
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
  }, [focus?.n, all[0]?.key, all.length > 0]); // eslint-disable-line react-hooks/exhaustive-deps
  // What was there when the history opened (and older pages loaded later) shows at once; only what comes later animates.
  const seen = useRef(Number.POSITIVE_INFINITY);
  if (seen.current === Number.POSITIVE_INFINITY && history?.loaded) seen.current = all.at(-1)?.entries[1] ?? -1;
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
    for (const item of all) {
      // Entries that arrive while watching ease in; a reply that streamed in place does not (it is already there).
      drawn.set(`h:${item.key}`, () => <HistoryRow key={item.key} item={item} enter={(item.entries[0] ?? 0) > seen.current && item.body.kind !== "text" && !gone.current.has(`h:${item.key}`)}
        station={station} session={sessionKey} title={title} keep={made.model} />);
    }
    // Only thinking and the reply stream here; a tool call shows once it is done, from the transcript.
    for (const live of history.live) drawn.set(`l:${live.id}`, () => <div key={`l:${live.id}`} data-vk={`l:${live.id}`} className={css.hLiveThinking}>{live.text}</div>);
    if (history.phase) { const phase = history.phase; drawn.set("phase", () => <PhaseLine key="phase" phase={phase} />); }
  }
  const usage = history?.usage;

  return (
    // The paths its agent writes are its session's files (Peeks.tsx).
    <PathSession.Provider value={paths}>
    <ReadWhole.Provider value={detail}>
    <section className={css.history} aria-label={t("web-main.history.label")}>
      <header className={css.historyHead}>
        <div className={css.historyIdentity}>{head}{summary}</div>
        <div className={css.historyTools}>
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
    </ReadWhole.Provider>
    </PathSession.Provider>
  );
}

// An item's rows as History.css.ts draws them: a line of its words, the line above a message with its gap, the switch
// under a folded text, a row of steps, a mark, and the gap between two items.
const LINE_PX = 21;
const LABEL_PX = 26;
const SWITCH_PX = 20;
const GROUP_PX = 30;
const MARK_PX = 18;
/** The least `item` stands tall where a line holds `per` Latin letters: a text past five lines is folded to them. */
function tall(item: HistoryItem, per: number): number {
  const words = (lines: number) => (lines > 5 ? 5 * LINE_PX + SWITCH_PX : lines * LINE_PX);
  const body = item.body;
  switch (body.kind) {
    case "text": return words(mdLines(body.content.md as Md, per, 6));
    case "post": return LABEL_PX + words(mdLines(body.content.md as Md, per, 6));
    case "received":
      return [body.content.note, ...body.content.messages.map((m) => m.text)]
        .reduce<number>((sum, text) => (text ? sum + (sum ? GAP_PX : 0) + LABEL_PX + words(textLines(text, per, 6)) : sum), 0)
        + body.content.tasks.reduce((sum, task) => sum + GAP_PX + LABEL_PX + (task.md ? words(mdLines(task.md as Md, per, 6)) : 0), 0);
    case "mark": return MARK_PX;
    case "group": return GROUP_PX;
  }
}
/** An item and its link's button, drawn again only when the item changes (or its place in the list). */
const HistoryRow = memo(function HistoryRow({ item, enter, station, session, title, keep }: {
  item: HistoryItem; enter: boolean; station: string; session: string;
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
      <KeepRow.Provider value={hold}><HistoryItemView item={item} /></KeepRow.Provider>
      {title !== undefined && entry !== undefined && <IconButton className={css.hItemLink} label={t("web-main.history.copyLink")} icon={Copy}
        onClick={() => copyLink({ station, session, id: session, title }, { key: session, entry })} />}
    </div>
  );
});

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
          {body.content.note && <Received from="ember" text={body.content.note} />}
          {body.content.tasks.map((task, i) => <Task key={i} task={task} />)}
          {body.content.messages.map((m) => (
            <Received key={m.key} text={m.text} place={m.place ? <Where place={m.place} /> : null}
              from={m.from.slackUser ? <SlackName user={m.from.slackUser} name={m.from.name} bound={m.from.bound} /> : m.from.name} />
          ))}
        </>
      );
    case "text":
      return <Fold className={`${css.hText} ${conversationCss.markdown}${body.content.subagent ? ` ${css.hSub}` : ""}`} of={body.content.md as Md} head={headOf(body.content.md as Md)}><MdView md={body.content.md as Md} /></Fold>;
    case "post":
      return (
        // Drawn like a received message (a line, then the words beside a bar): the two answer each other.
        <div className={`${css.hReceived} ${css.hPost}`} data-failed={body.content.failed}>
          <div className={css.hLabel}>
            <Send {...ICON} size={14} />
            {t("web-main.history.sentTo")}{body.content.place ? <Where place={body.content.place} /> : <span className={css.hPlace}><SlackLogo size={12} />Slack</span>}
            {body.content.block && <Pill tone="blue">Block</Pill>}
            {body.content.failed && <Pill tone="red">{t("web-main.history.sendFailed")}</Pill>}
          </div>
          <Fold className={`${css.hQuote} ${css.hQuoteMd} ${conversationCss.markdown}`} of={body.content.md as Md} head={headOf(body.content.md as Md)}><MdView md={body.content.md as Md} /></Fold>
        </div>
      );
    case "mark":
      // A wait: how long it waited, said by the core once it is over; still waiting, it counts on here.
      return body.content.wait
        ? <div className={css.hLabel}><Wait {...ICON} size={14} />{body.content.wait.until == null ? <span>{body.content.wait.what != null && <>{body.content.wait.what} · </>}{t("web-main.activity.waiting")} <Waited since={body.content.wait.since} seconds={body.content.wait.seconds} /></span> : body.content.text}</div>
        : <div className={css.hMark}>{body.content.text}</div>;
    case "group":
      return <Group group={body.content} />;
  }
});

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

function Received({ from, text, place }: { from: ReactNode; text: string; place?: ReactNode }) {
  return (
    <div className={css.hReceived}>
      <div className={css.hLabel}><ReceivedIcon {...ICON} size={14} />{t(from === "ember" ? "web-main.history.reminder.before" : "web-main.history.message.before")}<strong>{from === "ember" ? NAME : from}</strong>{t(from === "ember" ? "web-main.history.reminder.after" : "web-main.history.message.after")}{place && <> · {place}</>}</div>
      <Fold className={css.hQuote} of={text} head={textHead(text, HEAD_LINES)}>{text}</Fold>
    </div>
  );
}

/** Work the agent started in the background, ended: a line saying how, and what a sub-agent answered beside a bar. */
function Task({ task }: { task: HistoryTask }) {
  const Icon = task.agent ? Agent : Command;
  return (
    <div className={css.hReceived}>
      <div className={`${css.hLabel} ${css.hTask}`} data-failed={task.failed}><Icon {...ICON} size={14} /><span>{task.text}</span></div>
      {task.md != null && <Fold className={`${css.hQuote} ${css.hQuoteMd} ${conversationCss.markdown}`} of={task.md as Md} head={headOf(task.md as Md)}><MdView md={task.md as Md} /></Fold>}
    </div>
  );
}

function Group({ group }: { group: HistoryGroup }) {
  const [open, setOpen] = useState(false);
  useKeepRow(open);
  const { rows, failures, pending } = group;
  const calls = rows.some((row) => row.kind === "step");
  return (
    <div className={css.hGroup} data-failed={failures > 0}>
      <Tip label={group.title || undefined}><button type="button" className={css.hGroupHead} aria-expanded={open} onClick={() => setOpen(!open)}>
        {open ? <ChevronDown {...ICON} size={14} /> : <ChevronRight {...ICON} size={14} />}
        <span>{group.summary}</span>
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

const folds = new Map<Element, (long: boolean) => void>();
let watching: ResizeObserver | null = null;
function foldWatch(): ResizeObserver {
  return watching ??= new ResizeObserver((entries) => {
    const read = entries.flatMap(({ target }) => {
      const set = folds.get(target);
      return set ? [[set, target.scrollHeight > (parseFloat(getComputedStyle(target).lineHeight) || 21) * 5 + 4] as const] : [];
    });
    if (read.length) flushSync(() => { for (const [set, long] of read) set(long); });
  });
}

// Words that surely fill more than a fold shows have only their beginning drawn while folded: these lines of them, a
// few past the five shown (mdHead counts no more lines than are drawn, however wide the panel).
const HEAD_LINES = 8;
/** Whether what a fold holds turned out longer than it shows, as last measured. */
const longTrees = new WeakMap<Md, boolean>();
const longTexts = new Map<string, boolean>();
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
 * Long text in the history folds to five lines; a button unfolds it. Height
 * is measured, so markdown (lists, code) folds the same way as plain text. Text known to be long (`head`, its
 * beginning) is folded as it comes, unmeasured, and only that beginning is drawn until it is unfolded: a history
 * coming in lays out the lines it shows, not all the words of its long entries.
 */
function Fold({ children, of, head = null, className }: { children: ReactNode;
  /** What it folds (an entry's tree, a message's words): whether it turned out long is kept by it, so its row made
   *  again as the reader scrolls back (or the history opened again) is folded as it comes, not measured anew. */
  of: Md | string; head?: ReactNode; className?: string;
}) {
  const box = useRef<HTMLDivElement>(null);
  const cut = head != null;
  const [measured, setMeasured] = useState(() => (typeof of === "string" ? longTexts.get(of) : longTrees.get(of)) ?? false);
  const setLong = useCallback((long: boolean) => {
    if (typeof of !== "string") longTrees.set(of, long);
    else {
      if (longTexts.size > 2000) longTexts.clear();
      longTexts.set(of, long);
    }
    setMeasured(long);
  }, [of]);
  const long = cut || measured;
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
    folds.set(el, setLong);
    foldWatch().observe(el);
    return () => { folds.delete(el); foldWatch().unobserve(el); };
  }, [cut, setLong]);
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
  return (
    <div className={css.fold}>
      <div ref={box} className={`${css.foldBody}${className ? ` ${className}` : ""}`} data-folded={long && !open ? true : undefined}>{cut && !whole ? head : children}</div>
      {long && <button type="button" className={`${controlsCss.textToggle} ${css.foldToggle}`} onClick={toggle}>{open ? t("web-main.fold") : t("web-main.unfold")}</button>}
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
    <div className={css.hPhase} data-vk="phase" data-phase={phase.phase}>
      <span className={`${conversationCss.activityPulse} ${additionsCss.inline}`} aria-hidden="true" />
      <span key={phase.phase} className={css.hPhaseText}>{phase.text}</span>
      <span className={css.hPhaseTime}>{seconds}s</span>
    </div>
  );
}
