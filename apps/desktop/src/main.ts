// ember's desktop app: the web app (`pnpm run build:cloud`'s dist/cloud-app)
// in a window, with its client core in a utility process instead of the
// browser's SharedWorker (docs/client-core.md). Only the host is different:
// the page is served from app://ember, the core runs natively (client/node,
// the full iroh endpoint) with its data in userData, and a sign-in finished in
// the system browser comes back through ember://auth/callback.
import { app, BrowserWindow, ipcMain, MessageChannelMain, net, protocol, shell, utilityProcess, type MessagePortMain, type UtilityProcess } from "electron";
import { createHash } from "node:crypto";
import { stat } from "node:fs/promises";
import { join, normalize } from "node:path";
import { pathToFileURL } from "node:url";

const CLOUD_ORIGIN = (process.env.EMBER_CLOUD_ORIGIN ?? "https://ember.3720.org").replace(/\/+$/, "");
/**
 * Where the page comes from: the web app packed with the app, at app://ember; or, run from the source with
 * `--dev-url=<a Vite dev server>` (dev.sh HMR=1), that server, so changes to the page show as they are saved.
 */
const DEV_URL = process.argv.find((arg) => arg.startsWith("--dev-url="))?.slice("--dev-url=".length).replace(/\/+$/, "") ?? null;
const APP_ORIGIN = DEV_URL ? new URL(DEV_URL).origin : "app://ember";
/** Where ember cloud sends a native sign-in back to (cloud/src/auth.ts, APP_REDIRECT). */
const AUTH_CALLBACK = "ember://auth/callback";
/** build/ (apps/desktop/build.sh) when run from the source, the app's Resources when packaged: web/ and ember_core.node. */
const resources = app.isPackaged ? process.resourcesPath : join(__dirname, "..");
const web = join(resources, "web");

// A standard, secure origin: the page's absolute paths, storage and clipboard work as on https://.
protocol.registerSchemesAsPrivileged([
  { scheme: "app", privileges: { standard: true, secure: true, supportFetchAPI: true, codeCache: true } },
  // A web service on a station's machine, shown in a frame (see preview below): an origin of its own per station and port.
  { scheme: "ember-preview", privileges: { standard: true, secure: true, supportFetchAPI: true, corsEnabled: true, stream: true } },
]);

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
    dropOwnLink("核心进程退出了");
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

// The app's own way to the core, for what it serves itself (previews): a client of the core as a page is, making calls.
interface OwnLink { port: MessagePortMain; next: number; waiting: Map<number, { resolve: (value: unknown) => void; reject: (error: Error) => void }> }
let own: OwnLink | null = null;

function dropOwnLink(reason: string): void {
  if (!own) return;
  for (const { reject } of own.waiting.values()) reject(new Error(reason));
  own.port.close();
  own = null;
}

function coreCall(name: string, params: unknown): Promise<unknown> {
  if (!own) {
    const { port1, port2 } = new MessageChannelMain();
    coreProcess().postMessage(null, [port1]);
    const link: OwnLink = { port: port2, next: 1, waiting: new Map() };
    port2.on("message", ({ data }) => {
      const message = JSON.parse(String(data)) as { id?: number; ok?: unknown; error?: { message?: string } };
      const waiting = message.id === undefined ? undefined : link.waiting.get(message.id);
      if (!waiting) return;
      link.waiting.delete(message.id!);
      if (message.error) waiting.reject(new Error(message.error.message ?? "调用失败"));
      else waiting.resolve(message.ok);
    });
    port2.start();
    own = link;
  }
  const link = own;
  const id = link.next++;
  return new Promise((resolve, reject) => {
    link.waiting.set(id, { resolve, reject });
    link.port.postMessage({ id, call: name, params });
  });
}

// Previews: a page asks for a station's port as a host of ember-preview:// (p<port>-<the station's hash>), puts it in a
// frame, and every request of that frame comes here and goes to the station through the core (station.preview), over
// the mesh like any other call. The service's scripts are on an origin of their own, apart from the app's.
const previewStations = new Map<string, string>();

ipcMain.handle("preview:host", (event, station: unknown, port: unknown) => {
  if (!event.senderFrame?.url.startsWith(`${APP_ORIGIN}/`) || typeof station !== "string" || !Number.isInteger(port) || (port as number) < 1 || (port as number) > 65535) return null;
  const id = createHash("sha256").update(station).digest("hex").slice(0, 12);
  previewStations.set(id, station);
  return `p${port}-${id}`;
});

function plain(status: number, text: string): Response {
  return new Response(text, { status, headers: { "content-type": "text/plain; charset=utf-8" } });
}

async function preview(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const host = /^p(\d{1,5})-([0-9a-f]{12})$/.exec(url.hostname);
  const station = host ? previewStations.get(host[2]!) : undefined;
  if (!host || !station) return plain(404, "预览已经失效：在 ember 里重新打开它。");
  const body = request.method === "GET" || request.method === "HEAD" ? "" : Buffer.from(await request.arrayBuffer()).toString("base64");
  const headers: [string, string][] = [];
  request.headers.forEach((value, name) => headers.push([name, value]));
  try {
    const answer = await coreCall("station.preview", {
      station, port: Number(host[1]), method: request.method, path: url.pathname + url.search, headers, body,
    }) as { status: number; headers: [string, string][]; body: string };
    const empty = request.method === "HEAD" || [101, 204, 205, 304].includes(answer.status);
    return new Response(empty ? null : Buffer.from(answer.body, "base64"), { status: answer.status, headers: answer.headers });
  } catch (error) {
    return plain(502, `没能从 station 取到：${error instanceof Error ? error.message : String(error)}`);
  }
}

/** Pages outside the app open in the system browser, as a new tab would. */
function external(url: string): void {
  if (/^https?:\/\//.test(url)) void shell.openExternal(url);
}

function open(path = "/"): BrowserWindow {
  const window = new BrowserWindow({
    width: 1280,
    height: 820,
    show: false,
    // No title bar: the buttons sit in the page's top row (44 px, web/src/app.css), centred on it.
    titleBarStyle: "hiddenInset",
    trafficLightPosition: { x: 16, y: 15 },
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
/**
 * An ember:// URL handed to the app: the sign-in coming back (ember://auth/callback, loaded as the page), or an
 * item's link (ember://o/<workspace>/<station>/<session>, from the web's /o/ page), which the page opens in place.
 */
function arrived(url: string): void {
  const item = /^ember:\/\/o\/([^/?#]+)\/([^/?#]+)\/([^/?#]+)/.exec(url);
  if (!url.startsWith(AUTH_CALLBACK) && !item) return;
  const path = item ? `/o/${item[1]}/${item[2]}/${item[3]}` : `/auth/callback${new URL(url).search}`;
  const window = BrowserWindow.getFocusedWindow() ?? BrowserWindow.getAllWindows()[0];
  if (!window) {
    open(path);
    return;
  }
  if (item) window.webContents.send("app:navigate", path);
  else void window.loadURL(`${APP_ORIGIN}${path}`);
  if (window.isMinimized()) window.restore();
  window.focus();
}

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  // Run from the source (Electron's own app with this directory, dev.sh), ember:// opens it with the directory.
  if (app.isPackaged) app.setAsDefaultProtocolClient("ember");
  else app.setAsDefaultProtocolClient("ember", process.execPath, [app.getAppPath()]);
  // macOS hands the app its URLs here (possibly before it is ready); elsewhere they start a second instance.
  app.on("open-url", (event, url) => {
    event.preventDefault();
    void app.whenReady().then(() => arrived(url));
  });
  app.on("second-instance", (_event, argv) => {
    const url = argv.find((arg) => arg.startsWith("ember://"));
    if (url) arrived(url);
    else BrowserWindow.getAllWindows()[0]?.focus();
  });
  void app.whenReady().then(() => {
    protocol.handle("app", serve);
    protocol.handle("ember-preview", preview);
    open();
  });
  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) open();
  });
  app.on("window-all-closed", () => {
    if (process.platform !== "darwin") app.quit();
  });
}
