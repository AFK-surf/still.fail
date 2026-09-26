// Execution history, after Zork's: a readable account of what actually ran.
// Messages in and out, state marks and the agent's own words are boundaries;
// the tool calls and thinking between two boundaries fold into one group.
import { ArrowDownToLine, ChevronDown, ChevronRight, Send } from "lucide-react";
import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import type { ConnectView, SessionDetail, ShownPhase, ShownStep, TimelineEntry } from "./api.ts";
import { agentLabel, botUserIdOf, compactNumber, duration, parsePrompt, RUNTIME_LABEL, slackThreadUrl, splitThread, threadNamer } from "./format.ts";
import { Avatar, ICON, ModelLogo, Pill, SlackLogo } from "./ui.tsx";
import { usePerson } from "./station.tsx";
import { Prose } from "./Prose.tsx";

export function parseArgs(text: string): Record<string, unknown> | null {
  try {
    const value = JSON.parse(text) as unknown;
    return value && typeof value === "object" ? value as Record<string, unknown> : null;
  } catch {
    return null;
  }
}

/** Tool names without the MCP server prefix ember's tools carry. */
export function toolName(tool: string | undefined): string {
  return (tool ?? "").replace(/^mcp__ember__|^ember__|^ember\./, "");
}

type Category = "read" | "search" | "edit" | "command" | "web" | "agent" | "thread" | "other";

const CATEGORY: Record<Category, { verb: string; unit: string }> = {
  read: { verb: "读取", unit: "个文件" },
  search: { verb: "搜索", unit: "次" },
  edit: { verb: "编辑", unit: "个文件" },
  command: { verb: "运行", unit: "条命令" },
  web: { verb: "访问", unit: "个网页" },
  agent: { verb: "派出", unit: "个子 agent" },
  thread: { verb: "读取 thread", unit: "次" },
  other: { verb: "其他", unit: "项" },
};

function categorize(tool: string): Category {
  const name = toolName(tool);
  if (/^(Read|NotebookRead|view_image)$/.test(name)) return "read";
  if (/^(Glob|Grep|LS|ToolSearch)$/.test(name)) return "search";
  if (/^(Edit|MultiEdit|Write|NotebookEdit|apply_patch)$/.test(name)) return "edit";
  if (/^(Bash|BashOutput|KillShell|exec_command|shell|local_shell|write_stdin|unified_exec)$/.test(name)) return "command";
  if (/^(WebFetch|WebSearch|web_search)$/.test(name)) return "web";
  if (/^(Task|Agent|spawn_agent)$/.test(name)) return "agent";
  if (name === "chat_history") return "thread";
  return "other";
}

/** One line that says what a call did: the command, the file, the pattern. */
function hint(entry: TimelineEntry): string {
  const args = parseArgs(entry.text);
  const value = args ? args.command ?? args.cmd ?? args.file_path ?? args.path ?? args.pattern ?? args.url ?? args.query ?? args.description ?? args.prompt : entry.text;
  const text = typeof value === "string" ? value : Array.isArray(value) ? value.join(" ") : "";
  return text.split("\n")[0]!.slice(0, 160);
}

function fileOf(entry: TimelineEntry): string | null {
  const args = parseArgs(entry.text);
  const path = args?.file_path ?? args?.path ?? args?.notebook_path;
  return typeof path === "string" ? path : null;
}

interface Step { call: TimelineEntry; result: TimelineEntry | null }
type Item =
  | { type: "received"; entry: TimelineEntry }
  | { type: "text"; entry: TimelineEntry }
  | { type: "post"; step: Step }
  | { type: "mark"; kind: string }
  | { type: "group"; steps: Step[]; thinking: TimelineEntry[] };

function toItems(entries: TimelineEntry[]): Item[] {
  const items: Item[] = [];
  const steps = new Map<string, Step>();
  let group: Extract<Item, { type: "group" }> | null = null;
  let lastStep: Step | null = null;
  const openGroup = () => {
    if (!group) {
      group = { type: "group", steps: [], thinking: [] };
      items.push(group);
    }
    return group;
  };
  for (const e of entries) {
    if (e.kind === "tool_result") {
      const step = (e.callId && steps.get(e.callId)) || (lastStep && !lastStep.result ? lastStep : null);
      if (step) step.result = e;
      continue;
    }
    if (e.kind === "tool_call") {
      const step: Step = { call: e, result: null };
      if (e.callId) steps.set(e.callId, step);
      lastStep = step;
      const name = toolName(e.tool);
      const args = parseArgs(e.text);
      if (name === "chat_post" && typeof args?.text === "string" && !e.subagent) {
        items.push({ type: "post", step });
        group = null;
      } else if (name === "chat_state" && typeof args?.kind === "string" && !e.subagent) {
        items.push({ type: "mark", kind: args.kind });
        group = null;
      } else {
        openGroup().steps.push(step);
      }
      continue;
    }
    if (e.kind === "thinking") {
      openGroup().thinking.push(e);
      continue;
    }
    group = null;
    items.push(e.kind === "user" ? { type: "received", entry: e } : { type: "text", entry: e });
  }
  return items;
}

/**
 * The session as it ran: the main view of a session. `state` says where it
 * stands (in the header line) and `actions` what can
 * be done to it right now (stop a turn, release the process).
 */
export function History({ detail, connect, state, actions, details, slackBase, onOpenChat, live = [], phase = null }: {
  detail: SessionDetail; connect: ConnectView | undefined; state?: ReactNode; actions?: ReactNode; details?: ReactNode;
  /** Steps the runtime is streaming right now, after the transcript's last entry. */
  live?: ShownStep[];
  /** Where the running turn stands with the model. */
  phase?: ShownPhase | null;
  /** The Slack workspace URL, for links to threads. */
  slackBase?: string | null | undefined;
  /** Brings ember's own chat into view. */
  onOpenChat?: (() => void) | undefined;
}) {
  const botUserId = botUserIdOf(connect);
  const member = usePerson();
  const threadName = threadNamer(detail);
  // A thread address as a place: its platform's mark, its name, and a way there.
  const where = (address: string | null | undefined): ReactNode => {
    const t = address ? splitThread(address) : null;
    if (!t) return null;
    const name = threadName(t.channel, t.threadTs).where;
    if (t.channel === "EMBER") {
      return (
        <button type="button" className="h-place" onClick={onOpenChat} title="打开对话">
          <img src={`${import.meta.env.BASE_URL}ember.svg`} alt="" width={13} height={13} />{name}
        </button>
      );
    }
    const url = slackThreadUrl(slackBase, t.channel, t.threadTs);
    const inner = <><SlackLogo size={13} />{name}</>;
    return url
      ? <a className="h-place" href={url} target="_blank" rel="noopener" title="在 Slack 中打开">{inner}</a>
      : <span className="h-place">{inner}</span>;
  };
  const [usageOpen, setUsageOpen] = useState(false);
  const body = useRef<HTMLDivElement>(null);
  const count = detail.transcript?.timeline.length ?? 0;
  // Follow new steps while the reader is at the bottom; leave them alone when they scrolled up.
  const pinned = useRef(true);
  useEffect(() => {
    const el = body.current;
    if (!el) return;
    const onScroll = () => { pinned.current = el.scrollHeight - el.scrollTop - el.clientHeight < 80; };
    el.addEventListener("scroll", onScroll);
    return () => el.removeEventListener("scroll", onScroll);
  }, []);
  // Streaming grows the last step without adding entries; follow that too.
  const growth = live.reduce((n, s) => n + s.text.length + s.input.length + s.output.length, live.length);
  useEffect(() => {
    if (pinned.current && body.current) body.current.scrollTop = body.current.scrollHeight;
  }, [count, growth]);
  const { session, transcript } = detail;
  const items = useMemo(() => toItems(transcript?.timeline ?? []), [transcript]);
  const usage = transcript?.usage;
  const model = usage?.model ?? session.model ?? connect?.bind.model ?? null;
  const name = connect?.name ?? session.connect;
  const hitRate = usage && usage.inputTokens > 0 ? Math.round((usage.cachedTokens / usage.inputTokens) * 100) : null;

  return (
    <section className="history" aria-label="执行历史">
      <header className="history-head">
        <div className="history-identity">
          <span className="history-name"><ModelLogo model={model} runtime={session.runtime} size={13} />{agentLabel(model, session.effort)}</span>
          <span className="history-sep">·</span>
          <span>{RUNTIME_LABEL[session.runtime]}</span>
          {usage && <><span className="history-sep">·</span><span>{compactNumber(usage.inputTokens + usage.outputTokens)} tokens</span></>}
          {state && <><span className="history-sep">·</span>{state}</>}
        </div>
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
        <dl className="usage">
          <div><dt>模型调用</dt><dd>{usage.modelCalls} 次</dd></div>
          <div><dt>输入</dt><dd>{compactNumber(usage.inputTokens)}</dd></div>
          <div><dt>其中缓存</dt><dd>{compactNumber(usage.cachedTokens)}</dd></div>
          <div><dt>输出</dt><dd>{compactNumber(usage.outputTokens)}</dd></div>
          <div><dt>缓存命中率</dt><dd>{hitRate === null ? "未报告" : `${hitRate}%`}</dd></div>
        </dl>
      )}
      <div className="history-body" ref={body}>
        {!transcript ? (
          <p className="history-edge">{session.runtimeSessionId ? "找不到运行时记录，可能已归档。" : "运行时还没开始这个会话。"}</p>
        ) : (
          <>
            <p className="history-edge">已到 Session 开始处</p>
            {items.map((item, i) => (
              <HistoryItem key={i} item={item} where={where} person={(id) => member(id)?.name || detail.people[id] || id}
                mention={(text) => text.replace(/<@([A-Z0-9]+)>/g, (_, id: string) => `@${id === botUserId ? name : detail.people[id] ?? id}`)} />
            ))}
            {/* Only thinking and the reply stream here; a tool call shows once it is done, from the transcript. */}
            {live.filter((s) => !s.subagent && s.step !== "tool").map((s) => <LiveStepView key={s.id} step={s} />)}
            {phase && phase.phase !== "working" && <PhaseLine phase={phase} runtime={RUNTIME_LABEL[session.runtime]} />}
          </>
        )}
      </div>
    </section>
  );
}

function HistoryItem({ item, mention, person, where }: { item: Item; mention(text: string): string; person(id: string): string; where(address: string | null | undefined): ReactNode }) {
  switch (item.type) {
    case "received": {
      const { messages, note } = parsePrompt(item.entry.text);
      return (
        <>
          {note && <Received from="ember" text={note} />}
          {messages.map((m) => <Received key={m.ts} from={person(m.user)} text={mention(m.text)} place={where(m.thread)} />)}
        </>
      );
    }
    case "text":
      return <Fold className={`h-text markdown${item.entry.subagent ? " h-sub" : ""}`}><Prose>{item.entry.text}</Prose></Fold>;
    case "post": {
      const args = parseArgs(item.step.call.text)!;
      const kind = typeof args.kind === "string" ? args.kind : null;
      const failed = item.step.result?.ok === false;
      return (
        <div className="h-post" data-failed={failed}>
          <div className="h-post-head">
            <Send {...ICON} size={14} />
            发送到 {where(typeof args.to === "string" ? args.to : null) ?? <span className="h-place"><SlackLogo size={13} />Slack</span>}
            {kind === "final" && <Pill tone="green">已完成</Pill>}
            {kind === "block" && <Pill tone="blue">等你回复</Pill>}
            {failed && <Pill tone="red">发送失败</Pill>}
          </div>
          <Fold className="markdown"><Prose>{String(args.text)}</Prose></Fold>
        </div>
      );
    }
    case "mark":
      return <div className="h-mark">标记为{item.kind === "final" ? "已完成" : item.kind === "block" ? "等你回复" : item.kind}</div>;
    case "group":
      return <Group steps={item.steps} thinking={item.thinking} />;
  }
}

function Received({ from, text, place }: { from: string; text: string; place?: ReactNode }) {
  return (
    <div className="h-received">
      <div className="h-label"><ArrowDownToLine {...ICON} size={14} />收到来自 <strong>{from === "ember" ? "ember" : from}</strong> 的{from === "ember" ? "提醒" : "消息"}{place && <> · {place}</>}</div>
      <Fold className="h-quote">{text}</Fold>
    </div>
  );
}

function Group({ steps, thinking }: { steps: Step[]; thinking: TimelineEntry[] }) {
  const [open, setOpen] = useState(false);
  const counts = new Map<Category, Set<string> | number>();
  for (const s of steps) {
    const c = categorize(s.call.tool ?? "");
    const file = (c === "read" || c === "edit") ? fileOf(s.call) : null;
    if (file) {
      const set = (counts.get(c) as Set<string> | undefined) ?? new Set<string>();
      set.add(file);
      counts.set(c, set);
    } else {
      counts.set(c, ((counts.get(c) as number | undefined) ?? 0) + 1);
    }
  }
  const parts = [...counts].map(([c, v]) => `${CATEGORY[c].verb} ${typeof v === "number" ? v : v.size} ${CATEGORY[c].unit}`);
  const failed = steps.filter((s) => s.result?.ok === false).length;
  const pending = steps.filter((s) => !s.result).length;
  const firstThought = thinking[0]?.text.split("\n").find((l) => l.trim()) ?? "";
  const summary = steps.length ? `执行了 ${steps.length} 项操作：${parts.join("、")}` : `思考：${firstThought.slice(0, 80)}`;
  return (
    <div className="h-group" data-failed={failed > 0}>
      <button type="button" className="h-group-head" aria-expanded={open} onClick={() => setOpen(!open)}>
        {open ? <ChevronDown {...ICON} size={14} /> : <ChevronRight {...ICON} size={14} />}
        <span>{summary}</span>
        {failed > 0 && <Pill tone="red">{failed} 项失败</Pill>}
        {pending > 0 && <Pill tone="accent">{pending} 项进行中</Pill>}
      </button>
      {open && (
        <div className="h-steps">
          {thinking.map((t, i) => steps.length ? (
            <details key={`t${i}`} className="h-step">
              <summary><span className="h-step-name">思考</span><span className="h-step-hint">{t.text.split("\n").find((l) => l.trim())}</span></summary>
              <div className="h-step-body muted">{t.text}</div>
            </details>
          ) : <div key={`t${i}`} className="h-thinking">{t.text}</div>)}
          {steps.map((s, i) => <StepRow key={i} step={s} />)}
        </div>
      )}
    </div>
  );
}

function StepRow({ step }: { step: Step }) {
  const took = step.result?.at && step.call.at ? Date.parse(step.result.at) - Date.parse(step.call.at) : null;
  const state = !step.result ? "进行中" : step.result.ok === false ? "失败" : null;
  return (
    <details className="h-step" data-failed={step.result?.ok === false}>
      <summary>
        <span className="h-step-name">{toolName(step.call.tool)}</span>
        <span className="h-step-hint">{hint(step.call)}</span>
        <span className="h-step-meta">{state ?? (took !== null && took >= 0 ? duration(took) : "")}</span>
      </summary>
      <pre className="code">{step.call.text}</pre>
      {step.result && <pre className="code" data-failed={step.result.ok === false}>{step.result.text}</pre>}
    </details>
  );
}

/** The last lines of a stream, so a long command output shows where it is now. */
function lastLines(text: string, n: number): string {
  const lines = text.split("\n");
  return lines.length > n ? lines.slice(-n).join("\n") : text;
}

/** A value being written as JSON, read before it is complete: the string at `field`, as far as it has arrived. */
export function partialString(json: string, field: string): string | null {
  const m = new RegExp(`"${field}"\\s*:\\s*"`).exec(json);
  if (!m) return null;
  let out = "";
  for (let i = m.index + m[0].length; i < json.length; i++) {
    const c = json[i]!;
    if (c === '"') return out;
    if (c !== "\\") { out += c; continue; }
    const next = json[++i];
    if (next === undefined) break;
    if (next === "n") out += "\n";
    else if (next === "t") out += "\t";
    else if (next === "u") {
      const hex = json.slice(i + 1, i + 5);
      if (hex.length < 4) break;
      out += String.fromCharCode(parseInt(hex, 16));
      i += 4;
    } else out += next;
  }
  return out;
}

/** A step the runtime is streaming: the reply as it is written, thinking, or a tool running with its output. */
function LiveStepView({ step }: { step: ShownStep }) {
  if (step.step === "text") {
    return step.text ? <div className="h-text markdown h-live"><Prose>{step.text}</Prose></div> : null;
  }
  if (step.step === "thinking") {
    return (
      <div className="h-live-thinking">
        <span className="activity-pulse inline" aria-hidden="true" />思考中
        {step.text && <div className="h-live-thinking-text">{lastLines(step.text, 4)}</div>}
      </div>
    );
  }
  const name = toolName(step.tool);
  const said = name === "chat_post" ? partialString(step.input, "text") : null;
  const hintText = said === null ? hint({ kind: "tool_call", tool: step.tool ?? "", text: step.input, at: null } as TimelineEntry) || step.input.slice(0, 160) : "";
  return (
    <div className="h-live-tool" data-ended={step.ended || undefined}>
      <div className="h-live-tool-head">
        {step.ended ? <span className="h-live-done" aria-hidden="true">✓</span> : <span className="spinner" aria-hidden="true" />}
        <strong>{said !== null ? "正在发送消息" : name}</strong>
        {hintText && <code>{hintText}</code>}
      </div>
      {said && <div className="markdown h-live-said"><Prose>{said}</Prose></div>}
      {step.output && <pre className="h-live-output">{lastLines(step.output, 12)}</pre>}
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
  useEffect(() => {
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
      <div ref={box} className={`fold-body${className ? ` ${className}` : ""}`} data-folded={long && !open ? true : undefined}>{children}</div>
      {long && <button type="button" className="text-toggle fold-toggle" onClick={() => setOpen(!open)}>{open ? "收起" : "展开"}</button>}
    </div>
  );
}

/** The turn's state with the model, with a running clock: starting up, waiting for the first token, or thinking. */
function PhaseLine({ phase, runtime }: { phase: ShownPhase; runtime: string }) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, []);
  const seconds = Math.max(0, Math.floor((now - phase.since) / 1000));
  const text = phase.phase === "starting" ? `正在启动 ${runtime}` : phase.phase === "requesting" ? "已发送请求，等待模型响应" : "Thinking";
  return (
    <div className="h-phase" data-phase={phase.phase}>
      <span className="activity-pulse inline" aria-hidden="true" />
      <span>{text}</span>
      <span className="h-phase-time">{seconds}s</span>
    </div>
  );
}
