// Execution history, after Zork's: a readable account of what actually ran. The core puts it together
// (client/core-ts/src/history.ts): messages in and out, state marks and the agent's words stand alone; the tool calls and
// thinking between them fold into one group. Here it is only drawn.
import { PathSession } from "./Peeks.tsx";
import { failure, useToast } from "./toast.tsx";
import { DoingShown, useDoingState } from "./DoingMark.tsx";
import { ChevronDown, ChevronRight, Copy, Wait, Received as ReceivedIcon, Send } from "./icons.tsx";
import { DropdownMenu } from "radix-ui";
import { memo, useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { flushSync } from "react-dom";
import { animate, EASE_OUT, reducedMotion, type AnimationPlaybackControls } from "./motion.ts";
import { useApi, useHistory, useHistoryDetail, useHistoryOlder, type HistoryGroup, type HistoryItem, type HistoryStep, type HistoryView, type Place } from "./api.ts";
import { ICON, IconButton, Pill, SlackLogo, Tip } from "./ui.tsx";
import { useCopyChatLink } from "./ChatRef.tsx";
import { useLink, useStation } from "./station.tsx";
import { Link } from "react-router";
import { MdView } from "./Prose.tsx";
import type { Md } from "./core/md.ts";
import { mdHead, mdLines, textHead, textLines } from "../../client/core-ts/src/mdHead.ts";
import { ToolCall, ToolResult } from "./ToolStep.tsx";
import * as toolCss from "./ToolStep.css.ts";
import { useStickToBottom } from "./scroll.ts";
import { useOlderOnScroll, Waited } from "./Chat.tsx";
import { Mark } from "./brand.tsx";
import * as css from "./History.css.ts";
import * as controlsCss from "./styles/controls.css.ts";
import * as conversationCss from "./styles/conversation.css.ts";
import * as shellCss from "./styles/shell.css.ts";
import * as additionsCss from "./styles/additions.css.ts";

import { NAME } from "./channel.ts";
import { t } from "./i18n.ts";
import { ReadWhole, useWhole } from "./brief.ts";
import { useEvent } from "./event.ts";

/** How many of a history's latest items are drawn when it opens, and how many more each time the reader nears its top. */
const DRAWN = 10;

/**
 * The session as it ran: the main view of a session. `head` says what it runs on and `summary` what needs seeing to
 * (both in the head); `details` unfold under the head, open to begin with, from its switch there: the history's own,
 * not its tab's (a chat's agents each have a tab).
 * With its chat's `title`, each item offers its link (opening the history there), to paste into another chat.
 */
export function History({ station, sessionKey, head, summary, details, focus, title }: {
  station: string; sessionKey: string; head?: ReactNode; summary?: ReactNode; details?: ReactNode; title?: string | undefined;
  /** An entry to bring into view (n changes each time it is asked for). */
  focus?: { entry: number; n: number } | null;
}) {
  const history = useHistory(station, sessionKey).value;
  const paths = useMemo(() => ({ key: sessionKey, station }), [sessionKey, station]);
  const link = useLink();
  // A place as its platform's mark and its name; a still.fail chat opens its agent's page.
  const where = (place: Place | null): ReactNode => {
    if (!place) return null;
    const inner = <>{(place.surface === "ember" || place.surface === "stillfail") ? <Mark size={12} /> : <SlackLogo size={12} />}<span className={css.hPlaceName}>{place.name}</span></>;
    // A Slack thread opens in Slack; a still.fail chat, its agent's page.
    if (place.url) return <a className={css.hPlace} href={place.url} target="_blank" rel="noopener">{inner}</a>;
    return place.session
      ? <Link className={css.hPlace} to={link(`/chats/${encodeURIComponent(place.session)}`)}>{inner}</Link>
      : <span className={css.hPlace}>{inner}</span>;
  };
  // The items are drawn again only when they change (HistoryItemView): what they are handed stays the same function,
  // the latest one behind it.
  const latest = useRef(where);
  latest.current = where;
  const [stableWhere] = useState(() => (place: Place | null) => latest.current(place));
  const [usageOpen, setUsageOpen] = useState(true);
  const copyLink = useCopyChatLink(useToast());
  // Its link, opening the history at it: the same function for every item, as long as the history shows.
  const copyItem = useEvent((item: HistoryItem) => {
    if (title !== undefined) copyLink({ station, session: sessionKey, id: sessionKey, title }, { key: sessionKey, entry: item.entries[0] ?? 0 });
  });
  // The steps' and thoughts' whole words: read only as one is opened (the core has them in brief till then).
  const detail = useHistoryDetail(station, sessionKey);
  const body = useRef<HTMLDivElement>(null);
  // Follow new steps while the reader is at the bottom; leave them alone when they scrolled up.
  useStickToBottom(body, `.${css.hItem}, .live-tail, .${css.hText}`);
  const all = history?.items ?? [];
  // Only its latest entries come first: the pages before them load as the reader nears the top. Of what is loaded, only
  // the last few are drawn at first, enough to fill the pane; those before are drawn as the reader nears them, then the
  // pages before. Drawn whole, the core's latest page (a hundred items, each its words through Markdown) took the
  // opening frame of the panel or of its tab.
  const [more, setMore] = useState(0);
  // How large the pane is, as it is laid out (never read for it): before its history comes, it stands empty; with its
  // history there already (opened again), as large as the last one was.
  useLayoutEffect(() => {
    const watch = new ResizeObserver(([entry]) => { if (entry) pane = { width: entry.contentRect.width, height: entry.contentRect.height }; });
    watch.observe(body.current!);
    return () => watch.disconnect();
  }, []);
  const opening = useRef(0);
  if (!opening.current && all.length) opening.current = filling(all, pane);
  const drawn = opening.current + more;
  const hidden = Math.max(0, all.length - drawn);
  const items = hidden ? all.slice(hidden) : all;
  const older = useHistoryOlder(station, sessionKey);
  // Whether the reader has moved the pane (a wheel, a finger, a key): until then what is drawn is what it opened with.
  const moved = useRef(false);
  useEffect(() => {
    const el = body.current;
    if (!el) return;
    const mark = () => { moved.current = true; };
    for (const type of ["wheel", "touchmove", "keydown", "pointerdown"]) el.addEventListener(type, mark, { passive: true });
    return () => { for (const type of ["wheel", "touchmove", "keydown", "pointerdown"]) el.removeEventListener(type, mark); };
  }, []);
  const before = useCallback(() => {
    if (hidden) {
      // Not before the reader moves the pane: drawn as it opens, the items before laid it out a second time in the
      // frame it came in. Declined, it is asked again as the reader scrolls up.
      if (!moved.current) return Promise.reject(new Error("not read up to yet"));
      setMore((n) => n + DRAWN);
      return Promise.resolve();
    }
    return older();
  }, [hidden, older]);
  // What was drawn to fill the pane is counted from its words, not measured: once it is drawn, a pane it does not
  // fill after all draws the items before.
  useEffect(() => {
    if (!hidden) return;
    let timer = 0;
    const frame = requestAnimationFrame(() => {
      timer = window.setTimeout(() => {
        const el = body.current;
        if (el && !moved.current && el.scrollHeight <= el.clientHeight) setMore((n) => n + DRAWN);
      });
    });
    return () => { cancelAnimationFrame(frame); clearTimeout(timer); };
  }, [hidden]);
  useOlderOnScroll(body, hidden > 0 || (history?.more ?? false), items[0]?.key, before);
  // Opened at an entry (an activity row): the item that draws it comes into view, and says so for a moment. One before
  // what is loaded: the pages before come first.
  const focused = useRef<number | null>(null);
  useEffect(() => {
    if (!focus || focused.current === focus.n) return;
    const found = all.findIndex((item) => (item.entries[0] ?? 0) <= focus.entry && focus.entry <= (item.entries[1] ?? -1));
    // Loaded but not drawn yet: drawn back to it first.
    if (found >= 0 && found < hidden) return void setMore(all.length - found + DRAWN - opening.current);
    const at = found - hidden;
    const el = found < 0 ? null : body.current?.querySelector<HTMLElement>(`[data-item="${at}"]`);
    if (!el) {
      if (history?.more && focus.entry < (items[0]?.entries[0] ?? 0)) void older().catch(() => {});
      return;
    }
    focused.current = focus.n;
    // Once the pages just loaded are laid out (the pane holds its bottom through them until then).
    requestAnimationFrame(() => requestAnimationFrame(() => {
      el.scrollIntoView({ block: "center" });
      el.dataset.focus = "";
      setTimeout(() => delete el.dataset.focus, 1600);
    }));
  }, [focus?.n, items[0]?.key, items.length > 0, hidden]); // eslint-disable-line react-hooks/exhaustive-deps
  // What was there when the history opened (and older pages loaded later) shows at once; only what comes later animates.
  const seen = useRef(Number.POSITIVE_INFINITY);
  if (seen.current === Number.POSITIVE_INFINITY && history?.loaded) seen.current = all.at(-1)?.entries[1] ?? -1;
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
            <p className={css.historyEdge}>{history.edge}</p>
            {items.map((item, i) => (
              // Entries that arrive while watching ease in; a reply that streamed in place does not (it is already there).
              <HistoryRow key={item.key} item={item} at={i} enter={(item.entries[0] ?? 0) > seen.current && item.body.kind !== "text"} where={stableWhere}
                copy={title !== undefined && item.entries[0] !== undefined ? copyItem : undefined} />
            ))}
            {/* Only thinking and the reply stream here; a tool call shows once it is done, from the transcript. */}
            {history.live.map((s) => <div key={s.id} className={css.hLiveThinking}>{s.text}</div>)}
            {history.phase && <PhaseLine phase={history.phase} />}
          </>
        )}
      </div>
    </section>
    </ReadWhole.Provider>
    </PathSession.Provider>
  );
}

let pane: { width: number; height: number } | null = null;
// An item's rows as History.css.ts draws them: a line of its words, the line above a message with its gap, the switch
// under a folded text, a row of steps, a mark, and the gap between two items.
const LINE_PX = 21;
const LABEL_PX = 26;
const SWITCH_PX = 20;
const GROUP_PX = 30;
const MARK_PX = 18;
const GAP_PX = 14;
/** The least `item` stands tall where a line holds `per` Latin letters: a text past five lines is folded to them. */
function tall(item: HistoryItem, per: number): number {
  const words = (lines: number) => (lines > 5 ? 5 * LINE_PX + SWITCH_PX : lines * LINE_PX);
  const body = item.body;
  switch (body.kind) {
    case "text": return words(mdLines(body.content.md as Md, per, 6));
    case "post": return LABEL_PX + words(mdLines(body.content.md as Md, per, 6));
    case "received":
      return [body.content.note, ...body.content.messages.map((m) => m.text)]
        .reduce<number>((sum, text) => (text ? sum + (sum ? GAP_PX : 0) + LABEL_PX + words(textLines(text, per, 6)) : sum), 0);
    case "mark": return MARK_PX;
    case "group": return GROUP_PX;
  }
}
/**
 * How many of a history's latest items fill its pane: counted from their words, each taken as short as it can stand, so
 * no fewer than fill it. A pane not laid out yet (its history there before it) is taken as tall as the window and as
 * wide as a panel gets.
 */
function filling(all: HistoryItem[], pane: { width: number; height: number } | null): number {
  const height = pane ? pane.height + 40 : window.innerHeight;
  // A Latin letter of the history's text is six pixels wide or more.
  const per = (pane?.width ?? 960) / 6;
  let sum = 0;
  for (let n = 1; n <= all.length; n++) {
    sum += tall(all[all.length - n]!, per) + GAP_PX;
    if (sum >= height) return n;
  }
  return all.length;
}

/** An item and its link's button, drawn again only when the item changes (or its place in the list). */
const HistoryRow = memo(function HistoryRow({ item, at, enter, where, copy }: {
  item: HistoryItem; at: number; enter: boolean; where(place: Place | null): ReactNode; copy: ((item: HistoryItem) => void) | undefined;
}) {
  return (
    <div className={css.hItem} data-item={at} data-enter={enter || undefined}>
      <HistoryItemView item={item} where={where} />
      {copy && <IconButton className={css.hItemLink} label={t("web-main.history.copyLink")} icon={Copy} onClick={() => copy(item)} />}
    </div>
  );
});

const HistoryItemView = memo(function HistoryItemView({ item, where }: { item: HistoryItem; where(place: Place | null): ReactNode }) {
  const body = item.body;
  switch (body.kind) {
    case "received":
      return (
        <>
          {body.content.note && <Received from="ember" text={body.content.note} />}
          {body.content.messages.map((m) => (
            <Received key={m.key} text={m.text} place={where(m.place ?? null)}
              from={m.from.slackUser ? <SlackName user={m.from.slackUser} name={m.from.name} bound={m.from.bound} /> : m.from.name} />
          ))}
        </>
      );
    case "text":
      return <Fold className={`${css.hText} ${conversationCss.markdown}${body.content.subagent ? ` ${css.hSub}` : ""}`} head={headOf(body.content.md as Md)}><MdView md={body.content.md as Md} /></Fold>;
    case "post":
      return (
        // Drawn like a received message (a line, then the words beside a bar): the two answer each other.
        <div className={`${css.hReceived} ${css.hPost}`} data-failed={body.content.failed}>
          <div className={css.hLabel}>
            <Send {...ICON} size={14} />
            {t("web-main.history.sentTo")}{where(body.content.place ?? null) ?? <span className={css.hPlace}><SlackLogo size={12} />Slack</span>}
            {body.content.block && <Pill tone="blue">Block</Pill>}
            {body.content.failed && <Pill tone="red">{t("web-main.history.sendFailed")}</Pill>}
          </div>
          <Fold className={`${css.hQuote} ${css.hQuoteMd} ${conversationCss.markdown}`} head={headOf(body.content.md as Md)}><MdView md={body.content.md as Md} /></Fold>
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
      <Fold className={css.hQuote} head={textHead(text, HEAD_LINES)}>{text}</Fold>
    </div>
  );
}

function Group({ group }: { group: HistoryGroup }) {
  const [open, setOpen] = useState(false);
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
function Fold({ children, head = null, className }: { children: ReactNode; head?: ReactNode; className?: string }) {
  const box = useRef<HTMLDivElement>(null);
  const cut = head != null;
  const [measured, setLong] = useState(false);
  const long = cut || measured;
  const [open, setOpen] = useState(false);
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
  }, [cut]);
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
    <div className={css.hPhase} data-phase={phase.phase}>
      <span className={`${conversationCss.activityPulse} ${additionsCss.inline}`} aria-hidden="true" />
      <span key={phase.phase} className={css.hPhaseText}>{phase.text}</span>
      <span className={css.hPhaseTime}>{seconds}s</span>
    </div>
  );
}
