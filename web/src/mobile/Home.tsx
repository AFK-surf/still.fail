// Home is the `chats` view as the Android app lists it (apps/android/…/screens/Home.kt): one kind of item, newest first
// and grouped by day. A fixed head (you → settings · workspace · stations) and one bottom toolbar (全部 / 我参与的 · new
// chat). Both lists are followed at once, side by side: switching slides from one to the other with nothing to wait for.
import { useRef, useState } from "react";
import { useChats, useStations, useStatus, type ChatItem, type ChatsView, type StatusView, type TopicState } from "../api.ts";
import { useWorkspaces } from "../cloud/api.ts";
import { Archive, ChevronDown, Edit, Server, Unplug } from "../icons.tsx";
import { stationBase, useOnlyMine } from "../station.tsx";
import { useApp } from "./app.tsx";
import { Avatar, Illustration, MakerIcon, Mark, NavButton, SectionHeader, Seg, SlackMark, Spinner } from "./parts.tsx";
import { ChatMark } from "../ChatMark.tsx";
import { FirstStation } from "./Stations.tsx";
import { OpenJobs } from "./OpenJobs.tsx";
import { openWorkspaces } from "./Workspaces.tsx";
import * as css from "./Home.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as homeCss from "./styles/home.css.ts";
import { Tip } from "../ui.tsx";

export function Home() {
  const app = useApp();
  const scope = app.entry.id;
  const all = useChats(scope, false);
  const mine = useChats(scope, true);
  const [onlyMine, setOnlyMine] = useOnlyMine();
  const account = app.entry.account;
  const invited = useWorkspaces().value?.some((a) => a.invitations.length > 0) ?? false;
  // No station yet: nothing of the workspace's lists works, so adding the first station is the page.
  const none = useStations(scope).value?.length === 0;
  return (
    <div className={css.mHome}>
      {none ? (
        <div className={css.mHomePanes}><div className={css.mHomePane} style={{ display: "flex", flexDirection: "column" }}><FirstStation /></div></div>
      ) : (
        <div className={css.mHomePanes} data-mine={onlyMine || undefined}>
          <ChatPane chats={all} onlyMine={false} />
          <ChatPane chats={mine} onlyMine />
        </div>
      )}
      {/* The lists run under both bars, which are frosted glass over them. */}
      <header className={`${css.mHomeBar} ${pagesCss.mGlass}`}>
        <button type="button" className={css.mHomeMe} onClick={() => app.push(app.at("/settings/account"))} aria-label="我">
          <Avatar id={account.email} name={account.name || account.email} size={34} picture={account.picture} />
        </button>
        <button type="button" className={css.mHomeWorkspace} onClick={() => openWorkspaces(app)}>
          <b>{app.entry.name}</b>
          {invited && <span className={css.mDot} aria-label="有邀请" />}
          <ChevronDown size={16} />
        </button>
        {/* The archive: chats put away by hand or by the station once idle (the wide screen has it in the list's filter menu). */}
        {(all.value?.stations.length ?? 0) > 0 && <NavButton icon={Archive} iconSize={20} label="已归档" onClick={() => app.push(app.at("/archive"))} />}
        {/* A station not working marks it: grey offline, orange coming back, red failing (the core's `trouble`); its page says which. */}
        <span className="m-home-station">
          <NavButton icon={Server} iconSize={20} label={all.value?.trouble ? `Station：${all.value.trouble.text}` : "Station"} onClick={() => app.push(app.at("/settings/stations"))} />
          {all.value?.trouble && <span className="m-trouble-dot" data-state={all.value.trouble.state} aria-hidden="true" />}
        </span>
      </header>
      {/* One capsule floating over the list, round at both ends like what is in it: the switch fills it, and the new-chat
          button closes it at the right, a disc in the accent. */}
      {!none && <div className={css.mHomeToolbar}>
        <div className={`${pagesCss.mFloating} ${css.mHomeCapsule}`}>
          <Seg options={["全部", "我参与的"]} selected={onlyMine ? 1 : 0} onSelect={(i) => setOnlyMine(i === 1)} height={44} fill radius={22} inset={0} track={false} className={partsCss.mGrow} />
          <button type="button" className={css.mNewChat} onClick={() => app.push(app.at("/new"))} aria-label="新建对话"><Edit size={20} /></button>
        </div>
      </div>}
    </div>
  );
}

/** "Reading", and what the core has been waiting on for a while if anything (the core's `status`). */
function reading(status: StatusView | undefined): string {
  return status?.text ? `正在读取会话… ${status.text}` : "正在读取会话…";
}

/** One of the two lists, all or the viewer's: its states (connecting, failing, empty) and its days. */
function ChatPane({ chats, onlyMine }: { chats: TopicState<ChatsView>; onlyMine: boolean }) {
  const view = chats.value;
  const status = useStatus();
  return (
    <div className={css.mHomePane}>
      {!view ? <Note text={chats.error?.message ?? reading(status)} error={!!chats.error} /> : (
        <>
          {/* A station's link coming back is said on its rows; only with no rows to show does the list say it. */}
          {view.days.length === 0 && (view.loading || view.stations.some((s) => s.state === "connecting")) && <Note text={reading(status)} />}
          {view.days.length === 0 && !view.loading && view.stations.filter((s) => s.state === "error").map((s) => <Note key={`e/${s.station}`} text={`连不上「${s.name}」，正在重试…`} error />)}
          {view.days.length === 0 && !view.loading && !view.stations.some((s) => s.state === "error" || s.state === "connecting") && <Empty view={view} onlyMine={onlyMine} />}
          {/* What is left up a long while on the stations (./OpenJobs.tsx): nothing while there is none. */}
          <OpenJobs stations={view.stations} />
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
  return <p className={homeCss.mNote} data-error={error || undefined}>{text}</p>;
}

function Empty({ view, onlyMine }: { view: ChatsView; onlyMine: boolean }) {
  const app = useApp();
  const any = view.stations.length > 0;
  return (
    <div className={css.mEmpty}>
      <Illustration name={any ? "new-chat" : "station-offline"} width={240} />
      {onlyMine ? <p>没有你参与的会话。</p>
        : any ? <><p>还没有会话。在 Slack 里 @ {view.stations.length > 1 ? "它们" : "它"}，或者</p><button type="button" className={partsCss.mLink} onClick={() => app.push(app.at("/new"))}>新建对话</button></>
        : <><p>还没有 station。</p><button type="button" className={partsCss.mLink} onClick={() => app.push(app.at("/settings/stations"))}>看看 Station</button></>}
    </div>
  );
}

/**
 * A row: its title (bold while something in it is unread) and, for an agent that came from
 * Slack, the connect's mark; under it the last thing said; the chat's state on its picture (../ChatMark.tsx). Two lines,
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
    <button type="button" className={css.mChatRow} data-held={held || undefined} data-offline={item.offline ? true : undefined}
      aria-label={item.offline ? `${item.title}（${item.offline}）` : undefined}
      onPointerDown={() => { longPressed.current = false; timer.current = setTimeout(() => { longPressed.current = true; setHeld(true); }, 450); }}
      onPointerUp={release} onPointerCancel={release} onPointerLeave={release} onContextMenu={(e) => e.preventDefault()}
      onClick={() => { if (!longPressed.current) app.push(`${stationBase(item.station)}/chats/${encodeURIComponent(item.id)}`); }}>
      <AgentsPicture item={item} />
      <span className={css.mChatText}>
      <span className={css.mChatLine1}>
        <span className={css.mChatTitle} data-unread={item.unread || undefined}>{item.title}</span>
        {/* Only an agent that came from elsewhere (Slack, the only kind of connect) says so; an offline station, too. */}
        {item.offline ? <Tip label={item.offline}><span className={css.mChatMark}><Unplug size={14} /></span></Tip>
          : item.reconnecting ? <Tip label={item.reconnecting}><span className={css.mChatMark} aria-label={item.reconnecting}><Spinner size={12} /></span></Tip>
          : <span className={css.mChatMark}>{item.connect && <Tip label={item.originText ?? "Slack"}><span><SlackMark size={14} /></span></Tip>}</span>}
      </span>
      <span className={css.mChatLine2}>
        <span className={css.mChatLast}>{item.last && <LastMessage item={item} />}</span>
        <span className={css.mChatTime} data-shown={held || undefined}>{item.time?.lastActiveAt?.ago ?? ""}</span>
      </span>
      </span>
    </button>
  );
}

/**
 * Who is in a chat, as its row's picture: its agent's mark, or two of its agents' overlapping, with the chat's state
 * at the corner. A chat with no agent yet shows ember's.
 */
function AgentsPicture({ item }: { item: ChatItem }) {
  const agents = item.agents.slice(0, 2);
  return (
    <span className={css.mRowPicture} data-count={agents.length || 1}>
      {agents.length === 0
        ? <span className={css.mRowAgent} aria-hidden="true"><Mark size={26} /></span>
        : agents.map((a) => <span key={a.key} className={css.mRowAgent} aria-hidden="true"><MakerIcon maker={a.maker} runtime={a.runtime} size={agents.length > 1 ? 18 : 28} /></span>)}
      <ChatMark item={item} />
    </span>
  );
}

/** The last thing said, on one line, in the secondary colour (the row's picture says who is in it). */
function LastMessage({ item }: { item: ChatItem }) {
  return <span className={css.mLast}><span className={css.mLastText}>{item.last!.preview}</span></span>;
}
