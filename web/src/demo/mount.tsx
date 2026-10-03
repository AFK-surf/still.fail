// The official site's demo: the real app (a workspace's pages), in a part of the page (site/Site.tsx's demo box), on a made-up core — no
// worker, no station. story.ts plays a few chats in it; the visitor can click around and send messages too.
import "./demo.css.ts";
import { startScrollbars } from "../scrollbars.ts";
import { StrictMode, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import { MemoryRouter, Route, Routes, useLocation, useNavigate } from "react-router";
import "@fontsource-variable/inter";
import { setPageRoot } from "../brand.tsx";
import { Tooltip } from "radix-ui";
import { ToastProvider } from "../toast.tsx";
import { MobileWorkspace } from "../mobile/index.tsx";
import { WorkspaceShell, type WorkspaceEntry } from "../cloud/workspace.tsx";
import { CoreClient, type Topic } from "../core/client.ts";
import type { ModelOption } from "../api.ts";
import { setCore, setTopicSource } from "../core/react.ts";
import { addItem, chatView, newChat, received, VISITOR, chatsView, historyView, liveView, marked, message, outgoing, SAFARI_KEY } from "./fixtures.ts";
import { makeStory, openingChats } from "./story.ts";
import { RealStillFail, askForReal } from "./real.tsx";
import * as station from "./station.ts";

/** The demo's box; the app is drawn in a box of its own inside it (the buddy goes beside it: setPageRoot). */
let root: HTMLElement;
/** The visitor has clicked in the demo: from then on it is theirs (the story stops moving between chats). */
let touched = false;
let mounted = false;

// ---- The core ----


const chats = openingChats();
const subs = new Map<number, Topic>();
let post: (message: unknown) => void = () => undefined;

function valueOf(topic: Topic): unknown {
  const chat = "key" in topic ? chats.find((c) => c.key === topic.key) : "session" in topic ? chats.find((c) => c.key === topic.session) : undefined;
  switch (topic.topic) {
    case "overview": return station.overview();
    case "status": return { items: [] };
    case "connection": return { items: [] };
    // Nothing chosen: the defaults (the core's shape leaves them out).
    case "prefs": return {};
    case "doing": return { doing: [] };
    case "chats": return chatsView(chats);
    case "chat": return chat ? chatView(chat, station.runs()) : null;
    case "slackApp": return station.slackApp();
    case "live": return chat ? liveView(chat) : null;
    case "history": return chat ? historyView(chat) : null;
    case "host": return station.host();
    case "connects": return station.connects();
    case "stations": return [station.stationView()];
    case "archive": return station.archive();
    // What the core puts together of them (client/core-ts/src/choose.ts), as a new chat and a model control start.
    case "newChat": return newChatView();
    case "pick": return pickView(topic.of);
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
    who: "账号", autoNote: on ? `现在是 ${on.name}` : "额度用完或登录失效时换一个", changed: false, was: [], becomes: [],
    modelText: m?.name ?? "", accountText: "自动分配", accountNote: "额度用完或登录失效时换一个", accountWarn: false, saveText: "不变",
  };
}

// Every topic starts at its value: the first render shows the demo at once (and so does the site built to HTML).
setTopicSource(valueOf);

function publish() {
  for (const [id, topic] of subs) post({ id, value: valueOf(topic) });
}

// What the visitor sends is answered as an account its provider has banned would be: the turn fails, still.fail says why in
// the chat, and the agent is marked failed — the station's own words (session.rs failure_notice, quota.rs).
const BANNED = `⚠️ 认证失败，需要管理员检查账号：${station.BAN_DETAIL}`;

function answer(name: string, params: Record<string, unknown>): unknown {
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
  if (name === "draft.get" || name === "draft.put") return null;
  // Its chats are whole, never a window short of their end: nothing to move along, nowhere to keep a place.
  if (name === "chat.newer" || name === "chat.latest" || name === "chat.place") return name === "chat.newer" ? { more: false } : null;
  const chat = chats.find((c) => c.thread === params.thread || c.key === params.session);
  if (name === "chat.send" && chat && typeof params.text === "string" && params.text.trim()) {
    const text = params.text;
    story.end(chat.key);
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
    if (name === "station.upload" || name.startsWith("auth.")) throw new station.NeedsReal();
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
      const message = raw as { id: number; subscribe?: Topic; unsubscribe?: boolean; call?: string; params?: Record<string, unknown> };
      if (message.subscribe) {
        subs.set(message.id, message.subscribe);
        post({ id: message.id, value: valueOf(message.subscribe) });
      } else if (message.unsubscribe) {
        subs.delete(message.id);
      } else if (message.call) {
        void Promise.resolve()
          .then(() => answer(message.call!, message.params ?? {}))
          .then(
            (ok) => post({ id: message.id, ok }),
            (e: Error) => post({ id: message.id, error: { code: e instanceof station.NeedsReal ? "demo" : "internal", message: e.message } }),
          );
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
          <Routes><Route path="/w/:ws/*" element={phone ? <MobileWorkspace entry={ENTRY} /> : <WorkspaceShell entry={ENTRY} />} /></Routes>
          <RealStillFail />
        </MemoryRouter>
      </Tooltip.Provider>
    </ToastProvider>
  );
}

/** Runs the demo in `element` (once): the app, its made-up core, and the story played when it comes into view. */
export function mountDemo(element: HTMLElement): void {
  if (mounted) return;
  mounted = true;
  root = element;
  // What the page was built with (its opening frame, as HTML) gives way to the demo itself.
  root.replaceChildren();
  setPageRoot(root);
  const app = root.appendChild(document.createElement("div"));
  app.style.height = "100%";
  startScrollbars();

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
