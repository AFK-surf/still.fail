// Notifications in the browser (docs/notifications.md): the core's `notices` shown while a page is open, and pushes
// through the service worker (/sw.js) while none is. The desktop app shows its own from its main process, so its
// pages show none. Whether they are on is the core's (kept on the device), and the browser's permission. Only the
// workspace the viewer is in is heard of: each page tells the core where it is (`useInWorkspace`).
import { useEffect, useSyncExternalStore } from "react";
import { useNavigate } from "react-router";
import { core } from "./core/react.ts";
import type { Notice, NotifyView } from "./core/shapes.ts";

/** Where this browser kept the setting and the notices shown before the core did: moved into it once. */
const OLD_KEY = "stillfail.notify";
const OLD_SHOWN = "stillfail.noticesShown";

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

/** The workspace this page is in (an id, or `local`), as it told the core. */
let inWorkspace: string | undefined;

/**
 * This page is in `workspace` (an id, or `local`): the core is told (`client.focus`), so what it tells the viewer is
 * of it (client/core/src/attend.rs), and so are the notices this page shows.
 */
export function useInWorkspace(workspace: string): void {
  useEffect(() => {
    inWorkspace = workspace;
    void core().focus({ workspace }).catch(() => undefined);
    changed();
  }, [workspace]);
}

function useWorkspaceIn(): string | undefined {
  return useSyncExternalStore((l) => { listeners.add(l); return () => listeners.delete(l); }, () => inWorkspace, () => undefined);
}

/** The core's `notify` (null until it says; a core from before it: on, as the browser kept it). */
let kept: NotifyView | null = null;
let watching = false;
let migrating: Promise<void> | null = null;
/** The old setting moved into the core (or given up on for now): only then is the core's taken. */
const migrated = () => (migrating ??= migrate());

/** Follows the core's `notify` while the page runs. */
function watch(): void {
  if (watching || !NOTIFIES) return;
  watching = true;
  void migrated().then(() => {
    core().subscribe({ topic: "notify" }, (value) => { kept = value as NotifyView; changed(); }, () => {});
  });
}

/** The setting as this browser kept it before the core did (off, or nothing), into the core once. */
async function migrate(): Promise<void> {
  localStorage.removeItem(OLD_SHOWN);
  if (localStorage.getItem(OLD_KEY) !== "off") return;
  try {
    await core().call("notify.set", { on: false });
    localStorage.removeItem(OLD_KEY);
  } catch { /* tried again on the next start */ }
}

function state(): NotifyState {
  if (DESKTOP) return desktopOn === null ? "unsupported" : desktopOn ? "on" : "off";
  if (!NOTIFIES) return "unsupported";
  if (Notification.permission === "denied") return "denied";
  const on = kept?.on ?? localStorage.getItem(OLD_KEY) !== "off";
  return Notification.permission === "granted" && on ? "on" : "off";
}

export function useNotifyState(): NotifyState {
  watch();
  return useSyncExternalStore((l) => { listeners.add(l); return () => listeners.delete(l); }, state);
}

/** Turns them on (asking the browser first) or off, on this browser; rejects, as it was, when that could not be kept. */
export async function setNotify(on: boolean): Promise<NotifyState> {
  if (DESKTOP) {
    await DESKTOP.set(on);
    desktopOn = on;
    changed();
    return state();
  }
  if (!NOTIFIES) return "unsupported";
  const set = async (on: boolean) => {
    kept = await core().call("notify.set", { on }) as NotifyView;
  };
  if (on) {
    const permission = Notification.permission === "default" ? await Notification.requestPermission() : Notification.permission;
    if (permission === "granted") await set(true);
  } else {
    // The core takes this device's pushes off the accounts too.
    await set(false);
  }
  changed();
  await syncPush();
  return state();
}

/**
 * This browser's push subscription as the core says (`push`): subscribed and given to the accounts while it wants
 * one and the browser allows it, dropped otherwise. A cloud with no pushes yet (no key) leaves the page to show them.
 */
async function syncPush(): Promise<void> {
  if (!PUSHES) return;
  try {
    const registration = await navigator.serviceWorker.register("/sw.js");
    const current = await registration.pushManager.getSubscription();
    if (!(kept?.push ?? true) || Notification.permission !== "granted") {
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
  } catch {
    // Not now: the page shows them alone.
  }
}

function base64url(text: string): Uint8Array<ArrayBuffer> {
  const raw = atob(text.replace(/-/g, "+").replace(/_/g, "/"));
  return Uint8Array.from(raw, (c) => c.charCodeAt(0));
}

function equal(a: Uint8Array, b: Uint8Array): boolean {
  return a.length === b.length && a.every((v, i) => v === b[i]);
}

/**
 * Shows the notices the core says are to be shown now (docs/notifications.md; client/core/src/attend.rs decides:
 * not for a chat looked at, not while pushes say them), each from the one page that takes it, and opens a chat when
 * one is clicked (here, or in the service worker's notification).
 */
export function useNotices(): void {
  const navigate = useNavigate();
  const workspace = useWorkspaceIn();
  useEffect(() => {
    if (!NOTIFIES) return;
    watch();
    const open = (path: string) => { window.focus(); navigate(path); };
    const fromWorker = (event: MessageEvent) => {
      if (typeof event.data?.stillfailNavigate === "string") open(event.data.stillfailNavigate);
    };
    navigator.serviceWorker?.addEventListener("message", fromWorker);
    const taken = new Set<string>();
    const show = (n: Notice) => {
      const shown = new Notification(n.title, { body: n.body, tag: n.tag, icon: "/icon-192.png" });
      shown.onclick = () => { shown.close(); open(n.url); };
    };
    let pushSynced = false;
    let stop = () => {};
    let gone = false;
    void migrated().then(() => {
      if (gone) return;
      // Only the page's own workspace's; before it says which, all (the core has none left out either).
      stop = core().subscribe(workspace ? { topic: "notify", workspace } : { topic: "notify" }, (value) => {
        kept = value as NotifyView;
        if (!pushSynced) { pushSynced = true; void syncPush(); }
        for (const n of kept.show) {
          if (taken.has(n.id)) continue;
          taken.add(n.id);
          void core().call("notice.claim", { id: n.id }).then((answer) => {
            if ((answer as { show: boolean }).show && Notification.permission === "granted") show(n);
          }, () => {});
        }
      }, () => {});
    });
    return () => { gone = true; stop(); navigator.serviceWorker?.removeEventListener("message", fromWorker); };
  }, [navigate, workspace]);
}
