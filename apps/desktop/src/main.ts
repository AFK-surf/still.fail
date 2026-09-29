// still.fail's desktop app: the web app (`pnpm run build:cloud`'s dist/cloud-web)
// in a window, with its client core in a utility process instead of the
// browser's SharedWorker (docs/client-core.md). Only the host is different:
// the page is served from app://ember, the core runs natively (client/node,
// the full iroh endpoint) with its data in userData, and a sign-in finished in
// the system browser comes back through stillfail://auth/callback.
import { app, BrowserWindow, ipcMain, MessageChannelMain, net, protocol, shell, utilityProcess, type MessagePortMain, type UtilityProcess } from "electron";
import { autoUpdater } from "electron-updater";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, writeFileSync } from "node:fs";
import { readFile, stat } from "node:fs/promises";
import { hostname } from "node:os";
import { join, normalize } from "node:path";
import { pathToFileURL } from "node:url";
import { FETCH_LINK, socketScript, withSocketTag } from "../../../cloud/src/previewSocket";
import { LocalStation } from "./station";
import { Bridge, CHANNEL, FORMER_APP_ID, bundleIdOf, ownBundle } from "./bridge";
import { moveUserData } from "./moves.mts";

const CLOUD_ORIGIN = (process.env.STILLFAIL_CLOUD_ORIGIN ?? process.env.EMBER_CLOUD_ORIGIN ?? "https://app.still.fail").replace(/\/+$/, "");
/**
 * Where the page comes from: the web app packed with the app, at app://ember; or, run from the source with
 * `--dev-url=<a Vite dev server>` (dev.sh HMR=1), that server, so changes to the page show as they are saved.
 */
const DEV_URL = process.argv.find((arg) => arg.startsWith("--dev-url="))?.slice("--dev-url=".length).replace(/\/+$/, "") ?? null;
// app://ember keeps its name from before the rename: the page's storage (localStorage, IndexedDB) is the origin's.
const APP_ORIGIN = DEV_URL ? new URL(DEV_URL).origin : "app://ember";
// The dev server is plain http on the LAN: taken as secure, as app://ember is, so the page has what a secure page has
// (the clipboard among it) and behaves as the packed one does.
if (DEV_URL) app.commandLine.appendSwitch("unsafely-treat-insecure-origin-as-secure", APP_ORIGIN);
/** The app's link schemes: stillfail://, and ember:// as before the rename (links made then, pages that still make them). */
const SCHEMES = ["stillfail", "ember"];
/** build/ (apps/desktop/build.sh) when run from the source, the app's Resources when packaged: web/, stillfail_core.node and station/. */
const resources = app.isPackaged ? process.resourcesPath : join(__dirname, "..");
const web = join(resources, "web");
const station = new LocalStation(join(resources, app.isPackaged ? "station" : "station/stillfail"));

/**
 * The app's data (userData) from before the rename, when it was named ember: ~/Library/Application Support/ember.
 * Named still.fail now, it would start from nothing (signed out); so the first start moves what is there to the new
 * place and leaves a link at the old one. Not while the old app runs on it (its SingletonLock names a live process):
 * then this start uses the old place, and a later one moves it.
 */
function carryOverUserData(): void {
  const former = join(app.getPath("appData"), "ember");
  const alive = (pid: number) => { try { return pid !== process.pid && process.kill(pid, 0); } catch { return false; } };
  const { dir, moved, error } = moveUserData(app.getPath("userData"), former, alive);
  if (moved) console.info("moved the app's data from", former, "to", dir);
  if (error) console.warn("the app's data could not be moved from", former, error);
  if (dir !== app.getPath("userData")) app.setPath("userData", dir);
}

carryOverUserData();

// A standard, secure origin: the page's absolute paths, storage and clipboard work as on https://.
protocol.registerSchemesAsPrivileged([
  { scheme: "app", privileges: { standard: true, secure: true, supportFetchAPI: true, codeCache: true } },
  // A web service on a station's machine, shown in a frame (see preview below): an origin of its own per station and port.
  { scheme: "stillfail-preview", privileges: { standard: true, secure: true, supportFetchAPI: true, corsEnabled: true, stream: true } },
]);

/** A file of the web app, or for any other path (a client-side route) its index.html, as the cloud serves it (cloud/src/index.ts). */
async function serve(request: Request): Promise<Response> {
  const file = join(web, normalize(decodeURIComponent(new URL(request.url).pathname)));
  const found = await stat(file).then((s) => s.isFile(), () => false);
  return net.fetch(pathToFileURL(found ? file : join(web, "index.html")).toString());
}

let core: UtilityProcess | null = null;

/** The core's process, started when a page first asks for it and again after it exited. */
function coreProcess(): UtilityProcess {
  if (core) return core;
  const child = utilityProcess.fork(join(__dirname, "core.js"), [join(app.getPath("userData"), "core"), CLOUD_ORIGIN, join(resources, "stillfail_core.node")], { serviceName: "still.fail core" });
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

// The cloud's origin, for the page to know its links (web/src/core/client.ts, StillFailDesktop.cloudOrigin).
ipcMain.on("app:cloud-origin", (event) => { event.returnValue = CLOUD_ORIGIN; });

// The app's own way to the core, for what it serves itself (previews): a client of the core as a page is, making calls.
interface OwnLink { port: MessagePortMain; next: number; waiting: Map<number, { resolve: (value: unknown) => void; reject: (error: Error) => void; onProgress?: ((value: unknown) => void) | undefined }> }
let own: OwnLink | null = null;

function dropOwnLink(reason: string): void {
  if (!own) return;
  for (const { reject } of own.waiting.values()) reject(new Error(reason));
  own.port.close();
  own = null;
}

/** A call of the core's; `onProgress` hears the values it sends before its answer, `signal` cancels it. */
function coreCall(name: string, params: unknown, onProgress?: (value: unknown) => void, signal?: AbortSignal): Promise<unknown> {
  if (!own) {
    const { port1, port2 } = new MessageChannelMain();
    coreProcess().postMessage(null, [port1]);
    const link: OwnLink = { port: port2, next: 1, waiting: new Map() };
    port2.on("message", ({ data }) => {
      const message = JSON.parse(String(data)) as { id?: number; ok?: unknown; value?: unknown; error?: { message?: string } };
      const waiting = message.id === undefined ? undefined : link.waiting.get(message.id);
      if (!waiting) return;
      if ("value" in message && !message.error) {
        waiting.onProgress?.(message.value);
        return;
      }
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
    link.waiting.set(id, { resolve, reject, onProgress });
    link.port.postMessage({ id, call: name, params });
    signal?.addEventListener("abort", () => { if (link.waiting.has(id)) link.port.postMessage({ id, cancel: true }); }, { once: true });
  });
}

// Previews: a page asks for a station's port as a host of stillfail-preview:// (p<port>-<the station's hash>), puts that
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

// The frame a page puts in its own (stillfail-preview://<host>/_ember/frame), as the preview host's is on the web
// (cloud/src/preview.ts): the service in a frame of its own, and a history of its own. The bar's back, forward and go
// move along it with replace(), so they never step the page it sits in (a frame shares its window's history). Where it
// is, and whether it can go back or on, is said back to the page as it loads and as a page moves itself.
const FRAME = `<!doctype html>
<meta charset="utf-8">
<title>still.fail preview</title>
<style>
  html, body { margin: 0; height: 100%; background: #fff; }
  iframe { display: block; width: 100%; height: 100%; border: 0; }
</style>
<script src="/_ember/annotate.js"></script>
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
      if (inner.contentDocument.querySelector("meta[name=stillfail-redirect]")) return null;
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
    parent.postMessage({ type: "ember-preview-at", nonce, path, back: here > 0, forward: here < trail.length - 1, annotate: !!(window.stillfailAnnotate || window.emberAnnotate) }, "*");
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
  addEventListener("DOMContentLoaded", () => {
    document.body.append(inner);
    // Marking the page for a chat (/_ember/annotate.js, web/src/annotate/frame.ts), when it loaded.
    (window.stillfailAnnotate || window.emberAnnotate)?.attach(inner, nonce);
  });
  setInterval(report, 500);
</script>
<body></body>
`;

/** The service's pages' script for their WebSockets (previewSocket.ts), over their requests here. */
const SOCKET = socketScript(FETCH_LINK);

function plain(status: number, text: string): Response {
  return new Response(text, { status, headers: { "content-type": "text/plain; charset=utf-8" } });
}

/**
 * A request to the service as its answer comes (station.preview with `stream`): its status and headers, then its body,
 * which stops the request at the station when it is cancelled (its page gave it up) or `signal` aborts.
 */
function previewStream(params: Record<string, unknown>, signal: AbortSignal): Promise<{ status: number; headers: [string, string][]; body: ReadableStream<Uint8Array> }> {
  const stop = new AbortController();
  signal.addEventListener("abort", () => stop.abort(), { once: true });
  return new Promise((resolve, reject) => {
    let body!: ReadableStreamDefaultController<Uint8Array>;
    const stream = new ReadableStream<Uint8Array>({ start(c) { body = c; }, cancel() { stop.abort(); } });
    let headed = false;
    coreCall("station.preview", { ...params, stream: true }, (value) => {
      const v = value as { head?: { status: number; headers: [string, string][] }; chunk?: string };
      if (v.head && !headed) {
        headed = true;
        resolve({ status: v.head.status, headers: v.head.headers, body: stream });
      } else if (typeof v.chunk === "string") {
        try { body.enqueue(new Uint8Array(Buffer.from(v.chunk, "base64"))); } catch { /* cancelled */ }
      }
    }, stop.signal).then(
      () => { try { body.close(); } catch { /* cancelled */ } },
      (error: unknown) => {
        if (!headed) return reject(error instanceof Error ? error : new Error(String(error)));
        try { body.error(error); } catch { /* cancelled */ }
      },
    );
  });
}

/** A frame of a socket's stream to its page (previewSocket.ts, FETCH_LINK): kind, length, payload. */
function socketFrame(kind: number, payload: Uint8Array): Uint8Array {
  const out = new Uint8Array(5 + payload.length);
  out[0] = kind;
  new DataView(out.buffer).setUint32(1, payload.length);
  out.set(payload, 5);
  return out;
}

/**
 * A WebSocket of the service's page, over its requests here (previewSocket.ts, FETCH_LINK): GET opens it
 * (preview.socket) and streams what happens on it, POST sends a message (preview.socket.send).
 */
async function previewSocket(request: Request, url: URL, station: string, port: number, sid: string): Promise<Response> {
  if (request.method === "POST") {
    const bytes = new Uint8Array(await request.arrayBuffer());
    const kind = bytes[0];
    const payload = Buffer.from(bytes.subarray(5));
    const message = kind === 1 ? { text: payload.toString("utf8") }
      : kind === 2 ? { binary: payload.toString("base64") }
      : kind === 8 ? { close: [payload.length >= 2 ? payload.readUInt16BE(0) : 1000, payload.subarray(2).toString("utf8")] }
      : null;
    if (!message) return plain(400, "看不懂这条消息");
    try {
      await coreCall("preview.socket.send", { socket: sid, ...message });
      return new Response(null, { status: 204 });
    } catch (error) {
      return plain(410, error instanceof Error ? error.message : String(error));
    }
  }
  const stop = new AbortController();
  request.signal?.addEventListener("abort", () => stop.abort(), { once: true });
  const protocols = (url.searchParams.get("protocols") ?? "").split(",").map((p) => p.trim()).filter(Boolean);
  const utf8 = new TextEncoder();
  const body = new ReadableStream<Uint8Array>({
    start(out) {
      const put = (frame: Uint8Array) => { try { out.enqueue(frame); } catch { /* cancelled */ } };
      const close = (code: number, reason: string) => {
        put(socketFrame(8, new Uint8Array([code >> 8, code & 255, ...utf8.encode(reason)])));
        try { out.close(); } catch { /* cancelled */ }
      };
      coreCall("preview.socket", {
        station, port, path: url.searchParams.get("path") ?? "/", socket: sid,
        headers: protocols.length ? [["sec-websocket-protocol", protocols.join(", ")]] : [],
      }, (value) => {
        const v = value as { open?: { protocol: string }; text?: string; binary?: string };
        if (v.open) put(socketFrame(0, utf8.encode(v.open.protocol)));
        else if (typeof v.text === "string") put(socketFrame(1, utf8.encode(v.text)));
        else if (typeof v.binary === "string") put(socketFrame(2, new Uint8Array(Buffer.from(v.binary, "base64"))));
      }, stop.signal).then(
        (closed) => { const { code, reason } = closed as { code: number; reason: string }; close(code, reason); },
        () => close(1006, ""),
      );
    },
    cancel() { stop.abort(); },
  });
  return new Response(body, { headers: { "content-type": "application/octet-stream", "cache-control": "no-store" } });
}

async function preview(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const host = /^p(\d{1,5})-([0-9a-f]{12})$/.exec(url.hostname);
  const station = host ? previewStations.get(host[2]!) : undefined;
  if (!host || !station) return plain(404, "预览已经失效：在 still.fail 里重新打开它。");
  if (url.pathname === "/_ember/frame") return new Response(FRAME, { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" } });
  if (url.pathname === "/_ember/annotate.js") return new Response(await readFile(join(__dirname, "annotate.js")).catch(() => ""), { headers: { "content-type": "text/javascript; charset=utf-8", "cache-control": "no-store" } });
  if (url.pathname === "/_ember/socket.js") return new Response(SOCKET, { headers: { "content-type": "text/javascript; charset=utf-8", "cache-control": "no-store" } });
  const socket = /^\/_ember\/socket\/([0-9a-f-]{36})$/.exec(url.pathname);
  if (socket) return previewSocket(request, url, station, Number(host[1]), socket[1]!);
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
    // The answer as it comes (an event stream, a long poll), stopped at the station when the page gives it up.
    const signal = request.signal ?? new AbortController().signal;
    let path = url.pathname + url.search;
    let answer: { status: number; headers: [string, string][]; body: ReadableStream<Uint8Array> } | null = null;
    for (let hops = 0; hops < 5 && !answer; hops++) {
      const got = await previewStream({ station, port: Number(host[1]), method: request.method, path, headers, body }, signal);
      const location = got.status >= 300 && got.status < 400 ? got.headers.find(([k]) => k.toLowerCase() === "location")?.[1] : undefined;
      if (!location) { answer = got; break; }
      void got.body.cancel();
      const next = new URL(location, `http://localhost:${host[1]}${path}`);
      if (next.hostname !== "localhost" && next.hostname !== "127.0.0.1") return plain(502, `这个网页跳到了别的地址：${location}`);
      path = next.pathname + next.search;
      if (page) return new Response(`<!doctype html><meta charset="utf-8"><meta name="stillfail-redirect"><script>location.replace(${JSON.stringify(path)})</script>`, { headers: { "content-type": "text/html; charset=utf-8" } });
    }
    if (!answer) return plain(508, "跳转太多次了");
    const empty = request.method === "HEAD" || [101, 204, 205, 304].includes(answer.status);
    if (empty) {
      void answer.body.cancel();
      return new Response(null, { status: answer.status, headers: answer.headers });
    }
    // A page of the service gets its WebSockets through here (previewSocket.ts).
    const html = (answer.headers.find(([k]) => k.toLowerCase() === "content-type")?.[1] ?? "").startsWith("text/html");
    return new Response(page && html ? withSocketTag(answer.body) : answer.body, { status: answer.status, headers: answer.headers });
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
    const made = await coreCall("workspace.enroll", { account, workspace, name: machineName() }) as { token: string };
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

// Keeping the app current: the cloud has the latest build (scripts/release.sh desktop puts it in /releases/desktop/,
// stillfail-mac.yml; latest-mac.yml is the old feed, for apps from before the rename: see bridge.ts), looked for at
// start and every few hours. A newer one is said to the pages, which show 更新 beside the buddy (web/src/brand.tsx);
// clicked, it is downloaded, and once it is the app quits (the station stopped first) and opens as the new one.
const UPDATE_EVERY = 4 * 60 * 60 * 1000;

/** What the pages are told of an update (web/src/core/client.ts, AppUpdate). */
type UpdateState =
  | { phase: "available"; version: string }
  | { phase: "downloading"; version: string; percent: number }
  | { phase: "installing"; version: string }
  | { phase: "failed"; version: string; message: string };
let update: UpdateState | null = null;

function sayUpdate(next: UpdateState | null): void {
  update = next;
  for (const window of BrowserWindow.getAllWindows()) {
    if (!window.isDestroyed()) window.webContents.send("update:state", next);
  }
}

ipcMain.handle("update:state", (event) => event.senderFrame?.url.startsWith(`${APP_ORIGIN}/`) ? update : null);

/** Downloads the update said to be there (set by keepUpdated). */
let download = () => {};

ipcMain.on("update:start", (event) => {
  if (!event.senderFrame?.url.startsWith(`${APP_ORIGIN}/`) || !update || update.phase === "downloading" || update.phase === "installing") return;
  sayUpdate({ phase: "downloading", version: update.version, percent: 0 });
  download();
});

function keepUpdated(): void {
  if (!app.isPackaged) return;
  const feed = `${CLOUD_ORIGIN}/releases/desktop`;
  if (bundleIdOf(ownBundle()) === FORMER_APP_ID) {
    moveToRenamedApp(new Bridge(feed));
    return;
  }
  download = () => void autoUpdater.downloadUpdate().catch(() => {});
  autoUpdater.setFeedURL({ provider: "generic", url: feed, channel: CHANNEL });
  autoUpdater.logger = null;
  autoUpdater.autoDownload = false;
  autoUpdater.on("update-available", ({ version }) => {
    if (update?.version !== version) sayUpdate({ phase: "available", version });
  });
  autoUpdater.on("download-progress", ({ percent }) => {
    if (update?.phase === "downloading") sayUpdate({ ...update, percent: Math.floor(percent) });
  });
  autoUpdater.on("update-downloaded", ({ version }) => {
    sayUpdate({ phase: "installing", version });
    void stopStation().then(() => autoUpdater.quitAndInstall(true, true));
  });
  autoUpdater.on("error", (error) => {
    console.warn("updating the app failed", error.message);
    // Only a download the person asked for is said to have failed; a check that failed is tried again later.
    if (update?.phase === "downloading") sayUpdate({ phase: "failed", version: update.version, message: error.message });
  });
  const check = () => {
    if (update?.phase === "downloading" || update?.phase === "installing") return;
    void autoUpdater.checkForUpdates().catch((error: Error) => console.warn("looking for an update failed", error.message));
  };
  check();
  setInterval(check, UPDATE_EVERY);
}

/**
 * This build under the bundle id from before the rename (bridge.ts): its update is the app under the new id, whatever
 * its version (the same build under the other id is the move).
 */
function moveToRenamedApp(bridge: Bridge): void {
  download = () => {
    void bridge.prepare((percent) => {
      if (update?.phase === "downloading") sayUpdate({ ...update, percent });
    }).then(() => {
      if (update) sayUpdate({ phase: "installing", version: update.version });
      void stopStation().then(() => app.quit());
    }, (error: Error) => {
      console.warn("moving to the renamed app failed", error.message);
      if (update) sayUpdate({ phase: "failed", version: update.version, message: error.message });
    });
  };
  const check = () => {
    if (update?.phase === "downloading" || update?.phase === "installing") return;
    bridge.check().then((version) => {
      if (version && update?.version !== version) sayUpdate({ phase: "available", version });
    }, (error: Error) => console.warn("looking for the renamed app failed", error.message));
  };
  check();
  setInterval(check, UPDATE_EVERY);
}

/** Pages outside the app open in the system browser, as a new tab would. */
function external(url: string): void {
  if (/^https?:\/\//.test(url)) void shell.openExternal(url);
}

/**
 * A window of the app at `path`. The app's own window has no title bar: its buttons sit in the page's top row (44 px,
 * web/src/styles), centred on it. A page of the app opened in a new window (a web service's page of its own) has one:
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
 * A stillfail:// (or ember://) URL handed to the app: the sign-in coming back (stillfail://auth/callback, loaded as the
 * page), or an item's link (…://o/<workspace>/<station>/<session>, from the web's /o/ page), which the page opens in
 * place.
 */
function arrived(url: string): void {
  const item = /^(?:stillfail|ember):\/\/o\/([^/?#]+)\/([^/?#]+)\/([^/?#]+)/.exec(url);
  if (!/^(?:stillfail|ember):\/\/auth\/callback(?:[?#]|$)/.test(url) && !item) return;
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
  // Run from the source (Electron's own app with this directory, dev.sh), the links open it with the directory.
  for (const scheme of SCHEMES) {
    if (app.isPackaged) app.setAsDefaultProtocolClient(scheme);
    else app.setAsDefaultProtocolClient(scheme, process.execPath, [app.getAppPath()]);
  }
  // macOS hands the app its URLs here (possibly before it is ready); elsewhere they start a second instance.
  app.on("open-url", (event, url) => {
    event.preventDefault();
    void app.whenReady().then(() => arrived(url));
  });
  app.on("second-instance", (_event, argv) => {
    const url = argv.find((arg) => SCHEMES.some((scheme) => arg.startsWith(`${scheme}://`)));
    if (url) arrived(url);
    else BrowserWindow.getAllWindows()[0]?.focus();
  });
  void app.whenReady().then(() => {
    protocol.handle("app", serve);
    protocol.handle("stillfail-preview", preview);
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
