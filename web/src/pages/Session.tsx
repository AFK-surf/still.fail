// A session: its execution history is the page; what can be done to it sits
// with the history. A chat can be opened beside it: ember's own chat, which
// reaches the agent the way a Slack thread does.
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { ExternalLink, MessageSquarePlus, MessagesSquare, Square, Unplug, X } from "lucide-react";
import { DropdownMenu } from "radix-ui";
import { useEffect, useRef, useState } from "react";
import Markdown from "react-markdown";
import { useParams, useSearchParams } from "react-router";
import remarkGfm from "remark-gfm";
import { api, keys, useOverview, useSession, useSessions, type ConnectView, type SessionDetail } from "../api.ts";
import { History } from "../History.tsx";
import {
  absoluteTime, PROCESS_LABEL, relativeTime, sessionStatus, sessionTitle, slackThreadUrl, STATUS_LABEL, statusTone, threadNamer, turnResult,
} from "../format.ts";
import { useToast } from "../toast.tsx";
import { Button, Empty, ICON, IconButton, Menu, MobileBack, Pill, Tip } from "../ui.tsx";

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
  return <SessionView key={key} sessionKey={key} />;
}

function workspaceUrl(connect: ConnectView | undefined): string | null {
  const c = connect?.connection;
  return c && (c.state === "connected" || c.state === "reconnecting") ? c.workspace?.url ?? null : null;
}

function SessionView({ sessionKey }: { sessionKey: string }) {
  const detail = useSession(sessionKey);
  const overview = useOverview();
  const client = useQueryClient();
  const [params, setParams] = useSearchParams();
  const openChat = params.get("chat");
  const setChat = (threadTs: string | null) => setParams(threadTs ? { chat: threadTs } : {}, { replace: true });
  const create = useMutation({
    mutationFn: () => api.openChat(sessionKey),
    onSuccess: async ({ threadTs }) => {
      await client.invalidateQueries({ queryKey: keys.session(sessionKey) });
      setChat(threadTs);
    },
  });

  if (detail.isPending) return <div className="page" />;
  if (detail.isError) return <Empty><p>读不到这个会话：{detail.error.message}</p></Empty>;
  const { session, threads, chats } = detail.data;
  const connect = overview.data?.connects.find((c) => c.id === session.connect);
  const name = connect?.name ?? session.connect;
  const base = workspaceUrl(connect);
  const slackThreads = threads.filter((t) => t.channel !== "EMBER");
  const single = slackThreads.length === 1 ? slackThreads[0] : undefined;
  const singleUrl = single ? slackThreadUrl(base, single.channel, single.threadTs) : null;
  const status = sessionStatus(session);
  const chat = chats.find((c) => c.threadTs === openChat);
  const latestChat = chats.at(-1);

  return (
    <div className="session-page">
      <header className="page-bar">
        <MobileBack to="/sessions" label="会话" />
        <div className="page-bar-title">
          <h1>{sessionTitle(session, name)}</h1>
          <Pill tone={statusTone(status)}>{STATUS_LABEL[status]}</Pill>
        </div>
        <div className="page-bar-actions">
          {slackThreads.length > 1
            ? <ThreadMenu detail={detail.data} base={base} />
            : singleUrl && (
              <Tip label="在 Slack 中打开">
                <a className="icon-btn" href={singleUrl} target="_blank" rel="noopener" aria-label="在 Slack 中打开"><ExternalLink {...ICON} /></a>
              </Tip>
            )}
          {!chat && (latestChat
            ? <Button icon={MessagesSquare} onClick={() => setChat(latestChat.threadTs)}>对话</Button>
            : <Button icon={MessageSquarePlus} busy={create.isPending} onClick={() => create.mutate()}>新建对话</Button>)}
        </div>
      </header>
      {/* Without a chat the history is the page; with one, the chat takes the middle and the history moves to the right. */}
      <div className="session-body" data-chat={Boolean(chat)}>
        {chat && (
          <ChatPanel detail={detail.data} threadTs={chat.threadTs} name={name} onClose={() => setChat(null)}
            onSwitch={setChat} onNew={() => create.mutate()} creating={create.isPending} />
        )}
        <History detail={detail.data} connect={connect} footer={<Operations detail={detail.data} />} />
      </div>
    </div>
  );
}

/** What can be done to the session right now, at the foot of its history. */
function Operations({ detail }: { detail: SessionDetail }) {
  const toast = useToast();
  const { session } = detail;
  const stop = useMutation({ mutationFn: () => api.stop(session.key), onSuccess: () => toast("已请求停止") });
  const evict = useMutation({ mutationFn: () => api.evict(session.key), onSuccess: () => toast("已释放进程") });
  const status = sessionStatus(session);
  const running = status === "running" || status === "queued";
  const since = detail.turns.at(-1)?.startedAt ?? session.lastActiveAt;
  const calls = (detail.transcript?.timeline ?? []).filter((e) => e.kind === "tool_call" && e.at && Date.parse(e.at) >= since).length;
  const result = turnResult(session.lastTurn);
  const text = running
    ? (status === "queued" ? "排队中，马上开始" : `正在执行${calls ? `，已执行 ${calls} 项操作` : ""}`)
    : result === "block" ? "在等人回复。"
    : result === "failed" ? "上一轮失败了；新消息会重试。"
    : result === "unexpected" ? "上一轮没有给出明确结果就停了。"
    : result === "final" ? "上一轮已完成。"
    : "空闲。";
  return (
    <div className="operations" data-state={running ? "running" : result}>
      {running && <span className="activity-pulse" aria-hidden="true" />}
      <span className="operations-text">{text}<span className="muted"> · 进程{PROCESS_LABEL[session.process]}</span></span>
      {running && <Button icon={Square} onClick={() => stop.mutate()} busy={stop.isPending}>停止</Button>}
      {session.process === "warm" && <Button variant="ghost" icon={Unplug} onClick={() => evict.mutate()} busy={evict.isPending}>释放进程</Button>}
    </div>
  );
}

function ThreadMenu({ detail, base }: { detail: SessionDetail; base: string | null }) {
  const name = threadNamer(detail);
  return (
    <DropdownMenu.Root modal={false}>
      <Tip label="这个会话的 Slack thread">
        <DropdownMenu.Trigger asChild>
          <button type="button" className="icon-btn" aria-label="这个会话的 Slack thread"><ExternalLink {...ICON} /></button>
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
function ChatPanel({ detail, threadTs, name, onClose, onSwitch, onNew, creating }: {
  detail: SessionDetail; threadTs: string; name: string; onClose(): void; onSwitch(threadTs: string): void; onNew(): void; creating: boolean;
}) {
  const client = useQueryClient();
  const chat = detail.chats.find((c) => c.threadTs === threadTs)!;
  const [text, setText] = useState("");
  const list = useRef<HTMLDivElement>(null);
  const send = useMutation({
    mutationFn: (value: string) => api.sayInChat(threadTs, value),
    onSuccess: () => { setText(""); void client.invalidateQueries({ queryKey: keys.session(detail.session.key) }); },
  });
  useEffect(() => {
    if (list.current) list.current.scrollTop = list.current.scrollHeight;
  }, [chat.messages.length]);
  const status = sessionStatus(detail.session);
  const busy = status === "running" || status === "queued";
  const person = (id: string) => detail.people[id] ?? (id === "local" ? "管理员" : id);
  const submit = () => {
    const value = text.trim();
    if (value && !send.isPending) send.mutate(value);
  };
  const chatName = (c: SessionDetail["chats"][number], i: number) => c.title ?? `对话 ${i + 1}`;

  return (
    <section className="chat" aria-label="对话">
      <header className="chat-head">
        {detail.chats.length > 1
          ? <Menu label="切换对话" items={detail.chats.map((c, i) => ({ label: `${chatName(c, i)} · ${relativeTime(c.createdAt)}`, onSelect: () => onSwitch(c.threadTs) }))} />
          : <span className="kind-icon"><MessagesSquare {...ICON} /></span>}
        <strong className="chat-title">{chatName(chat, detail.chats.indexOf(chat))}</strong>
        <IconButton label="新建对话" icon={MessageSquarePlus} onClick={onNew} disabled={creating} />
        <IconButton label="关闭对话" icon={X} onClick={onClose} />
      </header>
      <div className="chat-list" ref={list}>
        {chat.messages.length === 0 && (
          <p className="chat-empty">在这里说的话会像 Slack 消息一样送到这个会话，{name} 会在这里回复。</p>
        )}
        {chat.messages.map((m) => m.role === "person" ? (
          <div key={m.ts} className="msg msg-human">
            <div className="msg-bubble">{m.text}</div>
            <div className="msg-meta">{person(m.user)} · <span title={absoluteTime(m.createdAt)}>{relativeTime(m.createdAt)}</span></div>
          </div>
        ) : (
          <div key={m.ts} className="msg msg-bot">
            <div className="msg-head">
              <span className="msg-name">{name}</span>
              <span className="msg-time" title={absoluteTime(m.createdAt)}>{relativeTime(m.createdAt)}</span>
            </div>
            <div className="markdown"><Markdown remarkPlugins={[remarkGfm]}>{m.text}</Markdown></div>
          </div>
        ))}
        {busy && chat.messages.at(-1)?.role === "person" && (
          <div className="chat-typing"><span className="activity-pulse inline" aria-hidden="true" />{name} 在处理…</div>
        )}
      </div>
      <form className="composer" onSubmit={(e) => { e.preventDefault(); submit(); }}>
        <textarea className="input composer-input" rows={2} value={text} placeholder={`发消息给 ${name}（Enter 发送，Shift+Enter 换行）`}
          onChange={(e) => setText(e.target.value)} aria-label="消息"
          onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) { e.preventDefault(); submit(); } }} />
        <Button variant="primary" type="submit" disabled={!text.trim()} busy={send.isPending}>发送</Button>
      </form>
      {send.error && <p className="field-error chat-error" role="alert">{send.error.message}</p>}
    </section>
  );
}
