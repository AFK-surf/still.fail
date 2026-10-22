// The official site's demo: the real app (a workspace's pages), in a part of the page (site/Site.tsx's demo box), on a made-up core — no
// worker, no station. story.ts plays a few chats in it; the visitor can click around and send messages too.
import { GoKeeper } from "../go.ts";
import "./demo.css.ts";
import "../viewer/whole.ts";
import { startScrollbars } from "../scrollbars.ts";
import { StrictMode, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import { MemoryRouter, Route, Routes, useLocation, useNavigate } from "react-router";
import "@fontsource-variable/inter";
import { setPageRoot } from "../brand.tsx";
import { withoutDownloads } from "../downloads.ts";
import { Tooltip } from "radix-ui";
import { ToastProvider } from "@stillfail/ui/toast.tsx";
import { MobileWorkspace } from "../mobile/index.tsx";
import { WorkspaceShell, type WorkspaceEntry } from "../cloud/workspace.tsx";
import { CoreClient, CoreError, type Topic } from "../core/client.ts";
import type { ModelOption } from "../api.ts";
import type { ChatItem, ChatMessage, ComposerLink, SearchView, ShareInView } from "../core/shapes.ts";
import { setCore, setTopicSource } from "../core/react.ts";
import { addItem, agentCardView, chatView, newChat, received, VISITOR, chatsView, historyView, liveView, marked, message, outgoing, SAFARI_KEY, STATION } from "./fixtures.ts";
import { makeStory, openingChats } from "./story.ts";
import { RealStillFail, askForReal } from "./real.tsx";
import * as station from "./station.ts";
import * as fonts from "../../../client/core-ts/src/fonts.ts";
import { followFonts } from "../fonts.ts";
import { markdown } from "../../../client/core-ts/src/markdown.ts";
import { inkKept } from "../../../client/core-ts/src/highlight.ts";

/** The demo's box; the app is drawn in a box of its own inside it (the buddy goes beside it: setPageRoot). */
let root: HTMLElement;
/** The visitor has clicked in the demo: from then on it is theirs (the story stops moving between chats). */
let touched = false;
let mounted = false;

// ---- The core ----


const chats = openingChats();
const subs = new Map<number, Topic>();
/** The calls under way, to cancel. */
const under = new Map<number, AbortController>();
let post: (message: unknown) => void = () => undefined;

/**
 * What a page that is not the site adds to the made-up core (web/stories: the data a story shows), asked before the
 * demo's own: a topic's value or a call's answer, undefined for the demo's. The site adds none.
 */
export interface DemoExtension {
  /** A `CoreError` instead: the topic fails as the core would say (a cloud from before without it, say). */
  topic?(topic: Topic): unknown;
  /** The demo's own value for a topic, changed (or undefined: as it is). */
  then?(topic: Topic, value: unknown): unknown;
  call?(name: string, params: Record<string, unknown>): unknown;
  /**
   * A call that says how far it has got as it goes (a screen view's states and frames): `emit` each value, with its bytes
   * beside it; the answer once it is over. `signal` aborts as the page cancels it. Undefined for the demo's.
   */
  stream?(name: string, params: Record<string, unknown>, emit: (value: unknown, bytes?: Uint8Array) => void, signal: AbortSignal): Promise<unknown> | undefined;
}
const extensions: DemoExtension[] = [];
export function extendDemo(extension: DemoExtension): void { extensions.push(extension); }

function valueOf(topic: Topic): unknown {
  for (const e of extensions) { const v = e.topic?.(topic); if (v !== undefined) return v; }
  let value = demoValueOf(topic);
  for (const e of extensions) { const v = e.then?.(topic, value); if (v !== undefined) value = v; }
  return value;
}

function demoValueOf(topic: Topic): unknown {
  const chat = "key" in topic ? chats.find((c) => c.key === topic.key) : "session" in topic ? chats.find((c) => c.key === topic.session) : undefined;
  switch (topic.topic) {
    case "overview": return station.overview();
    case "status": return { items: [] };
    case "connection": return { items: [] };
    // What the visitor chose (prefs.set, below): the defaults till then (the core's shape leaves them out).
    case "prefs": return { ...prefs, fonts: fonts.chosen(prefs.fonts), faces: fonts.shown(prefs.fonts) };
    case "doing": return { doing: [] };
    // What is written stays the page's here (draft.ts shows what it did), but for what was shared into a chat.
    case "composer": return composerView(String(topic.key ?? ""));
    case "chats": return chatsView(chats);
    case "chat": return chat ? chatView(chat, station.runs()) : null;
    case "slackApp": return station.slackApp();
    case "live": return chat ? liveView(chat) : null;
    case "history": return chat ? historyView(chat) : null;
    case "agentCard": return chat ? agentCardView(chat) : null;
    case "host": return station.host();
    case "stationNet": return station.NET;
    case "connects": return station.connects();
    case "stations": return [station.stationView()];
    case "archive": return station.archive(topic.q, topic.limit);
    case "profiles": return station.profiles();
    case "usage": return station.usage(topic.days ?? 7);
    case "decisions": return station.decisions(chats);
    case "drive": return station.driveFolder(topic.root, topic.path);
    case "drivePlace": return null;
    // A station's screens: none here (the stories add theirs).
    case "screens": return null;
    // What the core puts together of them (client/core-ts/src/choose.ts), as a new chat and a model control start.
    case "newChat": return newChatView();
    case "pick": return pickView(topic.of);
    case "shareIn": return shareInView(String(topic.source ?? ""), String(topic.query ?? ""));
    case "search": return searchView(String(topic.query ?? ""), typeof topic.kind === "string" ? topic.kind : null);
    // still.fail cloud's, for the phone's workspace pages (mobile/).
    case "accounts": return [station.ACCOUNT];
    case "workspaces": return station.workspaces();
    case "workspace": return station.workspace();
    case "loginSessions": return station.loginSessions();
    default:
      if (import.meta.env.DEV) console.warn("demo: no topic", topic);
      return null;
  }
}

/** A new chat on the demo's station, on its first model. */
function newChatView(): unknown {
  const s = station.stationView();
  const m = (s.models as unknown as ModelOption[])[0];
  const runtime = m?.runtimes[0];
  return {
    kept: s.id, stations: [s], any: true, station: s, model: m, runtime, efforts: runtime ? m.efforts[runtime] ?? [] : [],
    accounts: runtime ? m.accounts[runtime] ?? [] : [], pickAccount: false, waiting: false,
  };
}

/** A model control with nothing picked: a new chat's (on the first model), or an agent's (on its own). */
function pickView(of: string): unknown {
  const s = station.stationView();
  const chat = of.startsWith("session:") ? chats.find((c) => c.key === of.slice(8)) : undefined;
  const runs = station.runs();
  const options = chat ? (chat.model.runtime === "claude" ? runs.choices : []) : s.models as unknown as ModelOption[];
  const m = chat ? options.find((o) => o.model === chat.model.model) : options[0];
  const runtime = chat?.model.runtime ?? m?.runtimes[0] ?? "claude";
  const value = { model: chat?.model.model ?? m?.model, runtime, ...(chat ? { effort: chat.model.effort } : {}) };
  const on = chat && runtime === "claude" ? { id: runs.profile.id, name: runs.profile.name, current: true, kind: runs.profile.access.kind, runtime, ...(runs.profile.quota ? { quota: runs.profile.quota } : {}) } : undefined;
  return {
    options, runtimeFixed: !!chat, value, valueOption: m, draft: value, option: m?.model, runtimes: [], efforts: m?.efforts[runtime] ?? [],
    accounts: m?.accounts[runtime] ?? [], ...(on ? { account: { text: `自动 · ${on.name}`, auto: true, profile: on } } : {}),
    who: "账号", autoNote: on ? `现在是 ${on.name}` : "额度用完或登录失效时自动切换", changed: false, was: [], becomes: [],
    modelText: m?.name ?? "", accountText: "自动分配", accountNote: "额度用完或登录失效时自动切换", accountWarn: false, saveText: "无变更",
  };
}

/**
 * What another app shares (client/core-ts/src/share-in.ts), as the core puts it together of the demo's chats: those on
 * the page newest first (not a Slack chat), those whose title has what is typed, the one the same site's things went
 * to last first; the one station for a new chat. `shareIn.open` puts it in that chat's composer (below).
 */
const shareKept = new Map<string, string>();
/** The site of the first link in what is shared (`youtube.com`), as the core reads it (short hosts aside). */
const siteOf = (source: string): string | null => {
  const link = /https?:\/\/[^\s<>"']+/i.exec(source)?.[0];
  try { return link ? new URL(link).hostname.toLowerCase().replace(/^(www|m|mobile)\./, "") : null; } catch { return null; }
};
function shareRows(): ChatItem[] {
  return chatsView(chats).days.flatMap((d) => d.items).filter((i) => !i.connect && !i.originText);
}
function shareInView(source: string, query = ""): ShareInView {
  const site = siteOf(source);
  const q = query.trim().toLowerCase();
  // What is typed finds them by title, as the core's search does first.
  const rows = shareRows().filter((r) => !q || r.title.toLowerCase().includes(q));
  const kept = rows.find((r) => r.id === shareKept.get(site ?? ""));
  return {
    ...(site ? { site } : {}), items: (kept ? [kept, ...rows.filter((r) => r !== kept)] : rows).slice(0, 30),
    ...(kept ? { kept: { station: kept.station, id: kept.id, text: site ? `${site} 的链接上次发到这里` : "上次分享的文字发到这里" } } : {}),
    stations: [{ station: STATION, name: "Studio" }], newOn: STATION, loading: false,
  };
}

/** Where the first of the words is in a line found, as the core marks it. */
function marks(text: string, q: string): { from: number; to: number }[] {
  const at = text.toLowerCase().indexOf(q);
  return at < 0 ? [] : [{ from: at, to: at + q.length }];
}

/**
 * ⌘K's and the phone's search (the core's `search`, docs/search.md): the chats whose title has the words, and what the
 * station finds besides, made up from them (a file, a service, a member) so every kind shows.
 */
function searchView(query: string, kind: string | null): SearchView {
  const all = chatsView(chats).days.flatMap((d) => d.items);
  const q = query.trim().toLowerCase();
  const wait = { reading: false, failing: [], empty: false };
  if (!q) return { items: all.slice(0, 30), wait };
  const items = all.filter((i) => i.title.toLowerCase().includes(q));
  const first = items[0] ?? all[0];
  const where = { station: first?.station ?? STATION, stationName: first?.stationName ?? "Studio" };
  const said = (text: string) => ({ text, marks: marks(text, q) });
  const of = (c: ChatItem | undefined) => (c ? { chat: c.id, chatTitle: c.title } : {});
  const groups: NonNullable<SearchView["groups"]> = [
    { kind: "file", title: "文件", more: true, items: [
      { kind: "file", key: "f1", ...where, title: `${q}-notes.md`, ...said(`~/Documents/${q}`), path: `/Users/me/Documents/${q}/${q}-notes.md`, dir: false, fileKind: "markdown", size: 2048, sizeText: "2 KB", createdAt: Date.now() - 7_200_000 },
      { kind: "file", key: "f2", ...where, title: q, ...said("~/WebstormProjects"), path: `/Users/me/WebstormProjects/${q}`, dir: true, fileKind: "folder", createdAt: Date.now() - 172_800_000 },
    ] },
    { kind: "job", title: "服务和任务", more: false, items: [
      { kind: "job", key: "j1", ...where, title: `${q} 预览`, ...said(`pnpm dev --port 5173 · ${q}`), ...of(first), job: "j1", port: 5173 },
    ] },
    { kind: "member", title: "成员", more: false, items: [
      { kind: "member", key: "m1", station: "", stationName: "", title: `${q} 组 · 林`, ...said(`lin@example.com`), email: "lin@example.com" },
    ] },
  ];
  const shown = kind ? groups.filter((g) => g.kind === kind) : groups;
  return {
    items: kind && kind !== "chat" ? [] : items.slice(0, kind ? 50 : 8), chatsMore: !kind && items.length > 8, words: [q],
    groups: kind === "chat" ? [] : shown.map((g) => ({ ...g, more: !kind && g.more })), wait, note: "MacBook Air 离线，其上的内容未搜索",
  };
}

/**
 * What is written in a chat, where the core put words of its own (what is shared, `shareIn.open`): the rest of the
 * demo's composers are the page's alone (`composer` answers null for them).
 */
const composers = new Map<string, { text: string; rev: number; version: number; links: ComposerLink[] }>();
function composerView(key: string): unknown {
  const c = composers.get(key);
  if (!c) return null;
  const files = c.links.map((link, i) => ({ id: `link-${i}`, name: link.title || link.url, size: 0, done: null, error: null, link }));
  return { text: c.text, rev: c.rev, version: c.version, quotes: [], files, uploading: false, ready: c.text.trim() !== "" || files.length > 0, starting: false };
}
/**
 * `shareIn.open`, as the core splits what is shared (share-in.ts splitShared): its first link an attachment (the app's
 * title its title, else the short words before it), the words around it after what the composer holds; each once.
 */
function shareOpen(source: string, station: string, id: string | undefined, title: string | undefined, newKey?: string): unknown {
  const m = /https?:\/\/[^\s<>"'）)】」]+/i.exec(source);
  const tt = title?.trim() ?? "";
  const rest = m ? (source.slice(0, m.index) + source.slice(m.index + m[0].length)).trim() : source;
  const naming = !!m && rest !== "" && !rest.includes("\n") && rest.length <= 120 && (tt === "" || rest === tt);
  const link: ComposerLink | null = m ? { url: m[0], ...(tt || naming ? { title: tt || rest } : {}), ...(siteOf(m[0]) ? { site: siteOf(m[0])! } : {}) } : null;
  const words = m ? (naming || rest === tt ? "" : rest) : tt && !source.includes(tt) ? `${tt}\n${source}` : source;
  const row = id === undefined ? undefined : shareRows().find((r) => r.station === station && r.id === id);
  const key = row ? `${station}:${row.session}` : newKey ?? `new:${station}`;
  const c = composers.get(key) ?? { text: "", rev: 0, version: 0, links: [] };
  const text = words && !c.text.includes(words) ? (c.text.trim() ? `${c.text.trimEnd()}\n${words}` : words) : c.text;
  const links = link && !c.links.some((l) => l.url === link.url) ? [...c.links, link] : c.links;
  composers.set(key, { text, rev: text === c.text ? c.rev : c.rev + 1, version: c.version + 1, links });
  if (row) shareKept.set(siteOf(source) ?? "", row.id);
  setTimeout(publish, 0);
  return row ? { station, key, session: row.session, thread: row.thread, title: row.title } : { station, key };
}

// Every topic starts at its value: the first render shows the demo at once (and so does the site built to HTML). One
// that fails is loading until its error comes.
setTopicSource((topic) => { const v = valueOf(topic); return v instanceof CoreError ? undefined : v; });

/** A topic's value as the core sends it, or its error. */
function said(id: number, topic: Topic): unknown {
  const v = valueOf(topic);
  return v instanceof CoreError ? { id, error: { code: v.code, message: v.message, ...(v.status !== undefined ? { status: v.status } : {}) } } : { id, value: v };
}

function publish() {
  for (const [id, topic] of subs) post(said(id, topic));
}

// What the visitor sends is answered as an account its provider has banned would be: the turn fails, still.fail says why in
// the chat, and the agent is marked failed — the station's own words (session.rs failure_notice, quota.rs).
const BANNED = `⚠️ 认证失败，需要管理员检查账号：${station.BAN_DETAIL}`;

/** The prefs as the visitor set them here (the sidebar's list, …), kept for the page's life as a core keeps them. */
const prefs: Record<string, unknown> = {};

/** A message no longer asking anything of the viewer. */
const withoutAsked = ({ asked: _, ...m }: ChatMessage): ChatMessage => m;

function answer(name: string, params: Record<string, unknown>, emit: (value: unknown, bytes?: Uint8Array) => void = () => undefined, signal: AbortSignal = new AbortController().signal): unknown {
  for (const e of extensions) { const v = e.stream?.(name, params, emit, signal); if (v !== undefined) return v; }
  for (const e of extensions) { const v = e.call?.(name, params); if (v !== undefined) return v; }
  if (name === "markdown") return { md: markdown(String(params.text ?? "")) };
  if (name === "code.ink") return { ink: inkKept(String(params.code ?? ""), String(params.lang ?? "")) };
  if (name === "prefs.set") {
    for (const [field, value] of Object.entries(params)) {
      const before = prefs[field];
      if (value !== null && typeof value === "object" && !Array.isArray(value) && before && typeof before === "object") prefs[field] = { ...before, ...value };
      else if (value === null) delete prefs[field];
      else prefs[field] = value;
    }
    setTimeout(publish, 0);
    return null;
  }
  if (name === "shareIn.open" && typeof params.source === "string") {
    return shareOpen(params.source, String(params.station), params.id as string | undefined, params.title as string | undefined, typeof params.key === "string" && params.key.startsWith("new:") ? params.key : undefined);
  }
  // Words typed into a composer the core has words in (what was shared): kept with them.
  const written = name === "composer.text" ? composers.get(String(params.key)) : undefined;
  if (written && typeof params.text === "string") {
    written.text = params.text;
    written.version++;
    return { version: written.version };
  }
  // Taken to send: the page's own again.
  if (name === "composer.take") composers.delete(String(params.key));
  // A link taken out: the rest as it is.
  const holding = name === "composer.remove" ? composers.get(String(params.key)) : undefined;
  if (holding && typeof params.id === "string" && params.id.startsWith("link-")) {
    holding.links = holding.links.filter((_, i) => `link-${i}` !== params.id);
    holding.version++;
    setTimeout(publish, 0);
    return { version: holding.version };
  }
  if (name === "chat.create" || name === "newChat.create") {
    // 新建对话: made at once, under the key answered; what is sent to it follows.
    const made = newChat(Math.max(...chats.map((c) => c.thread)) + 1, typeof params.model === "string" ? params.model : undefined);
    made.title = "新对话";
    chats.push(made);
    setTimeout(publish, 0);
    return { key: made.key, runtime: made.model.runtime, model: made.model.model };
  }
  // Picks change nothing here.
  if (name === "newChat.pick" || name === "newChat.migrate" || name === "pick.set") return null;
  if (name === "pick.save") return { saved: false };
  // Drafts (draft.ts) are the core's: none kept here, as a core answers for a chat nothing was written in (null, not an
  // object without text, quotes and files).
  if (name === "draft.get" || name === "draft.put" || (name.startsWith("composer.") && name !== "composer.add")) return null;
  // A station's files named by their paths send nothing up: they stay as the page shows them.
  if (name === "composer.add" && Array.isArray(params.files) && params.files.every((f: { ref?: { mode?: string } }) => f.ref?.mode === "path")) return null;
  // Its chats are whole, never a window short of their end: nothing to move along, nowhere to keep a place.
  if (name === "chat.newer" || name === "chat.latest" || name === "chat.place" || name === "chat.around") return name === "chat.newer" ? { more: false } : null;
  if (name === "chat.find") return { words: [], hits: [], held: 0, of: 0, whole: true };
  const chat = chats.find((c) => c.thread === params.thread || c.key === params.session);
  // A card's option picked: its label sent, quoting the post, as the core sends it (and the card answered at once).
  if (name === "decision.answer" && chat && typeof params.option === "string") {
    answer("chat.send", { thread: chat.thread, text: params.option, chose: params.option });
    return null;
  }
  // Let go of here: not asked any more (its options still there).
  if (name === "decision.dismiss" && chat) {
    chat.messages = chat.messages.map((m) => (m.seq === params.seq ? withoutAsked(m) : m));
    setTimeout(publish, 0);
    return null;
  }
  if (name === "chat.send" && chat && typeof params.text === "string" && params.text.trim()) {
    const text = params.text;
    story.end(chat.key);
    // What is sent answers the card still waiting, at once, as the core has it (decisions.ts inMessages).
    const chose = typeof params.chose === "string" ? params.chose : undefined;
    chat.messages = chat.messages.map((m) => (m.decision && !m.decision.resolved
      ? { ...withoutAsked(m), decision: { resolved: true, answeredBy: "你", ...(chose ? { chosen: chose, text: `你 选了「${chose}」` } : { text: "你 回复了" }) } }
      : m));
    // As the core does: on its way at once (the outbox), then the station's own copy in its place, taken by the agent.
    chat.outbox = [outgoing(text)];
    // A new chat takes its first message's words as its title, as a station does.
    if (chat.messages.length === 0) chat.title = text.slice(0, 30);
    chat.failed = false;
    setTimeout(publish, 0);
    setTimeout(() => {
      chat.outbox = [];
      chat.messages = [...chat.messages, message(chat, "me", text)];
      addItem(chat, received(chat, VISITOR, text));
      publish();
    }, 450);
    setTimeout(() => {
      chat.running = { activity: "思考中", since: chat.running?.since ?? Date.now(), started: chat.running?.started ?? true };
      publish();
    }, 800);
    setTimeout(() => {
      chat.running = null;
      chat.blocked = false;
      chat.failed = true;
      chat.messages = [...chat.messages, message(chat, "ember", BANNED)];
      addItem(chat, marked("失败：账号被停用"));
      publish();
    }, 2600);
  }
  // What reaches past the demo is offered in a real still.fail instance instead, and fails here as not done.
  try {
    if (name === "station.upload" || name === "station.upload.part" || name === "composer.add" || name.startsWith("auth.")) throw new station.NeedsReal();
    // still.fail cloud's operations (ops.ts: by the account they go as): every one would reach out.
    if ("account" in params) throw new station.NeedsReal();
    if (typeof params.station === "string") return station.op(name);
  } catch (e) {
    if (e instanceof station.NeedsReal) askForReal();
    throw e;
  }
  return { more: false };
}

setCore(new CoreClient((onMessage) => {
  post = (message) => queueMicrotask(() => onMessage(message));
  return {
    post(raw) {
      const message = raw as { id: number; subscribe?: Topic; unsubscribe?: boolean; call?: string; params?: Record<string, unknown>; cancel?: boolean };
      if (message.subscribe) {
        subs.set(message.id, message.subscribe);
        post(said(message.id, message.subscribe));
      } else if (message.unsubscribe) {
        subs.delete(message.id);
      } else if (message.cancel) {
        under.get(message.id)?.abort();
      } else if (message.call) {
        // Under way until answered: a streamed call says how far it has got (its values, their bytes beside them).
        const abort = new AbortController();
        under.set(message.id, abort);
        const emit = (value: unknown, bytes?: Uint8Array) => post({ id: message.id, value, ...(bytes ? { bytes } : {}) });
        void Promise.resolve()
          .then(() => answer(message.call!, message.params ?? {}, emit, abort.signal))
          .then(
            // Bytes an answer gives (`bytes`, a file read) beside it, as the core gives them.
            (ok) => {
              const { bytes, ...rest } = (ok ?? {}) as { bytes?: unknown };
              post(bytes instanceof Uint8Array ? { id: message.id, ok: rest, bytes } : { id: message.id, ok });
            },
            (e: Error & { code?: string }) => post({ id: message.id, error: { code: e instanceof station.NeedsReal ? "demo" : e.code ?? "internal", message: e.message } }),
          )
          .finally(() => under.delete(message.id));
      }
    },
    close() {},
  };
}));

// ---- The story ----

let navigate: ((key: string) => void) | null = null;
/** The chat the story last opened: where either app opens. */
let opened = SAFARI_KEY;
const navigateTarget = () => opened;
const story = makeStory({
  chats,
  publish,
  open(key) {
    if (touched) return;
    opened = key;
    navigate?.(key);
  },
});
/** Lets the story open chats: a chat's address, the same in the desktop's app and the phone's. */
function Director() {
  const go = useNavigate();
  const here = useLocation().pathname;
  useEffect(() => {
    navigate = (key) => {
      const to = chatPath(key);
      // Already there (the chat either app opens on): not again, or going back would land on it once more.
      if (decodeURIComponent(to) !== decodeURIComponent(here)) void go(to);
    };
    return () => {
      navigate = null;
    };
  }, [go, here]);
  return null;
}

// ---- Wide and narrow ----

/** The made-up workspace, as the workspace's pages take it. */
const ENTRY: WorkspaceEntry = { id: station.WORKSPACE, name: "Acme", account: station.ACCOUNT };
/** A chat's page, by its key. */
const chatPath = (key: string) => `/w/${ENTRY.id}/s/local/chats/${encodeURIComponent(key)}`;
/** The demo's own width (not the window's) says which app it is: the phone's below this, as mobile/ is for phones. */
const PHONE_BELOW = 700;

function useDemoWidth(): number {
  const [width, setWidth] = useState(() => root.clientWidth);
  useEffect(() => {
    const observer = new ResizeObserver(() => setWidth(root.clientWidth));
    observer.observe(root);
    return () => observer.disconnect();
  }, []);
  return width;
}

function Demo() {
  return <DemoApp phone={useDemoWidth() < PHONE_BELOW} />;
}

/** The demo as the phone's app or the desktop's, opened on the chat in view (so switching between them keeps it). */
export function DemoApp({ phone }: { phone: boolean }) {
  const key = navigateTarget();
  // As still.fail cloud's app has them (cloud/CloudApp.tsx): the phone's pages, or the desktop's.
  return (
    <ToastProvider>
      <Tooltip.Provider delayDuration={400}>
        <MemoryRouter key={phone ? "phone" : "wide"} initialEntries={[`/w/${ENTRY.id}`, chatPath(key)]} initialIndex={1}>
          <Director />
          <GoKeeper />
          <Routes><Route path="/w/:ws/*" element={phone ? <MobileWorkspace entry={ENTRY} /> : <WorkspaceShell entry={ENTRY} />} /></Routes>
          <RealStillFail />
        </MemoryRouter>
      </Tooltip.Provider>
    </ToastProvider>
  );
}

/** The made-up core's chats, and telling the page they changed: for the browser checks (test/browser), which play
 * what a station would say into a chat. */
export const demoCore = { chats, publish };

/** Runs the demo in `element` (once): the app, its made-up core, and the story played when it comes into view. */
/** The demo's chats stop where they are, nobody at work any more (the stories' tests, to look at a page that holds still). */
export function endDemo(): void {
  story.end();
}

export function mountDemo(element: HTMLElement): void {
  if (mounted) return;
  mounted = true;
  root = element;
  // What the page was built with (its opening frame, as HTML) gives way to the demo itself.
  root.replaceChildren();
  setPageRoot(root);
  withoutDownloads();
  const app = root.appendChild(document.createElement("div"));
  app.style.height = "100%";
  startScrollbars();
  followFonts();

  // The app is made to be the whole page; here it is a part of one. Keys pressed elsewhere on the page are the page's
  // (space scrolls it rather than going to the composer), and nothing in it takes the focus, or scrolls the page to
  // itself, until the visitor has clicked in it.
  for (const type of ["keydown", "keyup", "keypress"]) {
    window.addEventListener(type, (event) => {
      // The app's own dialogs and menus are on the page, not in the demo's box: keys there are the app's too.
      const target = event.target;
      const app = target instanceof Element && (root.contains(target) || target.closest("[role=dialog], [role=menu], [data-radix-popper-content-wrapper]"));
      if (!app) event.stopImmediatePropagation();
    }, true);
  }
  const focus = HTMLElement.prototype.focus;
  HTMLElement.prototype.focus = function (options?: FocusOptions) {
    if (root.contains(this) && !touched) return;
    focus.call(this, { ...options, preventScroll: true });
  };
  // A link out of the demo (Slack, a web service, an app's settings) opens nothing: it too needs a real still.fail instance. Only the
  // app's own links count, in its box or its dialogs and menus on the page; the page's own, and the note's, go.
  const inApp = (el: Element) => !el.closest("[data-real-stillfail]") && (root.contains(el) || !!el.closest("[role=dialog], [role=menu], [data-radix-popper-content-wrapper]"));
  document.addEventListener("click", (event) => {
    const link = event.target instanceof Element ? event.target.closest<HTMLAnchorElement>("a[href]") : null;
    if (!link || !inApp(link)) return;
    const to = new URL(link.href, location.href);
    if (to.origin === location.origin && link.target !== "_blank") return;
    event.preventDefault();
    event.stopPropagation();
    askForReal();
  }, true);
  window.open = () => {
    askForReal();
    return null;
  };
  root.addEventListener("pointerdown", () => {
    touched = true;
    story.stop();
  }, true);

  // Played once the demo is seen: most of it in view, and not before the site's opening (its title's motion, which
  // tells when it is done; a page without it has none) has handed over to it.
  const opened = document.documentElement.dataset.motion === undefined ? Promise.resolve() : new Promise<void>((done) => {
    window.addEventListener("stillfail-site-opened", () => done(), { once: true });
    setTimeout(done, 8000);
  });
  void opened.then(() => new IntersectionObserver((entries, observer) => {
    if (!entries.some((e) => e.isIntersecting)) return;
    observer.disconnect();
    void story.play();
  }, { threshold: 0.6 }).observe(root));

  createRoot(app).render(
    <StrictMode>
      <Demo />
    </StrictMode>,
  );
}
