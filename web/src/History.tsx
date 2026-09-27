// Execution history, after Zork's: a readable account of what actually ran. The core puts it together
// (client/core/src/history.rs): messages in and out, state marks and the agent's words stand alone; the tool calls and
// thinking between them fold into one group. Here it is only drawn.
import { useToast } from "./toast.tsx";
import { ChevronDown, ChevronRight, Received as ReceivedIcon, Send } from "./icons.tsx";
import { DropdownMenu } from "radix-ui";
import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { useApi, useHistory, type HistoryGroup, type HistoryItem, type HistoryView, type Place } from "./api.ts";
import { ICON, Pill, SlackLogo } from "./ui.tsx";
import { useLink } from "./station.tsx";
import { Link } from "react-router";
import { Prose } from "./Prose.tsx";
import { useStickToBottom } from "./scroll.ts";
import { Mark } from "./brand.tsx";

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
    const inner = <>{place.surface === "ember" ? <Mark size={13} /> : <SlackLogo size={13} />}{place.name}</>;
    return place.session
      ? <Link className="h-place" to={link(`/chats/${encodeURIComponent(place.session)}`)} title="打开对话">{inner}</Link>
      : <span className="h-place">{inner}</span>;
  };
  const [usageOpen, setUsageOpen] = useState(false);
  const body = useRef<HTMLDivElement>(null);
  // Follow new steps while the reader is at the bottom; leave them alone when they scrolled up.
  useStickToBottom(body, ".h-item, .live-tail, .h-text");
  const items = history?.items ?? [];
  // Opened at an entry (an activity row): the item that draws it comes into view, and says so for a moment.
  useEffect(() => {
    if (!focus) return;
    const at = items.findIndex((item) => (item.entries[0] ?? 0) <= focus.entry && focus.entry <= (item.entries[1] ?? -1));
    const el = at < 0 ? null : body.current?.querySelector<HTMLElement>(`[data-item="${at}"]`);
    if (!el) return;
    el.scrollIntoView({ block: "center" });
    el.dataset.focus = "";
    const timer = setTimeout(() => delete el.dataset.focus, 1600);
    return () => clearTimeout(timer);
  }, [focus?.n, items.length > 0]); // eslint-disable-line react-hooks/exhaustive-deps
  // What was there when the history opened shows at once; only what comes later animates.
  const firstCount = useRef(Number.POSITIVE_INFINITY);
  if (firstCount.current === Number.POSITIVE_INFINITY && history?.loaded) firstCount.current = items.length;
  const usage = history?.usage;

  return (
    <section className="history" aria-label="执行历史">
      <header className="history-head">
        <div className="history-identity">{summary}</div>
        <div className="history-tools">
          {actions}
          {(usage || details) && (
            <button type="button" className="text-toggle" aria-expanded={usageOpen} onClick={() => setUsageOpen(!usageOpen)}>
              详情 <ChevronDown {...ICON} size={14} className={usageOpen ? "flip" : undefined} />
            </button>
          )}
        </div>
      </header>
      {usageOpen && details && <div className="history-details">{details}</div>}
      {usageOpen && usage && !details && (
        <dl className="usage">{usage.map((u) => <div key={u.label}><dt>{u.label}</dt><dd>{u.value}</dd></div>)}</dl>
      )}
      <div className="history-body" ref={body}>
        {!history ? <p className="history-edge">正在读取执行历史…</p> : history.empty ? <p className="history-edge">{history.edge}</p> : (
          <>
            <p className="history-edge">{history.edge}</p>
            {items.map((item, i) => (
              // Entries that arrive while watching ease in; a reply that streamed in place does not (it is already there).
              <div key={item.key} className="h-item" data-item={i} data-enter={i >= firstCount.current && item.body.kind !== "text" ? true : undefined}>
                <HistoryItemView item={item} where={where} />
              </div>
            ))}
            {/* Only thinking and the reply stream here; a tool call shows once it is done, from the transcript. */}
            {history.live.map((s) => <div key={s.id} className="h-live-thinking">{s.text}</div>)}
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
      return <Fold className={`h-text markdown${body.content.subagent ? " h-sub" : ""}`}><Prose>{body.content.text}</Prose></Fold>;
    case "post":
      return (
        // Drawn like a received message (a line, then the words beside a bar): the two answer each other.
        <div className="h-received h-post" data-failed={body.content.failed}>
          <div className="h-label">
            <Send {...ICON} size={14} />
            发送到 {where(body.content.place ?? null) ?? <span className="h-place"><SlackLogo size={13} />Slack</span>}
            {body.content.block && <Pill tone="blue">Block</Pill>}
            {body.content.failed && <Pill tone="red">发送失败</Pill>}
          </div>
          <Fold className="h-quote h-quote-md markdown"><Prose>{body.content.text}</Prose></Fold>
        </div>
      );
    case "mark":
      return <div className="h-mark">{body.content.text}</div>;
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
      <DropdownMenu.Trigger className="h-person">{name}</DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content className="popover menu-list" align="start" sideOffset={4} collisionPadding={8}>
          <DropdownMenu.Item className="menu-item" onSelect={() => void api.slackIdentity(user, !bound).catch((error: unknown) => toast(`${bound ? "解除" : "绑定"}没有成功：${error instanceof Error ? error.message : String(error)}`))}>{bound ? "不是我" : "这是我"}</DropdownMenu.Item>
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}

function Received({ from, text, place }: { from: ReactNode; text: string; place?: ReactNode }) {
  return (
    <div className="h-received">
      <div className="h-label"><ReceivedIcon {...ICON} size={14} />收到来自 <strong>{from === "ember" ? "ember" : from}</strong> 的{from === "ember" ? "提醒" : "消息"}{place && <> · {place}</>}</div>
      <Fold className="h-quote">{text}</Fold>
    </div>
  );
}

function Group({ group }: { group: HistoryGroup }) {
  const [open, setOpen] = useState(false);
  const { steps, thinking, failures, pending } = group;
  return (
    <div className="h-group" data-failed={failures > 0}>
      <button type="button" className="h-group-head" aria-expanded={open} onClick={() => setOpen(!open)} title={group.title || undefined}>
        {open ? <ChevronDown {...ICON} size={14} /> : <ChevronRight {...ICON} size={14} />}
        <span>{group.summary}</span>
        {failures > 0 && <Pill tone="red">{failures} 项失败</Pill>}
        {pending > 0 && <Pill tone="accent">{pending} 项进行中</Pill>}
      </button>
      {open && (
        <div className="h-steps">
          {thinking.map((t, i) => steps.length ? (
            <details key={`t${i}`} className="h-step">
              <summary><span className="h-step-name">思考</span><span className="h-step-hint">{t.first}</span></summary>
              <div className="h-step-body muted">{t.text}</div>
            </details>
          ) : <div key={`t${i}`} className="h-thinking">{t.text}</div>)}
          {steps.map((step, i) => (
            <details key={i} className="h-step" data-failed={step.failed}>
              <summary>
                {step.said
                  ? <span className="h-step-said">{step.said}</span>
                  : <><span className="h-step-name">{step.name}</span><span className="h-step-hint">{step.hint}</span></>}
                <span className="h-step-meta">{step.meta}</span>
              </summary>
              <pre className="code">{step.call}</pre>
              {step.result !== undefined && <pre className="code" data-failed={step.failed}>{step.result}</pre>}
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
    <div className="fold">
      <div ref={box} className={`fold-body${className ? ` ${className}` : ""}`} data-folded={long && !open ? true : undefined} data-anim={animate || undefined}>{children}</div>
      {long && <button type="button" className="text-toggle fold-toggle" onClick={() => { setAnimate(true); setOpen(!open); }}>{open ? "收起" : "展开"}</button>}
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
    <div className="h-phase" data-phase={phase.phase}>
      <span className="activity-pulse inline" aria-hidden="true" />
      <span key={phase.phase} className="h-phase-text">{phase.text}</span>
      <span className="h-phase-time">{seconds}s</span>
    </div>
  );
}
