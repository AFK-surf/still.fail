// still.fail's browser extension (docs/share-in.md): the toolbar button and the context menu hand what is in front of
// the person (the page, a link, a video, the words selected) to one of their still.fail chats. Each opens the page's
// /share in a small window of its own, signed in as the person's still.fail page is (the same browser); that page says
// where it goes and sends it, then closes the window. Nothing of the page is read beyond its address and title and
// what was clicked: the extension has no host permissions, only the tab it is used on (activeTab).

const ORIGIN = "https://app.still.fail";
const WIDTH = 420;
const HEIGHT = 640;

/** Where still.fail is: the options page's (a dev cloud), else the app's. */
async function origin() {
  const { origin } = await chrome.storage.sync.get({ origin: ORIGIN });
  return typeof origin === "string" && /^https?:\/\//.test(origin) ? origin.replace(/\/+$/, "") : ORIGIN;
}

/** A web page's own address (not the browser's pages, a file, a blob: a video plays from). */
const web = (url) => typeof url === "string" && /^https?:\/\//i.test(url) ? url : null;

/** Opens /share with what is shared, in a window of its own over the middle of the one in front. */
async function share({ url, title, text }) {
  const params = new URLSearchParams();
  if (url) params.set("url", url);
  if (title) params.set("title", title);
  if (text) params.set("text", text);
  params.set("popup", "1");
  const at = `${await origin()}/share?${params}`;
  const front = await chrome.windows.getLastFocused().catch(() => null);
  const place = front && typeof front.left === "number" && typeof front.width === "number"
    ? { left: Math.round(front.left + (front.width - WIDTH) / 2), top: Math.round((front.top ?? 0) + 72) }
    : {};
  await chrome.windows.create({ url: at, type: "popup", width: WIDTH, height: HEIGHT, focused: true, ...place });
}

const MENU = [
  { id: "page", contexts: ["page"], title: "menuPage" },
  { id: "link", contexts: ["link"], title: "menuLink" },
  { id: "media", contexts: ["video", "audio"], title: "menuMedia" },
  { id: "selection", contexts: ["selection"], title: "menuSelection" },
];

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => {
    for (const item of MENU) chrome.contextMenus.create({ id: item.id, contexts: item.contexts, title: chrome.i18n.getMessage(item.title) });
  });
});

// The toolbar button: the page in front.
chrome.action.onClicked.addListener((tab) => {
  void share({ url: web(tab.url), title: tab.title || null });
});

chrome.contextMenus.onClicked.addListener((info, tab) => {
  const page = web(info.pageUrl) ?? web(tab?.url);
  const title = tab?.title || null;
  switch (info.menuItemId) {
    case "page": return void share({ url: page, title });
    // A link: its address, the words it is (when the browser says them) as its title.
    case "link": return void share({ url: web(info.linkUrl) ?? page, title: info.linkText || info.selectionText || null });
    // A video or a sound: the page it is on (where it can be fetched from), and its own address when that is one.
    case "media": {
      const src = web(info.srcUrl);
      return void share(src && src !== page ? { url: src, title, text: page } : { url: page, title });
    }
    // Words selected: them, and the page they are on.
    case "selection": return void share({ url: page, title, text: info.selectionText || null });
  }
});
