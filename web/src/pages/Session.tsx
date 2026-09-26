// A session: its execution history is the page; what can be done to it sits
// with the history. A chat can be opened beside it: ember's own chat, which
// reaches the agent the way a Slack thread does.
import { useLink, useStation } from "../station.tsx";
import { CreatorText, PeopleStack, Ring } from "../components.tsx";
import { Info, PanelRightClose, PanelRightOpen, Square, Unplug, X } from "lucide-react";
import { DropdownMenu, Popover, Tabs } from "radix-ui";
import { useState, type ReactNode } from "react";
import { Link, Navigate, useParams } from "react-router";
import { lastChat } from "../lastChat.ts";
import { useAction, useApi, useChat, useHost, useLive, type ConnectView, type ProfileView, type SessionDetail } from "../api.ts";
import { History } from "../History.tsx";
import { ChatPanel } from "../Chat.tsx";
import {
  BADGE_LABEL, PROCESS_LABEL, RUNTIME_LABEL, absoluteTime, agentLabel, compactNumber, relativeTime, sessionStatus, sessionTitle, slackThreadUrl, statusBadge, threadNamer,
} from "../format.ts";
import { useToast } from "../toast.tsx";
import { AgentMark, Button, ConnectKindIcon, Empty, ICON, IconButton, Loading, Menu, MobileBack, ModelLogo, ResizeHandle, RuntimeLogo, SlackLogo, Time, Tip } from "../ui.tsx";

export function SessionPage() {
  const { key } = useParams();
  const station = useStation();
  // There is always a chat in view: the one last open, or a new one. In ember cloud the workspace decides which.
  if (!key) return <Navigate to={station.base ? station.base.replace(/\/s\/[^/]+$/, "") : lastChat("local", "/new")} replace />;
  return <SessionView key={key} sessionKey={key} />;
}

function workspaceUrl(connect: ConnectView | null): string | null {
  const c = connect?.connection;
  return c && (c.state === "connected" || c.state === "reconnecting") ? c.workspace?.url ?? null : null;
}

/** Tabs the right-hand panel can hold. A browser for the station's services comes later. */
const TAB_LABEL: Record<string, string> = { history: "执行历史" };

function SessionView({ sessionKey }: { sessionKey: string }) {
  const station = useStation();
  const link = useLink();
  const chatView = useChat(station.address, sessionKey);
  const liveView = useLive(station.address, sessionKey).value;
  const live = liveView?.steps ?? [];
  const phase = liveView?.phase ?? null;
  // Open tabs on the right; each can be closed, and with none open the panel goes away.
  // On narrow screens nothing opens by itself, since the panel would cover the chat.
  const [tabs, setTabs] = useState<string[]>(() => {
    if (!window.matchMedia("(min-width: 1101px)").matches) return [];
    try {
      return (JSON.parse(localStorage.getItem("ember.sideTabs") ?? "[\"history\"]") as string[]).filter((t) => t in TAB_LABEL);
    } catch {
      return ["history"];
    }
  });
  const [active, setActive] = useState(tabs[0] ?? "history");
  const saveTabs = (next: string[]) => {
    setTabs(next);
    localStorage.setItem("ember.sideTabs", JSON.stringify(next));
  };
  const openTab = (tab: string) => {
    if (!tabs.includes(tab)) saveTabs([...tabs, tab]);
    setActive(tab);
  };
  const closeTab = (tab: string) => {
    const next = tabs.filter((t) => t !== tab);
    saveTabs(next);
    if (active === tab && next.length) setActive(next.at(-1)!);
  };
  const panel = tabs.length > 0;
  if (!chatView.value) {
    if (chatView.error) return <Empty><p>读不到这个会话：{chatView.error.message}</p></Empty>;
    return <Loading label={station.name ? `正在从 ${station.name} 读取会话…` : "正在读取会话…"} />;
  }
  const { detail, connect, profile } = chatView.value;
  const { session, threads, chats } = detail;
  const name = connect?.name ?? session.connect;
  const base = workspaceUrl(connect);
  const slackThreads = threads.filter((t) => t.channel !== "EMBER");
  const single = slackThreads.length === 1 ? slackThreads[0] : undefined;
  const singleUrl = single ? slackThreadUrl(base, single.channel, single.threadTs) : null;
  const badge = statusBadge(sessionStatus(session));
  const model = detail.transcript?.usage?.model ?? session.model;
  const toggleHistory = () => (tabs.includes("history") && active === "history" ? closeTab("history") : openTab("history"));
  // One chat per session; older sessions may have several, of which the first is the one.
  const chat = chats[0];
  return (
    <div className="session-page" data-panel={panel}>
      <div className="session-main">
      <header className="page-bar">
        <MobileBack to={link("/sessions")} label="会话" />
        <div className="page-bar-title">
          <Tip label={`${agentLabel(model, session.effort)}${badge ? ` · ${BADGE_LABEL[badge]}` : ""} · 执行历史`}>
            <button type="button" className="agent-mark-btn" onClick={toggleHistory} aria-label="执行历史">
              <AgentMark model={model} runtime={session.runtime} badge={badge} size={22} />
            </button>
          </Tip>
          <h1>{sessionTitle(session, name)}</h1>
          {station.name && <span className="page-bar-station">{station.name}</span>}
        </div>
        <div className="page-bar-actions">
          <ChatInfo detail={detail} connect={connect} base={base} />
          {slackThreads.length > 1
            ? <ThreadMenu detail={detail} base={base} />
            : singleUrl && (
              <Tip label="在 Slack 中打开">
                <a className="icon-btn" href={singleUrl} target="_blank" rel="noopener" aria-label="在 Slack 中打开"><SlackLogo /></a>
              </Tip>
            )}
          {!panel && <IconButton label="打开侧栏" icon={PanelRightOpen} onClick={() => openTab("history")} />}
        </div>
      </header>
      {/* The chat is the page; the session's history sits in a tab set that takes the whole right side. */}
      <ChatPanel detail={detail} chat={chat} outbox={chatView.value.outbox} live={live} phase={phase} onOpenHistory={toggleHistory} />
      </div>
        {panel && (
          <Tabs.Root className="side-panel" value={tabs.includes(active) ? active : tabs[0]!} onValueChange={setActive}>
            <ResizeHandle variable="--panel-w" edge="left" min={320} max={960} label="调整侧栏宽度" />
            <div className="side-bar">
              <Tabs.List className="side-tab-list" aria-label="会话侧栏">
                {tabs.map((t) => (
                  <span key={t} className="side-tab-wrap">
                    <Tabs.Trigger className="side-tab" value={t} title={TAB_LABEL[t]}>
                      {t === "history"
                        ? <span className="side-tab-agent"><ModelLogo model={model} runtime={session.runtime} size={13} />{agentLabel(model, session.effort)}</span>
                        : TAB_LABEL[t]}
                    </Tabs.Trigger>
                    <button type="button" className="side-tab-close" aria-label={`关闭${TAB_LABEL[t]}`} onClick={() => closeTab(t)}><X size={12} strokeWidth={2} /></button>
                  </span>
                ))}
              </Tabs.List>
              {/* The panel's switch stays in the top-right corner, open or closed. */}
              <IconButton label="收起侧栏" icon={PanelRightClose} onClick={() => saveTabs([])} />
            </div>
            <Tabs.Content className="side-content" value="history">
              <History detail={detail} connect={connect ?? undefined} live={live} phase={phase} actions={<SessionActions detail={detail} />} slackBase={base}
                onOpenChat={() => (document.querySelector(".composer-text") as HTMLTextAreaElement | null)?.focus()}
                summary={<HistorySummary detail={detail} profile={profile} />}
                details={<SessionDetails detail={detail} profile={profile} />} />
            </Tabs.Content>
          </Tabs.Root>
        )}
    </div>
  );
}

/** The chat itself: where it came from, who started it and takes part, its Slack threads. Opens from the title bar. */
function ChatInfo({ detail, connect, base }: { detail: SessionDetail; connect: ConnectView | null; base: string | null }) {
  const { session } = detail;
  const link = useLink();
  const name = threadNamer(detail);
  const threads = detail.threads.filter((t) => t.channel !== "EMBER");
  const row = (label: string, value: ReactNode) => <div className="detail-row"><dt>{label}</dt><dd>{value}</dd></div>;
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
            {row("连接", connect ? <Link to={link(`/connects/${connect.id}`)} className="detail-link"><ConnectKindIcon kind={connect.kind} size={13} />{connect.name}</Link> : session.connect)}
            {row("发起", session.creator ? <CreatorText creator={session.creator} verb="发起" /> : <span className="muted">未记录</span>)}
            {row("参与", <span className="detail-inline"><PeopleStack people={session.participants} max={8} />{session.participants?.length ?? 0} 人</span>)}
            {row("创建", <Time at={session.createdAt} />)}
            {row("最近活动", <Time at={session.lastActiveAt} />)}
          </dl>
          {threads.length > 0 && (
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
          )}
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}

/** The history's head, folded: what is worth a glance — the allowance left, the cache hit rate, the station's free disk. */
function HistorySummary({ detail, profile }: { detail: SessionDetail; profile: ProfileView | null }) {
  const host = useHost(useStation().address).value;
  const usage = detail.transcript?.usage;
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
function SessionDetails({ detail, profile }: { detail: SessionDetail; profile: ProfileView | null }) {
  const { session } = detail;
  const station = useStation();
  const link = useLink();
  const host = useHost(station.address).value;
  const usage = detail.transcript?.usage;
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
function SessionActions({ detail }: { detail: SessionDetail }) {
  const api = useApi();
  const toast = useToast();
  const { session } = detail;
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
