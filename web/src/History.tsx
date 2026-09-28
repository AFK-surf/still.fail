// Execution history, after Zork's: a readable account of what actually ran. The core puts it together
// (client/core/src/history.rs): messages in and out, state marks and the agent's words stand alone; the tool calls and
// thinking between them fold into one group. Here it is only drawn.
import { useToast } from "./toast.tsx";
import { ChevronDown, ChevronRight, Received as ReceivedIcon, Send } from "./icons.tsx";
import { DropdownMenu } from "radix-ui";
import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { useApi, useHistory, useHistoryOlder, type HistoryGroup, type HistoryItem, type HistoryView, type Place } from "./api.ts";
import { ICON, Pill, SlackLogo } from "./ui.tsx";
import { useLink } from "./station.tsx";
import { Link } from "react-router";
import { Prose } from "./Prose.tsx";
import { useStickToBottom } from "./scroll.ts";
import { useOlderOnScroll } from "./Chat.tsx";
import { Mark } from "./brand.tsx";
import * as css from "./History.css.ts";
import * as controlsCss from "./styles/controls.css.ts";
import * as conversationCss from "./styles/conversation.css.ts";
import * as shellCss from "./styles/shell.css.ts";
import * as additionsCss from "./styles/additions.css.ts";

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
  // A place as its platform's mark and its name; an ember chat opens its agent's page.
  const where = (place: Place | null): ReactNode => {
    if (!place) return null;
    const inner = <>{place.surface === "ember" ? <Mark size={13} /> : <SlackLogo size={13} />}<span className={css.hPlaceName}>{place.name}</span></>;
    // A Slack thread opens in Slack; an ember chat, its agent's page.
    if (place.url) return <a className={css.hPlace} href={place.url} target="_blank" rel="noopener" title="在 Slack 中打开">{inner}</a>;
    return place.session
      ? <Link className={css.hPlace} to={link(`/chats/${encodeURIComponent(place.session)}`)} title="打开对话">{inner}</Link>
      : <span className={css.hPlace}>{inner}</span>;
  };
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
    <section className={css.history} aria-label="执行历史">
      <header className={css.historyHead}>
        <div className={css.historyIdentity}>{summary}</div>
        <div className={css.historyTools}>
          {actions}
          {(usage || details) && (
            <button type="button" className={controlsCss.textToggle} aria-expanded={usageOpen} onClick={() => setUsageOpen(!usageOpen)}>
              详情 <ChevronDown {...ICON} size={14} className={usageOpen ? css.flip : undefined} />
            </button>
          )}
        </div>
      </header>
      {usageOpen && details && <div className={css.historyDetails}>{details}</div>}
      {usageOpen && usage && !details && (
        <dl className={css.usage}>{usage.map((u) => <div key={u.label}><dt>{u.label}</dt><dd>{u.value}</dd></div>)}</dl>
      )}
      <div className={css.historyBody} ref={body}>
        {!history ? <p className={css.historyEdge}>正在读取执行历史…</p> : history.empty ? <p className={css.historyEdge}>{history.edge}</p> : (
          <>
            <p className={css.historyEdge}>{history.edge}</p>
            {items.map((item, i) => (
              // Entries that arrive while watching ease in; a reply that streamed in place does not (it is already there).
              <div key={item.key} className={css.hItem} data-item={i} data-enter={(item.entries[0] ?? 0) > seen.current && item.body.kind !== "text" ? true : undefined}>
                <HistoryItemView item={item} where={where} />
              </div>
            ))}
            {/* Only thinking and the reply stream here; a tool call shows once it is done, from the transcript. */}
            {history.live.map((s) => <div key={s.id} className={css.hLiveThinking}>{s.text}</div>)}
            {history.phase && <PhaseLine phase={history.phase} />}
          </>
        )}
      </div>
    </section>
  );
}

function HistoryItemView({ item, where }: { item: HistoryItem; where(place: Place | null): ReactNode }) {
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
            发送到 {where(body.content.place ?? null) ?? <span className={css.hPlace}><SlackLogo size={13} />Slack</span>}
            {body.content.block && <Pill tone="blue">Block</Pill>}
            {body.content.failed && <Pill tone="red">发送失败</Pill>}
          </div>
          <Fold className={`${css.hQuote} ${css.hQuoteMd} ${conversationCss.markdown}`}><Prose>{body.content.text}</Prose></Fold>
        </div>
      );
    case "mark":
      return <div className={css.hMark}>{body.content.text}</div>;
    case "group":
      return <Group group={body.content} />;
  }
}

/**
 * A Slack user's name: "你" once the viewer said it is them. Clicking it offers "这是我" (the station then takes that
 * Slack user for the viewer), or "不是我" once it does.
 */
function SlackName({ user, name, bound }: { user: string; name: string; bound: boolean }) {
  const api = useApi();
  const toast = useToast();
  return (
    <DropdownMenu.Root modal={false}>
      <DropdownMenu.Trigger className={css.hPerson}>{name}</DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content className={`${controlsCss.popover} ${controlsCss.menuList}`} align="start" sideOffset={4} collisionPadding={8}>
          <DropdownMenu.Item className={controlsCss.menuItem} onSelect={() => void api.slackIdentity(user, !bound).catch((error: unknown) => toast(`${bound ? "解除" : "绑定"}没有成功：${error instanceof Error ? error.message : String(error)}`))}>{bound ? "不是我" : "这是我"}</DropdownMenu.Item>
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}

function Received({ from, text, place }: { from: ReactNode; text: string; place?: ReactNode }) {
  return (
    <div className={css.hReceived}>
      <div className={css.hLabel}><ReceivedIcon {...ICON} size={14} />收到来自 <strong>{from === "ember" ? "ember" : from}</strong> 的{from === "ember" ? "提醒" : "消息"}{place && <> · {place}</>}</div>
      <Fold className={css.hQuote}>{text}</Fold>
    </div>
  );
}

function Group({ group }: { group: HistoryGroup }) {
  const [open, setOpen] = useState(false);
  const { steps, thinking, failures, pending } = group;
  return (
    <div className={css.hGroup} data-failed={failures > 0}>
      <button type="button" className={css.hGroupHead} aria-expanded={open} onClick={() => setOpen(!open)} title={group.title || undefined}>
        {open ? <ChevronDown {...ICON} size={14} /> : <ChevronRight {...ICON} size={14} />}
        <span>{group.summary}</span>
        {failures > 0 && <Pill tone="red">{failures} 项失败</Pill>}
        {pending > 0 && <Pill tone="accent">{pending} 项进行中</Pill>}
      </button>
      {open && (
        <div className={css.hSteps}>
          {thinking.map((t, i) => steps.length ? (
            <details key={`t${i}`} className={css.hStep}>
              <summary><span className={css.hStepName}>思考</span><span className={css.hStepHint}>{t.first}</span></summary>
              <div className={`${css.hStepBody} ${shellCss.muted}`}>{t.text}</div>
            </details>
          ) : <div key={`t${i}`} className={css.hThinking}>{t.text}</div>)}
          {steps.map((step, i) => (
            <details key={i} className={css.hStep} data-failed={step.failed}>
              <summary>
                {step.said
                  ? <span className={css.hStepSaid}>{step.said}</span>
                  : <><span className={css.hStepName}>{step.name}</span><span className={css.hStepHint}>{step.hint}</span></>}
                <span className={css.hStepMeta}>{step.meta}</span>
              </summary>
              <pre className={css.code}>{step.call}</pre>
              {step.result !== undefined && <pre className={css.code} data-failed={step.failed}>{step.result}</pre>}
            </details>
          ))}
        </div>
      )}
    </div>
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
  // Only a reader's own click animates; folding on arrival happens before the first paint.
  const [animate, setAnimate] = useState(false);
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
    return () => observer.disconnect();
  }, []);
  return (
    <div className={css.fold}>
      <div ref={box} className={`${css.foldBody}${className ? ` ${className}` : ""}`} data-folded={long && !open ? true : undefined} data-anim={animate || undefined}>{children}</div>
      {long && <button type="button" className={`${controlsCss.textToggle} ${css.foldToggle}`} onClick={() => { setAnimate(true); setOpen(!open); }}>{open ? "收起" : "展开"}</button>}
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
