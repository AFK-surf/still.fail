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

function Timeline({ entries }: { entries: TimelineEntry[] }) {
  if (entries.length === 0) return <p className="note">记录里还没有内容。</p>;
  return (
    <div className="timeline">
      {entries.map((entry, i) => <Entry key={i} entry={entry} />)}
    </div>
  );
}

function Entry({ entry }: { entry: TimelineEntry }) {
  const sub = entry.subagent ? " entry-subagent" : "";
  const who = entry.subagent ? "子 agent" : "agent";
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
              <div className="entry-text">{m.text}</div>
            </div>
          ))}
        </>
      );
    }
    case "assistant":
      return (
        <div className={`entry entry-assistant${sub}`}>
          <div className="entry-who">{who}</div>
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
    case "tool_call":
      return (
        <details className={`entry fold${sub}`}>
          <summary><span className="tool-name">{toolLabel(entry.tool)}</span> {toolHint(entry.text)}</summary>
          <pre className="code">{entry.text}</pre>
        </details>
      );
    case "tool_result":
      return (
        <details className={`entry fold${sub}`} data-failed={entry.ok === false}>
          <summary>{entry.ok === false ? "工具报错" : "工具输出"}</summary>
          <pre className="code">{entry.text}</pre>
        </details>
      );
  }
}

function toolLabel(tool: string | undefined): string {
  if (!tool) return "工具";
  const mcp = /^mcp__ember__(.+)$/.exec(tool);
  if (mcp) return { chat_post: "发到 Slack", chat_state: "声明状态", chat_history: "读 thread 历史" }[mcp[1]!] ?? mcp[1]!;
  return tool;
}

/** One line that says what the call did: the command, the file, or the message. */
function toolHint(args: string): string {
  try {
    const value = JSON.parse(args) as Record<string, unknown>;
    const hint = value.command ?? value.cmd ?? value.file_path ?? value.path ?? value.pattern ?? value.text ?? value.kind ?? value.description;
    if (typeof hint === "string") return hint.split("\n")[0]!.slice(0, 120);
  } catch {
    // free-form arguments
  }
  return args.split("\n")[0]!.slice(0, 120);
}
