// Execution history, after Zork's: a readable account of what actually ran. The core puts it together
// (client/core-ts/src/history.ts): messages in and out, state marks and the agent's words stand alone; the tool calls and
// thinking between them fold into one group. Here it is only drawn.
import { PathSession } from "./Peeks.tsx";
import { failure, useToast } from "./toast.tsx";
import { DoingShown, useDoingState } from "./DoingMark.tsx";
import { ChevronDown, ChevronRight, Wait, Received as ReceivedIcon, Send } from "./icons.tsx";
import { DropdownMenu } from "radix-ui";
import { memo, useEffect, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { flushSync } from "react-dom";
import { animate, EASE_OUT, reducedMotion, type AnimationPlaybackControls } from "./motion.ts";
import { useApi, useHistory, useHistoryOlder, type HistoryGroup, type HistoryItem, type HistoryStep, type HistoryView, type Place } from "./api.ts";
import { ICON, Pill, SlackLogo, Tip } from "./ui.tsx";
import { useLink, useStation } from "./station.tsx";
import { Link } from "react-router";
import { Prose } from "./Prose.tsx";
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
/**
 * The session as it ran: the main view of a session. `summary` says who it is (in the head), `actions` what can be done
 * to it right now (stop a turn, release the process), `details` unfolds under the head.
 */
export function History({ station, sessionKey, summary, actions, details, focus }: {
  station: string; sessionKey: string; summary?: ReactNode; actions?: ReactNode; details?: ReactNode;
  /** An entry to bring into view (n changes each time it is asked for). */
  focus?: { entry: number; n: number } | null;
}) {
  const history = useHistory(station, sessionKey).value;
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
  const [usageOpen, setUsageOpen] = useState(false);
  const body = useRef<HTMLDivElement>(null);
  // Follow new steps while the reader is at the bottom; leave them alone when they scrolled up.
  useStickToBottom(body, `.${css.hItem}, .live-tail, .${css.hText}`);
  const items = history?.items ?? [];
  // Only its latest entries come first: the pages before them load as the reader nears the top.
  const older = useHistoryOlder(station, sessionKey);
  useOlderOnScroll(body, history?.more ?? false, items[0]?.key, older);
  // Opened at an entry (an activity row): the item that draws it comes into view, and says so for a moment. One before
  // what is loaded: the pages before come first.
  const focused = useRef<number | null>(null);
  useEffect(() => {
    if (!focus || focused.current === focus.n) return;
    const at = items.findIndex((item) => (item.entries[0] ?? 0) <= focus.entry && focus.entry <= (item.entries[1] ?? -1));
    const el = at < 0 ? null : body.current?.querySelector<HTMLElement>(`[data-item="${at}"]`);
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
  }, [focus?.n, items[0]?.key, items.length > 0]); // eslint-disable-line react-hooks/exhaustive-deps
  // What was there when the history opened (and older pages loaded later) shows at once; only what comes later animates.
  const seen = useRef(Number.POSITIVE_INFINITY);
  if (seen.current === Number.POSITIVE_INFINITY && history?.loaded) seen.current = items.at(-1)?.entries[1] ?? -1;
  const usage = history?.usage;

  return (
    // The paths its agent writes are its session's files (Peeks.tsx).
    <PathSession.Provider value={sessionKey}>
    <section className={css.history} aria-label={t("web-main.history.label")}>
      <header className={css.historyHead}>
        <div className={css.historyIdentity}>{summary}</div>
        <div className={css.historyTools}>
          {actions}
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
              <div key={item.key} className={css.hItem} data-item={i} data-enter={(item.entries[0] ?? 0) > seen.current && item.body.kind !== "text" ? true : undefined}>
                <HistoryItemView item={item} where={stableWhere} />
              </div>
            ))}
            {/* Only thinking and the reply stream here; a tool call shows once it is done, from the transcript. */}
            {history.live.map((s) => <div key={s.id} className={css.hLiveThinking}>{s.text}</div>)}
            {history.phase && <PhaseLine phase={history.phase} />}
          </>
        )}
      </div>
    </section>
    </PathSession.Provider>
  );
}

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
      return <Fold className={`${css.hText} ${conversationCss.markdown}${body.content.subagent ? ` ${css.hSub}` : ""}`}><Prose>{body.content.text}</Prose></Fold>;
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
          <Fold className={`${css.hQuote} ${css.hQuoteMd} ${conversationCss.markdown}`}><Prose>{body.content.text}</Prose></Fold>
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
      <Fold className={css.hQuote}>{text}</Fold>
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
            <details key={i} className={css.hStep}>
              <summary><span className={css.hStepName}>{t("web-main.history.thinking")}</span><span className={css.hStepHint}>{row.content.first}</span></summary>
              <div className={`${css.hStepBody} ${shellCss.muted}`}>{row.content.text}</div>
            </details>
          ) : <div key={i} className={css.hThinking}>{row.content.text}</div>) : (
            <Step key={i} step={row.content} />
          ))}
        </div>
      )}
    </div>
  );
}

function Step({ step }: { step: HistoryStep }) {
  return (
    <details className={css.hStep} data-failed={step.failed}>
      <summary>
        {step.said
          ? <span className={css.hStepSaid}>{step.said}</span>
          : <><span className={css.hStepName}>{step.name}</span><span className={css.hStepHint}>{step.hint}</span></>}
        <span className={css.hStepMeta}>{step.meta}</span>
      </summary>
      <div className={toolCss.body}>
        <div className={toolCss.section}><ToolCall name={step.name} call={step.call} said={step.said !== undefined} /></div>
        {step.result !== undefined && <ToolResult name={step.name} call={step.call} result={step.result} failed={step.failed} />}
      </div>
    </details>
  );
}

/**
 * Long text in the history folds to five lines; a button unfolds it. Height
 * is measured, so markdown (lists, code) folds the same way as plain text.
 */
function Fold({ children, className }: { children: ReactNode; className?: string }) {
  const box = useRef<HTMLDivElement>(null);
  const [long, setLong] = useState(false);
  const [open, setOpen] = useState(false);
  const run = useRef<AnimationPlaybackControls | null>(null);
  // Measured before paint, so a long entry never shows at full height first.
  useLayoutEffect(() => {
    const el = box.current;
    if (!el) return;
    const check = () => {
      const line = parseFloat(getComputedStyle(el).lineHeight) || 21;
      setLong(el.scrollHeight > line * 5 + 4);
    };
    check();
    const observer = new ResizeObserver(check);
    observer.observe(el);
    return () => { observer.disconnect(); run.current?.stop(); };
  }, []);
  // Only a reader's own click moves it (folding on arrival happens before the first paint): from the height it shows
  // (on its way, if clicked again) to the one it has now.
  const toggle = () => {
    const el = box.current!;
    const from = el.getBoundingClientRect().height;
    run.current?.stop();
    Object.assign(el.style, { height: "", maxHeight: "", overflow: "" });
    flushSync(() => setOpen(!open));
    const to = el.getBoundingClientRect().height;
    if (reducedMotion() || Math.abs(to - from) < 1) return;
    // Its fold's height limit held off while it moves, what is past its height hidden.
    // Held at where it was until the motion takes it (from the next frame): the new height is never seen at once.
    Object.assign(el.style, { maxHeight: "none", overflow: "hidden", height: `${from}px` });
    const now = animate(el, { height: [`${from}px`, `${to}px`] }, { duration: 0.24, ease: EASE_OUT });
    run.current = now;
    void now.finished.then(() => { if (run.current === now) { Object.assign(el.style, { height: "", maxHeight: "", overflow: "" }); run.current = null; } }, () => {});
  };
  return (
    <div className={css.fold}>
      <div ref={box} className={`${css.foldBody}${className ? ` ${className}` : ""}`} data-folded={long && !open ? true : undefined}>{children}</div>
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
