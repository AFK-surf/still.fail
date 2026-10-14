// A file of the drive played as it comes, never fetched whole: the page's service worker (public/sw.js) answers
// `/__drive/<token>` itself, a range at a time, by asking this page for the bytes (a MessageChannel), and this page
// asks the core (`drive.read`). A <video> pointed there starts at once and seeks anywhere, reading only what it shows.
// The desktop app's page has none: the app answers the ranges itself (apps/desktop/src/main.ts, drive). Where neither
// is (a browser with no service worker for it), there is no stream: the caller reads the file whole instead (small
// enough) or says it cannot be played here.
import { readPart, type At } from "./model.ts";

/** `ahead`: how far into the file reading is welcome now (the playing position and some), null while not known. */
interface Opened { at: At; size: number; type: string; ahead?: (() => number | null) | undefined }

/** A part asked for past where reading is welcome waits for playback to come near, this long at most at a time (the
 *  service worker gives up on an answer after a minute). */
const HOLD_MS = 20_000;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/**
 * Whether to read a part at `offset` now: at once while within `ahead`; past it, once playback has come near or a while
 * has gone by (a player reading ahead of what it plays, as Safari's does, is kept to about what it will play soon).
 */
async function welcome(token: string, offset: number): Promise<boolean> {
  for (const since = performance.now(); performance.now() - since < HOLD_MS;) {
    const file = opened.get(token);
    if (!file) return false;
    const ahead = file.ahead?.();
    if (ahead === null || ahead === undefined || offset <= ahead) return true;
    await sleep(300);
  }
  return opened.has(token);
}
const opened = new Map<string, Opened>();
let listening = false;

interface Ask { stillfailDrive: 1; token: string; offset: number; length: number }

/** The service worker asks for a part of a file this page opened: it is read, and sent back (or why not). */
function answer(event: MessageEvent): void {
  const ask = event.data as Ask | null;
  if (ask?.stillfailDrive !== 1) return;
  const port = event.ports[0];
  if (!port) return;
  const file = opened.get(ask.token);
  // Another page's: the worker asks the next one.
  if (!file) { port.postMessage({ unknown: true }); return; }
  void welcome(ask.token, ask.offset).then((go) => (go ? readPart(file.at, ask.offset, ask.length) : Promise.reject(new Error("closed")))).then(
    (got) => port.postMessage({ total: got.total, bytes: got.bytes.buffer }, [got.bytes.buffer]),
    (e: unknown) => port.postMessage({ error: e instanceof Error ? e.message : String(e) }),
  );
}

let ready: Promise<boolean> | null = null;

/** Another worker took control, or `ms` went by. */
function changed(sw: ServiceWorkerContainer, ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    const done = () => { sw.removeEventListener("controllerchange", done); resolve(); };
    sw.addEventListener("controllerchange", done);
    setTimeout(done, ms);
  });
}

/** Whether the worker answers for the drive (one from before it says nothing). */
function hello(worker: ServiceWorker): Promise<boolean> {
  return new Promise<boolean>((resolve) => {
    const channel = new MessageChannel();
    const timer = setTimeout(() => resolve(false), 1500);
    channel.port1.onmessage = () => { clearTimeout(timer); resolve(true); };
    worker.postMessage({ stillfailDriveHello: 1 }, [channel.port2]);
  });
}

/** Whether this page's fetches go through the service worker: registered (it also takes pushes) and in control. */
export function streaming(): Promise<boolean> {
  if (typeof window !== "undefined" && window.stillfailDesktop?.driveOpen) return Promise.resolve(true);
  ready ??= (async () => {
    const sw = typeof navigator !== "undefined" ? navigator.serviceWorker : undefined;
    if (!sw || location.protocol !== "https:" && location.hostname !== "localhost" && location.hostname !== "127.0.0.1") return false;
    try {
      const registration = await sw.register("/sw.js");
      await sw.ready;
      // A page opened before the worker was there is taken over as it starts (clients.claim): waited for a moment.
      if (!sw.controller) await changed(sw, 3000);
      let ok = !!sw.controller && await hello(sw.controller);
      if (!ok) {
        // The worker in control is one from before the drive: the new one takes over once it is in (skipWaiting).
        await registration.update().catch(() => undefined);
        await changed(sw, 5000);
        ok = !!sw.controller && await hello(sw.controller);
      }
      if (ok && !listening) { sw.addEventListener("message", answer); listening = true; }
      return ok;
    } catch {
      return false;
    }
  })();
  // Not now: asked again next time (a worker coming in meanwhile).
  void ready.then((ok) => { if (!ok) ready = null; });
  return ready;
}

/** A URL a <video> or <audio> plays the file from, a range at a time (null: the app would not open it); `close` lets it go. */
export async function streamUrl(at: At, size: number, type: string, ahead?: () => number | null): Promise<{ url: string; close: () => void } | null> {
  const desktop = window.stillfailDesktop;
  if (desktop?.driveOpen) {
    const url = await desktop.driveOpen({ station: at.station, root: at.root, path: at.path, size, type });
    return url ? { url, close: () => desktop.driveClose?.(url) } : null;
  }
  const token = crypto.randomUUID();
  opened.set(token, { at, size, type, ahead });
  const url = `/__drive/${token}?n=${size}&t=${encodeURIComponent(type || "application/octet-stream")}`;
  return { url, close: () => { opened.delete(token); } };
}
