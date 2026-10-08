// The page's way to the core's utility process (web/src/core/client.ts,
// desktopOpener). A MessagePort cannot cross the context bridge, so it comes
// to the page as a window message, tagged with the id the page asked with.
import { contextBridge, ipcRenderer } from "electron";

const desktop = {
  openCore: (id: number) => ipcRenderer.send("core:open", id),
  /** The host a station's web service is shown at (stillfail-preview://<host>/): see main.ts, previews. */
  previewHost: (station: string, port: number): Promise<string | null> => ipcRenderer.invoke("preview:host", station, port),
  /** The page is in a workspace, reached as `account`: this machine's station may join it (see main.ts). */
  inWorkspace: (account: string, workspace: string) => ipcRenderer.send("station:workspace", account, workspace),
  /** The station the app carries: where it stands, and joining it to a workspace when asked to (main.ts, station:join). */
  station: {
    state: (): Promise<unknown> => ipcRenderer.invoke("station:state"),
    join: (account: string, workspace: string): Promise<unknown> => ipcRenderer.invoke("station:join", account, workspace),
  },
  /** The cloud's origin: its links (https://…/o/…) are the app's own. */
  cloudOrigin: ipcRenderer.sendSync("app:cloud-origin") as string,
  /** This build's version (0.1.<commits>). */
  version: ipcRenderer.sendSync("app:version") as string,
  /** The beta app (「youdid.wtf」, beside the released one: main.ts BETA). */
  beta: ipcRenderer.sendSync("app:beta") as boolean,
  /** The scheme a sign-in comes back to the app on (stillfail, or the beta app's stillfail-beta). */
  scheme: ipcRenderer.sendSync("app:scheme") as string,
  /** The language the page speaks (zh or en), for the app's menus and dialogs (main.ts). */
  language: (lang: string) => ipcRenderer.send("app:language", lang),
  /** A newer build of the app: what there is of it now, each change after, and downloading and installing it (main.ts). */
  appUpdate: {
    state: (): Promise<unknown> => ipcRenderer.invoke("update:state"),
    watch: (listener: (state: unknown) => void): (() => void) => {
      const on = (_event: unknown, state: unknown) => listener(state);
      ipcRenderer.on("update:state", on);
      return () => ipcRenderer.off("update:state", on);
    },
    start: () => ipcRenderer.send("update:start"),
    /** Asks for a newer build now: what it found (main.ts, UpdateCheck). */
    check: (): Promise<unknown> => ipcRenderer.invoke("update:check"),
  },
  /** The dock on the screen's edge (main.ts, dock.mts): its settings, null where it cannot run. */
  dock: {
    get: (): Promise<unknown> => ipcRenderer.invoke("dock:get"),
    set: (settings: unknown): Promise<unknown> => ipcRenderer.invoke("dock:set", settings),
  },
  /** Whether the app tells about the chats (its main process shows the notices: main.ts). */
  notify: {
    get: (): Promise<boolean | null> => ipcRenderer.invoke("notify:get"),
    set: (on: boolean): Promise<void> => ipcRenderer.invoke("notify:set", on),
  },
  /** The menu bar's items for the page's actions (main.ts setMenu, web/src/keymap.ts): their keys and which can be done now, and one chosen. */
  menu: {
    state: (state: unknown) => ipcRenderer.send("menu:state", state),
    onAction: (listener: (action: string) => void): (() => void) => {
      const on = (_event: unknown, action: string) => listener(action);
      ipcRenderer.on("menu:action", on);
      return () => ipcRenderer.off("menu:action", on);
    },
  },
  /** The computer woke from sleep after `away` ms (main.ts): the page's core gives up what is under way (client.ts). */
  onResume: (listener: (away: number) => void): (() => void) => {
    const on = (_event: unknown, away: number) => listener(away);
    ipcRenderer.on("power:resume", on);
    return () => ipcRenderer.off("power:resume", on);
  },
  /** The computer's network became another (main.ts followNetwork): the page's core opens its connections anew. */
  onNetwork: (listener: () => void): (() => void) => {
    const on = () => listener();
    ipcRenderer.on("network:changed", on);
    return () => ipcRenderer.off("network:changed", on);
  },
  /**
   * The app asks for the image a picture right-clicked stands in for (main.ts, wholeImage): `answer` gives it whole as a
   * PNG, or null where the picture is the image itself (web/src/wholeImages.ts). The returned function stops answering.
   */
  onImageWanted: (answer: (src: string) => Promise<Uint8Array | null>): (() => void) => {
    const on = (_event: unknown, id: number, src: string) => {
      void answer(src).catch(() => null).then((png) => ipcRenderer.send("image:whole", id, png));
    };
    ipcRenderer.on("image:wanted", on);
    return () => ipcRenderer.off("image:wanted", on);
  },
};
contextBridge.exposeInMainWorld("stillfailDesktop", desktop);
// Its name before the rename, while pages built before it may still look for it (a dev server's, dev.sh HMR=1).
contextBridge.exposeInMainWorld("emberDesktop", desktop);

// Tagged under both names too (emberCore, emberNavigate: what pages from before the rename read).
ipcRenderer.on("core:port", (event, id: number) => window.postMessage({ stillfailCore: "port", emberCore: "port", id }, location.origin, event.ports));
ipcRenderer.on("core:exit", (_event, reason: string) => window.postMessage({ stillfailCore: "exit", emberCore: "exit", reason }, location.origin));
// Whether the window is full screen, on the page's root (data-fullscreen): no window buttons to keep room for then.
ipcRenderer.on("window:fullscreen", (_event, on: boolean) => document.documentElement.toggleAttribute("data-fullscreen", on));
// An item's link opened from outside: the page goes there itself.
ipcRenderer.on("app:navigate", (_event, path: string) => window.postMessage({ stillfailNavigate: path, emberNavigate: path }, location.origin));
