// Home is the `chats` view as the Android app lists it (apps/android/…/screens/Home.kt): one kind of item, newest first
// and grouped by day. A fixed head (you → settings · workspace · stations) and one bottom toolbar (全部 / 我参与的 · new
// chat). Both lists are followed at once, side by side: switching slides from one to the other with nothing to wait for.
import { useRef, useState } from "react";
import { useChats, type ChatItem, type ChatsView, type TopicState } from "../api.ts";
import { useWorkspaces } from "../cloud/api.ts";
import { ChevronDown, Edit, Server, Unplug } from "../icons.tsx";
import { stationBase, useOnlyMine } from "../station.tsx";
import { useApp } from "./app.tsx";
import { Avatar, Badge, Illustration, MakerIcon, Mark, NavButton, SectionHeader, Seg, SlackMark, Spinner, stateOf } from "./parts.tsx";
import { openWorkspaces } from "./Workspaces.tsx";

export function Home() {
  const app = useApp();
  const scope = app.entry.id;
  const all = useChats(scope, false);
  const mine = useChats(scope, true);
  const [onlyMine, setOnlyMine] = useOnlyMine();
  const account = app.entry.account;
  const invited = useWorkspaces().value?.some((a) => a.invitations.length > 0) ?? false;
  return (
    <div className="m-home">
      <div className="m-home-panes" data-mine={onlyMine || undefined}>
        <ChatPane chats={all} onlyMine={false} />
        <ChatPane chats={mine} onlyMine />
      </div>
      {/* The lists run under both bars, which are frosted glass over them. */}
      <header className="m-home-bar m-glass">
        <button type="button" className="m-home-me" onClick={() => app.push(app.at("/settings/account"))} aria-label="我">
          <Avatar id={account.email} name={account.name || account.email} size={34} picture={account.picture} />
        </button>
        <button type="button" className="m-home-workspace" onClick={() => openWorkspaces(app)}>
          <b>{app.entry.name}</b>
          {invited && <span className="m-dot" aria-label="有邀请" />}
          <ChevronDown size={16} />
        </button>
        <NavButton icon={Server} iconSize={20} label="Station" onClick={() => app.push(app.at("/settings/stations"))} />
      </header>
      {/* One capsule floating over the list, round at both ends like what is in it: the switch fills it, and the new-chat
          button closes it at the right, a disc in the accent. */}
      <div className="m-home-toolbar">
        <div className="m-floating m-home-capsule">
          <Seg options={["全部", "我参与的"]} selected={onlyMine ? 1 : 0} onSelect={(i) => setOnlyMine(i === 1)} height={44} fill radius={22} inset={0} track={false} className="m-grow" />
          <button type="button" className="m-new-chat" onClick={() => app.push(app.at("/new"))} aria-label="新建对话"><Edit size={20} /></button>
        </div>
      </div>
    </div>
  );
}

/** One of the two lists, all or the viewer's: its states (connecting, failing, empty) and its days. */
function ChatPane({ chats, onlyMine }: { chats: TopicState<ChatsView>; onlyMine: boolean }) {
  const view = chats.value;
  return (
    <div className="m-home-pane">
      {!view ? <Note text={chats.error?.message ?? "正在读取会话…"} error={!!chats.error} /> : (
        <>
          {/* A station's link coming back is said on its rows; only with no rows to show does the list say it. */}
          {view.days.length === 0 && (view.loading || view.stations.some((s) => s.state === "connecting")) && <Note text="正在读取会话…" />}
          {view.days.length === 0 && !view.loading && view.stations.filter((s) => s.state === "error").map((s) => <Note key={`e/${s.station}`} text={`连不上「${s.name}」，正在重试…`} error />)}
          {view.days.length === 0 && !view.loading && !view.stations.some((s) => s.state === "error" || s.state === "connecting") && <Empty view={view} onlyMine={onlyMine} />}
          {view.days.map((day) => (
            <section key={day.daysAgo}>
              <SectionHeader title={day.label} />
              {day.items.map((item) => <ChatRow key={`${item.station}/${item.id}`} item={item} />)}
            </section>
          ))}
        </>
      )}
    </div>
  );
}

function Note({ text, error = false }: { text: string; error?: boolean }) {
  return <p className="m-note" data-error={error || undefined}>{text}</p>;
}

function Empty({ view, onlyMine }: { view: ChatsView; onlyMine: boolean }) {
  const app = useApp();
  const any = view.stations.length > 0;
  return (
    <div className="m-empty">
      <Illustration name={any ? "new-chat" : "station-offline"} width={240} />
      {onlyMine ? <p>没有你参与的会话。</p>
        : any ? <><p>还没有会话。在 Slack 里 @ {view.stations.length > 1 ? "它们" : "它"}，或者</p><button type="button" className="m-link" onClick={() => app.push(app.at("/new"))}>新建对话</button></>
        : <><p>还没有 station。</p><button type="button" className="m-link" onClick={() => app.push(app.at("/settings/stations"))}>看看 Station</button></>}
    </div>
  );
}

/**
 * A row: its title (bold while something in it is unread, a blue dot in the margin) and, for an agent that came from
 * Slack, the connect's mark; under it the last thing said, the agent's state on its picture when it said it. Two lines,
 * always the same height. The time shows while the row is held (or, with a mouse, pointed at). One whose station is
 * offline is greyed and says so.
 */
function ChatRow({ item }: { item: ChatItem }) {
  const app = useApp();
  const [held, setHeld] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const longPressed = useRef(false);
  const release = () => { clearTimeout(timer.current); setHeld(false); };
  return (
    <button type="button" className="m-chat-row" data-held={held || undefined} data-offline={item.offline ? true : undefined}
      aria-label={item.offline ? `${item.title}（${item.offline}）` : undefined}
      onPointerDown={() => { longPressed.current = false; timer.current = setTimeout(() => { longPressed.current = true; setHeld(true); }, 450); }}
      onPointerUp={release} onPointerCancel={release} onPointerLeave={release} onContextMenu={(e) => e.preventDefault()}
      onClick={() => { if (!longPressed.current) app.push(`${stationBase(item.station)}/chats/${encodeURIComponent(item.id)}`); }}>
      {item.unread && <span className="m-unread" aria-label="有未读消息" />}
      <AgentsPicture item={item} />
      <span className="m-chat-text">
      <span className="m-chat-line1">
        <span className="m-chat-title" data-unread={item.unread || undefined}>{item.title}</span>
        {/* Only an agent that came from elsewhere (Slack, the only kind of connect) says so; an offline station, too. */}
        {item.offline ? <span className="m-chat-mark" title={item.offline}><Unplug size={13} /></span>
          : item.reconnecting ? <span className="m-chat-mark" title={item.reconnecting} aria-label={item.reconnecting}><Spinner size={11} /></span>
          : <span className="m-chat-mark">{item.connect && <span title={item.originText ?? "Slack"}><SlackMark size={13} /></span>}</span>}
      </span>
      <span className="m-chat-line2">
        <span className="m-chat-last">{item.last && <LastMessage item={item} />}</span>
        <span className="m-chat-time" data-shown={held || undefined}>{item.time?.lastActiveAt?.ago ?? ""}</span>
      </span>
      </span>
    </button>
  );
}

/**
 * Who is in a chat, as its row's picture: its agent's mark, or two of its agents' overlapping, with its state (the
 * core's) at the corner. A chat with no agent yet shows ember's.
 */
function AgentsPicture({ item }: { item: ChatItem }) {
  const agents = item.agents.slice(0, 2);
  const state = stateOf(item.state ?? undefined);
  return (
    <span className="m-row-picture" data-count={agents.length || 1} aria-hidden="true">
      {agents.length === 0
        ? <span className="m-row-agent"><Mark size={18} /></span>
        : agents.map((a) => <span key={a.key} className="m-row-agent"><MakerIcon maker={a.maker} runtime={a.runtime} size={agents.length > 1 ? 13 : 19} /></span>)}
      {state !== "done" && <Badge state={state} size={10} ring={2} around="var(--m-bg)" style={{ position: "absolute", right: -2, bottom: -2 }} />}
    </span>
  );
}

/** The last thing said, on one line, in the secondary colour (the row's picture says who is in it). */
function LastMessage({ item }: { item: ChatItem }) {
  return <span className="m-last"><span className="m-last-text">{item.last!.preview}</span></span>;
}
