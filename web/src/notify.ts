// Notifications in the browser (docs/notifications.md): the core's `notices` shown while a page is open, and pushes
// through the service worker (/sw.js) while none is. The desktop app shows its own from its main process, so its
// pages show none. Whether they are on is this browser's (localStorage), and the browser's permission.
import { useEffect, useSyncExternalStore } from "react";
import { useNavigate } from "react-router";
import { core } from "./core/react.ts";
import type { Notice, NoticesView } from "./core/shapes.ts";

const KEY = "stillfail.notify";
/** Notices a page of this browser has shown (by id and time), so that several pages show each once. */
const SHOWN = "stillfail.noticesShown";

const listeners = new Set<() => void>();
const changed = () => listeners.forEach((l) => l());

/** Where the page runs has notifications of its own (the desktop app shows them from its main process). */
const NOTIFIES = typeof window !== "undefined" && "Notification" in window && !window.stillfailDesktop;
const PUSHES = NOTIFIES && "serviceWorker" in navigator && "PushManager" in window;
/** The desktop app's setting (null until asked, or for an app from before notifications). */
const DESKTOP = typeof window !== "undefined" ? window.stillfailDesktop?.notify : undefined;
let desktopOn: boolean | null = null;
if (DESKTOP) void DESKTOP.get().then((on) => { desktopOn = on; changed(); });

/** This client can tell about the chats: the setting shows. */
export const CAN_NOTIFY = NOTIFIES || !!DESKTOP;

export type NotifyState = "on" | "off" | "denied" | "unsupported";

function state(): NotifyState {
  if (DESKTOP) return desktopOn === null ? "unsupported" : desktopOn ? "on" : "off";
  if (!NOTIFIES) return "unsupported";
  if (Notification.permission === "denied") return "denied";
  return Notification.permission === "granted" && localStorage.getItem(KEY) !== "off" ? "on" : "off";
}

export function useNotifyState(): NotifyState {
  return useSyncExternalStore((l) => { listeners.add(l); return () => listeners.delete(l); }, state);
}

/** Turns them on (asking the browser first) or off, on this browser. */
export async function setNotify(on: boolean): Promise<NotifyState> {
  if (DESKTOP) {
    await DESKTOP.set(on);
    desktopOn = on;
    changed();
    return state();
  }
  if (!NOTIFIES) return "unsupported";
  if (on) {
    const permission = Notification.permission === "default" ? await Notification.requestPermission() : Notification.permission;
    if (permission === "granted") localStorage.removeItem(KEY);
  } else {
    localStorage.setItem(KEY, "off");
  }
  changed();
  await syncPush();
  return state();
}

let pushing = false;

/**
 * This browser's push subscription as the setting says: subscribed and given to the accounts while on, dropped while
 * off. A cloud with no pushes yet (no key) leaves the page to show them alone.
 */
async function syncPush(): Promise<void> {
  if (!PUSHES) return;
  try {
    const registration = await navigator.serviceWorker.register("/sw.js");
    const current = await registration.pushManager.getSubscription();
    if (state() !== "on") {
      pushing = false;
      if (current) {
        await core().call("push.unregister").catch(() => {});
        await current.unsubscribe();
      }
      return;
    }
    const { vapid } = await core().call("push.key") as { vapid: string };
    const key = base64url(vapid);
    const same = current && equal(new Uint8Array(current.options.applicationServerKey ?? new ArrayBuffer(0)), key);
    if (current && !same) await current.unsubscribe();
    const subscription = same ? current : await registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: key });
    const json = subscription.toJSON();
    await core().call("push.register", { kind: "web", endpoint: json.endpoint, keys: json.keys });
    pushing = true;
  } catch {
    pushing = false;
  }
}

function base64url(text: string): Uint8Array<ArrayBuffer> {
  const raw = atob(text.replace(/-/g, "+").replace(/_/g, "/"));
  return Uint8Array.from(raw, (c) => c.charCodeAt(0));
}

function equal(a: Uint8Array, b: Uint8Array): boolean {
  return a.length === b.length && a.every((v, i) => v === b[i]);
}

/** The chat a notice is about is the one this page shows, and the page is looked at. */
function looking(n: Notice): boolean {
  const path = decodeURIComponent(location.pathname);
  return document.visibilityState === "visible" && document.hasFocus() && path.endsWith(`/s/${n.stationId}/chats/${n.session}`) && path.startsWith(`/w/${n.workspace}/`);
}

/** Whether another page of this browser showed it already; if not, it is this one's to show. */
function claim(n: Notice): boolean {
  const key = `${n.at}:${n.id}`;
  let shown: string[] = [];
  try { shown = JSON.parse(localStorage.getItem(SHOWN) ?? "[]") as string[]; } catch { /* none kept */ }
  if (shown.includes(key)) return false;
  localStorage.setItem(SHOWN, JSON.stringify([...shown, key].slice(-50)));
  return true;
}

/**
 * Shows the core's notices from this page, and opens a chat when one is clicked (here, or in the service worker's
 * notification). A page hidden behind others leaves them to pushes, when this browser has them.
 */
export function useNotices(): void {
  const navigate = useNavigate();
  useEffect(() => {
    if (!NOTIFIES) return;
    void syncPush();
    const open = (path: string) => { window.focus(); navigate(path); };
    const fromWorker = (event: MessageEvent) => {
      if (typeof event.data?.stillfailNavigate === "string") open(event.data.stillfailNavigate);
    };
    navigator.serviceWorker?.addEventListener("message", fromWorker);
    let seen: Set<string> | null = null;
    const stop = core().subscribe({ topic: "notices" }, (value) => {
      const items = (value as NoticesView).items;
      // What was there before this page came is old news.
      if (!seen) { seen = new Set(items.map((n) => n.id)); return; }
      for (const n of items) {
        if (seen.has(n.id)) continue;
        seen.add(n.id);
        if (state() !== "on" || looking(n)) continue;
        if (pushing && document.visibilityState !== "visible") continue;
        if (!claim(n)) continue;
        const shown = new Notification(n.title, { body: n.body, tag: n.tag, icon: "/icon-192.png" });
        shown.onclick = () => { shown.close(); open(n.url); };
      }
    }, () => {});
    return () => { stop(); navigator.serviceWorker?.removeEventListener("message", fromWorker); };
  }, [navigate]);
}
