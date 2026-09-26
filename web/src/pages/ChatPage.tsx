// A chat: a thread (a Slack thread or a chat on ember's page) with its people
// and agents. The messages are the page; each agent's execution history can
// be opened beside them, one tab per agent.
import { scopeOf, useLink, useStation } from "../station.tsx";
import { CreatorText, PeopleStack, Ring } from "../components.tsx";
import { Info, PanelRightClose, PanelRightOpen, Square, Unplug, X } from "lucide-react";
import { Popover, Tabs } from "radix-ui";
import { useEffect, useRef, useState, type ReactNode } from "react";
import { Link, Navigate, useNavigate, useParams } from "react-router";
import { lastChat } from "../lastChat.ts";
import { useAction, useApi, useChat, useChats, useHost, useLives, useStationCall, type ChatAgentView, type ChatView, type LiveView, type ProfileView, type SessionSummary, type ThreadView } from "../api.ts";
import { History } from "../History.tsx";
import { ChatPanel } from "../Chat.tsx";
import {
  BADGE_LABEL, PROCESS_LABEL, RUNTIME_LABEL, absoluteTime, agentLabel, compactNumber, sessionStatus, slackThreadUrl, slackWorkspaceUrl, statusBadge,
} from "../format.ts";
import { chatOpening, track } from "../telemetry.ts";
import { useToast } from "../toast.tsx";
import { AgentMark, ConnectKindIcon, Empty, ICON, IconButton, Loading, MobileBack, ModelLogo, ResizeHandle, RuntimeLogo, SlackLogo, Time, Tip } from "../ui.tsx";

/**
 * An item's page, one for every item: its chat's messages (none before its agent has a chat), the composer, and its
 * agents' execution histories beside them. The address is the item's: its chat's thread, or its agent's session key
 * until the first message makes the chat, and the page moves there.
 */
export function ChatPage() {
  const { chat } = useParams();
  const station = useStation();
  // There is always a chat in view: the one last open, or a new one. In ember cloud the workspace decides which.
  if (!chat) return <Navigate to={station.base ? station.base.replace(/\/s\/[^/]+$/, "") : lastChat("local", "/new")} replace />;
  const thread = Number(chat);
  return Number.isInteger(thread) ? <ChatScreen key={chat} of={{ thread }} /> : <Unchatted key={chat} session={chat} />;
}

/** An agent's item before it has a chat; once one is made for it (elsewhere too), the page moves to it. */
function Unchatted({ session }: { session: string }) {
  const station = useStation();
  const chats = useChats(scopeOf(station.address), false);
  const made = chats.value?.days.flatMap((d) => d.items).find((i) => i.station === station.address && i.thread !== null && i.agents.some((a) => a.key === session));
  if (made) return <Navigate to={`${station.base}/chats/${made.thread}`} replace />;
  return <ChatScreen of={{ session }} />;
}

/** Reports how long the chat took to show its messages, once, when they first do. */
function useChatOpened(chat: ChatView | undefined): void {
  const [opening] = useState(chatOpening);
  const reported = useRef(false);
  useEffect(() => {
    if (!chat || reported.current) return;
    reported.current = true;
    const surface = chat.thread === null || chat.thread.surface === "ember" ? "ember" : "slack";
    // The frame after the commit: when the messages are on screen.
    requestAnimationFrame(() => track("chat_opened", { surface, open: opening.cold ? "cold" : "warm", ms: Math.round(performance.now() - opening.at) }));
  }, [chat, opening]);
}

/** Which history tabs each chat has open, and which one is in front: each chat keeps its own (the latest 200 chats). */
const TABS = "ember.chatTabs";
type Kept = { tabs: string[]; active: string | null };
function keptTabs(chat: string): Kept | undefined {
  try {
    return (JSON.parse(localStorage.getItem(TABS) ?? "{}") as Record<string, Kept>)[chat];
  } catch {
    return undefined;
  }
}
function keepTabs(chat: string, kept: Kept): void {
  let all: Record<string, Kept> = {};
  try {
    all = JSON.parse(localStorage.getItem(TABS) ?? "{}") as Record<string, Kept>;
  } catch {
    // start over
  }
  delete all[chat];
  all[chat] = kept;
  const keys = Object.keys(all);
  for (const key of keys.slice(0, Math.max(0, keys.length - 200))) delete all[key];
  localStorage.setItem(TABS, JSON.stringify(all));
}

function ChatScreen({ of }: { of: { thread: number } | { session: string } }) {
  const station = useStation();
  const link = useLink();
  const navigate = useNavigate();
  const call = useStationCall(station.address);
  const chatView = useChat(station.address, of);
  useChatOpened(chatView.value);
  const agents = chatView.value?.agents ?? [];
  const lives = useLives(station.address, agents.map((a) => a.session.key));
  // One history tab per agent, by session key; each can be closed, and with none open the panel goes away.
  // Each chat keeps its own tabs. One not opened before shows the history of the session it is bound to (the agent
  // it was made for, or the agent itself when it has no chat yet); a chat bound to no session opens none.
  const chatKey = `${station.address}:${"thread" in of ? of.thread : of.session}`;
  const [kept] = useState(() => keptTabs(chatKey));
  const [chosen, setTabs] = useState<string[] | null>(() => kept?.tabs ?? null);
  const bound = "session" in of ? of.session : chatView.value?.thread?.sessions[0]?.session ?? null;
  const tabs = chosen ?? (bound ? [bound] : []);
  const [active, setActiveState] = useState<string | null>(kept?.active ?? null);
  const open = tabs.filter((key) => agents.some((a) => a.session.key === key));
  const shown = active && open.includes(active) ? active : open[0] ?? null;
  // Tabs and the one in front change together, and are kept for this chat in one write.
  const commit = (next: string[], front: string | null) => {
    setTabs(next);
    setActiveState(front);
    keepTabs(chatKey, { tabs: next, active: front });
  };
  const saveTabs = (next: string[]) => commit(next, active);
  const setActive = (key: string | null) => commit(open, key);
  const openTab = (key: string) => commit(open.includes(key) ? open : [...open, key], key);
  const closeTab = (key: string) => {
    const next = open.filter((t) => t !== key);
    commit(next, shown === key ? next.at(-1) ?? null : active);
  };
  const toggleHistory = (key: string) => (open.includes(key) && shown === key ? closeTab(key) : openTab(key));
  if (!chatView.value) {
    if (chatView.error) return <Empty><p>读不到这个对话：{chatView.error.message}</p></Empty>;
    return <Loading label={station.name ? `正在从 ${station.name} 读取对话…` : "正在读取对话…"} />;
  }
  const chat = chatView.value;
  const panel = open.length > 0;
  const slackUrl = !chat.thread || chat.thread.surface === "ember" ? null : slackThreadUrl(slackWorkspaceUrl(slackConnect(chat)), chat.thread.channel, chat.thread.threadTs);
  // Before its agent has a chat, the first message makes one, bound to the agent, and the page moves to it.
  const session = "session" in of ? of.session : null;
  const firstMessage = session === null ? {} : {
    ensureChat: async () => ({ key: session, thread: (await call.request<{ id: number }>("POST", "/threads", { session })).id }),
    onSent: (thread: number) => navigate(`${station.base}/chats/${thread}`, { replace: true }),
  };
  return (
    <div className="session-page" data-panel={panel}>
      <div className="session-main">
      <header className="page-bar">
        <MobileBack to={link("/chats")} label="对话" />
        {/* The chat's title, then who is in it: its people, then its agents (each opens its history). */}
        <div className="page-bar-title">
          <h1>{chat.title}</h1>
          {chat.people.length > 0 && <PeopleStack people={chat.people} max={5} />}
          {agents.map((a) => {
            const model = lives.get(a.session.key)?.usage?.model ?? a.session.model;
            const badge = statusBadge(sessionStatus(a.session));
            return (
              <Tip key={a.session.key} label={`${agentLabel(model, a.session.effort)}${badge ? ` · ${BADGE_LABEL[badge]}` : ""} · 执行历史`}>
                <button type="button" className="agent-mark-btn" onClick={() => toggleHistory(a.session.key)} aria-label={`${agentLabel(model, a.session.effort)} 的执行历史`}>
                  <AgentMark model={model} runtime={a.session.runtime} badge={badge} size={20} />
                </button>
              </Tip>
            );
          })}
        </div>
        <div className="page-bar-actions">
          {chat.thread && <ChatInfo chat={chat} thread={chat.thread} lives={lives} />}
          {slackUrl && (
            <Tip label="在 Slack 中打开">
              <a className="icon-btn" href={slackUrl} target="_blank" rel="noopener" aria-label="在 Slack 中打开"><SlackLogo /></a>
            </Tip>
          )}
          {!panel && agents[0] && <IconButton label="打开侧栏" icon={PanelRightOpen} onClick={() => openTab(agents[0]!.session.key)} />}
        </div>
      </header>
      {/* The chat is the page; its agents' histories sit in a tab set that takes the whole right side. */}
      <ChatPanel chat={chat} lives={lives} onOpenHistory={toggleHistory} {...firstMessage} />
      </div>
        {panel && shown && (
          <Tabs.Root className="side-panel" value={shown} onValueChange={setActive}>
            <ResizeHandle variable="--panel-w" edge="left" min={320} max={960} label="调整侧栏宽度" />
            <div className="side-bar">
              <Tabs.List className="side-tab-list" aria-label="执行历史">
                {open.map((key) => {
                  const a = agents.find((x) => x.session.key === key)!;
                  const model = lives.get(key)?.usage?.model ?? a.session.model;
                  const label = agentLabel(model, a.session.effort);
                  return (
                    <span key={key} className="side-tab-wrap">
                      <Tabs.Trigger className="side-tab" value={key} title={`${label} 的执行历史`}>
                        <span className="side-tab-agent"><ModelLogo model={model} runtime={a.session.runtime} size={13} />{label}</span>
                      </Tabs.Trigger>
                      <button type="button" className="side-tab-close" aria-label={`关闭 ${label} 的执行历史`} onClick={() => closeTab(key)}><X size={12} strokeWidth={2} /></button>
                    </span>
                  );
                })}
              </Tabs.List>
              {/* The panel's switch stays in the top-right corner, open or closed. */}
              <IconButton label="收起侧栏" icon={PanelRightClose} onClick={() => saveTabs([])} />
            </div>
            {open.map((key) => {
              const a = agents.find((x) => x.session.key === key)!;
              const live = lives.get(key);
              return (
                <Tabs.Content key={key} className="side-content" value={key}>
                  <History session={a.session} threads={a.threads} connect={a.connect ?? undefined} live={live} actions={<SessionActions session={a.session} />}
                    summary={<HistorySummary live={live} profile={a.profile} />}
                    details={<SessionDetails session={a.session} live={live} profile={a.profile} />} />
                </Tabs.Content>
              );
            })}
          </Tabs.Root>
        )}
    </div>
  );
}

/** The connect a Slack chat's agents reach Slack through: links into Slack start at its workspace. */
function slackConnect(chat: ChatView) {
  return chat.agents.find((a) => a.connect?.kind === "slack")?.connect ?? null;
}

/** The chat itself: where it came from, who started it and takes part, its agents. Opens from the title bar. */
function ChatInfo({ chat, thread, lives }: { chat: ChatView; thread: ThreadView; lives: ReadonlyMap<string, LiveView> }) {
  const link = useLink();
  const connect = slackConnect(chat);
  const row = (label: string, value: ReactNode) => <div className="detail-row"><dt>{label}</dt><dd>{value}</dd></div>;
  const where = thread.surface === "ember" ? null : thread.channel.startsWith("D") ? "私信" : `#${thread.channelName ?? thread.channel}`;
  return (
    <Popover.Root>
      <Tip label="对话信息">
        <Popover.Trigger asChild>
          <button type="button" className="icon-btn" aria-label="对话信息"><Info {...ICON} /></button>
        </Popover.Trigger>
      </Tip>
      <Popover.Portal>
        <Popover.Content className="popover chat-info" align="end" sideOffset={6} collisionPadding={8}>
          <dl className="details">
            {row("来自", where
              ? <span className="detail-inline"><SlackLogo size={13} />{connect ? <Link to={link(`/connects/${connect.id}`)} className="detail-link">{connect.name}</Link> : "Slack"} · {where}</span>
              : "ember 对话")}
            {row("发起", thread.creator ? <CreatorText creator={thread.creator} verb="发起" /> : <span className="muted">未记录</span>)}
            {row("参与", <span className="detail-inline"><PeopleStack people={chat.people} max={8} />{chat.people.length} 人</span>)}
            {row("创建", <Time at={thread.createdAt} />)}
            {thread.lastMessage && row("最近消息", <Time at={thread.lastMessage.createdAt} />)}
          </dl>
          {chat.agents.length > 0 && (
            <ul className="details-list">
              {chat.agents.map((a) => <AgentLine key={a.session.key} agent={a} model={lives.get(a.session.key)?.usage?.model ?? a.session.model} />)}
            </ul>
          )}
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}

/** An agent of the chat in its info: what it runs, where it came from, and how it stands. */
/** `model` is the one actually running (the live usage's), else the session's. */
function AgentLine({ agent, model }: { agent: ChatAgentView; model: string | null }) {
  const { session, connect } = agent;
  const status = sessionStatus(session);
  const badge = statusBadge(status);
  return (
    <li>
      <span className="detail-inline"><AgentMark model={model} runtime={session.runtime} badge={badge} size={14} />{agentLabel(model, session.effort)}</span>
      <span className="muted">
        {connect ? <><ConnectKindIcon kind={connect.kind} size={11} /> {connect.name} · </> : null}{PROCESS_LABEL[session.process]} · 最近活动 <Time at={session.lastActiveAt} />
      </span>
    </li>
  );
}

/** The history's head, folded: what is worth a glance — the allowance left, the cache hit rate, the station's free disk. */
function HistorySummary({ live, profile }: { live: LiveView | undefined; profile: ProfileView | null }) {
  const host = useHost(useStation().address).value;
  const usage = live?.usage;
  const hitRate = usage && usage.inputTokens > 0 ? Math.round((usage.cachedTokens / usage.inputTokens) * 100) : null;
  const windows = profile?.quota?.state === "ok" ? profile.quota.windows : [];
  const free = host && host.disk.totalBytes > 0 ? host.disk.freeBytes : null;
  const parts: ReactNode[] = [
    ...windows.map((w) => <span key={w.label} title={w.resetsAt ? `${absoluteTime(w.resetsAt)} 重置` : undefined}>{w.label} 已用 {Math.round(w.usedPercent)}%</span>),
    hitRate !== null && <span key="cache">缓存命中 {hitRate}%</span>,
    free !== null && <span key="disk">磁盘剩 {Math.round(free / 1024 ** 3)} GB</span>,
  ].filter(Boolean);
  return <span className="history-summary">{parts.flatMap((p, i) => (i ? [<span key={`s${i}`} className="history-sep">·</span>, p] : [p]))}</span>;
}

/** Unfolded under the history's head: the model and its use, the allowance, the station. */
function SessionDetails({ session, live, profile }: { session: SessionSummary; live: LiveView | undefined; profile: ProfileView | null }) {
  const station = useStation();
  const link = useLink();
  const host = useHost(station.address).value;
  const usage = live?.usage;
  const quota = profile?.quota;
  const hitRate = usage && usage.inputTokens > 0 ? Math.round((usage.cachedTokens / usage.inputTokens) * 100) : null;
  const gb = (bytes: number) => `${Math.round(bytes / 1024 ** 3)} GB`;
  const row = (label: string, value: ReactNode) => <div className="detail-row"><dt>{label}</dt><dd>{value}</dd></div>;
  return (
    <div className="session-details">
      <section className="details-group">
        <h3>模型</h3>
        <dl className="details">
          {row("运行时", <span className="detail-inline"><RuntimeLogo runtime={session.runtime} size={13} />{RUNTIME_LABEL[session.runtime]}</span>)}
          {row("Profile", <Link className="detail-link" to={link(`/settings/accounts/${session.profile}`)}>{profile?.name ?? session.profile}</Link>)}
          {row("进程", PROCESS_LABEL[session.process])}
          {usage && row("调用", `${usage.modelCalls} 次`)}
          {usage && row("输入", `${compactNumber(usage.inputTokens)}${hitRate === null ? "" : ` · 缓存 ${hitRate}%`}`)}
          {usage && row("输出", compactNumber(usage.outputTokens))}
        </dl>
        <div className="resource-rings">
          {quota?.state === "ok" && quota.windows.length > 0
            ? quota.windows.map((w) => <Ring key={w.label} percent={w.usedPercent} label={w.label} title={`${w.label}已用 ${w.usedPercent}%${w.resetsAt ? `，${absoluteTime(w.resetsAt)} 重置` : ""}`} />)
            : <span className="muted resource-note">额度：{quota?.detail ?? (quota ? "查不到" : "还没查过")}</span>}
        </div>
      </section>
      <section className="details-group">
        <h3>Station</h3>
        <dl className="details">
          {row("名字", station.name || host?.hostname || "本机")}
          {host && row("机器", `${host.hostname} · ${host.cpus} 核 · ${gb(host.memory.totalBytes)}`)}
        </dl>
        {host && (
          <div className="resource-rings">
            <Ring percent={host.load * 100} label="CPU" title={`负载 ${host.load}（${host.cpus} 核）`} />
            <Ring percent={(host.memory.usedBytes / host.memory.totalBytes) * 100} label="内存" title={`内存 ${gb(host.memory.usedBytes)} / ${gb(host.memory.totalBytes)}`} />
            {host.disk.totalBytes > 0 && (
              <Ring percent={(1 - host.disk.freeBytes / host.disk.totalBytes) * 100} label="磁盘" title={`磁盘剩 ${gb(host.disk.freeBytes)} / ${gb(host.disk.totalBytes)}`} />
            )}
          </div>
        )}
      </section>
    </div>
  );
}

/** What can be done to it right now: stop a turn, release an idle process. */
function SessionActions({ session }: { session: SessionSummary }) {
  const api = useApi();
  const toast = useToast();
  const stop = useAction(() => api.stop(session.key), () => toast("已请求停止"));
  const evict = useAction(() => api.evict(session.key), () => toast("已释放进程"));
  const status = sessionStatus(session);
  return (
    <>
      {(status === "running" || status === "queued") && <IconButton label="停止当前任务" icon={Square} onClick={() => void stop.run()} disabled={stop.busy} />}
      {session.process === "warm" && <IconButton label="释放进程" icon={Unplug} onClick={() => void evict.run()} disabled={evict.busy} />}
    </>
  );
}
