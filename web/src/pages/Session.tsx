import { useMutation } from "@tanstack/react-query";
import { ExternalLink, History as HistoryIcon, Square } from "lucide-react";
import { useMemo } from "react";
import Markdown from "react-markdown";
import { useParams, useSearchParams } from "react-router";
import remarkGfm from "remark-gfm";
import { api, useOverview, useSession, useSessions, type BotView, type SessionDetail } from "../api.ts";
import { History, parseArgs, toolName } from "../History.tsx";
import { absoluteTime, cleanText, parsePrompt, relativeTime, sessionStatus, turnResult } from "../format.ts";
import { useToast } from "../toast.tsx";
import { Avatar, Button, Empty, IconButton, Menu, Pill } from "../ui.tsx";

export function SessionPage() {
  const { key } = useParams();
  const sessions = useSessions();
  const overview = useOverview();
  if (!key) {
    const hasBots = (overview.data?.bots.length ?? 0) > 0;
    return (
      <Empty>
        <img src="/admin/ember.svg" alt="" width={36} height={36} />
        <h2>{sessions.data?.length ? "选一个会话" : hasBots ? "还没有会话" : "添加第一个 bot"}</h2>
        <p>{sessions.data?.length ? "左边是所有 bot 在 Slack 里的会话，最近的在最上面。"
          : hasBots ? "在 Slack 里 @ 一个 bot，它接到的第一条消息会在这里出现。"
          : "每个 bot 是一个 Slack app，绑定一种运行时和模型。点左侧 Bot 旁边的 + 开始。"}</p>
      </Empty>
    );
  }
  return <Conversation key={key} sessionKey={key} />;
}

/** Slack deep link to the thread, when the bot's workspace is known. */
function threadUrl(bot: BotView | undefined, channel: string, threadTs: string): string | null {
  const workspace = bot && (bot.connection.state === "connected" || bot.connection.state === "reconnecting") ? bot.connection.workspace : null;
  return workspace?.url ? `${workspace.url}archives/${channel}/p${threadTs.replace(".", "")}` : null;
}

function Conversation({ sessionKey }: { sessionKey: string }) {
  const detail = useSession(sessionKey);
  const overview = useOverview();
  const [params, setParams] = useSearchParams();
  const toast = useToast();
  const historyOpen = params.get("history") !== "0";
  const stop = useMutation({ mutationFn: () => api.stop(sessionKey), onSuccess: () => toast("已请求停止") });
  const evict = useMutation({ mutationFn: () => api.evict(sessionKey), onSuccess: () => toast("已释放进程") });

  if (detail.isPending) return <div className="page" />;
  if (detail.isError) return <Empty><p>读不到这个会话：{detail.error.message}</p></Empty>;
  const { session } = detail.data;
  const bot = overview.data?.bots.find((b) => b.id === session.bot);
  const botName = bot?.name ?? session.bot;
  const url = threadUrl(bot, session.channel, session.threadTs);
  const toggleHistory = () => setParams(historyOpen ? { history: "0" } : {}, { replace: true });

  return (
    <div className="conversation-layout" data-history={historyOpen}>
      <section className="conversation" aria-label="会话">
        <header className="page-bar">
          <div className="page-bar-title">
            <Avatar id={session.bot} name={botName} size={22} />
            <h1>{cleanText(session.firstText) || "（没有消息）"}</h1>
          </div>
          <div className="page-bar-actions">
            {url && <a className="icon-btn" href={url} target="_blank" rel="noopener" aria-label="在 Slack 中打开" title="在 Slack 中打开"><ExternalLink size={16} strokeWidth={1.7} /></a>}
            <IconButton label={historyOpen ? "收起执行历史" : "执行历史"} icon={HistoryIcon} aria-pressed={historyOpen} onClick={toggleHistory} />
            <Menu items={[
              { label: "停止当前任务", disabled: session.process !== "running", onSelect: () => stop.mutate() },
              { label: "释放进程", disabled: session.process !== "warm", onSelect: () => evict.mutate() },
            ]} />
          </div>
        </header>
        <Messages detail={detail.data} botName={botName}
          botUserId={bot && (bot.connection.state === "connected" || bot.connection.state === "reconnecting") ? bot.connection.botUserId : null} />
        <ActivityBar detail={detail.data} url={url} onStop={() => stop.mutate()} stopping={stop.isPending} />
      </section>
      {historyOpen && <History detail={detail.data} bot={bot} onClose={toggleHistory} />}
    </div>
  );
}

type Line =
  | { kind: "human"; at: number; user: string; text: string }
  | { kind: "bot"; at: number; text: string; state: string | null; failed: boolean }
  | { kind: "notice"; at: number; text: string };

/** The thread as people saw it: their messages, the bot's posts, and turns that failed. */
function useLines(detail: SessionDetail): Line[] {
  return useMemo(() => {
    const lines: Line[] = detail.inbound.map((m) => ({ kind: "human", at: Number(m.ts) * 1000, user: m.user, text: m.text }));
    const timeline = detail.transcript?.timeline ?? [];
    const results = new Map(timeline.filter((e) => e.kind === "tool_result" && e.callId).map((e) => [e.callId!, e]));
    for (const e of timeline) {
      if (e.kind !== "tool_call" || e.subagent || toolName(e.tool) !== "chat_post") continue;
      const args = parseArgs(e.text);
      if (typeof args?.text !== "string") continue;
      lines.push({
        kind: "bot", at: e.at ? Date.parse(e.at) : 0, text: args.text,
        state: typeof args.kind === "string" ? args.kind : null,
        failed: e.callId ? results.get(e.callId)?.ok === false : false,
      });
    }
    for (const t of detail.turns) {
      if (t.outcome === "failed" && t.endedAt) lines.push({ kind: "notice", at: t.endedAt, text: `这一轮失败了：${t.detail ?? "原因未知"}` });
    }
    return lines.sort((a, b) => a.at - b.at);
  }, [detail]);
}

function Messages({ detail, botName, botUserId }: { detail: SessionDetail; botName: string; botUserId: string | null }) {
  const lines = useLines(detail);
  const mention = (text: string) => text.replace(/<@([A-Z0-9]+)>/g, (_, id: string) => `@${id === botUserId ? botName : id}`);
  if (lines.length === 0) return <div className="messages"><p className="muted">还没有消息。</p></div>;
  return (
    <div className="messages">
      {lines.map((line, i) => {
        if (line.kind === "human") {
          const { messages } = parsePrompt(line.text);
          const text = messages.length ? messages.map((m) => m.text).join("\n") : line.text;
          return (
            <div key={i} className="msg msg-human">
              <div className="msg-bubble">{mention(text)}</div>
              <div className="msg-meta">{line.user} · {relativeTime(line.at)}</div>
            </div>
          );
        }
        if (line.kind === "notice") return <div key={i} className="msg-notice" role="note">{line.text}</div>;
        return (
          <div key={i} className="msg msg-bot">
            <div className="msg-head">
              <Avatar id={detail.session.bot} name={botName} size={22} />
              <span className="msg-name">{botName}</span>
              <span className="msg-time" title={line.at ? absoluteTime(line.at) : undefined}>{line.at ? relativeTime(line.at) : ""}</span>
              {line.state === "final" && <Pill tone="green">已完成</Pill>}
              {line.state === "block" && <Pill tone="blue">等你回复</Pill>}
              {line.failed && <Pill tone="red">发送失败</Pill>}
            </div>
            <div className="markdown"><Markdown remarkPlugins={[remarkGfm]}>{line.text}</Markdown></div>
          </div>
        );
      })}
    </div>
  );
}

function ActivityBar({ detail, url, onStop, stopping }: { detail: SessionDetail; url: string | null; onStop(): void; stopping: boolean }) {
  const { session } = detail;
  const status = sessionStatus(session);
  if (status === "running" || status === "queued") {
    const lastTurn = detail.turns.at(-1);
    const since = lastTurn?.startedAt ?? session.lastActiveAt;
    const calls = (detail.transcript?.timeline ?? []).filter((e) => e.kind === "tool_call" && e.at && Date.parse(e.at) >= since).length;
    return (
      <div className="activity" data-state="running">
        <span className="activity-pulse" aria-hidden="true" />
        <span>{status === "queued" ? "排队中，马上开始" : `正在执行${calls ? `，已执行 ${calls} 项操作` : ""}`}</span>
        <Button icon={Square} onClick={onStop} busy={stopping}>停止</Button>
      </div>
    );
  }
  const result = turnResult(session.lastTurn);
  const text = result === "block" ? "在等你回复：去 Slack thread 里回复它。"
    : result === "failed" ? "上一轮失败了。在 Slack 里回复会重试。"
    : result === "unexpected" ? "上一轮没有给出明确结果就停了。"
    : "对话在 Slack thread 里继续。";
  return (
    <div className="activity" data-state={result}>
      <span>{text}</span>
      {url && <a className="btn btn-secondary" href={url} target="_blank" rel="noopener">在 Slack 中打开</a>}
    </div>
  );
}
