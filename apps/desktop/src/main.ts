// ember's desktop app: the web app (`pnpm run build:cloud`'s dist/cloud-web)
// in a window, with its client core in a utility process instead of the
// browser's SharedWorker (docs/client-core.md). Only the host is different:
// the page is served from app://ember, the core runs natively (client/node,
// the full iroh endpoint) with its data in userData, and a sign-in finished in
// the system browser comes back through ember://auth/callback.
import { app, BrowserWindow, ipcMain, MessageChannelMain, net, Notification, protocol, shell, utilityProcess, type MessagePortMain, type UtilityProcess } from "electron";
import { autoUpdater } from "electron-updater";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, writeFileSync } from "node:fs";
import { stat } from "node:fs/promises";
import { hostname } from "node:os";
import { join, normalize } from "node:path";
import { pathToFileURL } from "node:url";
import { LocalStation } from "./station";

const CLOUD_ORIGIN = (process.env.EMBER_CLOUD_ORIGIN ?? "https://ember.3720.org").replace(/\/+$/, "");
/**
 * Where the page comes from: the web app packed with the app, at app://ember; or, run from the source with
 * `--dev-url=<a Vite dev server>` (dev.sh HMR=1), that server, so changes to the page show as they are saved.
 */
const DEV_URL = process.argv.find((arg) => arg.startsWith("--dev-url="))?.slice("--dev-url=".length).replace(/\/+$/, "") ?? null;
const APP_ORIGIN = DEV_URL ? new URL(DEV_URL).origin : "app://ember";
// The dev server is plain http on the LAN: taken as secure, as app://ember is, so the page has what a secure page has
// (the clipboard among it) and behaves as the packed one does.
if (DEV_URL) app.commandLine.appendSwitch("unsafely-treat-insecure-origin-as-secure", APP_ORIGIN);
/** Where ember cloud sends a native sign-in back to (cloud/src/auth.ts, APP_REDIRECT). */
const AUTH_CALLBACK = "ember://auth/callback";
/** build/ (apps/desktop/build.sh) when run from the source, the app's Resources when packaged: web/, ember_core.node and station/. */
const resources = app.isPackaged ? process.resourcesPath : join(__dirname, "..");
const web = join(resources, "web");
const station = new LocalStation(join(resources, app.isPackaged ? "station" : "station/ember"));

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

// ember cloud's origin, for the page to know its links (web/src/core/client.ts, EmberDesktop.cloudOrigin).
ipcMain.on("app:cloud-origin", (event) => { event.returnValue = CLOUD_ORIGIN; });

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

// Previews: a page asks for a station's port as a host of ember-preview:// (p<port>-<the station's hash>), puts that
// host's /_ember/frame (FRAME below) in a frame, and every other request of the host comes here and goes to the station
// through the core (station.preview), over the mesh like any other call. The service's scripts are on an origin of
// their own, apart from the app's.
const previewStations = new Map<string, string>();

ipcMain.handle("preview:host", (event, station: unknown, port: unknown) => {
  if (!event.senderFrame?.url.startsWith(`${APP_ORIGIN}/`) || typeof station !== "string" || !Number.isInteger(port) || (port as number) < 1 || (port as number) > 65535) return null;
  const id = createHash("sha256").update(station).digest("hex").slice(0, 12);
  previewStations.set(id, station);
  return `p${port}-${id}`;
});

// The frame a page puts in its own (ember-preview://<host>/_ember/frame), as the preview host's is on the web
// (cloud/src/preview.ts): the service in a frame of its own, and a history of its own. The bar's back, forward and go
// move along it with replace(), so they never step the page it sits in (a frame shares its window's history). Where it
// is, and whether it can go back or on, is said back to the page as it loads and as a page moves itself.
const FRAME = `<!doctype html>
<meta charset="utf-8">
<title>ember preview</title>
<style>
  html, body { margin: 0; height: 100%; background: #fff; }
  iframe { display: block; width: 100%; height: 100%; border: 0; }
</style>
<script>
  const params = new URLSearchParams(location.search);
  const nonce = params.get("n") || "";
  const trail = [];
  let here = -1;
  let moving = false;
  let said = "";
  const inner = document.createElement("iframe");
  const where = () => {
    try {
      // A redirect on its way (see preview below) is no place of its own.
      if (inner.contentDocument.querySelector("meta[name=ember-redirect]")) return null;
      const at = inner.contentWindow.location;
      return at.protocol === "about:" ? null : at.pathname + at.search + at.hash;
    } catch { return null; }
  };
  const report = () => {
    const path = where();
    if (path === null) return;
    if (!moving && trail[here] !== path) {
      trail.splice(here + 1);
      trail.push(path);
      here = trail.length - 1;
    }
    const state = path + "|" + here + "|" + trail.length;
    if (state === said) return;
    said = state;
    parent.postMessage({ type: "ember-preview-at", nonce, path, back: here > 0, forward: here < trail.length - 1 }, "*");
  };
  const replace = (path) => {
    moving = true;
    inner.contentWindow.location.replace(path);
  };
  window.addEventListener("message", (event) => {
    if (event.source !== parent || event.data?.type !== "ember-preview-nav") return;
    const { action, path } = event.data;
    if (action === "back" && here > 0) replace(trail[--here]);
    else if (action === "forward" && here < trail.length - 1) replace(trail[++here]);
    else if (action === "reload") { moving = true; inner.contentWindow.location.reload(); }
    else if (action === "go" && typeof path === "string" && path.startsWith("/")) inner.contentWindow.location.replace(path);
  });
  inner.src = params.get("path") || "/";
  inner.addEventListener("load", () => { report(); moving = false; });
  addEventListener("DOMContentLoaded", () => document.body.append(inner));
  setInterval(report, 500);
</script>
<body></body>
`;

function plain(status: number, text: string): Response {
  return new Response(text, { status, headers: { "content-type": "text/plain; charset=utf-8" } });
}

async function preview(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const host = /^p(\d{1,5})-([0-9a-f]{12})$/.exec(url.hostname);
  const station = host ? previewStations.get(host[2]!) : undefined;
  if (!host || !station) return plain(404, "预览已经失效：在 ember 里重新打开它。");
  if (url.pathname === "/_ember/frame") return new Response(FRAME, { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" } });
  const body = request.method === "GET" || request.method === "HEAD" ? "" : Buffer.from(await request.arrayBuffer()).toString("base64");
  const headers: [string, string][] = [];
  request.headers.forEach((value, name) => headers.push([name, value]));
  try {
    // The frame takes no redirect from this handler. One of a page it goes to (its address must change, a page's own
    // routes read it): the frame is sent there by a page that goes at once. One of anything else is followed here.
    // A redirect off the service is said.
    // A custom scheme's requests may come without Sec-Fetch-Dest: a page is then what asks for HTML.
    const dest = request.headers.get("sec-fetch-dest");
    const page = dest ? ["document", "iframe"].includes(dest) : (request.headers.get("accept") ?? "").includes("text/html");
    let path = url.pathname + url.search;
    let answer: { status: number; headers: [string, string][]; body: string } | null = null;
    for (let hops = 0; hops < 5 && !answer; hops++) {
      const got = await coreCall("station.preview", { station, port: Number(host[1]), method: request.method, path, headers, body }) as { status: number; headers: [string, string][]; body: string };
      const location = got.status >= 300 && got.status < 400 ? got.headers.find(([k]) => k.toLowerCase() === "location")?.[1] : undefined;
      if (!location) { answer = got; break; }
      const next = new URL(location, `http://localhost:${host[1]}${path}`);
      if (next.hostname !== "localhost" && next.hostname !== "127.0.0.1") return plain(502, `这个网页跳到了别的地址：${location}`);
      path = next.pathname + next.search;
      if (page) return new Response(`<!doctype html><meta charset="utf-8"><meta name="ember-redirect"><script>location.replace(${JSON.stringify(path)})</script>`, { headers: { "content-type": "text/html; charset=utf-8" } });
    }
    if (!answer) return plain(508, "跳转太多次了");
    const empty = request.method === "HEAD" || [101, 204, 205, 304].includes(answer.status);
    return new Response(empty ? null : Buffer.from(answer.body, "base64"), { status: answer.status, headers: answer.headers });
  } catch (error) {
    return plain(502, `没能从 station 取到：${error instanceof Error ? error.message : String(error)}`);
  }
}

// This machine as a station: the one the app runs (station.ts), or one installed here. A page in a workspace says so
// (web/src/cloud/workspace.tsx); a station in no workspace yet joins it, once: one removed from its workspace later is
// not joined again by itself. Only the workspace's owner and admins can add stations: for others the cloud says no,
// and it is tried again in the next workspace they open.
const joinedOnce = join(app.getPath("userData"), "station-joined");
let joining = false;

ipcMain.on("station:workspace", (event, account: unknown, workspace: unknown) => {
  if (!event.senderFrame?.url.startsWith(`${APP_ORIGIN}/`) || typeof account !== "string" || typeof workspace !== "string") return;
  void joinHere(account, workspace);
});

async function joinHere(account: string, workspace: string): Promise<void> {
  if (joining || !station.carried || station.enrolled || existsSync(joinedOnce)) return;
  joining = true;
  try {
    const made = await coreCall("cloud.request", {
      account, method: "POST", path: `/v1/workspaces/${encodeURIComponent(workspace)}/enrollments`, body: { name: machineName() },
    }) as { token: string };
    await station.enroll(CLOUD_ORIGIN, made.token);
    writeFileSync(joinedOnce, workspace);
    console.info("this machine joined the workspace as a station", workspace);
  } catch (error) {
    console.warn("this machine did not join the workspace as a station", workspace, error instanceof Error ? error.message : error);
  } finally {
    joining = false;
  }
}

/** The machine's name as the user set it (System Settings, Sharing), for its station's. */
function machineName(): string {
  try {
    return execFileSync("scutil", ["--get", "ComputerName"], { encoding: "utf8" }).trim();
  } catch {
    return hostname().replace(/\.local$/, "");
  }
}

// Keeping the app current: ember cloud has the latest build (scripts/release.sh desktop puts it in /releases/desktop/),
// looked for at start and every few hours. A newer one is downloaded as the app runs and installed when it quits;
// a notification says it is ready, and clicked it quits (the station stopped first) and opens the new one.
const UPDATE_EVERY = 4 * 60 * 60 * 1000;

function keepUpdated(): void {
  if (!app.isPackaged) return;
  autoUpdater.setFeedURL({ provider: "generic", url: `${CLOUD_ORIGIN}/releases/desktop` });
  autoUpdater.logger = null;
  autoUpdater.on("error", (error) => console.warn("updating the app failed", error.message));
  let said: string | null = null;
  autoUpdater.on("update-downloaded", ({ version }) => {
    if (said === version || !Notification.isSupported()) return;
    said = version;
    const note = new Notification({ title: `ember ${version} 已经准备好`, body: "点这里重启完成更新；不点也会在下次退出时装好。" });
    note.on("click", () => void stopStation().then(() => autoUpdater.quitAndInstall()));
    note.show();
  });
  const check = () => void autoUpdater.checkForUpdates().catch((error: Error) => console.warn("looking for an update failed", error.message));
  check();
  setInterval(check, UPDATE_EVERY);
}

/** Pages outside the app open in the system browser, as a new tab would. */
function external(url: string): void {
  if (/^https?:\/\//.test(url)) void shell.openExternal(url);
}

/**
 * A window of the app at `path`. The app's own window has no title bar: its buttons sit in the page's top row (44 px,
 * web/src/app.css), centred on it. A page of the app opened in a new window (a web service's page of its own) has one:
 * its page has no row for them.
 */
function open(path = "/", titled = false): BrowserWindow {
  const window = new BrowserWindow({
    width: titled ? 1100 : 1280,
    height: 820,
    show: false,
    ...(titled ? {} : { titleBarStyle: "hiddenInset", trafficLightPosition: { x: 16, y: 15 } } as const),
    webPreferences: { preload: join(__dirname, "preload.js"), sandbox: true, contextIsolation: true },
  });
  window.once("ready-to-show", () => window.show());
  // A new window of the app's own pages opens in the app, as another window like this one; anything else is outside.
  window.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith(`${APP_ORIGIN}/`)) {
      const at = new URL(url);
      open(at.pathname + at.search + at.hash, true);
    } else external(url);
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
  // An item's link may name a web service to open with it (?service=<job>).
  const path = item ? `/o/${item[1]}/${item[2]}/${item[3]}${new URL(url).search}` : `/auth/callback${new URL(url).search}`;
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

let stationStopped = false;

/** Stops the station (and its runtimes) before the app quits: after it, quitting goes ahead without waiting again. */
async function stopStation(): Promise<void> {
  if (stationStopped) return;
  await station.stop().catch(() => {});
  stationStopped = true;
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
    station.start();
    keepUpdated();
  });
  // The station stops with the app, its runtimes first; the app quits once it has.
  app.on("before-quit", (event) => {
    if (stationStopped) return;
    event.preventDefault();
    void stopStation().then(() => app.quit());
  });
  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) open();
  });
  app.on("window-all-closed", () => {
    if (process.platform !== "darwin") app.quit();
  });
}
