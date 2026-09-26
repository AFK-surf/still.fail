// A chat: a thread (a Slack thread or a chat on ember's page) with its people
// and agents. The messages are the page; each agent's execution history can
// be opened beside them, one tab per agent.
import { StationPreview } from "../Preview.tsx";
import { scopeOf, useLink, useStation } from "../station.tsx";
import { CreatorText, PeopleStack, QuotaBars, QuotaRing, Ring, mark, refillsIn } from "../components.tsx";
import { Globe, Info, PanelRightClose, PanelRightOpen, Square, Unplug, X } from "lucide-react";
import { DropdownMenu, Popover, Tabs } from "radix-ui";
import { useEffect, useRef, useState, type ReactNode } from "react";
import { Link, Navigate, useNavigate, useParams } from "react-router";
import { lastChat } from "../lastChat.ts";
import { useAction, useApi, useChat, useChats, useHost, useLives, useStationCall, useStations, type ChatAgentView, type ChatView, type LiveView, type ProfileView, type SessionSummary, type ThreadView } from "../api.ts";
import { History } from "../History.tsx";
import { ChatPanel } from "../Chat.tsx";
import {
  BADGE_LABEL, EFFORTS, EFFORT_LABEL, PROCESS_LABEL, RUNTIME_LABEL, agentLabel, compactNumber, slackThreadUrl, slackWorkspaceUrl, type Status,
} from "../format.ts";
import { chatOpening, track } from "../telemetry.ts";
import { useToast } from "../toast.tsx";
import { AgentMark, Chooser, ChooserItem, ConnectKindIcon, Empty, ICON, IconButton, Loading, MobileBack, ModelLogo, ProviderLogo, ResizeHandle, RuntimeLogo, SlackLogo, Time, Tip } from "../ui.tsx";

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
  // An item is its agent's: the address is the session, whether or not it has a chat yet (the core shows the chat
  // once there is one, at the same address).
  return <ChatScreen key={chat} of={{ session: chat }} />;
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
  // The tabs as last left while the agents are not known yet: the panel holds its place instead of coming in later.
  // A preview's tab (`preview:<port>`) is the chat's own, whatever its agents.
  const open = agents.length ? tabs.filter((key) => previewPort(key) !== null || agents.some((a) => a.session.key === key)) : tabs;
  const shown = active && open.includes(active) ? active : open[0] ?? null;
  // Tabs and the one in front change together, and are kept for this chat in one write.
  const commit = (next: string[], front: string | null) => {
    setTabs(next);
    setActiveState(front);
    keepTabs(chatKey, { tabs: next, active: front });
  };
  const saveTabs = (next: string[]) => commit(next, active);
  const setActive = (key: string | null) => commit(open, key);
  // Whether the panel is being opened here (it eases in then), not shown with the chat as it was left.
  const [opening, setOpening] = useState(false);
  const openTab = (key: string) => {
    if (open.length === 0) setOpening(true);
    commit(open.includes(key) ? open : [...open, key], key);
  };
  const closeTab = (key: string) => {
    const next = open.filter((t) => t !== key);
    commit(next, shown === key ? next.at(-1) ?? null : active);
  };
  const toggleHistory = (key: string) => (open.includes(key) && shown === key ? closeTab(key) : openTab(key));
  // An activity row: its agent's history, open at that entry.
  const [focus, setFocus] = useState<{ key: string; entry: number; n: number } | null>(null);
  const openHistory = (key: string, entry?: number) => {
    if (entry === undefined) return toggleHistory(key);
    openTab(key);
    setFocus({ key, entry, n: Date.now() });
  };
  if (!chatView.value) {
    if (chatView.error) return <Empty><p>读不到这个对话：{chatView.error.message}</p></Empty>;
    return <Loading label={station.name ? `正在从 ${station.name} 读取对话…` : "正在读取对话…"} />;
  }
  const chat = chatView.value;
  const panel = open.length > 0;
  const slackUrl = !chat.thread || chat.thread.surface === "ember" ? null : slackThreadUrl(slackWorkspaceUrl(slackConnect(chat)), chat.thread.channel, chat.thread.threadTs);
  // Before its agent has a chat, the first message makes one, bound to the agent; the page stays (the core shows the
  // chat at the same address once it is there).
  const session = "session" in of && !chat.thread ? of.session : null;
  const firstMessage = session === null ? {} : {
    ensureChat: async () => ({ key: session, thread: (await call.request<{ id: number }>("POST", "/threads", { session })).id }),
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
            const badge = a.badge;
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
          <OpenPreview onOpen={(port) => openTab(`preview:${port}`)} />
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
      <ChatPanel chat={chat} lives={lives} onOpenHistory={openHistory} {...firstMessage} />
      </div>
        {panel && shown && (
          <Tabs.Root className="side-panel" value={shown} onValueChange={setActive} data-opening={opening || undefined} onAnimationEnd={(e) => { if (e.target === e.currentTarget) setOpening(false); }}>
            <ResizeHandle variable="--panel-w" edge="left" min={320} max={960} label="调整侧栏宽度" />
            <div className="side-bar">
              <Tabs.List className="side-tab-list" aria-label="执行历史">
                {open.map((key) => {
                  const port = previewPort(key);
                  if (port !== null) {
                    return (
                      <span key={key} className="side-tab-wrap">
                        <Tabs.Trigger className="side-tab" value={key} title={`localhost:${port} 的预览`}>
                          <span className="side-tab-agent"><Globe size={13} strokeWidth={1.75} />localhost:{port}</span>
                        </Tabs.Trigger>
                        <button type="button" className="side-tab-close" aria-label={`关闭 localhost:${port} 的预览`} onClick={() => closeTab(key)}><X size={12} strokeWidth={2} /></button>
                      </span>
                    );
                  }
                  const a = agents.find((x) => x.session.key === key);
                  // Not known yet: its place, empty, until it is.
                  if (!a) return <span key={key} className="side-tab-wrap" />;
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
              const port = previewPort(key);
              if (port !== null) return <Tabs.Content key={key} className="side-content" value={key}><StationPreview station={station.address} port={port} /></Tabs.Content>;
              const a = agents.find((x) => x.session.key === key);
              const live = lives.get(key);
              if (!a) return <Tabs.Content key={key} className="side-content" value={key} />;
              return (
                <Tabs.Content key={key} className="side-content" value={key}>
                  <History session={a.session} threads={a.threads} connect={a.connect ?? undefined} live={live} actions={<SessionActions session={a.session} status={a.status} />}
                    focus={focus?.key === key ? focus : null}
                    summary={<HistorySummary agent={a} />}
                    details={<SessionDetails agent={a} live={live} />} />
                </Tabs.Content>
              );
            })}
          </Tabs.Root>
        )}
    </div>
  );
}

/** A preview tab's port, from its key (`preview:<port>`); null for an agent's history tab. */
function previewPort(key: string): number | null {
  const match = /^preview:(\d{1,5})$/.exec(key);
  return match ? Number(match[1]) : null;
}

/** Opens a web service on the station's machine (by its localhost port) in the side panel. */
function OpenPreview({ onOpen }: { onOpen: (port: number) => void }) {
  const [port, setPort] = useState("");
  const [open, setOpen] = useState(false);
  const valid = /^\d{1,5}$/.test(port) && Number(port) >= 1 && Number(port) <= 65535;
  return (
    <Popover.Root open={open} onOpenChange={setOpen}>
      <Tip label="预览这台机器上的网页">
        <Popover.Trigger asChild>
          <button type="button" className="icon-btn" aria-label="预览这台机器上的网页"><Globe {...ICON} /></button>
        </Popover.Trigger>
      </Tip>
      <Popover.Portal>
        <Popover.Content className="popover preview-open" align="end" sideOffset={6} collisionPadding={8}>
          <form onSubmit={(e) => { e.preventDefault(); if (valid) { onOpen(Number(port)); setOpen(false); } }}>
            <label className="preview-open-label">
              <span>localhost:</span>
              <input autoFocus inputMode="numeric" value={port} onChange={(e) => setPort(e.target.value.trim())} placeholder="3000" aria-label="端口" />
            </label>
            <button type="submit" className="btn btn-primary" disabled={!valid}>打开</button>
          </form>
          <p className="preview-open-note">station 所在机器上跑着的网页服务，在侧栏里打开。</p>
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
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
  const { status, badge } = agent;
  return (
    <li>
      <span className="detail-inline"><AgentMark model={model} runtime={session.runtime} badge={badge} size={14} />{agentLabel(model, session.effort)}</span>
      <span className="muted">
        {connect ? <><ConnectKindIcon kind={connect.kind} size={11} /> {connect.name} · </> : null}{PROCESS_LABEL[session.process]} · 最近活动 <Time at={session.lastActiveAt} />
      </span>
    </li>
  );
}

/**
 * The history's line under its head: only what is worth a look now, as the core says (a quota running out, the disk
 * filling up, an account that cannot run); nothing when all is well.
 */
function HistorySummary({ agent }: { agent: ChatAgentView }) {
  if (agent.attention.length === 0) return null;
  return (
    <span className="history-summary">
      {agent.attention.map((a, i) => (
        a.kind === "quota" ? (
          <Tip key={i} label={<>{a.label}剩余 {a.left}%{a.until !== null && <><br />{refillsIn(a.until)}</>}</>}>
            <span className="attention attention-quota"><QuotaRing percent={100 - a.left} size={20} /><span className="quota-ring-letter">{mark(a.label).text}</span></span>
          </Tip>
        ) : a.kind === "disk" ? (
          <span key={i} className="attention" data-tone="amber">磁盘剩 {Math.round(a.freeBytes / 1024 ** 3)} GB</span>
        ) : (
          <span key={i} className="attention" data-tone="red">{a.state === "login" ? `「${a.name}」要重新登录` : `「${a.name}」的 key 被拒绝`}</span>
        )
      ))}
    </span>
  );
}

/**
 * Unfolded under the history's head, by how much each thing matters: the account it runs on (with its quota) first,
 * which can be changed here, or left to the station; then the model and effort; then what it has used; the station
 * last, folded. Changes take from its next turn on.
 */
function SessionDetails({ agent, live }: { agent: ChatAgentView; live: LiveView | undefined }) {
  const { session, profile } = agent;
  const station = useStation();
  const link = useLink();
  const api = useApi();
  const toast = useToast();
  const host = useHost(station.address).value;
  const view = useStations(scopeOf(station.address)).value?.find((s) => s.station === station.address);
  const models = view?.runtimes.find((r) => r.runtime === session.runtime)?.models ?? [];
  const change = useAction((input: { profile?: string | null; model?: string | null; effort?: string | null }) => api.sessionSettings(session.key, input), () => toast("已改，下一轮起生效"));
  const usage = live?.usage;
  const hitRate = usage && usage.inputTokens > 0 ? Math.round((usage.cachedTokens / usage.inputTokens) * 100) : null;
  const gb = (bytes: number) => `${Math.round(bytes / 1024 ** 3)} GB`;
  const current = agent.profiles.find((p) => p.current);
  const name = current?.name ?? profile?.name ?? session.profile;
  return (
    <div className="session-details">
      {/* How it runs, in one row: the model, how hard it thinks, then the account it runs on (with its quota), each a
          menu. The account is the station's pick unless kept to one here. */}
      <div className="run-model">
        <Chooser className="chooser run-chip" title="换模型" label={<><ModelLogo model={session.model} runtime={session.runtime} size={13} />{session.model ?? "运行时默认"}</>}>
          <ChooserItem checked={!session.model} onSelect={() => void change.run({ model: null })}>运行时默认</ChooserItem>
          {[...new Set([...(session.model ? [session.model] : []), ...models])].map((m) => (
            <ChooserItem key={m} checked={session.model === m} onSelect={() => void change.run({ model: m })}><ModelLogo model={m} runtime={session.runtime} size={12} />{m}</ChooserItem>
          ))}
        </Chooser>
        <Chooser className="chooser run-chip" title="换思考深度" label={session.effort ?? "默认深度"}>
          <ChooserItem checked={!session.effort} onSelect={() => void change.run({ effort: null })}>运行时默认</ChooserItem>
          {EFFORTS[session.runtime].map((e) => <ChooserItem key={e} checked={session.effort === e} onSelect={() => void change.run({ effort: e })}>{EFFORT_LABEL[e] ?? e}（{e}）</ChooserItem>)}
        </Chooser>
        <Chooser className="chooser run-chip" title={session.profilePinned ? "手动指定的 Profile" : "station 自动分配的 Profile"}
          label={(
            <>
              <ProviderLogo runtime={session.runtime} kind={current?.kind ?? profile?.access.kind ?? "env"} size={13} />
              {session.profilePinned ? name : `自动 · ${name}`}
              <QuotaBars quota={current?.quota ?? profile?.quota} compact />
            </>
          )}>
          <ChooserItem checked={!session.profilePinned} onSelect={() => void change.run({ profile: null })}>
            <span className="run-option-text"><strong>自动分配</strong><span className="muted">能用就留在当前账号；额度用完或登录失效时，换一个还有额度的</span></span>
          </ChooserItem>
          <DropdownMenu.Separator className="menu-separator" />
          {agent.profiles.map((p) => (
            <ChooserItem key={p.id} checked={session.profilePinned && p.current} onSelect={() => void change.run({ profile: p.id })}>
              <ProviderLogo runtime={p.runtime ?? session.runtime} kind={p.kind ?? "env"} size={15} />
              <span className="run-option-text"><span>{p.name}</span>{p.current && !session.profilePinned && <span className="muted">当前</span>}</span>
              <QuotaBars quota={p.quota} compact />
            </ChooserItem>
          ))}
        </Chooser>
      </div>
      {change.error && <p className="field-error" role="alert">{change.error.message}</p>}
      {/* What it used: a line, quiet. */}
      <p className="run-usage muted">
        {RUNTIME_LABEL[session.runtime]} · {PROCESS_LABEL[session.process]}
        {usage && <> · 调用 {usage.modelCalls} 次 · 输入 {compactNumber(usage.inputTokens)}{hitRate === null ? "" : `（缓存 ${hitRate}%）`} · 输出 {compactNumber(usage.outputTokens)}</>}
        {" · "}<Link className="detail-link" to={link(`/settings/accounts/${session.profile}`)}>Profile 详情</Link>
      </p>
      {/* The station: folded. */}
      <details className="run-station">
        <summary className="muted">{station.name || host?.hostname || "本机"}{host ? ` · ${host.cpus} 核 · ${gb(host.memory.totalBytes)}` : ""}</summary>
        {host && (
          <div className="resource-rings">
            <Ring percent={host.load * 100} label="CPU" title={`负载 ${host.load}（${host.cpus} 核）`} />
            <Ring percent={(host.memory.usedBytes / host.memory.totalBytes) * 100} label="内存" title={`内存 ${gb(host.memory.usedBytes)} / ${gb(host.memory.totalBytes)}`} />
            {host.disk.totalBytes > 0 && <Ring percent={(1 - host.disk.freeBytes / host.disk.totalBytes) * 100} label="磁盘" title={`磁盘剩 ${gb(host.disk.freeBytes)} / ${gb(host.disk.totalBytes)}`} />}
          </div>
        )}
      </details>
    </div>
  );
}

/** What can be done to it right now: stop a turn, release an idle process. */
function SessionActions({ session, status }: { session: SessionSummary; status: Status }) {
  const api = useApi();
  const toast = useToast();
  const stop = useAction(() => api.stop(session.key), () => toast("已请求停止"));
  const evict = useAction(() => api.evict(session.key), () => toast("已释放进程"));
  return (
    <>
      {(status === "running" || status === "queued") && <IconButton label="停止当前任务" icon={Square} onClick={() => void stop.run()} disabled={stop.busy} />}
      {session.process === "warm" && <IconButton label="释放进程" icon={Unplug} onClick={() => void evict.run()} disabled={evict.busy} />}
    </>
  );
}
