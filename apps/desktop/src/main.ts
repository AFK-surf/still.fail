// ember's desktop app: the web app (`pnpm run build:cloud`'s dist/cloud-app)
// in a window, with its client core in a utility process instead of the
// browser's SharedWorker (docs/client-core.md). Only the host is different:
// the page is served from app://ember, the core runs natively (client/node,
// the full iroh endpoint) with its data in userData, and a sign-in finished in
// the system browser comes back through ember://auth/callback.
import { app, BrowserWindow, ipcMain, MessageChannelMain, net, protocol, shell, utilityProcess, type UtilityProcess } from "electron";
import { stat } from "node:fs/promises";
import { join, normalize } from "node:path";
import { pathToFileURL } from "node:url";

const CLOUD_ORIGIN = (process.env.EMBER_CLOUD_ORIGIN ?? "https://ember.3720.org").replace(/\/+$/, "");
const APP_ORIGIN = "app://ember";
/** Where ember cloud sends a native sign-in back to (cloud/src/auth.ts, APP_REDIRECT). */
const AUTH_CALLBACK = "ember://auth/callback";
/** build/ (apps/desktop/build.sh) when run from the source, the app's Resources when packaged: web/ and ember_core.node. */
const resources = app.isPackaged ? process.resourcesPath : join(__dirname, "..");
const web = join(resources, "web");

// A standard, secure origin: the page's absolute paths, storage and clipboard work as on https://.
protocol.registerSchemesAsPrivileged([{ scheme: "app", privileges: { standard: true, secure: true, supportFetchAPI: true, codeCache: true } }]);

/** A file of the web app, or for any other path (a client-side route) its index.html, as ember cloud serves it (cloud/src/index.ts). */
async function serve(request: Request): Promise<Response> {
  const file = join(web, normalize(decodeURIComponent(new URL(request.url).pathname)));
  const found = await stat(file).then((s) => s.isFile(), () => false);
  return net.fetch(pathToFileURL(found ? file : join(web, "index.html")).toString());
}

let core: UtilityProcess | null = null;

/** The core's process, started when a page first asks for it and again after it exited. */
function coreProcess(): UtilityProcess {
  if (core) return core;
  const child = utilityProcess.fork(join(__dirname, "core.js"), [join(app.getPath("userData"), "core"), CLOUD_ORIGIN, join(resources, "ember_core.node")], { serviceName: "ember core" });
  child.on("exit", (code) => {
    if (core === child) core = null;
    // Its ports are dead with it: every page opens a new one.
    for (const window of BrowserWindow.getAllWindows()) {
      if (!window.isDestroyed()) window.webContents.send("core:exit", `核心进程退出了（${code}）`);
    }
  });
  core = child;
  return child;
}

// A page asks for a channel to the core (web/src/core/client.ts, desktopOpener): one end goes to the core, the other to the page.
ipcMain.on("core:open", (event, id: unknown) => {
  if (typeof id !== "number" || !event.senderFrame?.url.startsWith(`${APP_ORIGIN}/`)) return;
  const { port1, port2 } = new MessageChannelMain();
  coreProcess().postMessage(null, [port1]);
  event.sender.postMessage("core:port", id, [port2]);
});

/** Pages outside the app open in the system browser, as a new tab would. */
function external(url: string): void {
  if (/^https?:\/\//.test(url)) void shell.openExternal(url);
}

function open(path = "/"): BrowserWindow {
  const window = new BrowserWindow({
    width: 1280,
    height: 820,
    show: false,
    webPreferences: { preload: join(__dirname, "preload.js"), sandbox: true, contextIsolation: true },
  });
  window.once("ready-to-show", () => window.show());
  window.webContents.setWindowOpenHandler(({ url }) => {
    external(url);
    return { action: "deny" };
  });
  // Leaving the app (a sign-in going to Google, a link) goes to the system browser instead.
  window.webContents.on("will-navigate", (event, url) => {
    if (url.startsWith(`${APP_ORIGIN}/`)) return;
    event.preventDefault();
    external(url);
  });
  void window.loadURL(`${APP_ORIGIN}${path}`);
  return window;
}

/** The system browser finished a sign-in: the page's own /auth/callback completes it (web/src/cloud/gate.tsx). */
function signedIn(url: string): void {
  if (!url.startsWith(AUTH_CALLBACK)) return;
  const path = `/auth/callback${new URL(url).search}`;
  const window = BrowserWindow.getFocusedWindow() ?? BrowserWindow.getAllWindows()[0];
  if (!window) {
    open(path);
    return;
  }
  void window.loadURL(`${APP_ORIGIN}${path}`);
  if (window.isMinimized()) window.restore();
  window.focus();
}

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.setAsDefaultProtocolClient("ember");
  // macOS hands the app its URLs here (possibly before it is ready); elsewhere they start a second instance.
  app.on("open-url", (event, url) => {
    event.preventDefault();
    void app.whenReady().then(() => signedIn(url));
  });
  app.on("second-instance", (_event, argv) => {
    const url = argv.find((arg) => arg.startsWith(AUTH_CALLBACK));
    if (url) signedIn(url);
    else BrowserWindow.getAllWindows()[0]?.focus();
  });
  void app.whenReady().then(() => {
    protocol.handle("app", serve);
    open();
  });
  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) open();
  });
  app.on("window-all-closed", () => {
    if (process.platform !== "darwin") app.quit();
  });
}
