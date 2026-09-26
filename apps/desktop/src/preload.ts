// The page's way to the core's utility process (web/src/core/client.ts,
// desktopOpener). A MessagePort cannot cross the context bridge, so it comes
// to the page as a window message, tagged with the id the page asked with.
import { contextBridge, ipcRenderer } from "electron";

contextBridge.exposeInMainWorld("emberDesktop", {
  openCore: (id: number) => ipcRenderer.send("core:open", id),
});

ipcRenderer.on("core:port", (event, id: number) => window.postMessage({ emberCore: "port", id }, location.origin, event.ports));
ipcRenderer.on("core:exit", (_event, reason: string) => window.postMessage({ emberCore: "exit", reason }, location.origin));
