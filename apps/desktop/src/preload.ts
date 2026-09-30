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
  /** The cloud's origin: its links (https://…/o/…) are the app's own. */
  cloudOrigin: ipcRenderer.sendSync("app:cloud-origin") as string,
  /** This build's version (0.1.<commits>). */
  version: ipcRenderer.sendSync("app:version") as string,
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
  /** Whether the app tells about the chats (its main process shows the notices: main.ts). */
  notify: {
    get: (): Promise<boolean | null> => ipcRenderer.invoke("notify:get"),
    set: (on: boolean): Promise<void> => ipcRenderer.invoke("notify:set", on),
  },
  /** The computer woke from sleep after `away` ms (main.ts): the page's core gives up what is under way (client.ts). */
  onResume: (listener: (away: number) => void): (() => void) => {
    const on = (_event: unknown, away: number) => listener(away);
    ipcRenderer.on("power:resume", on);
    return () => ipcRenderer.off("power:resume", on);
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
