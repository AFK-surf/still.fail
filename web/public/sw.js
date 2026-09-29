// still.fail's service worker: pushes (docs/notifications.md). A notice is shown when no page of the app is looked
// at (an open page shows it itself, from the client core); clicking one opens its chat, in a page already open when
// there is one.
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
