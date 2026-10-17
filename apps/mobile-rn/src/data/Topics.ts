// Screens read the core's topics (data/Topics.kt): each topic named here as the web client's `Topic`
// (web/src/core/client.ts), and followed by `useTopic` (web/src/core/react.ts) or, on a page of the stack, by the
// page's own `PageTopics`, kept while the page is in the stack. What the core sends has its shape
// (web/src/core/shapes.ts, generated as Shapes.kt is): the value comes typed as it is, nothing decoded here.
import { createContext, useContext, useEffect, useMemo, useRef, useSyncExternalStore } from "react";
import type { CoreClient, Topic } from "../../../../web/src/core/client.ts";
import { core as theCore, topicKey, topicNow, useTopic, type TopicState } from "../../../../web/src/core/react.ts";
import type { ChatItem, ChatsView, ChatView } from "../../../../web/src/core/shapes.ts";
import { ChatDecoder, ChatsDecoder } from "./ChatDecoder";
import { TopicTiming } from "./TopicTiming";

/** A topic's value as a screen sees it: the value (kept through a later error), why it failed, whether it is still coming. */
export type { TopicState };

/** What an item's page is of: its chat's thread, or its agent's session while it has no chat (ChatOf.Thread, ChatOf.Session). */
export type ChatOf = { thread: number } | { session: string };
export const ChatOf = {
  Thread: (id: number): ChatOf => ({ thread: id }),
  Session: (key: string): ChatOf => ({ session: key }),
};

/** A row's page: its agent's, chat or no chat (the core shows the chat once there is one). */
export function page(item: ChatItem): ChatOf {
  return { session: item.session };
}

/** The next state as shown: a value is kept through a later error, and while it is being read again (followed anew). */
function after<T>(was: TopicState<T>, next: TopicState<T>): TopicState<T> {
  return next.value === undefined && (next.error !== null || next.loading) ? { ...next, value: was.value } : next;
}

/** What a topic followed now was last shown as, and by how many. */
interface Latest { shown: TopicState<unknown>; followers: number }

/**
 * What each topic followed now (by PageTopics, preread) was last shown as: one followed again elsewhere (a sheet over
 * its page, a page pushed over another showing it) starts from it, not from nothing for the frames the core takes to
 * send it again.
 */
const latest = new Map<string, Latest>();

const LOADING: TopicState<never> = { value: undefined, error: null, loading: true };

function latestOf<T>(topic: Topic): TopicState<T> {
  const shown = latest.get(topicKey(topic))?.shown as TopicState<T> | undefined;
  if (shown) return shown;
  // What a page's `useTopic` holds of it, if one does.
  const now = topicNow<T>(topic);
  return now === undefined ? LOADING : { value: now, error: null, loading: false };
}

/** Each value as a page reads it: a chat's newest words parsed ahead (ChatDecoder), a list's rows as they are. */
function reader(topic: Topic): (value: unknown) => unknown {
  if (topic.topic === "chat") { const d = new ChatDecoder(); return (v) => d.read(v as ChatView); }
  if (topic.topic === "chats") { const d = new ChatsDecoder(); return (v) => d.read(v as ChatsView); }
  return (v) => v;
}

/** Follows `topic` from `start`, each state as shown given to `show` and kept in `latest` while it is followed; returns how to stop. */
function followShown<T>(core: CoreClient, topic: Topic, start: TopicState<T>, show: (state: TopicState<T>) => void): () => void {
  const key = topicKey(topic);
  let entry = latest.get(key);
  if (!entry) { entry = { shown: start, followers: 0 }; latest.set(key, entry); }
  const kept = entry;
  kept.followers++;
  let shown = start;
  const read = reader(topic);
  const next = (state: TopicState<T>) => { shown = after(shown, state); kept.shown = shown; show(shown); };
  const off = core.subscribe(
    topic,
    (value) => {
      const arrived = performance.now();
      const v = value === null ? undefined : (read(value) as T);
      TopicTiming.decoded(topic, arrived, value, false);
      next({ value: v, error: null, loading: false });
    },
    (error) => {
      TopicTiming.decoded(topic, performance.now(), undefined, true);
      next({ value: undefined, error, loading: false });
    },
  );
  let stopped = false;
  return () => {
    if (stopped) return;
    stopped = true;
    off();
    if (--kept.followers === 0 && latest.get(key) === kept) latest.delete(key);
  };
}

/**
 * Reads topics ahead of the page that shows them (a workspace switched to, App.tsx): each followed for `keepMs`, so the
 * page following them then starts from what they were (`latest`) rather than from nothing. Resolves once each has a
 * value or an error, or after `waitMs`.
 */
export function preread(core: CoreClient, topics: Topic[], waitMs: number, keepMs: number): Promise<void> {
  return new Promise((resolve) => {
    let left = topics.length;
    let over = false;
    const done = () => { if (!over) { over = true; clearTimeout(timer); resolve(); } };
    const timer = setTimeout(done, waitMs);
    if (left === 0) { done(); return; }
    for (const topic of topics) {
      const start = latestOf<unknown>(topic);
      let ready = start.value !== undefined || start.error !== null;
      const one = () => { if (--left === 0) done(); };
      if (ready) one();
      const stop = followShown(core, topic, start, (s) => {
        if (!ready && (s.value !== undefined || s.error !== null)) { ready = true; one(); }
      });
      setTimeout(stop, keepMs);
    }
  });
}

/** A topic a page follows: its state now, and who hears when it changes. */
interface Followed {
  state: TopicState<unknown>;
  listeners: Set<() => void>;
  /** How to stop following it; null while paused. */
  stop: (() => void) | null;
  readers: number;
}

/**
 * The topics a page of the stack follows, kept while the page is in the stack rather than only while it is drawn
 * (App.tsx): coming back to it, what it shows is there at once, not gone and coming in again (its list's rows, so it
 * keeps its place; what grows in above them). Following one in the core costs next to nothing. One the page stops
 * reading while drawn (a search's query typed on) is let go.
 */
export class PageTopics {
  static readonly UNREAD_MS = 10_000;

  readonly #followed = new Map<string, Followed>();
  /** What waits to let a topic go (the Kotlin's scope's delays): cancelled with it. */
  #timers = new Set<ReturnType<typeof setTimeout>>();
  /** Whether the page is drawn now (App.tsx). */
  drawn = false;

  #follow(core: CoreClient, topic: Topic, f: Followed): () => void {
    return followShown(core, topic, f.state, (s) => {
      f.state = s;
      TopicTiming.shown(topic, s.value, s.error !== null);
      for (const l of f.listeners) l();
    });
  }

  /** The topic as this page follows it: its state, and a way to hear it change (useSyncExternalStore's). */
  of<T>(core: CoreClient, topic: Topic): { get: () => TopicState<T>; subscribe: (l: () => void) => () => void } {
    const key = topicKey(topic);
    let f = this.#followed.get(key);
    if (f) {
      // Paused (its page switched away from): followed again from what it last showed.
      if (f.stop === null) {
        TopicTiming.followed(topic, f.state.value !== undefined);
        f.stop = this.#follow(core, topic, f);
      }
    } else {
      f = { state: latestOf(topic), listeners: new Set(), stop: null, readers: 0 };
      TopicTiming.followed(topic, f.state.value !== undefined);
      this.#followed.set(key, f);
      f.stop = this.#follow(core, topic, f);
    }
    const it = f;
    return {
      get: () => it.state as TopicState<T>,
      subscribe: (l) => { it.listeners.add(l); return () => { it.listeners.delete(l); }; },
    };
  }

  read(topic: Topic): void {
    const f = this.#followed.get(topicKey(topic));
    if (f) f.readers++;
  }

  /**
   * No longer read: let go a while later if still not read and the page still drawn, so not when what stopped reading
   * it is the page itself going, nor a row of its list scrolled out and back.
   */
  unread(topic: Topic): void {
    const key = topicKey(topic);
    const it = this.#followed.get(key);
    if (!it) return;
    if (--it.readers > 0) return;
    const timer = setTimeout(() => {
      this.#timers.delete(timer);
      if (this.drawn && it.readers === 0 && this.#followed.get(key) === it) {
        this.#followed.delete(key);
        it.stop?.();
        it.stop = null;
      }
    }, PageTopics.UNREAD_MS);
    this.#timers.add(timer);
  }

  /**
   * A place's top page switched away from on the bar (App.tsx), its state kept: its topics are let go in the core, what
   * they last showed kept. Coming back, the page is drawn from that at once, as it was left (its list as long, so its
   * scroll place stays where it was, not clamped to a list still being read), and each is followed again from it.
   */
  pause(): void {
    for (const f of this.#followed.values()) { f.stop?.(); f.stop = null; }
    for (const timer of this.#timers) clearTimeout(timer);
    this.#timers = new Set();
  }

  /** The page left the stack: its topics are let go. */
  close(): void {
    this.pause();
  }
}

/** The page being drawn's topics (App.tsx), or none outside the stack's pages. */
export const LocalPageTopics = createContext<PageTopics | null>(null);

const NO_STORE = { get: () => undefined, subscribe: () => () => undefined };

/**
 * Follows `topic` (null: nothing): on a page of the stack while the page is in it (PageTopics), else while it is drawn
 * (useTopic, which shares one subscription among all that show it).
 */
export function rememberTopic<T>(topic: Topic | null): TopicState<T> {
  const page = useContext(LocalPageTopics);
  const key = topic ? topicKey(topic) : null;
  const paged = page !== null && topic !== null;
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const store = useMemo(() => (paged ? page!.of<T>(theCore(), topic!) : null), [page, key, paged]);
  useEffect(() => {
    if (!paged || !topic) return;
    page!.read(topic);
    return () => page!.unread(topic);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page, key, paged]);
  const own = useSyncExternalStore((store ?? NO_STORE).subscribe, (store ?? NO_STORE).get as () => TopicState<T> | undefined);
  const drawn = useTopic<T>(paged ? null : topic);
  // A chat's newest words parsed ahead as they come (PageTopics' do it as they follow).
  const decoder = useRef<ChatDecoder | null>(null);
  if (!paged && topic?.topic === "chat" && drawn.value !== undefined) {
    decoder.current ??= new ChatDecoder();
    decoder.current.read(drawn.value as ChatView);
  }
  return paged && own ? own : drawn;
}

export const Topics = {
  accounts: { topic: "accounts" } as Topic,
  workspaces: { topic: "workspaces" } as Topic,
  /** A scope's chat list: all, the viewer's (`mine`), or the watching ones (`watching`). */
  chats: (scope: string, mine: boolean, watching = false): Topic => ({ topic: "chats", scope, mine, ...(watching ? { watching: true } : {}) }),
  stations: (scope: string): Topic => ({ topic: "stations", scope }),
  /** The workspace's profiles in one list: each shared one once (client/core-ts/src/views/profiles.ts). */
  profiles: (scope: string): Topic => ({ topic: "profiles", scope }),
  /** The archived chats of a scope's stations online, newest first by the day archived (client/core-ts/src/views/archive.ts):
   *  those with `q` in their title or last line, the newest `limit` of them (the list's first page by default). */
  archive: (scope: string, q = "", limit: number = ARCHIVE_PAGE): Topic => ({ topic: "archive", scope, ...(q !== "" ? { q } : {}), ...(limit > 0 ? { limit } : {}) }),
  /** How many archived chats the archive's list shows at first, and how many more as it is scrolled near its end (web pages/Archive.tsx). */
  get ARCHIVE_PAGE() { return ARCHIVE_PAGE; },
  connects: (scope: string, mine: boolean): Topic => ({ topic: "connects", scope, mine }),
  workspace: (id: string): Topic => ({ topic: "workspace", workspace: id }),
  /** The stations of the viewer's other workspaces that could be added to this one as they are (docs/multi-workspace.md). */
  joinable: (workspace: string): Topic => ({ topic: "joinable", workspace }),
  /** The workspaces a station is in, for its home workspace's owners and admins. */
  memberships: (station: string): Topic => ({ topic: "memberships", station }),
  /** A station's screens a person can see and drive (docs/remote-screens.md): its page lists them. */
  screens: (station: string): Topic => ({ topic: "screens", station }),
  loginSessions: (account: string): Topic => ({ topic: "loginSessions", account }),
  overview: (station: string): Topic => ({ topic: "overview", station }),
  host: (station: string): Topic => ({ topic: "host", station }),
  /** An item's page: its chat, or its agent before it has one. */
  chat: (station: string, of: ChatOf): Topic => ("thread" in of ? { topic: "chat", station, thread: of.thread } : { topic: "chat", station, session: of.session }),
  live: (station: string, key: string): Topic => ({ topic: "live", station, key }),
  /** An agent's execution history, read for people (the core's). */
  history: (station: string, key: string): Topic => ({ topic: "history", station, key }),
  /** A chat's agent in brief, for its card (client/core-ts/src/views/brief.ts; AgentSheet.tsx). */
  agentCard: (station: string, key: string): Topic => ({ topic: "agentCard", station, key }),
  /** A chat's services and background jobs as its pages show them (the same `of` as its `chat`; Jobs.tsx). */
  chatJobs: (station: string, of: ChatOf): Topic => ("thread" in of ? { topic: "chatJobs", station, thread: of.thread } : { topic: "chatJobs", station, session: of.session }),
  /** An image of a chat open in the preview: the ones beside it, as the chat's page shows them (the same `of` as its `chat`). */
  imageNear: (station: string, of: ChatOf, path: string): Topic =>
    ("thread" in of ? { topic: "imageNear", station, thread: of.thread, path } : { topic: "imageNear", station, session: of.session, path }),
  /** The services and jobs left up a long while on the scope's stations that are up (OpenJobs.tsx). */
  longJobs: (scope: string): Topic => ({ topic: "longJobs", scope }),
  /** What the agents of a scope's stations spent over its last `days` (7 or 30): client/core-ts/src/views/usage.ts. */
  usage: (scope: string, days: number): Topic => ({ topic: "usage", scope, days }),
  /** A job as it is now (kept current by the core). */
  job: (station: string, id: string): Topic => ({ topic: "job", station, id }),
  /** A job's last `lines` lines of output and when it last grew, current as it grows. */
  jobLog: (station: string, job: string, lines: number): Topic => ({ topic: "jobLog", station, job, lines }),
  /**
   * What the core has been waiting on for a while (a slow request, a link down), said under a page's "loading…": a
   * workspace's (its stations, its account's socket, the relay), nothing of another; with none, all of it.
   */
  status: (workspace: string | null = null): Topic => ({ topic: "status", ...(workspace != null ? { workspace } : {}) }),
  /** What wants the viewer in the chats they take part in, the last 20 (docs/notifications.md; Notices). */
  notices: { topic: "notices" } as Topic,
  /**
   * Notifications on this device: on or off, asked, whether to hold pushes, what to show now (attend.ts; Notices),
   * only `workspace`'s if given.
   */
  notify: (workspace: string | null = null): Topic => ({ topic: "notify", ...(workspace != null ? { workspace } : {}) }),
  /** How its person likes it on this device, and what the device is (Prefs.ts). */
  prefs: { topic: "prefs" } as Topic,
  /** What people set going here and the core has not finished, until it answers (client/core-ts/src/doing.ts; AppState.isDoing). */
  doing: { topic: "doing" } as Topic,
  /** This phone's adb as lent to a station's agents (client/core-ts/src/adb.ts; AdbShare.tsx). */
  // A topic the web client does not name (the web has no adb to lend): passed as the core takes it.
  adbShare: { topic: "adbShare" } as unknown as Topic,
  /** The decisions waiting for the viewer in a workspace's chats, one at a time on its page (client/core-ts/src/decisions.ts; Decisions.tsx). */
  decisions: (workspace: string): Topic => ({ topic: "decisions", workspace }),
  /** What changed in still.fail, as this app shows it, and what an update brought until `changelog.seen` (Changelog.tsx). */
  changelog: { topic: "changelog" } as Topic,
  /**
   * What each workspace has waiting (how many chats want their person, how many are unread) and the chat last open in
   * it; of those other than `workspace` (the one in view), the most urgent (client/core-ts/src/views/marks.ts).
   */
  workspaceMarks: (workspace: string): Topic => ({ topic: "workspaceMarks", workspace }),
  /** The workspace's security mode (its lock), and what turning it on would sign (client/core-ts/src/views/lock.ts). */
  lock: (workspace: string): Topic => ({ topic: "lock", workspace }),
  lockDraft: (workspace: string): Topic => ({ topic: "lockDraft", workspace }),
  /** The workspace's vaults as the viewer sees them, and the agents' requests waiting on them (client/core-ts/src/views/vault.ts). */
  vaults: (workspace: string): Topic => ({ topic: "vaults", workspace }),
  /** A vault's items: their names once it is unlocked on this device, else the listed ones' (Vault.tsx). */
  vaultItems: (workspace: string, vault: string): Topic => ({ topic: "vaultItems", workspace, vault }),
  /** An item's uses by agents, the latest first (the station's record of them; Vault.tsx's item page). */
  vaultUses: (workspace: string, vault: string, item: string): Topic => ({ topic: "vaultUses", workspace, vault, item }),
  /** What is written to a chat on this device until sent (`chat`: its key, `thread:<id>`, or `new`; Drafts). */
  draft: (station: string, chat: string): Topic => ({ topic: "draft", station, chat }),
  /**
   * The chats of a scope a few words find, titles first: only `station`'s, not `exclude` (a chat's id or agent), `limit`
   * at most (ChatRefMenu); with `messages`, that many of the messages that have the words too (Search.tsx). `elsewhere`:
   * then those of the viewer's other workspaces, each saying whose (`ChatItem.outside`: the `@` menu).
   */
  chatSearch: (scope: string, query: string, station: string | null = null, exclude: string | null = null, limit: number | null = null, messages: number | null = null, elsewhere = false): Topic => ({
    topic: "chatSearch", scope, query,
    ...(station != null ? { station } : {}), ...(exclude != null ? { exclude } : {}), ...(limit != null ? { limit } : {}), ...(messages != null ? { messages } : {}),
    // `elsewhere` is not in the web's Topic yet (the web's `@` menu does not ask it): the core takes it.
    ...(elsewhere ? { elsewhere: true } : {}),
  }) as Topic,
  /** A new chat's page in a scope: its stations, the one it starts on and what it runs there, as last picked here (web/src/pick.ts). */
  newChat: (scope: string): Topic => ({ topic: "newChat", scope }),
  /** Where something another app shares goes (docs/share-in.md): `source` what is shared, `query` what is typed to find a chat. */
  shareIn: (scope: string, source: string, query: string): Topic => ({ topic: "shareIn", scope, source, query }),
  /** A model control: what it runs on now and what its panel picked (`of`: new, session:<key>, connect:<id>, connect-new). */
  pick: (station: string, of: string): Topic => ({ topic: "pick", station, of }),

  /**
   * A folder of a station's drive (docs/drive.md): `root` as the station names it, `path` under it (empty: the root
   * itself). What is held shows first; the core reads it again each time it is shown, a refusal as the topic's error.
   */
  drive: (station: string, root: string, path: string): Topic => ({ topic: "drive", station, root, path }),
  /** Where a file of a drive was left on this device: a text's offset, a video's time (ms); null before it was opened. */
  drivePlace: (station: string, root: string, path: string): Topic => ({ topic: "drivePlace", station, root, path }),

  /** A connect's Slack app as Slack has it (read through the station; again after a write to the connect). */
  slackApp: (station: string, connect: string): Topic => ({ topic: "slackApp", station, connect }),
};

/** How many archived chats the archive's list shows at first, and how many more as it is scrolled near its end. */
export const ARCHIVE_PAGE = 60;
