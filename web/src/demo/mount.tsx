// The official site's demo: the real app (a workspace's pages), in a part of the page (site/Site.tsx's demo box), on a made-up core — no
// worker, no station. story.ts plays a few chats in it; the visitor can click around and send messages too.
import { GoKeeper } from "../go.ts";
import "./demo.css.ts";
import "../viewer/whole.ts";
import { startScrollbars } from "../scrollbars.ts";
import { StrictMode, useEffect, useState } from "react";
import { flushSync } from "react-dom";
import { createRoot, hydrateRoot } from "react-dom/client";
import { MemoryRouter, Route, Routes, useLocation, useNavigate } from "react-router";
import "@fontsource-variable/inter";
import { t } from "../i18n.ts";
import { withoutDownloads } from "../downloads.ts";
import { Tooltip } from "radix-ui";
import { ToastProvider } from "@stillfail/ui/toast.tsx";
import { MobileWorkspace } from "../mobile/index.tsx";
import { WorkspaceShell, type WorkspaceEntry } from "../cloud/workspace.tsx";
import { CoreClient, CoreError, type Topic } from "../core/client.ts";
import type { ModelOption } from "../api.ts";
import type { ChatItem, ChatMessage, ChatView, ComposerLink, DriveFolder, SearchView, ShareInView, StationView } from "../core/shapes.ts";
import { setCore, setTopicSource } from "../core/react.ts";
import { addItem, agentCardView, chatView, newChat, received, VISITOR, chatsView, historyView, liveView, marked, message, outgoing, SAFARI_KEY, STATION } from "./fixtures.ts";
import { makeStory, openingChats } from "./story.ts";
import { RealStillFail, askForReal } from "./real.tsx";
import * as station from "./station.ts";
import { inEnglish } from "./english.ts";
import * as fonts from "../../../client/core-ts/src/fonts.ts";
import { railView } from "../../../client/core-ts/src/rail.ts";
import { deviceLocale, langOf } from "../i18n.ts";
import { changed, tabsOf } from "../../../client/core-ts/src/chat-tabs.ts";
import { followFonts } from "../fonts.ts";
import { markdown } from "../../../client/core-ts/src/markdown.ts";
import * as keymap from "../../../client/core-ts/src/keymap.ts";
import { inkKept } from "../../../client/core-ts/src/highlight.ts";
import { bookAnswer, keepBook, keptBook, searchBook } from "../../../client/core-ts/src/reader.ts";
import { find as findCommands } from "../../../client/core-ts/src/commands.ts";
import { openOf } from "../../../client/core-ts/src/search-open.ts";
import { Browsing, CALLS as BROWSE_CALLS, withDrive } from "../../../client/core-ts/src/drive-browse.ts";
import { collate } from "../../../client/core-ts/src/hosts/collate.ts";

/** The demo's box; the app is drawn in a box of its own inside it. */
let root: HTMLElement;
/** The visitor has clicked in the demo: from then on it is theirs (the story stops moving between chats). */
let touched = false;
let mounted = false;

// ---- The core ----


const chats = openingChats();
const subs = new Map<number, Topic>();
/** Every topic the page has subscribed to, by its JSON (demoTape). */
const seen = new Map<string, Topic>();
/** The calls under way, to cancel. */
const under = new Map<number, AbortController>();
let post: (message: unknown) => void = () => undefined;

/**
 * What a page that is not the site adds to the made-up core (web/stories: the data a story shows), asked before the
 * demo's own: a topic's value or a call's answer, undefined for the demo's. The site adds none.
 */
export interface DemoExtension {
  /**
   * A `CoreError` instead: the topic fails as the core would say (a cloud from before without it, say); `HELD`: it is
   * never answered, as one the core is still reading (its page waiting).
   */
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
/** A topic an extension holds (`topic`): the core says nothing of it yet. */
export const HELD = Symbol("held");
export function extendDemo(extension: DemoExtension): void { extensions.push(extension); }

function valueOf(topic: Topic): unknown {
  const made = extendedValueOf(topic);
  // On the site's English page, what the demo makes up is said in English too (english.ts), the agents' prose before
  // it is read as Markdown (so that what is read is what is shown).
  return withProse(topic, language === "en" && made !== HELD ? inEnglish(made) : made);
}

function withProse(topic: Topic, value: unknown): unknown {
  if (topic.topic !== "chat" || !value || value instanceof CoreError || value === HELD) return value;
  const chat = value as ChatView;
  // Like the real core, send prose with the message, before the row's first layout. Stories may change its words
  // in an extension: read the final text, so the source offsets and the tree always describe those same words.
  return { ...chat, messages: chat.messages.map((m) => m.authorKind === "agent" ? { ...m, md: markdown(m.text) } : m) };
}

function extendedValueOf(topic: Topic): unknown {
  for (const e of extensions) { const v = e.topic?.(topic); if (v !== undefined) return v; }
  let value = demoValueOf(topic);
  for (const e of extensions) { const v = e.then?.(topic, value); if (v !== undefined) value = v; }
  // Those with a drive, this machine's first, as the core gives them.
  if (topic.topic === "stations" && topic.drive && Array.isArray(value)) return withDrive(value as StationView[], topic.here ?? null);
  return value;
}

/** How the station's files are browsed here: as the core does it (drive-browse.ts), on what the demo has. */
const browsing = new Browsing({
  prefs: () => prefs,
  countText: (folders, files, hiddenOnly) => {
    const parts = [folders ? t("web-pages.drive.rootsCount", { n: folders }) : "", files ? t("web-pages.files.filesCount", { n: files }) : ""].filter(Boolean);
    return parts.length ? parts.join(" · ") : t(hiddenOnly ? "web-pages.drive.noVisible" : "web-pages.drive.emptyFolder");
  },
  // Names in the order the page's language reads them, as the core's web host has them.
  collate,
  setPrefs: (patch) => void answer("prefs.set", patch),
  entries: (at, root, path) => {
    const folder = extendedValueOf({ topic: "drive", station: at, root, path }) as DriveFolder | null;
    return folder && !(folder instanceof CoreError) ? folder.entries : null;
  },
  stations: (scope) => ((extendedValueOf({ topic: "stations", scope }) ?? []) as StationView[])
    .flatMap((s) => (s.overview?.drive ? [{ station: s.station, name: s.name, home: s.overview.drive.home ?? null }] : [])),
  now: () => Date.now(),
  newId: () => Math.random().toString(36).slice(2, 10),
  invalid: (what) => new Error(what),
  changed: () => { setTimeout(publish, 0); },
});

function demoValueOf(topic: Topic): unknown {
  const chat = "key" in topic ? chats.find((c) => c.key === topic.key) : "session" in topic ? chats.find((c) => c.key === topic.session) : undefined;
  switch (topic.topic) {
    case "overview": return station.overview();
    case "status": return { items: [] };
    case "connection": return { items: [] };
    // What the visitor chose (prefs.set, below): the defaults till then (the core's shape leaves them out).
    case "prefs": {
      // The rail's words in the language the app takes from these (i18n.ts): the visitor's choice in it, else the demo's,
      // else the browser's.
      const view = { ...(language ? { lang: language } : {}), ...prefs };
      return { ...view, fonts: fonts.chosen(prefs.fonts), faces: fonts.shown(prefs.fonts), keymap: keymap.view({ ...prefs, device: DEVICE }), railView: railView(prefs, langOf(typeof view.lang === "string" ? view.lang : deviceLocale())) };
    }
    case "doing": return { doing: [] };
    // What is written stays the page's here (draft.ts shows what it did), but for what was shared into a chat.
    case "composer": return composerView(String(topic.key ?? ""));
    case "chats": return chatsView(chats);
    case "chat": return chat ? withTabs(chatView(chat, station.runs()), `${String(topic.station)}:${chat.key}`, chat.key) : null;
    case "slackApp": return station.slackApp();
    case "live": return chat ? liveView(chat) : null;
    case "history": return chat ? historyView(chat) : null;
    case "agentCard": return chat ? agentCardView(chat) : null;
    case "host": return station.host();
    case "stationNet": return start === "stations" && typeof topic.station === "string" ? station.netOf(topic.station) : station.NET;
    case "connects": return station.connects();
    // The site's page that shows the workspace's machines together has them all; elsewhere the chats' one.
    case "stations": return start === "stations" ? station.stationViews() : [station.stationView()];
    case "archive": return station.archive(topic.q, topic.limit);
    case "profiles": return station.profiles();
    case "vaults": return station.vaults();
    case "vaultItems": return station.vaultItems();
    case "vaultUses": return { item: String(topic.item ?? ""), uses: [] };
    case "usage": return station.usage(topic.days ?? 7);
    case "resources": return station.resources();
    case "drive": return station.driveFolder(topic.root, topic.path);
    case "memory": return station.op("memory.get");
    // (the demo reaches no page: nothing to show of a link but where it goes)
    case "linkPreview": return { kind: "none" };
    // (nor a machine's files: as its station's op, it needs a real one)
    case "filePeek": return station.op("file.peek");
    case "drivePlace": return null;
    case "driveBrowse": return browsing.view(topic);
    case "filesTabs": return browsing.tabsView(topic.workspace);
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
  // Each says where it opens, as the core says it (search-open.ts).
  const shown = (kind ? groups.filter((g) => g.kind === kind) : groups).map((g) => ({ ...g, items: g.items.map((i) => {
    const open = openOf(i);
    return open ? { ...i, open } : i;
  }) }));
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
  const key = row ? `${station}:${row.session}` : newKey ?? `new:${station.split("/")[0]}`;
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
setTopicSource((topic) => { const v = valueOf(topic); return v instanceof CoreError || v === HELD ? undefined : v; });

/** A topic's value as the core sends it, or its error; null while it is held. */
function said(id: number, topic: Topic): unknown {
  const v = valueOf(topic);
  if (v === HELD) return null;
  return v instanceof CoreError ? { id, error: { code: v.code, message: v.message, ...(v.status !== undefined ? { status: v.status } : {}) } } : { id, value: v };
}

function publish() {
  for (const [id, topic] of subs) { const m = said(id, topic); if (m) post(m); }
}

// What the visitor sends is answered as an account its provider has banned would be: the turn fails, still.fail says why in
// the chat, and the agent is marked failed — the station's own words (session.rs failure_notice, quota.rs).
const BANNED = `⚠️ 认证失败，需要管理员检查账号：${station.BAN_DETAIL}`;

/** The prefs as the visitor set them here (the sidebar's list, …), kept for the page's life as a core keeps them. */
const prefs: Record<string, unknown> = {};
/** This device as a core told it would have it (prefs.ts device): what its keymap goes by. */
const DEVICE = { app: "web", mac: /Mac|iPhone|iPad/.test(navigator.platform) };

/** A chat's side-panel tabs, as the core says them (client/core-ts/src/chat-tabs.ts): from what is kept for it here. */
function withTabs(view: ChatView, key: string, session: string): ChatView {
  const kept = (prefs.chatTabs as Record<string, unknown> | undefined)?.[key];
  return { ...view, tabs: tabsOf(kept, view.agents, view.noChat === true, session) };
}

/** A message no longer asking anything of the viewer. */
const withoutAsked = ({ asked: _, ...m }: ChatMessage): ChatMessage => m;

function answer(name: string, params: Record<string, unknown>, emit: (value: unknown, bytes?: Uint8Array) => void = () => undefined, signal: AbortSignal = new AbortController().signal): unknown {
  for (const e of extensions) { const v = e.stream?.(name, params, emit, signal); if (v !== undefined) return v; }
  for (const e of extensions) { const v = e.call?.(name, params); if (v !== undefined) return v; }
  if (BROWSE_CALLS.includes(name)) return browsing.call(name, params);
  if (name === "markdown") return { md: markdown(String(params.text ?? "")) };
  if (name === "code.ink") return { ink: inkKept(String(params.code ?? ""), String(params.lang ?? "")) };
  if (name === "reader.book") {
    const text = String(params.text ?? "");
    const { id, book } = keepBook(text, params.markdown === true);
    return bookAnswer(id, book, text, { withText: true });
  }
  if (name === "reader.search") {
    const book = keptBook(Number(params.id));
    return { at: book ? searchBook(book, String(params.query ?? "")) : [] };
  }
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
  if (name === "keys.set") {
    const { patch, moved, said } = keymap.change({ ...prefs, device: DEVICE }, typeof params.action === "string" ? params.action : null, Array.isArray(params.keys) ? params.keys.map((k) => keymap.binding(k) ?? String(k)) : null);
    // As prefs.set keeps a map: null takes an action's entry out.
    if (patch) prefs.keys = Object.fromEntries(Object.entries({ ...(prefs.keys as Record<string, unknown> | undefined), ...patch }).filter(([, v]) => v !== null));
    else delete prefs.keys;
    setTimeout(publish, 0);
    return { moved, said };
  }
  // A chat's tabs changed as the core changes them (chat-tabs.ts), kept with the prefs (`chatTabs`).
  if (name.startsWith("chat.tabs.") && typeof params.chat === "string") {
    const action = name.slice("chat.tabs.".length);
    if (action !== "open" && action !== "close" && action !== "front" && action !== "clear") return null;
    const key = params.chat;
    const at = key.indexOf(":");
    const session = at > 0 ? key.slice(at + 1) : "";
    const chat = key.startsWith("new:") ? undefined : chats.find((c) => c.key === session);
    const view = chat ? chatView(chat, station.runs()) : undefined;
    const tabs = (prefs.chatTabs ?? {}) as Record<string, unknown>;
    const next = changed(tabs[key], view?.agents ?? [], view?.noChat === true, view ? session : null, { action, tab: typeof params.tab === "string" ? params.tab : null, auto: params.auto !== false });
    if (next) {
      prefs.chatTabs = { ...tabs, [key]: next };
      setTimeout(publish, 0);
    }
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
  // ⌘K's commands, found as the core finds them (client/core-ts/src/commands.ts), in the page's words.
  if (name === "commands.find") return findCommands(String(params.query ?? ""), Array.isArray(params.offered) ? params.offered : [], t);
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
        seen.set(JSON.stringify(message.subscribe), message.subscribe);
        const m = said(message.id, message.subscribe);
        if (m) post(m);
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

/** Whether the demo is the phone's app, kept as its width changes (the site's frame changes it as it is scrolled):
 *  the app is drawn again only when that changes, not at every width. */
function useDemoPhone(): boolean {
  const [phone, setPhone] = useState(() => root.clientWidth < PHONE_BELOW);
  useEffect(() => {
    const observer = new ResizeObserver(() => setPhone(root.clientWidth < PHONE_BELOW));
    observer.observe(root);
    return () => observer.disconnect();
  }, []);
  return phone;
}

/** How many times the app has been put back as it opened (MountedDemo.reopen): its key, so that it starts again. */
let rounds = 0;
let startAgain: ((round: number) => void) | null = null;

function Demo() {
  const phone = useDemoPhone();
  const [round, setRound] = useState(rounds);
  useEffect(() => {
    startAgain = setRound;
    return () => {
      startAgain = null;
    };
  }, []);
  return <DemoApp key={round} phone={phone} />;
}

/** The demo as the phone's app or the desktop's, opened on the chat in view (so switching between them keeps it). */
export function DemoApp({ phone }: { phone: boolean }) {
  const key = navigateTarget();
  // As still.fail cloud's app has them (cloud/CloudApp.tsx): the phone's pages, or the desktop's.
  return (
    <ToastProvider>
      <Tooltip.Provider delayDuration={400}>
        <MemoryRouter key={phone ? "phone" : "wide"} initialEntries={at ? [`/w/${ENTRY.id}/${at}`] : start === "stations" ? [`/w/${ENTRY.id}/settings/stations`] : [`/w/${ENTRY.id}`, chatPath(key)]} initialIndex={at || start === "stations" ? 0 : 1}>
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

/**
 * Every topic the page has subscribed to and what it says now, and those of `extra` (apps/mbui/scripts/web-layout.mjs:
 * the same data given to mbui's app, to hold its layout against the page's). Its errors left out.
 */
export function demoTape(extra: Topic[] = []): { topic: Topic; value: unknown }[] {
  const all = new Map(seen);
  for (const t of extra) all.set(JSON.stringify(t), t);
  return [...all.values()].flatMap((topic) => { const v = valueOf(topic); return v instanceof CoreError || v === undefined || v === HELD ? [] : [{ topic, value: v }]; });
}

/** The demo's chats stop where they are, nobody at work any more (the stories' tests, to look at a page that holds still). */
export function endDemo(): void {
  story.end();
}

/** Where the demo opens: on its chat, the story played (the default); or on the stations' page, as the page that shows
 *  all of the workspace's machines together, no story played. */
let start: "chat" | "stations" = "chat";
/** A page of the app's to open on instead (its path in the workspace), its story not played. */
let at: string | undefined;
/** The language the demo is in: the app's and what it makes up (the site's English page: "en"); else as the app's own. */
let language: "zh" | "en" | undefined;

/** Where the demo opens, its language, and whether the caller's phone frame can be taken over in place. */
export interface DemoOptions { start?: "chat" | "stations"; at?: string; lang?: "zh" | "en"; reusePhoneFrame?: boolean }

/** The demo opens as `options` say: as it is mounted, and as its opening frame is built into the page (prerender.tsx). */
export function openOn(options: DemoOptions): void {
  start = options.start ?? "chat";
  at = options.at;
  language = options.lang;
}

/** What the page holds of its demo. */
export interface MountedDemo {
  /**
   * The app as it opened again, drawn before this returns, if the visitor has clicked in it since it last was (the
   * site's scene, played back, plays on the app as it was put together: OneComputer.tsx).
   */
  reopen(): void;
}

const mountedDemo: MountedDemo = {
  reopen() {
    if (!touched) return;
    touched = false;
    rounds += 1;
    flushSync(() => startAgain?.(rounds));
  },
};

/** Runs the demo in `element` (once): the app, its made-up core, and the story played when it comes into view. */
export function mountDemo(element: HTMLElement, options: DemoOptions = {}): MountedDemo {
  if (mounted) return mountedDemo;
  mounted = true;
  openOn(options);
  root = element;
  // The narrow opening scene was built from this same demo. Take its phone frame over in place so the scene keeps
  // the rows it already measured and copied, instead of replacing them while the visitor is scrolling.
  const frame = options.reusePhoneFrame && options.start === "stations" && !options.at && root.dataset.phone !== undefined && root.clientWidth < PHONE_BELOW
    ? root.querySelector(":scope > [inert]") : null;
  const built = frame?.children.length === 2 ? frame.lastElementChild as HTMLElement : null;
  const app = built ?? document.createElement("div");
  if (built) built.removeAttribute("class");
  root.replaceChildren(app);
  withoutDownloads();
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
      else if (type === "keydown") { touched = true; story.stop(); }
    }, true);
  }
  // A press may still become a page scroll. Let the app focus during it, but only count it as using the demo if it
  // ends normally: a browser that takes the gesture for scrolling sends pointercancel instead of pointerup.
  const pressing = new Set<number>();
  const focus = HTMLElement.prototype.focus;
  HTMLElement.prototype.focus = function (options?: FocusOptions) {
    if (root.contains(this) && !touched && pressing.size === 0) return;
    focus.call(this, { ...options, preventScroll: true });
  };
  // A link out of the demo (Slack, a web service, an app's settings) opens nothing: it too needs a real still.fail instance. Only the
  // app's own links count, in its box or its dialogs and menus on the page; the page's own go.
  const inApp = (el: Element) => root.contains(el) || !!el.closest("[role=dialog], [role=menu], [data-radix-popper-content-wrapper]");
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
  root.addEventListener("pointerdown", (event) => { pressing.add(event.pointerId); }, true);
  window.addEventListener("pointerup", (event) => { if (pressing.delete(event.pointerId)) { touched = true; story.stop(); } }, true);
  window.addEventListener("pointercancel", (event) => { pressing.delete(event.pointerId); }, true);
  window.addEventListener("blur", () => pressing.clear());

  // Played once the demo is seen: most of it in view.
  if (start === "chat" && !at) new IntersectionObserver((entries, observer) => {
    if (!entries.some((e) => e.isIntersecting)) return;
    observer.disconnect();
    void story.play();
  }, { threshold: 0.6 }).observe(root);

  const view = (
    <StrictMode>
      <Demo />
    </StrictMode>
  );
  if (built) hydrateRoot(app, view);
  else createRoot(app).render(view);
  return mountedDemo;
}
