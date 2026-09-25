// A session: its execution history is the page; what can be done to it sits
// with the history. A chat can be opened beside it: ember's own chat, which
// reaches the agent the way a Slack thread does.
import { useIsMine, useLink, usePerson, useStation } from "../station.tsx";
import { CreatorText, PeopleStack } from "../components.tsx";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { ArrowUp, PanelRightClose, PanelRightOpen, Square, Unplug, X } from "lucide-react";
import { DropdownMenu, Tabs } from "radix-ui";
import { useEffect, useRef, useState, type ReactNode } from "react";
import Markdown from "react-markdown";
import { Link, useParams } from "react-router";
import remarkGfm from "remark-gfm";
import { useApi, keys, useOverview, useSession, useSessions, type ConnectView, type SessionDetail } from "../api.ts";
import { History } from "../History.tsx";
import {
  PROCESS_LABEL, RUNTIME_LABEL, STATUS_LABEL, absoluteTime, agentLabel, relativeTime, sessionStatus, sessionTitle, slackThreadUrl, statusTone, threadNamer, turnResult,
} from "../format.ts";
import { useToast } from "../toast.tsx";
import { Button, ConnectKindIcon, Empty, ICON, IconButton, Loading, Menu, MobileBack, Pill, RuntimeLogo, SlackLogo, Tip } from "../ui.tsx";

export function SessionPage() {
  const { key } = useParams();
  const sessions = useSessions();
  const overview = useOverview();
  if (!key) {
    const hasConnects = (overview.data?.connects.length ?? 0) > 0;
    return (
      <Empty>
        <img src={`${import.meta.env.BASE_URL}ember.svg`} alt="" width={36} height={36} />
        <h2>{sessions.data?.length ? "选一个会话" : hasConnects ? "还没有会话" : "添加第一个连接"}</h2>
        <p>{sessions.data?.length ? "左边是所有连接的会话，最近活动的在最上面。"
          : hasConnects ? "在 Slack 里 @ 它，收到的第一条消息会在这里出现。"
          : "连接是人找到 ember 的地方，比如一个 Slack app；每个连接绑定一个模型。点左侧「连接」旁边的 + 开始。"}</p>
      </Empty>
    );
  }
  return <SessionView key={key} sessionKey={key} />;
}

function workspaceUrl(connect: ConnectView | undefined): string | null {
  const c = connect?.connection;
  return c && (c.state === "connected" || c.state === "reconnecting") ? c.workspace?.url ?? null : null;
}

function SessionView({ sessionKey }: { sessionKey: string }) {
  const station = useStation();
  const link = useLink();
  const detail = useSession(sessionKey);
  const overview = useOverview();
  // The side panel stays open on wide screens unless closed; on narrow ones it opens on demand, over the chat.
  const [panel, setPanel] = useState<boolean>(() => localStorage.getItem("ember.sidePanel") !== "0" && window.matchMedia("(min-width: 1101px)").matches);
  const [tab, setTab] = useState(() => localStorage.getItem("ember.sideTab") ?? "history");
  const togglePanel = (open: boolean) => {
    setPanel(open);
    localStorage.setItem("ember.sidePanel", open ? "1" : "0");
  };
  if (detail.isPending) return <Loading label={station.name ? `正在从 ${station.name} 读取会话…` : "正在读取会话…"} />;
  if (detail.isError) return <Empty><p>读不到这个会话：{detail.error.message}</p></Empty>;
  const { session, threads, chats } = detail.data;
  const connect = overview.data?.connects.find((c) => c.id === session.connect);
  const name = connect?.name ?? session.connect;
  const base = workspaceUrl(connect);
  const slackThreads = threads.filter((t) => t.channel !== "EMBER");
  const single = slackThreads.length === 1 ? slackThreads[0] : undefined;
  const singleUrl = single ? slackThreadUrl(base, single.channel, single.threadTs) : null;
  const status = sessionStatus(session);
  // One chat per session; older sessions may have several, of which the first is the one.
  const chat = chats[0];
  return (
    <div className="session-page">
      <header className="page-bar">
        <MobileBack to={link("/sessions")} label="会话" />
        <div className="page-bar-title">
          {station.name && <span className="station-tag">{station.name}</span>}
          <h1>{sessionTitle(session, name)}</h1>
          <Pill tone={statusTone(status)}>{STATUS_LABEL[status]}</Pill>
        </div>
        <div className="page-bar-actions">
          {slackThreads.length > 1
            ? <ThreadMenu detail={detail.data} base={base} />
            : singleUrl && (
              <Tip label="在 Slack 中打开">
                <a className="icon-btn" href={singleUrl} target="_blank" rel="noopener" aria-label="在 Slack 中打开"><SlackLogo /></a>
              </Tip>
            )}
          <IconButton label={panel ? "收起侧栏" : "执行历史与详情"} icon={panel ? PanelRightClose : PanelRightOpen} aria-pressed={panel} onClick={() => togglePanel(!panel)} />
        </div>
      </header>
      {/* The chat is the page; the session's history and details sit in a tab set on the right. */}
      <div className="session-body" data-panel={panel}>
        <ChatPanel detail={detail.data} chat={chat} />
        {panel && (
          <Tabs.Root className="side-panel" value={tab} onValueChange={(v) => { setTab(v); localStorage.setItem("ember.sideTab", v); }}>
            <div className="side-tabs">
              <Tabs.List className="side-tab-list" aria-label="会话侧栏">
                <Tabs.Trigger className="side-tab" value="history">执行历史</Tabs.Trigger>
                <Tabs.Trigger className="side-tab" value="details">详情</Tabs.Trigger>
              </Tabs.List>
              <IconButton label="收起侧栏" icon={X} onClick={() => togglePanel(false)} />
            </div>
            <Tabs.Content className="side-content" value="history">
              <History detail={detail.data} connect={connect} actions={<SessionActions detail={detail.data} />} />
            </Tabs.Content>
            <Tabs.Content className="side-content" value="details">
              <SessionDetails detail={detail.data} connect={connect} base={base} />
            </Tabs.Content>
          </Tabs.Root>
        )}
      </div>
    </div>
  );
}

/** What a session is: where it runs, what runs it, who is in it, where it is talked about. */
function SessionDetails({ detail, connect, base }: { detail: SessionDetail; connect: ConnectView | undefined; base: string | null }) {
  const { session } = detail;
  const station = useStation();
  const link = useLink();
  const name = threadNamer(detail);
  const threads = detail.threads.filter((t) => t.channel !== "EMBER");
  const row = (label: string, value: ReactNode) => <div className="detail-row"><dt>{label}</dt><dd>{value}</dd></div>;
  return (
    <div className="session-details">
      <dl className="details">
        {station.name && row("Station", station.name)}
        {row("连接", connect ? <Link to={link(`/connects/${connect.id}`)} className="detail-link"><ConnectKindIcon kind={connect.kind} size={13} />{connect.name}</Link> : session.connect)}
        {row("运行时", <span className="detail-inline"><RuntimeLogo runtime={session.runtime} size={13} />{RUNTIME_LABEL[session.runtime]}</span>)}
        {row("模型", agentLabel(detail.transcript?.usage?.model ?? session.model, session.effort))}
        {row("发起", session.creator ? <CreatorText creator={session.creator} verb="发起" /> : <span className="muted">未记录</span>)}
        {row("参与", <span className="detail-inline"><PeopleStack people={session.participants} max={8} />{session.participants?.length ?? 0} 人</span>)}
        {row("状态", <SessionState detail={detail} />)}
        {row("创建", absoluteTime(session.createdAt))}
        {row("最近活动", `${relativeTime(session.lastActiveAt)}`)}
      </dl>
      {threads.length > 0 && (
        <section className="details-section">
          <h3>Slack thread</h3>
          <ul className="details-list">
            {threads.map((t) => {
              const url = slackThreadUrl(base, t.channel, t.threadTs);
              const { where, when } = name(t.channel, t.threadTs);
              return (
                <li key={`${t.channel}/${t.threadTs}`}>
                  {url ? <a href={url} target="_blank" rel="noopener" className="detail-link"><SlackLogo size={13} />{where}</a> : <span className="detail-inline"><SlackLogo size={13} />{where}</span>}
                  <span className="muted">{when} 开始 · {t.messages} 条消息</span>
                </li>
              );
            })}
          </ul>
        </section>
      )}
    </div>
  );
}

/** Where the session stands, for the history's header line. */
function SessionState({ detail }: { detail: SessionDetail }) {
  const { session } = detail;
  const status = sessionStatus(session);
  const running = status === "running" || status === "queued";
  const since = detail.turns.at(-1)?.startedAt ?? session.lastActiveAt;
  const calls = (detail.transcript?.timeline ?? []).filter((e) => e.kind === "tool_call" && e.at && Date.parse(e.at) >= since).length;
  const result = turnResult(session.lastTurn);
  const text = running
    ? (status === "queued" ? "排队中" : `正在执行${calls ? ` · 已执行 ${calls} 项` : ""}`)
    : result === "block" ? "等人回复"
    : result === "failed" ? "上一轮失败"
    : result === "unexpected" ? "上一轮没给出结果"
    : result === "final" ? "上一轮已完成"
    : "空闲";
  return (
    <span className="session-state" data-state={running ? "running" : result}>
      {running && <span className="activity-pulse inline" aria-hidden="true" />}
      {text}
      <span className="history-sep">·</span>
      进程{PROCESS_LABEL[session.process]}
    </span>
  );
}

/** What can be done to it right now: stop a turn, release an idle process. */
function SessionActions({ detail }: { detail: SessionDetail }) {
  const api = useApi();
  const toast = useToast();
  const { session } = detail;
  const stop = useMutation({ mutationFn: () => api.stop(session.key), onSuccess: () => toast("已请求停止") });
  const evict = useMutation({ mutationFn: () => api.evict(session.key), onSuccess: () => toast("已释放进程") });
  const status = sessionStatus(session);
  return (
    <>
      {(status === "running" || status === "queued") && <IconButton label="停止当前任务" icon={Square} onClick={() => stop.mutate()} disabled={stop.isPending} />}
      {session.process === "warm" && <IconButton label="释放进程" icon={Unplug} onClick={() => evict.mutate()} disabled={evict.isPending} />}
    </>
  );
}

function ThreadMenu({ detail, base }: { detail: SessionDetail; base: string | null }) {
  const name = threadNamer(detail);
  return (
    <DropdownMenu.Root modal={false}>
      <Tip label="这个会话的 Slack thread">
        <DropdownMenu.Trigger asChild>
          <button type="button" className="icon-btn" aria-label="这个会话的 Slack thread"><SlackLogo /></button>
        </DropdownMenu.Trigger>
      </Tip>
      <DropdownMenu.Portal>
        <DropdownMenu.Content className="popover menu-list thread-menu" align="end" sideOffset={4} collisionPadding={8}>
          <DropdownMenu.Label className="menu-label">在 Slack 中打开</DropdownMenu.Label>
          {detail.threads.filter((t) => t.channel !== "EMBER").map((t) => {
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

/** ember's own chat with the session: what people type reaches the agent like a Slack message; it answers with chat_post. */
function ChatPanel({ detail, chat }: { detail: SessionDetail; chat: SessionDetail["chats"][number] | undefined }) {
  const list = useRef<HTMLDivElement>(null);
  const messages = chat?.messages ?? [];
  useEffect(() => {
    if (list.current) list.current.scrollTop = list.current.scrollHeight;
  }, [messages.length]);
  const status = sessionStatus(detail.session);
  const busy = status === "running" || status === "queued";
  const member = usePerson();
  const isMine = useIsMine();
  const person = (id: string) => (isMine({ id, email: id }) ? "你" : member(id)?.name || detail.people[id] || (id === "local" ? "管理员" : id));
  const agent = agentLabel(detail.transcript?.usage?.model ?? detail.session.model, detail.session.effort);

  return (
    <section className="chat" aria-label="对话">
      <div className="chat-list" ref={list}>
        {messages.length === 0 && (
          <div className="chat-empty">
            <p>在这里给这个会话发消息，agent 会在这里回复。</p>
            <p className="muted">{detail.threads.some((t) => t.channel !== "EMBER") ? "它在 Slack 里的来往，在右边的执行历史里能看到。" : ""}</p>
          </div>
        )}
        {messages.map((m) => m.role === "person" ? (
          <div key={m.ts} className="msg msg-human">
            <div className="msg-bubble">{m.text}</div>
            <div className="msg-meta">{person(m.user)} · <span title={absoluteTime(m.createdAt)}>{relativeTime(m.createdAt)}</span></div>
          </div>
        ) : (
          <div key={m.ts} className="msg msg-bot">
            <div className="msg-head">
              <span className="msg-name">{agent}</span>
              <span className="msg-time" title={absoluteTime(m.createdAt)}>{relativeTime(m.createdAt)}</span>
            </div>
            <div className="markdown"><Markdown remarkPlugins={[remarkGfm]}>{m.text}</Markdown></div>
          </div>
        ))}
        {busy && messages.at(-1)?.role === "person" && (
          <div className="chat-typing"><span className="activity-pulse inline" aria-hidden="true" />正在处理…</div>
        )}
      </div>
      <Composer sessionKey={detail.session.key} />
    </section>
  );
}

/** Where people write to the session; the first message makes its chat. Zork's composer: a soft frame that grows with the text, and a round send button. */
function Composer({ sessionKey, className }: { sessionKey: string; className?: string }) {
  const api = useApi();
  const station = useStation();
  const client = useQueryClient();
  const [text, setText] = useState("");
  const input = useRef<HTMLTextAreaElement>(null);
  const send = useMutation({
    mutationFn: (value: string) => api.sayToSession(sessionKey, value),
    onSuccess: () => { setText(""); void client.invalidateQueries({ queryKey: keys.session(station.id, sessionKey) }); },
  });
  // Grow with the text up to the frame's limit; the frame is never resized by hand.
  useEffect(() => {
    const el = input.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = `${Math.min(el.scrollHeight, 160)}px`;
  }, [text]);
  const ready = Boolean(text.trim()) && !send.isPending;
  const submit = () => {
    if (ready) send.mutate(text.trim());
  };
  return (
    <div className={`composer-wrap${className ? ` ${className}` : ""}`}>
      <form className="composer-box" data-multiline={text.includes("\n") || text.length > 60 || undefined}
        onSubmit={(e) => { e.preventDefault(); submit(); }} onClick={() => input.current?.focus()}>
        <textarea ref={input} className="composer-text" rows={1} value={text} placeholder="给这个会话发消息" aria-label="消息"
          onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) { e.preventDefault(); submit(); } }} />
        <div className="composer-toolbar">
          <Tip label="发送">
            <button type="submit" className="send-btn" disabled={!ready} aria-label="发送" aria-busy={send.isPending || undefined}>
              {send.isPending ? <span className="spinner" aria-hidden="true" /> : <ArrowUp size={16} strokeWidth={2} />}
            </button>
          </Tip>
        </div>
      </form>
      {send.error && <p className="field-error chat-error" role="alert">{send.error.message}</p>}
    </div>
  );
}
