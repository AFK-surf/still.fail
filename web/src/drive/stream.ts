// A file of the drive played as it comes, never fetched whole: the page's service worker (public/sw.js) answers
// `/__drive/<token>` itself, a range at a time, by asking this page for the bytes (a MessageChannel), and this page
// asks the core (`drive.read`). A <video> pointed there starts at once and seeks anywhere, reading only what it shows.
// Where no service worker runs the page (a browser that has none for it, the desktop app's own scheme), there is no
// stream: the caller reads the file whole instead (small enough) or says it cannot be played here.
import { readPart, type At } from "./model.ts";

interface Opened { at: At; size: number; type: string }
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
  readPart(file.at, ask.offset, ask.length).then(
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

/** A URL a <video> or <audio> plays the file from, a range at a time; `close` lets it go. */
export function streamUrl(at: At, size: number, type: string): { url: string; close: () => void } {
  const token = crypto.randomUUID();
  opened.set(token, { at, size, type });
  const url = `/__drive/${token}?n=${size}&t=${encodeURIComponent(type || "application/octet-stream")}`;
  return { url, close: () => { opened.delete(token); } };
}
