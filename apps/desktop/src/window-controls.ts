import { type BrowserWindow } from "electron";
import { join } from "node:path";

interface SnapTarget {
  setBounds(handle: Buffer, x: number, y: number, width: number, height: number): void;
  detach(handle: Buffer): void;
}
const SNAP_MESSAGE = 0x8000 + 71;

/** A missing/broken addon leaves Windows' own controls available. Builds verify the packaged addon too. */
export function loadSnapTarget(resources: string): SnapTarget | null {
  if (process.platform !== "win32") return null;
  try { return require(join(resources, "window-controls.node")) as SnapTarget; }
  catch (error) { console.error("Window controls: using the system buttons", error); return null; }
}

/** Only the main window's own page can call this (main.ts). No HWND or arbitrary messages cross the page bridge. */
export function attachWindowControls(window: BrowserWindow, native: SnapTarget) {
  const handle = window.getNativeWindowHandle();
  let hover = false;
  let pressed = false;
  // On Windows isFullScreen() can still report the old value inside the transition event.
  let fullscreen = window.isFullScreen();
  const state = () => ({ maximized: window.isMaximized(), fullscreen, hover, pressed });
  const tell = () => { if (!window.isDestroyed() && !window.webContents.isDestroyed()) window.webContents.send("window:state", state()); };
  const hide = () => {
    native.setBounds(handle, 0, 0, 0, 0);
    hover = pressed = false;
  };
  const action = (value: unknown) => {
    if (value === "minimize") window.minimize();
    if (value === "maximize" && !window.isFullScreen() && window.isMaximizable()) {
      if (window.isMaximized()) window.unmaximize(); else window.maximize();
    }
    if (value === "close") window.close();
  };
  window.hookWindowMessage(SNAP_MESSAGE, (value) => {
    const next = value.readUInt32LE();
    hover = next === 1 || next === 2;
    pressed = next === 2;
    if (next === 3) action("maximize");
    tell();
  });
  window.on("maximize", tell);
  window.on("unmaximize", tell);
  window.on("enter-full-screen", () => { fullscreen = true; hide(); tell(); });
  window.on("leave-full-screen", () => { fullscreen = false; tell(); });
  // No invisible input target may remain on a reloading page or over a crashed renderer.
  window.webContents.on("did-start-navigation", (_event, _url, inPlace, mainFrame) => { if (mainFrame && !inPlace) hide(); });
  window.webContents.on("render-process-gone", hide);
  window.webContents.on("did-finish-load", tell);
  return {
    state, action,
    bounds(value: unknown) {
      if (value === null || fullscreen) { hide(); return; }
      if (!Array.isArray(value) || value.length !== 4 || !value.every((n) => Number.isSafeInteger(n) && n >= 0 && n <= 65535)) return;
      const [x, y, width, height] = value as [number, number, number, number];
      // The page measures the actual button including browser zoom and monitor DPI; no fixed display scale.
      native.setBounds(handle, x, y, width, height);
    },
  };
}
