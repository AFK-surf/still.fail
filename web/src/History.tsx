// Execution history, after Zork's: a readable account of what actually ran.
// Messages in and out, state marks and the agent's own words are boundaries;
// the tool calls and thinking between two boundaries fold into one group.
import { ArrowDownToLine, ChevronDown, ChevronRight, Send, X } from "lucide-react";
import { useMemo, useState } from "react";
import Markdown from "react-markdown";
import remarkGfm from "remark-gfm";
import type { ConnectView, SessionDetail, TimelineEntry } from "./api.ts";
import { botUserIdOf, compactNumber, duration, parsePrompt, RUNTIME_LABEL, splitThread, threadNamer } from "./format.ts";
import { Avatar, ICON, IconButton, Pill } from "./ui.tsx";

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

export function History({ detail, connect, onClose }: { detail: SessionDetail; connect: ConnectView | undefined; onClose(): void }) {
  const botUserId = botUserIdOf(connect);
  const threadName = threadNamer(detail);
  // Only worth saying which thread when there is more than one.
  const where = (address: string | null | undefined) => {
    const t = address && detail.threads.length > 1 ? splitThread(address) : null;
    return t ? threadName(t.channel, t.threadTs).where : null;
  };
  const [usageOpen, setUsageOpen] = useState(false);
  const { session, transcript } = detail;
  const items = useMemo(() => toItems(transcript?.timeline ?? []), [transcript]);
  const usage = transcript?.usage;
  const model = usage?.model ?? session.model ?? connect?.bind.model ?? null;
  const name = connect?.name ?? session.connect;
  const hitRate = usage && usage.inputTokens > 0 ? Math.round((usage.cachedTokens / usage.inputTokens) * 100) : null;

  return (
    <aside className="history" aria-label="执行历史">
      <header className="history-head">
        <div className="history-identity">
          <Avatar id={session.connect} name={name} size={18} />
          <span className="history-name">{name}</span>
          <span className="history-sep">·</span>
          <span>{RUNTIME_LABEL[session.runtime]}</span>
          {model && <><span className="history-sep">·</span><span>{model}</span></>}
          {usage && <><span className="history-sep">·</span><span>{compactNumber(usage.inputTokens + usage.outputTokens)} tokens</span></>}
        </div>
        <div className="history-tools">
          {usage && (
            <button type="button" className="text-toggle" aria-expanded={usageOpen} onClick={() => setUsageOpen(!usageOpen)}>
              用量 <ChevronDown {...ICON} size={14} />
            </button>
          )}
          <IconButton label="关闭执行历史" icon={X} onClick={onClose} />
        </div>
      </header>
      {usageOpen && usage && (
        <dl className="usage">
          <div><dt>模型调用</dt><dd>{usage.modelCalls} 次</dd></div>
          <div><dt>输入</dt><dd>{compactNumber(usage.inputTokens)}</dd></div>
          <div><dt>其中缓存</dt><dd>{compactNumber(usage.cachedTokens)}</dd></div>
          <div><dt>输出</dt><dd>{compactNumber(usage.outputTokens)}</dd></div>
          <div><dt>缓存命中率</dt><dd>{hitRate === null ? "未报告" : `${hitRate}%`}</dd></div>
        </dl>
      )}
      <div className="history-body">
        {!transcript ? (
          <p className="history-edge">{session.runtimeSessionId ? "找不到运行时记录，可能已归档。" : "运行时还没开始这个会话。"}</p>
        ) : (
          <>
            <p className="history-edge">已到 Session 开始处</p>
            {items.map((item, i) => (
              <HistoryItem key={i} item={item} where={where} person={(id) => detail.people[id] ?? id}
                mention={(text) => text.replace(/<@([A-Z0-9]+)>/g, (_, id: string) => `@${id === botUserId ? name : detail.people[id] ?? id}`)} />
            ))}
          </>
        )}
      </div>
    </aside>
  );
}

function HistoryItem({ item, mention, person, where }: { item: Item; mention(text: string): string; person(id: string): string; where(address: string | null | undefined): string | null }) {
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
      return <div className={`h-text markdown${item.entry.subagent ? " h-sub" : ""}`}><Markdown remarkPlugins={[remarkGfm]}>{item.entry.text}</Markdown></div>;
    case "post": {
      const args = parseArgs(item.step.call.text)!;
      const kind = typeof args.kind === "string" ? args.kind : null;
      const failed = item.step.result?.ok === false;
      return (
        <div className="h-post" data-failed={failed}>
          <div className="h-post-head">
            <Send {...ICON} size={14} />
            发送到 {where(typeof args.to === "string" ? args.to : null) ?? "Slack"}
            {kind === "final" && <Pill tone="green">已完成</Pill>}
            {kind === "block" && <Pill tone="blue">等你回复</Pill>}
            {failed && <Pill tone="red">发送失败</Pill>}
          </div>
          <div className="markdown"><Markdown remarkPlugins={[remarkGfm]}>{String(args.text)}</Markdown></div>
        </div>
      );
    }
    case "mark":
      return <div className="h-mark">标记为{item.kind === "final" ? "已完成" : item.kind === "block" ? "等你回复" : item.kind}</div>;
    case "group":
      return <Group steps={item.steps} thinking={item.thinking} />;
  }
}

function Received({ from, text, place }: { from: string; text: string; place?: string | null }) {
  const [open, setOpen] = useState(false);
  const long = text.length > 280 || text.split("\n").length > 5;
  return (
    <div className="h-received">
      <div className="h-label"><ArrowDownToLine {...ICON} size={14} />收到来自 <strong>{from === "ember" ? "ember" : from}</strong> 的{from === "ember" ? "提醒" : "消息"}{place && <span className="h-place">{place}</span>}</div>
      <blockquote className="h-quote" data-clamped={long && !open}>{text}</blockquote>
      {long && <button type="button" className="text-toggle" onClick={() => setOpen(!open)}>{open ? "收起" : "展开更多"}</button>}
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
