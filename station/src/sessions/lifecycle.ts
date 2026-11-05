// Sessions and chats as people make, change, archive and delete them (the Rust station's hub.rs: new_session, open_chat,
// add_to_thread, say, bind_single, configure, archive, archive_chat, auto_archive, delete_session,
// continue_machine_session). Archiving here is the record (archived, hidden) and what goes with it (the process ends,
// other stations are told); packing an archived session's files is the hub's ColdStorage.
import { type PresetCopy, keepCopy } from "./presets.ts";
import { copyFileSync, mkdirSync, renameSync, rmSync } from "node:fs";
import { createHash } from "node:crypto";
import { rm } from "node:fs/promises";
import { basename, dirname, join, relative, sep } from "node:path";
import { DISK_LOW_BYTES } from "../ops/disk.ts";
import { PlaceRefused } from "../ops/places.ts";
import { log } from "../ops/log.ts";
import { tr, type Lang, stationLang } from "../ops/i18n.ts";
import { checkContext } from "./context-cap.ts";
import { type MachineSession, type Roots, rolloutOf, rolloutsIn } from "../read/machine.ts";
import { readTimeline, sessionPlaces, sharedTranscripts, transcriptSources } from "../read/transcript.ts";
import { forgetMarks, marksDir } from "../read/transcripts.ts";
import { ARCHIVED_WORKSPACE_BATCH, AUTO, type ArchivedWorkspace, type Attachment, MANUAL, type Quote, STILLFAIL_SURFACE, type ThreadRow } from "../store/store.ts";
import { sessionBindingsReady } from "../store/session-bindings-index.ts";
import { archiveMarksReady } from "../store/archive-mark-index.ts";
import type { SessionChange } from "./accounts.ts";
import { unlockWorktrees, withLock } from "./archive.ts";
import { roomOf } from "./footprint.ts";
import { type Runtime, runs, runtimeNamed, runtimeTitle } from "./config.ts";
import { FAST_RUNTIMES } from "../agents/profiles.ts";
import { CLIENT_KEY_KEPT_MS, type Hub, connectOf, newChatKey, newSingleSessionKey, newToken } from "./hub.ts";
import { INTERNAL_CHANNEL, INTERNAL_CONNECT, chatKey, chatWorkspace } from "./internal.ts";
import { STATION_AUTHOR } from "../store/rows.ts";

/// A session of its own, talked to in the station's chat.
export type NewChat = {
  runtime: Runtime;
  profile?: string | null;
  model?: string | null;
  effort?: string | null;
  fast?: boolean | null;
  /// The most context it runs with, in tokens (sessions/context-cap.ts); none: the model's whole window.
  context?: number | null;
  title?: string | null;
  createdBy: string;
  /// The key the asking client knows it by until it is made (`clientKey`): the sidebar's rows say it for a while.
  clientKey?: string | null;
  /// The workspace its chat is in (the asker's, or the opening session's); absent: the station's home one.
  ws?: string | null;
  /// The preset it is opened with (presets.ts), its copy kept with it; or the copy itself, another station's preset as
  /// the app read it there (`presetCopy`).
  preset?: string | null;
  presetCopy?: PresetCopy | null;
};

const trimmed = (v: string | null | undefined) => {
  const t = v?.trim();
  return t ? t : null;
};

/// Points a single-session connect at a session: an existing one (any session on the same runtime, whichever connect
/// started it) or, with null, a new empty one. The bound session's key.
export function bindSingle(hub: Hub, connectId: string, target: string | null, title: string | null, createdBy: string | null): string {
  const config = hub.config();
  const connect = connectOf(config, connectId);
  if (connect.mode !== "single-session") throw new Error(`connect ${connectId} is not single-session`);
  if (target === null) {
    const key = newSingleSessionKey(connect.id);
    hub.createSession(config, key, connect, "all", null, trimmed(title), createdBy);
    hub.store.setBinding(connect.id, key);
    return key;
  }
  const row = hub.store.getSession(target);
  if (!row) throw new Error(`unknown session ${target}`);
  if (row.runtime !== connect.bind.runtime) throw new Error(`session ${target} runs ${row.runtime}, the connect runs ${connect.bind.runtime}`);
  // A connect's sessions are its workspace's chats (docs/multi-workspace.md): none of another workspace.
  const home = hub.workspaces()[0] ?? null;
  if (home !== null && hub.wsOf(row) !== (connect.workspace ?? home)) throw new Error(`session ${target} is in another workspace than the connect`);
  hub.store.setBinding(connect.id, target);
  log.info("hub", "single-session connect rebound", { connect: connect.id, session: target });
  return target;
}

/// Opens a chat on the station's pages with a session in it. More sessions can join it later (addToThread).
export function openChat(hub: Hub, session: string, createdBy: string, title: string | null): ThreadRow {
  if (!hub.internal) throw new Error("still.fail chat is not available");
  const row = hub.store.getSession(session);
  if (!row) throw new Error(`unknown session ${session}`);
  // The first chat made with a session is its own; later ones are chats of their own (ThreadRow.home).
  const home = hub.store.homeChat(session) !== null ? null : session;
  // Its own chat keeps the name the session was given before it had one.
  const name = title ?? (home !== null ? row.title : null);
  const thread = hub.store.openThreadOf(STILLFAIL_SURFACE, INTERNAL_CHANNEL, hub.nextTs(), name, createdBy, home);
  hub.store.joinThread(thread.id, session, INTERNAL_CONNECT);
  return thread;
}

function stillfailChat(hub: Hub, thread: number): ThreadRow {
  const row = hub.store.getThread(thread);
  if (!row || row.surface !== STILLFAIL_SURFACE) throw new Error(`no still.fail chat ${thread}`);
  return row;
}

/// Brings another session into a chat on the station's pages; it hears what is said from then on.
export function addToThread(hub: Hub, thread: number, session: string) {
  stillfailChat(hub, thread);
  const row = hub.store.getSession(session);
  if (row === null) throw new Error(`unknown session ${session}`);
  // A chat is one workspace's (docs/multi-workspace.md): no session of another joins it. Outside any workspace, all are
  // the same one's.
  const there = hub.store.threadSessions(thread)[0];
  if (hub.workspaces().length > 0 && there !== undefined && hub.wsOf(there.session) !== hub.wsOf(row)) throw new Error(`session ${session} is in another workspace than the chat`);
  hub.store.joinThread(thread, session, INTERNAL_CONNECT);
}

/// A person's message in a chat on the station's pages: recorded with its quotes and files and delivered to every
/// session in the chat, like a Slack message. `client`: the app it was sent from, as it said. Its entry number.
export function say(hub: Hub, thread: number, user: string, text: string, attachments: Attachment[] = [], quotes: Quote[] = [], client: string | null = null): number {
  stillfailChat(hub, thread);
  if (hub.store.manuallyArchived(thread)) throw new Error(tr(stationLang(), "station.chat.archived"));
  const [n] = hub.store.insertMessage({ thread, ts: hub.nextTs(), authorKind: "person", author: user, text, attachments, quotes, client });
  const sessions = hub.store.threadSessions(thread).map((m) => m.session);
  hub.deliver(thread, n, sessions, text);
  return n;
}

/// A session of its own, talked to in the station's chat: the runtime, model and effort chosen by whoever starts it
/// rather than a connect's, and the profile: one given keeps it there; else the pool picks one with the model on. Only
/// the profiles allowed in its workspace (docs/multi-workspace.md).
export function newSession(hub: Hub, options: NewChat, lang: Lang = stationLang()): [string, ThreadRow] {
  const config = hub.config();
  const client = trimmed(options.clientKey);
  // A reply can be lost when the station restarts. The same request must find the rows already made, including when
  // the process stopped between inserting the session, the thread and its membership.
  const key = client === null ? newChatKey() : chatKey(`c-${createHash("sha256").update(JSON.stringify([options.ws ?? null, options.createdBy, client])).digest("hex").slice(0, 32)}`, (k) => hub.store.getSession(k) !== null);
  const existing = hub.store.getSession(key);
  if (existing !== null) {
    if (client !== null) hub.clientKeysMade.set(key, [client, hub.now()]);
    const thread = hub.store.homeChat(key) ?? openChat(hub, key, options.createdBy, existing.title);
    hub.store.joinThread(thread.id, key, INTERNAL_CONNECT);
    return [key, thread];
  }
  const runtime = options.runtime;
  const all = config.profiles.filter((p) => p.runtimes.includes(runtime));
  if (all.length === 0) throw new Error(`no ${runtime} profile configured`);
  const here = new Set(hub.profilesIn(options.ws ?? null).map((p) => p.id));
  const profiles = all.filter((p) => here.has(p.id));
  if (profiles.length === 0) throw new Error(tr(lang, "station.session.noProfileHere", { runtime: runtimeTitle(runtime) }));
  const model = trimmed(options.model);
  const pinned = options.profile ?? null;
  let profile;
  if (pinned !== null) {
    profile = profiles.find((p) => p.id === pinned);
    if (!profile) {
      const there = all.find((p) => p.id === pinned);
      throw new Error(there ? tr(lang, "station.profile.notHere", { profile: there.name }) : `no ${runtime} profile ${pinned}`);
    }
    if (model !== null && !runs(profile, model)) throw new Error(tr(lang, "station.profile.modelOff", { profile: profile.name, model }));
  } else profile = hub.accounts.pick(profiles, model, true);
  const effort = options.effort ? options.effort : null;
  checkContext(runtime, options.context, lang);
  if (effort !== null) {
    const allowed = hub.accounts.modelEfforts(runtime, model, pinned, (p) => here.has(p.id));
    if (!allowed.includes(effort)) throw new Error(`effort must be one of ${allowed.join(", ")}`);
  }
  const workspace = chatWorkspace(config.dataDir, key);
  mkdirSync(workspace, { recursive: true });
  // (before its rows: one that names no preset of its workspace makes no chat)
  const preset = trimmed(options.preset);
  if (options.presetCopy) keepCopy(workspace, options.presetCopy);
  else if (preset !== null) hub.presets.keepFor(workspace, options.ws ?? hub.workspaces()[0] ?? null, preset);
  mkdirSync(join(config.dataDir, "repos"), { recursive: true });
  const now = hub.now();
  // Known before its rows are (their events can reach the client before this answers), and for a while after.
  if (client !== null) {
    for (const [k, [, at]] of hub.clientKeysMade) if (now - at >= CLIENT_KEY_KEPT_MS) hub.clientKeysMade.delete(k);
    hub.clientKeysMade.set(key, [Array.from(client).slice(0, 120).join(""), now]);
  }
  const title = trimmed(options.title);
  hub.store.insertSession({
    key,
    connect: INTERNAL_CONNECT,
    scope: "all",
    title,
    createdBy: options.createdBy,
    runtime,
    profile: profile.id,
    profilePinned: pinned !== null,
    model: model ?? profile.model ?? null,
    effort,
    fast: FAST_RUNTIMES.includes(runtime) ? (options.fast ?? null) : null,
    context: options.context ?? null,
    workspace,
    cwd: null,
    runtimeSessionId: null,
    token: newToken(),
    createdAt: now,
    lastActiveAt: now,
    ws: options.ws ?? null,
  });
  log.info("hub", "session created", { session: key, connect: INTERNAL_CONNECT, runtime, profile: profile.id, model, preset });
  return [key, openChat(hub, key, options.createdBy, title)];
}

/// Changes how a session runs from its next turn on: another profile of its runtime (another account, say), another
/// model it can run, another effort. Its transcript is shared by the runtime's profiles, so the next message resumes it
/// with all it had; its process ends so the change takes: at once when idle, else when the running turn is over, before
/// the next one starts (nobody waits for the turn to end to change it). Another model starts over
/// what went with the old one: its effort back to the runtime's default, its profile back to the station's choice
/// (picked here, among those that run the model), unless given with it. Given back to the station to pick again
/// (`repick`), its account is picked now as a new session's would be. Whether it goes on afresh once its prompt cache is
/// over (`afresh`, null: as the station is set) is read as its next turn starts: its process goes on.
export async function configure(hub: Hub, key: string, change: SessionChange, lang: Lang = stationLang()) {
  const { afresh, ...rest } = change;
  if (afresh !== undefined) {
    if (!hub.store.getSession(key)) throw new Error(`unknown session ${key}`);
    hub.store.setSessionAfresh(key, afresh);
    log.info("hub", "going on afresh once its cache is over set", { session: key, afresh: afresh ?? "station's" });
    if (Object.keys(rest).length === 0) return;
  }
  const { row, runtime, model, effort, profile, pinned, repick } = hub.accounts.change(key, change, lang);
  const movedRuntime = runtime !== row.runtime && typeof profile === "string";
  const recapped = change.context !== undefined && change.context !== row.context;
  if (movedRuntime) {
    if (row.runtimeSessionId) hub.store.ranIn(key, row.runtimeSessionId, row.profile);
    hub.store.setSessionRuntime(key, runtime, profile, pinned === true, model, effort, change.fast ?? null, change.context ?? null);
  } else {
    if (profile !== undefined) hub.store.setSessionProfile(key, profile ?? row.profile, profile !== null);
    if (model !== row.model || effort !== row.effort) hub.store.setSessionModel(key, model, effort);
    if (change.fast !== undefined) hub.store.setSessionFast(key, change.fast);
    if (recapped) hub.store.setSessionContext(key, change.context ?? null);
    if (repick) hub.accounts.repick(key);
    else if (profile === null) hub.accounts.runOn(key);
  }
  // Another most context is what its process starts with (Claude Code's settings, a Codex thread's config): only a new
  // one takes it.
  await hub.changed(key, movedRuntime || recapped);
  log.info("hub", "session changed", { session: key, profile: hub.store.getSession(key)?.profile ?? "", model, effort, context: hub.store.getSession(key)?.context ?? "" });
  // Its last turn stopped at the allowance, or waits to be tried again on a model at capacity: changed, it goes on by
  // itself (at once).
  const last = hub.store.lastTurn(key);
  const detail = last?.outcome === "failed" ? (last.detail ?? "") : "";
  if (detail.startsWith("rate_limit") || (detail.startsWith("overloaded") && last?.declared === "waiting")) void hub.actor(hub.store.getSession(key) ?? row).goOn();
}

/// Where an archived session's transcript copy is.
const transcriptCopy = (hub: Hub, key: string) => join(hub.store.archiveDir(), "transcripts", `${key}.jsonl.zst`);

/// Hides a session from lists, or shows it again; `by` is MANUAL or AUTO. Archiving also ends its idle process and
/// hands its files to cold storage once it is idle; they are restored before the next runtime starts, and before it is
/// shown again (a promise then, when cold storage takes its time: the session is shown once they are back).
export function archiveBy(hub: Hub, key: string, archived: boolean, by: string): void | Promise<void> {
  const row = hub.store.getSession(key);
  if (!row) throw new Error(`unknown session ${key}`);
  if (!archived) {
    const shown = () => {
      hub.store.setArchived(key, false, by);
      rmSync(transcriptCopy(hub, key), { force: true });
    };
    const restoring = hub.cold.restore(key);
    return restoring ? restoring.then(shown) : shown();
  }
  hub.store.setArchived(key, archived, by);
  hub.closed(key);
  const actor = hub.actor(row);
  void actor
    .putAway()
    .then(() => actor.evict())
    .then(() => actor.cleanArchive());
}

/// Hides a session from lists, or shows it again, by hand.
export const archive = (hub: Hub, key: string, archived: boolean) => archiveBy(hub, key, archived, MANUAL);

/// Archives a chat on the pages, or shows it again: a session's own chat goes with its session; a chat of its own goes
/// alone, its sessions staying as they are.
export function archiveChat(hub: Hub, thread: number, archived: boolean): void | Promise<void> {
  const chat = stillfailChat(hub, thread);
  if (chat.home !== null) return archive(hub, chat.home, archived);
  hub.store.setThreadHidden(thread, archived, MANUAL);
}

/// A snapshot-bounded walk of archived workspaces; no main-thread query returns more than a page.
async function* archivedWorkspaces(hub: Hub, through: number | ArchivedWorkspace, needed: () => boolean = () => true): AsyncGenerator<ArchivedWorkspace> {
  let after: ArchivedWorkspace | null = null;
  for (;;) {
    if (!needed()) return;
    const page = hub.store.archivedSessions(after, through);
    for (const s of page) yield s;
    if (page.length < ARCHIVED_WORKSPACE_BATCH) return;
    after = page[page.length - 1]!;
    // Even if every file check completes immediately, other station work gets a turn before the next database page.
    await new Promise<void>((resolve) => setImmediate(resolve));
  }
}

/// Empties the workspaces of sessions archived past archivedWorkspaceMs, one after another: each keeps the files sent in
/// its chat, its history and its transcripts (cold.ts `expire`). Returns when the next one archived comes due (null:
/// none, or off).
export async function expireArchived(hub: Hub, now: number): Promise<number | null> {
  const after = hub.config().archivedWorkspaceMs;
  const { cold } = hub;
  if (after <= 0 || !cold.expire || !cold.holdsMore) return null;
  for await (const s of archivedWorkspaces(hub, now - after)) {
    try {
      if (await cold.holdsMore(s.key)) await cold.expire(s.key, now - after);
    } catch (error) {
      log.warn("hub", "the workspace of a long-archived session was not emptied", { session: s.key, error: (error as Error).message });
    }
  }
  const next = hub.store.nextArchivedAt(now - after);
  return next === null ? null : next + after;
}

/// The disk of the station's data is low (ops/disk.ts): archived workspaces are emptied before archivedWorkspaceMs, the
/// longest archived first, as `expireArchived` empties them, until `free` is DISK_LOW_BYTES again. None with
/// archivedWorkspaceDays 0 (kept on purpose).
export async function relieveArchived(hub: Hub, free: () => number): Promise<void> {
  const { cold } = hub;
  if (hub.config().archivedWorkspaceMs <= 0 || !cold.expire || !cold.holdsMore) return;
  if (free() >= DISK_LOW_BYTES) return;
  const through = hub.store.lastArchivedSession();
  if (through === null) return;
  for await (const s of archivedWorkspaces(hub, through, () => free() < DISK_LOW_BYTES)) {
    if (free() >= DISK_LOW_BYTES) return;
    try {
      // Shown and archived again since, it is not the one looked at: `expire` leaves it.
      if (!(await cold.holdsMore(s.key))) continue;
      if (free() >= DISK_LOW_BYTES) return;
      await cold.expire(s.key, s.archivedAt);
    } catch (error) {
      log.warn("hub", "the workspace of an archived session was not emptied", { session: s.key, error: (error as Error).message });
    }
  }
}

/// Archives what has idled past autoArchiveMs (counted from its last activity, or from being shown again by hand) and is
/// done: nothing running or waiting to be heard, no background job or service of its own still up (a watch above all),
/// not stopped at a block for someone, nothing its chat's starter has not read, and no single-session connect feeding
/// it. Anything new said brings it back. Returns when the next one not idle long enough yet will have (null: none, or
/// auto-archiving off): what is idle but not done by now is not on a clock, so it is looked at again after a while.
/// A session heard only in Slack goes after slackArchiveMs even when stopped at a block: nobody answers it from here.
/// With autoArchiveReviewed, the rest goes only once the archive review recommended each of its chats.
export function autoArchive(hub: Hub, now: number, prepareUnread?: (thread: number) => void, prepareBindings?: () => void,
  prepareJobs?: (session: string) => void, prepareMarks?: () => void): number | null {
  const { store } = hub;
  const { autoArchiveMs: after, slackArchiveMs, autoArchiveReviewed, automaticDecisions } = hub.config();
  if (after <= 0 && slackArchiveMs <= 0) return null;
  let next: number | null = null;
  const idle = (at: (number | null | undefined)[], wait = after) => {
    if (wait <= 0) return false;
    const due = Math.max(0, ...at.filter((x): x is number => typeof x === "number")) + wait;
    if (due > now && (next === null || due < next)) next = due;
    return due <= now;
  };
  const unread = (t: ThreadRow) => {
    if (t.createdBy === null || t.surface !== STILLFAIL_SURFACE) return false;
    const answer = store.unreadForArchive(t.createdBy, t.id);
    if (answer === null) { prepareUnread?.(t.id); return true; }
    return answer;
  };
  // Over the sessions shown and the chats of their own (and those chats' sessions), never every one ever archived.
  const live = store.liveSessions();
  const own = store.chatsOfTheirOwn();
  if (live.length === 0 && own.length === 0) return null;
  // An old station's reverse mark lookup may be incomplete. Never guess that a chat is unpinned or not kept.
  if (!archiveMarksReady(store.db)) { prepareMarks?.(); return null; }
  const bindingsReady = live.length === 0 || sessionBindingsReady(store.db);
  const waitingForBindings = !bindingsReady && prepareBindings !== undefined;
  if (waitingForBindings) prepareBindings?.();
  const oldBindings = !bindingsReady && !waitingForBindings ? store.listBindings() : null;
  // Each session's undelivered messages and last turn, read for those idle long enough alone, once each: read for every
  // session shown and every member of their chats at each look, the station's thread was held 17 s on a station short of
  // memory (2026-11-03), what was said meanwhile waiting.
  const statsRead = new Map<string, ReturnType<typeof store.workOf>>();
  const statOf = (key: string) => {
    if (!statsRead.has(key)) statsRead.set(key, store.workOf(key));
    return statsRead.get(key);
  };
  let oldJobs: Set<string> | null = null;
  const jobsRead = new Map<string, boolean>();
  const hasUpJob = (key: string) => {
    if (jobsRead.has(key)) return jobsRead.get(key)!;
    const found = store.sessionHasUpJob(key);
    let answer = found;
    if (answer === null && prepareJobs !== undefined) { prepareJobs(key); answer = true; }
    if (answer === null) { oldJobs ??= new Set(store.jobsUp().map((j) => j.sessionKey)); answer = oldJobs.has(key); }
    jobsRead.set(key, answer);
    return answer;
  };
  const working = (key: string) => {
    const row = store.getSession(key);
    if (!row) return true;
    const stat = statOf(key);
    const last = stat?.lastTurn ?? null;
    return row.running || hub.processState(key) === "running" || stat?.pending === true || (last !== null && last.endedAt === null) || hasUpJob(key);
  };
  const busy = (key: string) => working(key) || statOf(key)?.lastTurn?.declared === "block";
  // A chat someone pinned stays in the lists until put away by hand.
  const { pinned, kept } = store.archiveMarks();
  // Where only what the archive review recommended goes (`autoArchiveReviewed`): none while the review is off.
  const recommended = (thread: number) => !autoArchiveReviewed || (automaticDecisions.completion.enabled && store.archiveSuggested(thread));
  for (const s of live) {
    if (waitingForBindings || (bindingsReady ? store.preparedSessionBound(s.key) : oldBindings!.has(s.key)) || pinned(s.key)) continue;
    // Idle long enough by its times alone, before anything else of it is read.
    const quiet = idle([s.lastActiveAt, s.shownAt]);
    const quietLong = idle([s.lastActiveAt, s.shownAt], slackArchiveMs);
    if (!quiet && !quietLong) continue;
    const threads = store.sessionThreads(s.key);
    const slack = threads.length > 0 && threads.every((t) => t.thread.surface !== STILLFAIL_SURFACE);
    const done = quiet && !busy(s.key);
    const lingering = slack && quietLong && !working(s.key);
    if (!done && !lingering) continue;
    if (!lingering && !threads.every((t) => recommended(t.thread.id))) continue;
    if (threads.some((t) => kept(t.thread.id) || unread(t.thread))) continue;
    log.info("hub", "archiving an idle session", { session: s.key });
    archiveBy(hub, s.key, true, AUTO);
  }
  for (const t of own) {
    const said = store.lastMessage(t.id)?.createdAt ?? null;
    if (kept(t.id) || !idle([t.createdAt, said, t.shownAt]) || unread(t) || !recommended(t.id)) continue;
    if (store.threadSessions(t.id).some((m) => pinned(m.session) || busy(m.session))) continue;
    log.info("hub", "archiving an idle chat", { thread: t.id });
    store.setThreadHidden(t.id, true, AUTO);
  }
  return next;
}

/// Check on the usual schedule, and try again when an old chat's missing unread boundary is ready.
export function startAutoArchiveTimer(hub: Hub, time: { after(ms: number, run: () => void): () => void },
  readers: { prepareSaid(threads: readonly number[], signal?: AbortSignal): Promise<void>; prepareSessionBindings(signal?: AbortSignal): Promise<void>;
    prepareSessionUpJobs(sessions: readonly string[], signal?: AbortSignal): Promise<void>; prepareArchiveMarks?(signal?: AbortSignal): Promise<void> }): () => void {
  const cancel = new AbortController();
  let timer: (() => void) | null = null;
  let preparing = false;
  let preparingBindings = false;
  let preparingJobs = false;
  let preparingMarks = false;
  const schedule = (ms: number) => {
    timer?.();
    timer = time.after(ms, check);
  };
  const check = () => {
    timer = null;
    let next: number | null = null;
    const missing = new Set<number>();
    const missingJobs = new Set<string>();
    let missingBindings = false;
    let missingMarks = false;
    try {
      next = autoArchive(hub, hub.now(), (thread) => missing.add(thread), () => { missingBindings = true; }, (session) => missingJobs.add(session), () => { missingMarks = true; });
    } catch (error) {
      log.warn("hub", "auto-archiving failed", { error: (error as Error).message });
    }
    schedule(Math.min(600_000, next === null ? Infinity : next - hub.now()));
    if (!preparingMarks && missingMarks && readers.prepareArchiveMarks) {
      preparingMarks = true;
      void readers.prepareArchiveMarks(cancel.signal).then(() => {
        preparingMarks = false;
        if (!cancel.signal.aborted) schedule(0);
      }, (error) => {
        preparingMarks = false;
        if (!cancel.signal.aborted) log.warn("hub", "preparing archive marks failed", { error: (error as Error).message });
      });
    }
    if (!preparing && missing.size) {
      preparing = true;
      void readers.prepareSaid([...missing], cancel.signal).then(() => {
        preparing = false;
        if (!cancel.signal.aborted) schedule(0);
      }, (error) => {
        preparing = false;
        if (!cancel.signal.aborted) log.warn("hub", "preparing unread state for auto-archiving failed", { error: (error as Error).message });
      });
    }
    if (!preparingBindings && missingBindings) {
      preparingBindings = true;
      void readers.prepareSessionBindings(cancel.signal).then(() => {
        preparingBindings = false;
        if (!cancel.signal.aborted) schedule(0);
      }, (error) => {
        preparingBindings = false;
        if (!cancel.signal.aborted) log.warn("hub", "preparing bindings for auto-archiving failed", { error: (error as Error).message });
      });
    }
    if (!preparingJobs && missingJobs.size) {
      // Retry one archive pass when the requested batch is done, not one full pass per session. The regular timer
      // still checks sessions whose preparation finished while another has a longer old history.
      preparingJobs = true;
      void readers.prepareSessionUpJobs([...missingJobs], cancel.signal).then(() => {
        preparingJobs = false;
        if (!cancel.signal.aborted) schedule(0);
      }, (error) => {
        preparingJobs = false;
        if (!cancel.signal.aborted) log.warn("hub", "preparing jobs for auto-archiving failed", { error: (error as Error).message });
      });
    }
  };
  schedule(60_000);
  return () => { cancel.abort(); timer?.(); timer = null; };
}

/// Deletes a session: its process ends, its rows go (with the threads only it was in) and its workspace directory,
/// transcript copy and what the readers kept of its transcripts' reading with them. The runtime's transcript stays in
/// the profile's home, which may be a person's own.
export async function deleteSession(hub: Hub, key: string) {
  const row = hub.store.getSession(key);
  if (!row) throw new Error(`unknown session ${key}`);
  const actor = hub.dropActor(key);
  await actor?.dispose();
  hub.live.forget(key);
  const { dataDir, profiles } = hub.config();
  const transcripts = transcriptSources(dataDir, profiles, hub.store.runtimeSessionSources(key), sessionPlaces(row)).paths.map((p) => p.path);
  hub.store.deleteSession(key);
  hub.closed(key);
  rmSync(transcriptCopy(hub, key), { force: true });
  forgetMarks(marksDir(dataDir), transcripts);
  // Sessions made by the station keep their workspace in a directory of their own.
  const sessions = join(dataDir, "sessions");
  const own = basename(row.workspace) === "workspace" && (row.workspace + sep).startsWith(sessions + sep);
  const home = own ? dirname(row.workspace) : row.workspace;
  const room = roomOf(dataDir, row.workspace);
  if (room !== null) {
    // Git worktrees it archived are let go first, so `git worktree prune` can clean them up.
    await withLock(room, async () => {
      await unlockWorktrees(room);
      await rm(home, { recursive: true, force: true });
    });
  } else rmSync(home, { recursive: true, force: true });
  log.info("hub", "session deleted", { session: key });
}

/// Copies a machine session's transcript to where the station's runtimes keep theirs (`shared`:
/// data/transcripts/<runtime>), at the same place under it, so a profile resumes it there: for Codex every file it keeps
/// the thread in. The originals are not touched. Where the transcript read is.
function copyTranscript(roots: Roots, session: MachineSession, shared: string): string {
  const root = session.runtime === "claude" ? roots.claude : roots.codex;
  const files = [session.path];
  if (session.runtime === "codex") {
    const rollouts: string[] = [];
    rolloutsIn(root, rollouts);
    files.push(...rollouts.filter((p) => p !== session.path && rolloutOf(p, session.id)));
  }
  const under = (path: string) => {
    const rel = relative(root, path);
    if (rel.startsWith("..") || rel === "") throw new Error(`${path} is not the machine's`);
    return rel;
  };
  for (const from of files) {
    const to = join(shared, under(from));
    mkdirSync(dirname(to), { recursive: true });
    const partial = to.replace(/\.jsonl$/, "") + ".jsonl.part";
    copyFileSync(from, partial);
    renameSync(partial, to);
  }
  return join(shared, under(session.path));
}

/// Goes on in a chat with a session the machine's own Claude Code or Codex kept (run in a terminal). Its transcript is
/// copied into the shared transcripts (the original is left as it was, and can go on in the terminal on its own); the
/// new session resumes it, running in the directory it ran in. The chat starts with a note of where it came from,
/// linking to the session's execution history, which shows what was said before (it is not copied into the chat). A
/// session already going on with it is that one's chat, brought back if archived. `ws`: the workspace the new chat is in
/// (null: the home one's).
export async function continueMachineSession(hub: Hub, roots: Roots, found: MachineSession, createdBy: string, lang: Lang = stationLang(), ws: string | null = null): Promise<[string, ThreadRow]> {
  const { store } = hub;
  const runtime = found.runtime;
  // One it went on in (a runtime session left for a new one included).
  const going = store.sessionOfRuntime(runtime, found.id);
  if (going) {
    const thread = store.homeChat(going.key);
    if (thread) {
      if (going.archivedAt !== null) {
        // Its files come back before its runtime starts in any case: a failure here is only told.
        void Promise.resolve()
          .then(() => archive(hub, going.key, false))
          .catch((error) => log.warn("hub", "archived session not shown again", { session: going.key, error: (error as Error).message }));
      }
      return [going.key, thread];
    }
  }
  // Looked at as ops/places.ts does: never on this thread in a folder macOS protects (still.fail Helper asked instead).
  try {
    await hub.places.directory(found.cwd, { lang });
  } catch (e) {
    if (e instanceof PlaceRefused && (e.code === "gone" || e.code === "not_a_directory")) throw new Error(tr(lang, "station.session.cwdGone", { cwd: found.cwd }));
    throw e;
  }
  // Looked at again, in case it was continued meanwhile.
  const already = store.sessionOfRuntime(runtime, found.id);
  if (already) {
    const thread = store.homeChat(already.key);
    if (thread) return [already.key, thread];
  }
  const config = hub.config();
  // On the profiles the chat's workspace runs on.
  const profiles = hub.profilesIn(ws).filter((p) => p.runtimes.includes(runtime));
  if (profiles.length === 0) throw new Error(tr(lang, "station.session.noProfile", { runtime: runtimeTitle(runtime) }));
  // The model it ran, where a profile runs it; else the one picked runs its own.
  const keptModel = found.model !== null && profiles.some((p) => p.models.includes(found.model!)) ? found.model : null;
  const profile = hub.accounts.pick(profiles, keptModel, false);
  const model = keptModel ?? profile.model ?? profile.models[0] ?? null;
  const copy = copyTranscript(roots, found, sharedTranscripts(config.dataDir, runtime));
  // Where its execution history is when it comes here: its last entry, read as the history reads it (from the shared
  // place, read/transcript.ts `transcriptPaths`).
  const entries = readTimeline(runtime, copy).length;
  const last = entries > 0 ? entries - 1 : null;
  const key = newChatKey();
  const workspace = chatWorkspace(config.dataDir, key);
  mkdirSync(workspace, { recursive: true });
  mkdirSync(join(config.dataDir, "repos"), { recursive: true });
  const now = hub.now();
  const titleOf = found.title ?? found.first;
  const title = titleOf !== null ? Array.from(titleOf).slice(0, 80).join("") : null;
  store.insertSession({
    key,
    connect: INTERNAL_CONNECT,
    scope: "all",
    title,
    createdBy,
    runtime,
    profile: profile.id,
    profilePinned: false,
    model,
    effort: null,
    fast: null,
    workspace,
    cwd: found.cwd,
    runtimeSessionId: found.id,
    token: newToken(),
    createdAt: now,
    lastActiveAt: now,
    ...(ws !== null ? { ws } : {}),
  });
  log.info("hub", "session continued from the machine's own", { session: key, runtime, profile: profile.id, from: found.id, cwd: found.cwd });
  const thread = openChat(hub, key, createdBy, title);
  // What was said before stays in its transcript: the note links to the session's execution history, which shows it, at
  // where it was when it came here (the pages open `?history=<session>&entry=<n>` links there).
  const at = last !== null ? `&entry=${last}` : "";
  const note = tr(lang, "station.session.continued", { runtime: runtimeTitle(runtime), cwd: found.cwd, link: `?history=${key}${at}` });
  store.insertMessage({ thread: thread.id, ts: hub.nextTs(), authorKind: STATION_AUTHOR, author: STATION_AUTHOR, text: note });
  store.setRead(createdBy, thread.id, store.lastEntry(thread.id));
  return [key, thread];
}
