// The page's way to the core's utility process (web/src/core/client.ts,
// desktopOpener). A MessagePort cannot cross the context bridge, so it comes
// to the page as a window message, tagged with the id the page asked with.
import { contextBridge, ipcRenderer } from "electron";

contextBridge.exposeInMainWorld("emberDesktop", {
  openCore: (id: number) => ipcRenderer.send("core:open", id),
  /** The host a station's web service is shown at (ember-preview://<host>/): see main.ts, previews. */
  previewHost: (station: string, port: number): Promise<string | null> => ipcRenderer.invoke("preview:host", station, port),
  /** The page is in a workspace, reached as `account`: this machine's station may join it (see main.ts). */
  inWorkspace: (account: string, workspace: string) => ipcRenderer.send("station:workspace", account, workspace),
});

ipcRenderer.on("core:port", (event, id: number) => window.postMessage({ emberCore: "port", id }, location.origin, event.ports));
ipcRenderer.on("core:exit", (_event, reason: string) => window.postMessage({ emberCore: "exit", reason }, location.origin));
// An item's link opened from outside: the page goes there itself.
ipcRenderer.on("app:navigate", (_event, path: string) => window.postMessage({ emberNavigate: path }, location.origin));
