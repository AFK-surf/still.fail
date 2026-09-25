import { useMutation } from "@tanstack/react-query";
import { useMemo, useState, type ReactNode } from "react";
import { Link, useParams } from "react-router";
import { api, useOverview, useSession, useSessions, type SessionSummary, type TimelineEntry } from "../api.ts";
import {
  absoluteTime, cleanText, duration, parsePrompt, PROCESS_LABEL, relativeTime, RUNTIME_LABEL, sessionStatus, STATUS_LABEL, turnResult,
} from "../format.ts";
import { useToast } from "../toast.tsx";

export function SessionsPage() {
  const { key } = useParams();
  return (
    <div className="split" data-detail={Boolean(key)}>
      <SessionList selected={key} />
      <section className="detail-pane" aria-label="会话详情">
        {key ? <SessionDetailView key={key} sessionKey={key} /> : (
          <div className="empty"><p>选一个会话，看它在做什么。</p></div>
        )}
      </section>
    </div>
  );
}

function SessionList({ selected }: { selected: string | undefined }) {
  const overview = useOverview();
  const sessions = useSessions();
  const [bot, setBot] = useState<string | null>(null);
  const bots = overview.data?.bots ?? [];
  const botName = useMemo(() => new Map(bots.map((b) => [b.id, b.name])), [bots]);
  const memory = (overview.data?.processes ?? []).reduce((sum, p) => sum + (p.rssMb ?? 0), 0);
  const list = (sessions.data ?? [])
    .filter((s) => !bot || s.bot === bot)
    .sort((a, b) => rank(a) - rank(b) || b.lastActiveAt - a.lastActiveAt);

  return (
    <section className="list-pane" aria-label="会话列表">
      <div className="hearth">
        <div className="hearth-counts">
          <span className="count" data-temp="running"><span className="count-value">{overview.data?.counts.running ?? 0}</span>运行中</span>
          <span className="count" data-temp="warm"><span className="count-value">{overview.data?.counts.warm ?? 0}</span>保温中</span>
          <span className="count"><span className="count-value">{overview.data?.counts.sessions ?? 0}</span>全部</span>
        </div>
        {memory > 0 && <div className="note">运行时进程共占 {memory} MB 内存</div>}
        {bots.length > 1 && (
          <div className="filters" role="group" aria-label="按 bot 筛选">
            <button type="button" className="chip" aria-pressed={bot === null} onClick={() => setBot(null)}>全部 bot</button>
            {bots.map((b) => (
              <button key={b.id} type="button" className="chip" aria-pressed={bot === b.id} onClick={() => setBot(b.id)}>
                <span className="dot" data-state={b.connection.state} />{b.name}
              </button>
            ))}
          </div>
        )}
      </div>
      {list.length === 0 ? (
        <div className="empty"><p>{sessions.isPending ? "加载中" : "还没有会话。在 Slack 里 @ 一个 bot，这里就会出现。"}</p></div>
      ) : (
        <ul className="sessions">
          {list.map((s) => {
            const status = sessionStatus(s);
            return (
              <li key={s.key}>
                <Link className="session" data-temp={s.process} aria-current={s.key === selected} to={`/sessions/${encodeURIComponent(s.key)}`}>
                  <p className="session-title">{cleanText(s.firstText) || "（没有消息）"}</p>
                  <div className="session-meta">
                    <span className="status" data-status={status}>{STATUS_LABEL[status]}</span>
                    <span>{botName.get(s.bot) ?? s.bot}</span>
                    <span>{relativeTime(s.lastActiveAt)}</span>
                    {s.turns > 0 && <span>{s.turns} 轮</span>}
                  </div>
                </Link>
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}

/** Running first, then anything waiting on a person, then the rest by recency. */
function rank(s: SessionSummary): number {
  const status = sessionStatus(s);
  if (status === "running" || status === "queued") return 0;
  if (status === "block" || status === "failed" || status === "unexpected") return 1;
  return 2;
}

function SessionDetailView({ sessionKey }: { sessionKey: string }) {
  const detail = useSession(sessionKey);
  const overview = useOverview();
  const toast = useToast();
  const stop = useMutation({ mutationFn: () => api.stop(sessionKey), onSuccess: () => toast("已请求停止当前任务") });
  const evict = useMutation({ mutationFn: () => api.evict(sessionKey), onSuccess: () => toast("已释放进程") });

  if (detail.isPending) return null;
  if (detail.isError) return <div className="empty"><p>读不到这个会话：{detail.error.message}</p></div>;
  const { session: s, turns, transcript } = detail.data;
  const bot = overview.data?.bots.find((b) => b.id === s.bot);
  const status = sessionStatus(s);

  return (
    <article className="detail">
      <Link className="back" to="/sessions">返回会话列表</Link>
      <h1 className="detail-title">{cleanText(s.firstText) || "（没有消息）"}</h1>
      <dl className="facts">
        <Fact term="状态"><span className="status" data-status={status}>{STATUS_LABEL[status]}</span></Fact>
        <Fact term="进程">{PROCESS_LABEL[s.process]}</Fact>
        <Fact term="Bot">{bot?.name ?? s.bot}</Fact>
        <Fact term="运行时">{RUNTIME_LABEL[s.runtime]}{s.model ? `，${s.model}` : ""}</Fact>
        <Fact term="账号">{s.profile}</Fact>
        <Fact term="开始于">{absoluteTime(s.createdAt)}</Fact>
        <Fact term="最近活动">{relativeTime(s.lastActiveAt)}</Fact>
        <Fact term="频道">{s.channel}</Fact>
      </dl>
      <div className="actions">
        <button type="button" className="button" disabled={s.process !== "running" || stop.isPending} onClick={() => stop.mutate()}>停止当前任务</button>
        <button type="button" className="button" disabled={s.process !== "warm" || evict.isPending} onClick={() => evict.mutate()}
          title="结束空闲的运行时进程以释放内存；下一条消息会自动恢复对话">释放进程</button>
      </div>
      {(stop.error || evict.error) && <p className="error" role="alert">{(stop.error ?? evict.error)!.message}</p>}

      {turns.length > 0 && (
        <>
          <div className="turns" aria-label="每一轮的结果">
            {turns.map((t) => {
              const result = t.endedAt === null && s.process === "running" ? "running" : turnResult(t);
              const took = t.endedAt ? `，用时 ${duration(t.endedAt - t.startedAt)}` : "";
              return <span key={t.id} className="turn" data-result={result} title={`${absoluteTime(t.startedAt)} ${STATUS_LABEL[result]}${took}${t.detail ? `\n${t.detail}` : ""}`} />;
            })}
          </div>
          <div className="turns-caption">共 {turns.length} 轮，最近一轮{STATUS_LABEL[turnResult(turns.at(-1)!)]}</div>
        </>
      )}

      {transcript ? <Timeline entries={transcript.timeline} /> : (
        <p className="note">{s.runtimeSessionId ? "找不到这个会话的运行时记录（可能已归档或被删除）。" : "运行时还没开始这个会话。"}</p>
      )}
      <details className="fold" style={{ marginTop: 28 }}>
        <summary>技术信息</summary>
        <dl className="facts">
          <Fact term="会话 key"><span className="inline-code">{s.key}</span></Fact>
          <Fact term="运行时会话 ID"><span className="inline-code">{s.runtimeSessionId ?? "无"}</span></Fact>
          <Fact term="工作目录"><span className="inline-code">{s.workspace}</span></Fact>
          {transcript && <Fact term="运行时记录"><span className="inline-code">{transcript.path}</span></Fact>}
        </dl>
      </details>
    </article>
  );
}

function Fact({ term, children }: { term: string; children: ReactNode }) {
  return <div className="fact"><dt>{term}</dt><dd>{children}</dd></div>;
}

type Item =
  | { type: "entry"; entry: TimelineEntry }
  | { type: "tool"; call: TimelineEntry; result: TimelineEntry | null };

/** Pairs each tool call with its result (by call id, else the latest open call). */
function toItems(entries: TimelineEntry[]): Item[] {
  const items: Item[] = [];
  const open = new Map<string, Extract<Item, { type: "tool" }>>();
  let lastOpen: Extract<Item, { type: "tool" }> | null = null;
  for (const entry of entries) {
    if (entry.kind === "tool_call") {
      const item = { type: "tool" as const, call: entry, result: null };
      items.push(item);
      if (entry.callId) open.set(entry.callId, item);
      lastOpen = item;
    } else if (entry.kind === "tool_result") {
      const item = (entry.callId && open.get(entry.callId)) || (lastOpen && !lastOpen.result ? lastOpen : null);
      if (item) {
        item.result = entry;
        if (entry.callId) open.delete(entry.callId);
      } else {
        items.push({ type: "entry", entry });
      }
    } else {
      items.push({ type: "entry", entry });
    }
  }
  return items;
}

/** `<@U123>` → `@name` for known users (the bots), `@U123` otherwise. */
function useMentions(): (text: string) => string {
  const overview = useOverview();
  const names = useMemo(() => new Map((overview.data?.bots ?? []).flatMap((b) =>
    b.connection.state === "connected" || b.connection.state === "reconnecting" ? [[b.connection.botUserId, b.name] as const] : [])), [overview.data]);
  return (text) => text.replace(/<@([A-Z0-9]+)>/g, (_, id: string) => `@${names.get(id) ?? id}`);
}

function Timeline({ entries }: { entries: TimelineEntry[] }) {
  const mentions = useMentions();
  if (entries.length === 0) return <p className="note">记录里还没有内容。</p>;
  return (
    <div className="timeline">
      {toItems(entries).map((item, i) => item.type === "tool"
        ? <ToolItem key={i} call={item.call} result={item.result} />
        : <Entry key={i} entry={item.entry} mentions={mentions} />)}
    </div>
  );
}

function Entry({ entry, mentions }: { entry: TimelineEntry; mentions: (text: string) => string }) {
  const sub = entry.subagent ? " entry-subagent" : "";
  switch (entry.kind) {
    case "user": {
      const { messages, note } = parsePrompt(entry.text);
      return (
        <>
          {note && (
            <div className={`entry entry-ember${sub}`}>
              <div className="entry-who">ember</div>
              <div className="entry-text">{note}</div>
            </div>
          )}
          {messages.map((m) => (
            <div key={m.ts} className={`entry entry-user${sub}`}>
              <div className="entry-who">{m.user}{entry.at ? `，${absoluteTime(Date.parse(entry.at))}` : ""}</div>
              <div className="entry-text">{mentions(m.text)}</div>
            </div>
          ))}
        </>
      );
    }
    case "assistant":
      return (
        <div className={`entry entry-aside${sub}`}>
          <div className="entry-who">{entry.subagent ? "子 agent" : "agent"}的内部说明，没有发到 Slack</div>
          <div className="entry-text">{entry.text}</div>
        </div>
      );
    case "thinking":
      return (
        <details className={`entry fold${sub}`}>
          <summary>思考</summary>
          <div className="entry-text note">{entry.text}</div>
        </details>
      );
    default:
      return (
        <details className={`entry fold${sub}`} data-failed={entry.ok === false}>
          <summary>{entry.ok === false ? "工具报错" : "工具输出"}</summary>
          <pre className="code">{entry.text}</pre>
        </details>
      );
  }
}

const STATE_TEXT: Record<string, string> = { final: "已完成", block: "等你回复" };

function ToolItem({ call, result }: { call: TimelineEntry; result: TimelineEntry | null }) {
  const sub = call.subagent ? " entry-subagent" : "";
  const args = parseArgs(call.text);
  const name = (call.tool ?? "").replace(/^mcp__ember__|^ember__|^mcp__ember_/, "");
  const failed = result?.ok === false;

  if (name === "chat_post" && typeof args?.text === "string") {
    const kind = typeof args.kind === "string" ? args.kind : null;
    return (
      <div className={`entry entry-post${sub}`} data-failed={failed}>
        <div className="entry-who">
          发到 Slack{kind && STATE_TEXT[kind] ? <span className="post-state" data-kind={kind}>{STATE_TEXT[kind]}</span> : null}
          {failed && "，发送失败"}
        </div>
        <div className="entry-text">{args.text}</div>
        {failed && result && <pre className="code">{result.text}</pre>}
      </div>
    );
  }
  if (name === "chat_state" && typeof args?.kind === "string") {
    return <div className={`entry entry-marker${sub}`}>标记为{STATE_TEXT[args.kind] ?? args.kind}</div>;
  }
  return (
    <details className={`entry fold${sub}`} data-failed={failed}>
      <summary>
        <span className="tool-name">{toolLabel(name || call.tool)}</span> {toolHint(args, call.text)}
        {!result && <span className="note">，等待结果</span>}
        {failed && "，报错"}
      </summary>
      <pre className="code">{call.text}</pre>
      {result && <pre className="code" data-failed={failed}>{result.text}</pre>}
    </details>
  );
}

function parseArgs(text: string): Record<string, unknown> | null {
  try {
    const value = JSON.parse(text) as unknown;
    return value && typeof value === "object" ? value as Record<string, unknown> : null;
  } catch {
    return null;
  }
}

function toolLabel(tool: string | undefined): string {
  if (!tool) return "工具";
  return { chat_history: "读 thread 历史", exec_command: "命令" }[tool] ?? tool;
}

/** One line that says what the call did: the command, the file, or the pattern. */
function toolHint(args: Record<string, unknown> | null, raw: string): string {
  const hint = args ? args.command ?? args.cmd ?? args.file_path ?? args.path ?? args.pattern ?? args.url ?? args.description : raw;
  const text = typeof hint === "string" ? hint : Array.isArray(hint) ? hint.join(" ") : "";
  return text.split("\n")[0]!.slice(0, 140);
}
