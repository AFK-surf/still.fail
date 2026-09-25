import { useMutation } from "@tanstack/react-query";
import { ExternalLink, History as HistoryIcon, Square, Unplug } from "lucide-react";
import { DropdownMenu } from "radix-ui";
import { useMemo } from "react";
import Markdown from "react-markdown";
import { useParams, useSearchParams } from "react-router";
import remarkGfm from "remark-gfm";
import { api, useOverview, useSession, useSessions, type ConnectView, type SessionDetail } from "../api.ts";
import { History, parseArgs, toolName } from "../History.tsx";
import {
  absoluteTime, botUserIdOf, parsePrompt, sessionTitle, relativeTime, sessionStatus, slackThreadUrl, splitThread, turnResult, threadNamer,
} from "../format.ts";
import { useToast } from "../toast.tsx";
import { Avatar, Button, Empty, ICON, IconButton, Menu, MobileBack, Pill, Tip } from "../ui.tsx";

export function SessionPage() {
  const { key } = useParams();
  const sessions = useSessions();
  const overview = useOverview();
  if (!key) {
    const hasConnects = (overview.data?.connects.length ?? 0) > 0;
    return (
      <Empty>
        <img src="/admin/ember.svg" alt="" width={36} height={36} />
        <h2>{sessions.data?.length ? "选一个会话" : hasConnects ? "还没有会话" : "添加第一个连接"}</h2>
        <p>{sessions.data?.length ? "左边是所有连接的会话，最近活动的在最上面。"
          : hasConnects ? "在 Slack 里 @ 它，收到的第一条消息会在这里出现。"
          : "连接是人找到 ember 的地方，比如一个 Slack app；每个连接绑定一个模型。点左侧「连接」旁边的 + 开始。"}</p>
      </Empty>
    );
  }
  return <Conversation key={key} sessionKey={key} />;
}

function workspaceUrl(connect: ConnectView | undefined): string | null {
  const c = connect?.connection;
  return c && (c.state === "connected" || c.state === "reconnecting") ? c.workspace?.url ?? null : null;
}

function Conversation({ sessionKey }: { sessionKey: string }) {
  const detail = useSession(sessionKey);
  const overview = useOverview();
  const [params, setParams] = useSearchParams();
  const toast = useToast();
  // Open beside the conversation on wide screens; on narrow ones it would cover it, so start closed.
  const historyOpen = params.has("history") ? params.get("history") === "1" : window.matchMedia("(min-width: 1101px)").matches;
  const stop = useMutation({ mutationFn: () => api.stop(sessionKey), onSuccess: () => toast("已请求停止") });
  const evict = useMutation({ mutationFn: () => api.evict(sessionKey), onSuccess: () => toast("已释放进程") });

  if (detail.isPending) return <div className="page" />;
  if (detail.isError) return <Empty><p>读不到这个会话：{detail.error.message}</p></Empty>;
  const { session, threads } = detail.data;
  const connect = overview.data?.connects.find((c) => c.id === session.connect);
  const name = connect?.name ?? session.connect;
  const base = workspaceUrl(connect);
  const toggleHistory = () => setParams({ history: historyOpen ? "0" : "1" }, { replace: true });
  const title = sessionTitle(session, name);
  const single = threads.length <= 1 ? threads[0] : undefined;
  const singleUrl = single ? slackThreadUrl(base, single.channel, single.threadTs) : null;

  return (
    <div className="conversation-layout" data-history={historyOpen}>
      <section className="conversation" aria-label="会话">
        <header className="page-bar">
          <MobileBack to="/sessions" label="会话" />
          <div className="page-bar-title">
            <h1>{title}</h1>
            {session.scope === "all" && <Pill>{threads.length} 个 thread</Pill>}
          </div>
          <div className="page-bar-actions">
            {session.scope === "all" && threads.length > 1
              ? <ThreadMenu detail={detail.data} base={base} />
              : singleUrl && (
                <Tip label="在 Slack 中打开">
                  <a className="icon-btn" href={singleUrl} target="_blank" rel="noopener" aria-label="在 Slack 中打开"><ExternalLink {...ICON} /></a>
                </Tip>
              )}
            <IconButton label={historyOpen ? "收起执行历史" : "执行历史"} icon={HistoryIcon} aria-pressed={historyOpen} onClick={toggleHistory} />
            <Menu items={[
              { label: "停止当前任务", icon: Square, disabled: session.process !== "running", onSelect: () => stop.mutate() },
              { label: "释放进程", icon: Unplug, disabled: session.process !== "warm", onSelect: () => evict.mutate() },
            ]} />
          </div>
        </header>
        <Messages detail={detail.data} name={name} botUserId={botUserIdOf(connect)} base={base} />
        <ActivityBar detail={detail.data} url={singleUrl} onStop={() => stop.mutate()} stopping={stop.isPending} />
      </section>
      {historyOpen && <History detail={detail.data} connect={connect} onClose={toggleHistory} />}
    </div>
  );
}

function ThreadMenu({ detail, base }: { detail: SessionDetail; base: string | null }) {
  const name = threadNamer(detail);
  return (
    <DropdownMenu.Root modal={false}>
      <Tip label="这个会话的 thread">
        <DropdownMenu.Trigger asChild>
          <button type="button" className="icon-btn" aria-label="这个会话的 thread"><ExternalLink {...ICON} /></button>
        </DropdownMenu.Trigger>
      </Tip>
      <DropdownMenu.Portal>
        <DropdownMenu.Content className="popover menu-list thread-menu" align="end" sideOffset={4} collisionPadding={8}>
          <DropdownMenu.Label className="menu-label">在 Slack 中打开</DropdownMenu.Label>
          {detail.threads.map((t) => {
            const url = slackThreadUrl(base, t.channel, t.threadTs);
            const { where, when } = name(t.channel, t.threadTs);
            return (
              <DropdownMenu.Item key={`${t.channel}/${t.threadTs}`} className="menu-item" disabled={!url}
                onSelect={() => { if (url) window.open(url, "_blank", "noopener"); }}>
                <span className="thread-item">
                  <span>{where}</span>
                  <span className="muted">{when} 开始 · {t.messages} 条消息</span>
                </span>
              </DropdownMenu.Item>
            );
          })}
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}

type Line = { at: number; thread: string | null } & (
  | { kind: "human"; user: string; text: string }
  | { kind: "bot"; text: string; state: string | null; failed: boolean }
  | { kind: "notice"; text: string }
);

/** The conversations as people saw them: their messages, the agent's posts, and turns that failed. */
function useLines(detail: SessionDetail): Line[] {
  return useMemo(() => {
    const lines: Line[] = detail.inbound.map((m) => ({
      kind: "human", at: Number(m.ts) * 1000, thread: `${m.channel}/${m.threadTs}`, user: m.user, text: m.text,
    }));
    const timeline = detail.transcript?.timeline ?? [];
    const results = new Map(timeline.filter((e) => e.kind === "tool_result" && e.callId).map((e) => [e.callId!, e]));
    for (const e of timeline) {
      if (e.kind !== "tool_call" || e.subagent || toolName(e.tool) !== "chat_post") continue;
      const args = parseArgs(e.text);
      if (typeof args?.text !== "string") continue;
      lines.push({
        kind: "bot", at: e.at ? Date.parse(e.at) : 0, text: args.text,
        // Older sessions posted without naming a thread; they only had one.
        thread: typeof args.to === "string" ? args.to : null,
        state: typeof args.kind === "string" ? args.kind : null,
        failed: e.callId ? results.get(e.callId)?.ok === false : false,
      });
    }
    for (const t of detail.turns) {
      if (t.outcome === "failed" && t.endedAt) lines.push({ kind: "notice", at: t.endedAt, thread: null, text: `这一轮失败了：${t.detail ?? "原因未知"}` });
    }
    return lines.sort((a, b) => a.at - b.at);
  }, [detail]);
}

function Messages({ detail, name, botUserId, base }: { detail: SessionDetail; name: string; botUserId: string | null; base: string | null }) {
  const lines = useLines(detail);
  const threadName = threadNamer(detail);
  const person = (id: string) => detail.people[id] ?? id;
  const mention = (text: string) => text.replace(/<@([A-Z0-9]+)>/g, (_, id: string) => `@${id === botUserId ? name : person(id)}`);
  const many = detail.threads.length > 1;
  if (lines.length === 0) return <div className="messages"><p className="muted">还没有消息。</p></div>;
  let current: string | null = null;
  return (
    <div className="messages">
      {lines.map((line, i) => {
        // With several threads, mark where the conversation moves to another one.
        let divider = null;
        if (many && line.thread && line.thread !== current) {
          current = line.thread;
          const t = splitThread(line.thread);
          if (t) {
            const { where, when } = threadName(t.channel, t.threadTs);
            const url = slackThreadUrl(base, t.channel, t.threadTs);
            divider = (
              <div className="thread-divider" key={`d${i}`}>
                {url ? <a href={url} target="_blank" rel="noopener">{where}</a> : <span>{where}</span>}
                <span className="muted">{when} 的 thread</span>
              </div>
            );
          }
        }
        let body;
        if (line.kind === "human") {
          const { messages } = parsePrompt(line.text);
          const text = messages.length ? messages.map((m) => m.text).join("\n") : line.text;
          body = (
            <div key={i} className="msg msg-human">
              <div className="msg-bubble">{mention(text)}</div>
              <div className="msg-meta">{person(line.user)} · <span title={absoluteTime(line.at)}>{relativeTime(line.at)}</span></div>
            </div>
          );
        } else if (line.kind === "notice") {
          body = <div key={i} className="msg-notice" role="note">{line.text}</div>;
        } else {
          body = (
            <div key={i} className="msg msg-bot">
              <div className="msg-head">
                <Avatar id={detail.session.connect} name={name} size={22} />
                <span className="msg-name">{name}</span>
                <span className="msg-time" title={line.at ? absoluteTime(line.at) : undefined}>{line.at ? relativeTime(line.at) : ""}</span>
                {line.state === "final" && <Pill tone="green">已完成</Pill>}
                {line.state === "block" && <Pill tone="blue">等你回复</Pill>}
                {line.failed && <Pill tone="red">发送失败</Pill>}
              </div>
              <div className="markdown"><Markdown remarkPlugins={[remarkGfm]}>{line.text}</Markdown></div>
            </div>
          );
        }
        return divider ? [divider, body] : body;
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
  const text = result === "block" ? "在等人回复：去 Slack thread 里回复它。"
    : result === "failed" ? "上一轮失败了。在 Slack 里回复会重试。"
    : result === "unexpected" ? "上一轮没有给出明确结果就停了。"
    : "对话在 Slack 里继续。";
  return (
    <div className="activity" data-state={result}>
      <span>{text}</span>
      {url && <a className="btn btn-secondary" href={url} target="_blank" rel="noopener">在 Slack 中打开</a>}
    </div>
  );
}
