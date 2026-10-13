// still.fail's service worker: pushes (docs/notifications.md). A notice is shown when no page of the app is looked
// at (an open page shows it itself, from the client core); clicking one opens its chat, in a page already open when
// there is one.
// And a station's drive played as it comes (web/src/drive/stream.ts): `/__drive/<token>` is answered here, a range at
// a time, with bytes the page that opened it reads from the station; nothing else is touched (no respondWith).
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));

self.addEventListener("push", (event) => {
  let notice = null;
  try { notice = event.data?.json() ?? null; } catch { /* not ours */ }
  if (!notice || notice.type !== "notice") return;
  event.waitUntil((async () => {
    const pages = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    if (pages.some((page) => page.visibilityState === "visible")) return;
    await self.registration.showNotification(notice.title, { body: notice.body, tag: notice.tag, icon: "/icon-192.png", data: { url: notice.url } });
  })());
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const path = event.notification.data?.url ?? "/";
  event.waitUntil((async () => {
    const pages = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    const page = pages.find((p) => p.focused) ?? pages[0];
    if (page) {
      await page.focus();
      page.postMessage({ stillfailNavigate: path });
      return;
    }
    await self.clients.openWindow(path);
  })());
});

/** How much of a file one answer's part asks the page for. */
const DRIVE_PART = 1024 * 1024;

// A page asks whether this worker streams the drive (one from before it does not answer): it does.
self.addEventListener("message", (event) => {
  if (event.data?.stillfailDriveHello && event.ports[0]) event.ports[0].postMessage({ drive: 1 });
});

self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin || !url.pathname.startsWith("/__drive/")) return;
  event.respondWith(driveAnswer(event, url));
});

/** Asks a page for a part of what it opened: its answer, or `unknown` when it is not that page's. */
function askPage(page, message) {
  return new Promise((resolve) => {
    const channel = new MessageChannel();
    const timer = setTimeout(() => resolve({ error: "timeout" }), 60_000);
    channel.port1.onmessage = (event) => { clearTimeout(timer); resolve(event.data); };
    page.postMessage({ stillfailDrive: 1, ...message }, [channel.port2]);
  });
}

/** The page that opened `token` (the one asking, else any of the app's) answers for its bytes. */
async function ask(clientId, message) {
  const own = clientId ? await self.clients.get(clientId) : null;
  const pages = own ? [own] : await self.clients.matchAll({ type: "window" });
  for (const page of pages) {
    const answer = await askPage(page, message);
    if (!answer.unknown) return answer;
  }
  return { error: "gone" };
}

/** A 206 with the range asked for (all of it, 200, when none was), its bytes asked for as they are read. */
async function driveAnswer(event, url) {
  const token = url.pathname.slice("/__drive/".length);
  const total = Number(url.searchParams.get("n"));
  const type = url.searchParams.get("t") || "application/octet-stream";
  const clientId = event.clientId || event.resultingClientId;
  if (!Number.isSafeInteger(total) || total < 0) return new Response(null, { status: 400 });
  const range = /^bytes=(\d*)-(\d*)$/.exec(event.request.headers.get("range") || "");
  let start = 0;
  let end = total - 1;
  if (range) {
    if (range[1] === "" && range[2] !== "") start = Math.max(0, total - Number(range[2]));
    else {
      start = Number(range[1]);
      if (range[2] !== "") end = Math.min(Number(range[2]), total - 1);
    }
    if (start >= total || start > end) return new Response(null, { status: 416, headers: { "content-range": `bytes */${total}` } });
  }
  let at = start;
  let stopped = false;
  const body = new ReadableStream({
    async pull(controller) {
      if (stopped) return;
      if (at > end) { controller.close(); return; }
      const got = await ask(clientId, { token, offset: at, length: Math.min(DRIVE_PART, end - at + 1) });
      if (stopped) return;
      if (got.error || !got.bytes || got.bytes.byteLength === 0) { controller.error(new Error(got.error || "nothing read")); return; }
      controller.enqueue(new Uint8Array(got.bytes));
      at += got.bytes.byteLength;
      if (at > end) controller.close();
    },
    // The player moved on (a seek): no more of this range is read.
    cancel() { stopped = true; },
  });
  const headers = { "content-type": type, "accept-ranges": "bytes", "content-length": String(end - start + 1), "cache-control": "no-store" };
  if (range) headers["content-range"] = `bytes ${start}-${end}/${total}`;
  return new Response(body, { status: range ? 206 : 200, headers });
}
