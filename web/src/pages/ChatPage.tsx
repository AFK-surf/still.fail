// A chat: a thread (a Slack thread or a chat on ember's page) with its people
// and agents. The messages are the page; each agent's execution history can
// be opened beside them, one tab per agent.
import { StationPreview } from "../Preview.tsx";
import { useLink, useStation } from "../station.tsx";
import { CreatorText, PeopleStack, QuotaRing, Ring } from "../components.tsx";
import { Close, Info, PanelClose, PanelOpen, Stop, Unplug, Web } from "../icons.tsx";
import { Popover, Tabs } from "radix-ui";
import { useEffect, useRef, useState, type ReactNode } from "react";
import { Link, Navigate, useNavigate, useParams, useSearchParams } from "react-router";
import { lastChat } from "../lastChat.ts";
import type { Job } from "../core/shapes.ts";
import { useAction, useApi, useChat, useChats, useHistory, useHost, useLives, useStationCall, type ChatAgent, type ChatView, type Session, type Status, type ChatThread } from "../api.ts";
import { History } from "../History.tsx";
import { ModelTriple } from "../ModelTriple.tsx";
import { ChatPanel } from "../Chat.tsx";
import { chatOpening, track } from "../telemetry.ts";
import { useToast } from "../toast.tsx";
import { AgentMark, ConnectKindIcon, Empty, ICON, IconButton, Loading, MobileBack, ModelLogo, ResizeHandle, SlackLogo, Time, Tip } from "../ui.tsx";

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
    const surface = !chat.thread || chat.thread.surface === "ember" ? "ember" : "slack";
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
  // Its agents' background jobs; a service's tab (`service:<job>`) is the chat's own while one of them has it.
  const jobs = agents.flatMap((a) => a.jobs ?? []);
  const open = agents.length ? tabs.filter((key) => (serviceOf(key) !== null && jobs.some((j) => j.id === serviceOf(key))) || agents.some((a) => a.session.key === key)) : tabs;
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
  // A link that names a web service of the chat's (`?service=<job>`, a service's link in Slack): its tab, open.
  const [search, setSearch] = useSearchParams();
  const asked = search.get("service");
  useEffect(() => {
    if (!asked) return;
    openTab(`service:${asked}`);
    setSearch((now) => { now.delete("service"); return now; }, { replace: true });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [asked]);
  // ember's own links (/o/<workspace>/<station>/<session>, as agents post them): one of this chat's agents' web services
  // opens beside the chat; another session of the workspace opens here, in the page, not through the desktop app.
  const opens = useRef({ agents, openTab });
  opens.current = { agents, openTab };
  useEffect(() => {
    const onClick = (event: MouseEvent) => {
      if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      const anchor = (event.target as Element | null)?.closest?.("a[href]") as HTMLAnchorElement | null;
      if (!anchor) return;
      const url = new URL(anchor.href, location.href);
      const item = /^\/o\/([^/]+)\/([^/]+)\/([^/]+)\/?$/.exec(url.pathname);
      if (!item) return;
      const session = decodeURIComponent(item[3]!);
      const service = url.searchParams.get("service");
      if (service && opens.current.agents.some((a) => a.session.key === session)) {
        event.preventDefault();
        opens.current.openTab(`service:${service}`);
      } else if (url.origin === location.origin) {
        event.preventDefault();
        navigate(`/w/${item[1]}/s/${item[2]}/chats/${encodeURIComponent(session)}${url.search}`);
      }
    };
    document.addEventListener("click", onClick, true);
    return () => document.removeEventListener("click", onClick, true);
  }, [navigate]);
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
  const slackUrl = chat.slackUrl;
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
          {agents.map((a) => (
            <Tip key={a.session.key} label={`${a.session.agentText}${a.session.badgeText ? ` · ${a.session.badgeText}` : ""} · 执行历史`}>
              <button type="button" className="agent-mark-btn" onClick={() => toggleHistory(a.session.key)} aria-label={`${a.session.agentText} 的执行历史`}>
                <AgentMark maker={a.session.maker} runtime={a.session.runtime} badge={a.badge} badgeText={a.session.badgeText} size={20} />
              </button>
            </Tip>
          ))}
        </div>
        <div className="page-bar-actions">
          <JobsPanel station={station.address} jobs={jobs} onOpen={(job) => openTab(`service:${job}`)} />
          {chat.thread && <ChatInfo chat={chat} thread={chat.thread} />}
          {slackUrl && (
            <Tip label="在 Slack 中打开">
              <a className="icon-btn" href={slackUrl} target="_blank" rel="noopener" aria-label="在 Slack 中打开"><SlackLogo /></a>
            </Tip>
          )}
          {!panel && agents[0] && <IconButton label="打开侧栏" icon={PanelOpen} onClick={() => openTab(agents[0]!.session.key)} />}
        </div>
      </header>
      {/* The chat is the page; its agents' histories sit in a tab set that takes the whole right side. */}
      <ChatPanel chat={chat} draftKey={chatKey} lives={lives} onOpenHistory={openHistory} {...firstMessage} />
      </div>
        {panel && shown && (
          <Tabs.Root className="side-panel" value={shown} onValueChange={setActive} data-opening={opening || undefined} onAnimationEnd={(e) => { if (e.target === e.currentTarget) setOpening(false); }}>
            <ResizeHandle variable="--panel-w" edge="left" min={320} max={960} label="调整侧栏宽度" />
            <div className="side-bar">
              <Tabs.List className="side-tab-list" aria-label="执行历史">
                {open.map((key) => {
                  const service = jobs.find((j) => j.id === serviceOf(key));
                  if (service) {
                    return (
                      <span key={key} className="side-tab-wrap">
                        <Tabs.Trigger className="side-tab" value={key} title={service.name}>
                          <span className="side-tab-agent"><Web size={13} strokeWidth={1.75} /><span className="side-tab-text" data-text={service.name}>{service.name}</span></span>
                        </Tabs.Trigger>
                        <button type="button" className="side-tab-close" aria-label={`关闭 ${service.name}`} onClick={() => closeTab(key)}><Close size={12} strokeWidth={2} /></button>
                      </span>
                    );
                  }
                  const a = agents.find((x) => x.session.key === key);
                  // Not known yet: its place, empty, until it is.
                  if (!a) return <span key={key} className="side-tab-wrap" />;
                  const label = a.session.agentText;
                  return (
                    <span key={key} className="side-tab-wrap">
                      <Tabs.Trigger className="side-tab" value={key} title={`${label} 的执行历史`}>
                        <span className="side-tab-agent"><ModelLogo maker={a.session.maker} runtime={a.session.runtime} size={13} /><span className="side-tab-text" data-text={label}>{label}</span></span>
                      </Tabs.Trigger>
                      <button type="button" className="side-tab-close" aria-label={`关闭 ${label} 的执行历史`} onClick={() => closeTab(key)}><Close size={12} strokeWidth={2} /></button>
                    </span>
                  );
                })}
              </Tabs.List>
              {/* The panel's switch stays in the top-right corner, open or closed. */}
              <IconButton label="收起侧栏" icon={PanelClose} onClick={() => saveTabs([])} />
            </div>
            {open.map((key) => {
              const service = jobs.find((j) => j.id === serviceOf(key));
              // Kept loaded while another tab shows: switching back does not load it anew.
              if (service) {
                return (
                  <Tabs.Content key={key} className="side-content" value={key} forceMount>
                    {service.port !== undefined && (service.state === "running" || service.state === "exited")
                      ? <StationPreview station={station.address} port={service.port} name={service.name} service={service.id} />
                      : <Empty><p>「{service.name}」{service.state === "failed" ? "没能启动" : "已经停了"}。</p></Empty>}
                  </Tabs.Content>
                );
              }
              const a = agents.find((x) => x.session.key === key);
              if (!a) return <Tabs.Content key={key} className="side-content" value={key} />;
              return (
                <Tabs.Content key={key} className="side-content" value={key}>
                  <History station={station.address} sessionKey={key} actions={<SessionActions session={a.session} status={a.status} />}
                    focus={focus?.key === key ? focus : null}
                    summary={<HistorySummary agent={a} />}
                    details={<SessionDetails agent={a} />} />
                </Tabs.Content>
              );
            })}
          </Tabs.Root>
        )}
    </div>
  );
}

/** A web service's tab: its job, from its key (`service:<job>`); null for an agent's history tab. */
function serviceOf(key: string): string | null {
  return key.startsWith("service:") ? key.slice("service:".length) : null;
}

/** A job's state, in words. */
function jobState(job: Job): string {
  switch (job.state) {
    case "running": return "运行中";
    case "exited": return job.port !== undefined ? "正在重启" : job.exitCode === 0 ? "已完成" : `已结束（退出码 ${job.exitCode ?? "?"}）`;
    case "stopped": return "已停止";
    default: return "没能启动";
  }
}

/** The chat's web services (opened beside it) and background jobs (their last output): from the title bar. */
function JobsPanel({ station, jobs, onOpen }: { station: string; jobs: Job[]; onOpen: (job: string) => void }) {
  const call = useStationCall(station);
  const [open, setOpen] = useState(false);
  const [shown, setShown] = useState<{ id: string; text: string | null } | null>(null);
  const services = jobs.filter((j) => j.port !== undefined);
  const plain = jobs.filter((j) => j.port === undefined);
  const log = (id: string) => {
    if (shown?.id === id) return setShown(null);
    setShown({ id, text: null });
    void call.request<{ text: string }>("GET", `/jobs/${encodeURIComponent(id)}/log?lines=80`)
      .then((r) => setShown((now) => (now?.id === id ? { id, text: r.text || "（还没有输出）" } : now)), (e: Error) => setShown((now) => (now?.id === id ? { id, text: `读不到输出：${e.message}` } : now)));
  };
  return (
    <Popover.Root open={open} onOpenChange={(next) => { setOpen(next); if (!next) setShown(null); }}>
      <Tip label="服务和后台任务">
        <Popover.Trigger asChild>
          <button type="button" className="icon-btn" aria-label="服务和后台任务" data-count={jobs.length || undefined}><Web {...ICON} /></button>
        </Popover.Trigger>
      </Tip>
      <Popover.Portal>
        <Popover.Content className="popover jobs-panel" align="end" sideOffset={6} collisionPadding={8}>
          {jobs.length === 0 && <p className="jobs-empty">这个对话里还没有服务或后台任务。agent 起了以后会列在这里。</p>}
          {services.length > 0 && (
            <section>
              <div className="jobs-head">服务</div>
              {services.map((j) => {
                const up = j.state === "running" || j.state === "exited";
                return (
                  <div key={j.id} className="jobs-row">
                    <span className="jobs-name">{j.name}</span>
                    <span className="jobs-state" data-state={j.state}>{jobState(j)}</span>
                    {up && <button type="button" className="btn btn-secondary jobs-open" onClick={() => { onOpen(j.id); setOpen(false); }}>打开</button>}
                  </div>
                );
              })}
            </section>
          )}
          {plain.length > 0 && (
            <section>
              <div className="jobs-head">后台任务</div>
              {plain.map((j) => (
                <div key={j.id}>
                  <button type="button" className="jobs-row jobs-toggle" aria-expanded={shown?.id === j.id} onClick={() => log(j.id)}>
                    <span className="jobs-name">{j.name}</span>
                    <span className="jobs-state" data-state={j.state}>{jobState(j)}</span>
                  </button>
                  {shown?.id === j.id && <pre className="code jobs-log">{shown.text ?? "正在读取…"}</pre>}
                </div>
              ))}
            </section>
          )}
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
function ChatInfo({ chat, thread }: { chat: ChatView; thread: ChatThread }) {
  const link = useLink();
  const connect = slackConnect(chat);
  const row = (label: string, value: ReactNode) => <div className="detail-row"><dt>{label}</dt><dd>{value}</dd></div>;
  const where = chat.place;
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
            {row("创建", <Time stamp={thread.time?.createdAt} />)}
            {thread.lastMessage && row("最近消息", <Time stamp={thread.lastMessage.time?.createdAt} />)}
          </dl>
          {chat.agents.length > 0 && (
            <ul className="details-list">
              {chat.agents.map((a) => <AgentLine key={a.session.key} agent={a} />)}
            </ul>
          )}
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}

/** An agent of the chat in its info: what it runs, where it came from, and how it stands. */
function AgentLine({ agent }: { agent: ChatAgent }) {
  const { session, connect } = agent;
  return (
    <li>
      <span className="detail-inline"><AgentMark maker={session.maker} runtime={session.runtime} badge={agent.badge} badgeText={session.badgeText} size={14} />{session.agentText}</span>
      <span className="muted">
        {connect ? <><ConnectKindIcon kind={connect.kind} size={11} /> {connect.name} · </> : null}{session.processText} · 最近活动 <Time stamp={session.time?.lastActiveAt} />
      </span>
    </li>
  );
}

/**
 * The history's line under its head: only what is worth a look now, as the core says (a quota running out, the disk
 * filling up, an account that cannot run); nothing when all is well.
 */
function HistorySummary({ agent }: { agent: ChatAgent }) {
  if (agent.attention.length === 0) return null;
  return (
    <span className="history-summary">
      {agent.attention.map((a, i) => (
        a.quota ? (
          <Tip key={i} label={<>{a.text}{a.more && <><br />{a.more}</>}</>}>
            <span className="attention attention-quota"><QuotaRing left={a.quota.left} level={a.quota.level} size={20} /><span className="quota-ring-letter">{a.quota.mark}</span></span>
          </Tip>
        ) : (
          <span key={i} className="attention" data-tone={a.kind === "disk" ? "amber" : "red"}>{a.text}</span>
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
function SessionDetails({ agent }: { agent: ChatAgent }) {
  const { session } = agent;
  const station = useStation();
  const link = useLink();
  const api = useApi();
  const toast = useToast();
  const host = useHost(station.address).value;
  const change = useAction((input: { profile?: string | null; model?: string | null; effort?: string | null }) => api.sessionSettings(session.key, input), () => toast("已改，下一轮起生效"));
  const usage = useHistory(station.address, session.key).value?.usageLine;
  return (
    <div className="session-details">
      {/* How it runs, in one row: the model, how hard it thinks, then the account it runs on (with its quota). */}
      <ModelTriple title="换模型、思考深度和账号" runtimeFixed
        options={agent.choices} current={agent.account}
        value={{ model: session.model ?? "", runtime: session.runtime, effort: session.effort ?? null, profile: session.profilePinned ? session.profile ?? null : null }}
        onPick={({ model, effort, profile }) => void change.run({ model, effort, profile })} />
      {change.error && <p className="field-error" role="alert">{change.error.message}</p>}
      {/* What it used: a line, quiet. */}
      <p className="run-usage muted">
        {session.runtimeText} · {session.processText}
        {usage && <> · {usage}</>}
        {" · "}<Link className="detail-link" to={link(`/settings/accounts/${session.profile}`)}>Profile 详情</Link>
      </p>
      {/* The station it runs on, and how loaded it is. */}
      <div className="run-station">
        <p className="muted">{station.name || host?.hostname || "本机"}{host ? ` · ${host.summary}` : ""}</p>
        {host && (
          <div className="resource-rings">
            {host.meters.map((m) => <Ring key={m.label} percent={m.percent} level={m.level} label={m.short} title={`${m.label} ${m.value}`} />)}
          </div>
        )}
      </div>
    </div>
  );
}

/** What can be done to it right now: stop a turn, release an idle process. */
function SessionActions({ session, status }: { session: Session; status: Status }) {
  const api = useApi();
  const toast = useToast();
  const stop = useAction(() => api.stop(session.key), () => toast("已请求停止"));
  const evict = useAction(() => api.evict(session.key), () => toast("已释放进程"));
  return (
    <>
      {(status === "running" || status === "queued") && <IconButton label="停止当前任务" icon={Stop} onClick={() => void stop.run()} disabled={stop.busy} />}
      {session.process === "warm" && <IconButton label="释放进程" icon={Unplug} onClick={() => void evict.run()} disabled={evict.busy} />}
    </>
  );
}
