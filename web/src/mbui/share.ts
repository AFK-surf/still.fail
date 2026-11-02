// What another app shares into still.fail on the web (docs/share-in.md): the installed page's share target and the
// browser extension (apps/extension) open /share?url=&title=&text= (the extension with `popup=1&ext=<its id>`, in a
// small window of its own). The app takes it as it takes what Android shares (apps/mbui sfapp/share.mbt, its host's
// `shared_in`): its share sheet lists where it can go. In the extension's window the app is over another (`over`, as
// Android's OverActivity): only the sheet is drawn, and the chat picked opens in the browser's still.fail tab.

/// What is shared: what the core is given (the link, or the text, or the text with the link after it when they are
/// apart), `title` what the app gave as its subject.
export interface Shared { source: string; title: string | null; popup: boolean; ext?: string | undefined }

/// What /share was given (`?url=&title=&text=&popup=1&ext=`): null when nothing.
export function sharedOf(search: string): Shared | null {
  const q = new URLSearchParams(search);
  const field = (name: string) => q.get(name)?.trim() || null;
  const url = field("url"), text = field("text"), title = field("title");
  // A selection, or what an app says with its link (Android's text often has the link in it already): the link after it.
  const source = url ? (text && !text.includes(url) ? `${text}\n${url}` : text ?? url) : text;
  if (!source) return null;
  const ext = field("ext");
  return { source, title: title && title !== source ? title : null, popup: q.get("popup") === "1", ...(ext ? { ext } : {}) };
}

/// How long the extension's window stays after the chat's tab is asked for, what it put in the chat kept on the device
/// by then.
const POPUP_STAYS_MS = 1500;

type ExtensionRuntime = { sendMessage(id: string, message: unknown, answer: (reply: unknown) => void): void; lastError?: unknown };

/// From the extension's window: the chat at `url` in the browser's still.fail tab, which the extension finds (or opens)
/// and goes to, closing this window (apps/extension/background.js). With no extension to ask (or one that cannot), in
/// a new tab, this window closing after.
function openFromPopup(s: Shared, url: string): void {
  const alone = () => { window.open(url, "_blank"); setTimeout(() => window.close(), POPUP_STAYS_MS); };
  const runtime = (globalThis as { chrome?: { runtime?: ExtensionRuntime } }).chrome?.runtime;
  if (!s.ext || !runtime?.sendMessage) return alone();
  try {
    runtime.sendMessage(s.ext, { open: url }, (reply) => {
      if (runtime.lastError || (reply as { ok?: boolean } | undefined)?.ok !== true) alone();
    });
  } catch {
    alone();
  }
}

/// What the page says to mbui's web host (apps/mbui mbui/src/host/host_js.mbt `shared_in`, `over_done`): what was shared,
/// taken once (the address then the app's own, `/`), and the app over another done.
interface ShareHook { take(): string; done(openApp: boolean): void }

/// Set up as the page loads, before the host: what /share was given waits for the app (signed in, it takes it; signing
/// in first comes back to this same address); in the extension's window the app is over another, its chat links going
/// to the browser's still.fail tab and the window going once its sheet is let go of.
export function takeShare(post: (channel: string, json: string) => void, wrapOpen: (open: (url: string) => boolean) => void): void {
  if (location.pathname !== "/share") return;
  const search = location.search;
  const shared = sharedOf(search);
  let taken = false;
  const hook: ShareHook = {
    take() {
      if (taken || shared === null) return "";
      taken = true;
      history.replaceState(null, "", "/");
      return JSON.stringify({ text: shared.source, ...(shared.title ? { title: shared.title } : {}) });
    },
    // let go of, the window goes; 打开 still.fail (signed out here: signed in first), what is shared in a tab of its own
    done(openApp) {
      if (!shared?.popup) return;
      if (openApp) {
        const q = new URLSearchParams(search);
        q.delete("popup");
        q.delete("ext");
        window.open(`${location.origin}/share?${q}`, "_blank");
      }
      window.close();
    },
  };
  (globalThis as { __mbshare?: ShareHook }).__mbshare = hook;
  if (shared?.popup) {
    post("system", JSON.stringify({ over: true }));
    wrapOpen((url) => (openFromPopup(shared, new URL(url, location.origin).href), true));
  }
}
