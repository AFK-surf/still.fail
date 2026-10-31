// still.fail's app (apps/mbui, the same one every device runs) in a browser: mbui's web host (apps/mbui/mbui/web/host.js)
// draws it on a canvas, and the core it talks to is this page's, the web's own worker (src/core/worker.ts), given to it
// as `globalThis.__mbcore` (mbui/core's js.mbt). What the app says is a message's JSON and maybe bytes beside it, as
// on the native hosts (src/core/core_native.c there); what the worker says back goes to mbui's queue on the channel
// "core" (the host's `post`), its bytes beside its JSON.
import { BUILT_AT } from "../core/built.ts";
import { BETA } from "../channel.ts";
// the app's words' face in a browser: the web's own Inter (its Latin, as the web's pages have it), not the whole face
// the native hosts carry (apps/mbui src/sfbase/inter_face_js.mbt)
import interLatin from "@fontsource-variable/inter/files/inter-latin-wght-normal.woff2?url";

/// The worker's name, as the web's pages name theirs (src/core/client.ts): one build's pages share its core.
const workerName = `stillfail-core-${BUILT_AT}${BETA ? "-test" : ""}`;

interface MbHost {
  post(channel: string, json: string, bytes?: Uint8Array): void;
}

const host = (): MbHost | undefined => (globalThis as { __mbhost?: MbHost }).__mbhost;

/// What the worker says, to the app: its JSON without the bytes, and those beside it.
function toApp(data: unknown): void {
  if (typeof data !== "object" || data === null) return;
  const message = data as { bytes?: unknown; retired?: boolean; rejoin?: boolean; fault?: { name: string; message: string; stack?: string } };
  // A newer build's core took over: this page is of the older build and loads the newer.
  if (message.retired) {
    location.reload();
    return;
  }
  // An error the core survived: the worker's console is out of reach, so said here.
  if (message.fault) {
    console.error("still.fail core:", message.fault.message, message.fault.stack ?? "");
    return;
  }
  // (`rejoin`: another tab's worker runs the core now; the app asks it again, mbui/core's core.mbt)
  if (message.bytes instanceof Uint8Array) {
    const { bytes, ...rest } = message;
    host()?.post("core", JSON.stringify(rest), bytes as Uint8Array);
  } else host()?.post("core", JSON.stringify(message));
}

let worker: Worker | null = null;

/// The core's worker, started as the page loads: its databases and the station links come up while the app's script is
/// still on its way (the app's `start` takes the one there is).
function startWorker(): void {
  if (worker) return;
  void navigator.storage?.persist?.().catch(() => false);
  // Spelled out: Vite bundles a worker only from a literal `new Worker(new URL(…, import.meta.url))`.
  worker = new Worker(new URL("../core/worker.ts", import.meta.url), { type: "module", name: workerName });
  worker.onmessage = (event: MessageEvent) => toApp(event.data);
  worker.onerror = (event) => host()?.post("core", JSON.stringify({ fatal: event.message || "the core's worker failed" }));
}

function start(): boolean {
  startWorker();
  return true;
}

function send(json: string, bytes: Uint8Array | null): void {
  if (!worker) return;
  let message: unknown;
  try {
    message = JSON.parse(json);
  } catch {
    return;
  }
  const taken = withFiles(message, bytes);
  // (bytes beside another call: handed over with it, as a native host's bridge hands them, src/core/worker.ts unwrap)
  if (bytes !== null && taken === message) worker.postMessage({ withBytes: message, bytes });
  else worker.postMessage(taken);
}

interface MbHostFiles {
  heldFile?(id: number): File | null;
}

/// The files of a `composer.add` as the web's core takes them, Blobs in the message itself (client/core-ts/src/
/// composer.ts FileIn): the app's are read whole and beside it (`blob.hostBytes`: where in `bytes`), or held by the
/// host (`blob.hostFile`: the page's File for it, web/host.js H.heldFile), as the native engines' bridge takes them
/// (client/core-ts/src/hosts/bridge.ts).
function withFiles(message: unknown, bytes: Uint8Array | null): unknown {
  const m = message as { call?: unknown; params?: { files?: unknown } } | null;
  if (m?.call !== "composer.add" || !Array.isArray(m.params?.files)) return message;
  const out = structuredClone(m) as typeof m & { params: { files: unknown[] } };
  for (const f of out.params.files as { blob?: { hostBytes?: unknown; hostFile?: unknown; type?: unknown } }[]) {
    const b = f?.blob;
    if (!b) continue;
    const type = typeof b.type === "string" ? b.type : "";
    const at = b.hostBytes;
    if (bytes && Array.isArray(at) && at.length === 2 && Number.isSafeInteger(at[0]) && Number.isSafeInteger(at[1]) && at[0] >= 0 && at[1] >= 0 && at[0] + at[1] <= bytes.length) {
      f.blob = new Blob([bytes.slice(at[0], at[0] + at[1])], { type }) as never;
    } else if (typeof b.hostFile === "number") {
      const file = (host() as (MbHost & MbHostFiles) | undefined)?.heldFile?.(b.hostFile) ?? null;
      if (file) f.blob = file as never;
      else delete f.blob;
    }
  }
  return out;
}

function stop(): void {
  worker?.postMessage({ bye: true });
  worker?.terminate();
  worker = null;
}

(globalThis as { __mbcore?: unknown }).__mbcore = {
  start: (_dataDir: string, _cloud: string, _beta: boolean) => start(),
  send,
  stop,
  // Signing in is this page going to the cloud's, which brings it back here (mbui/core's js.mbt `auth_return_to`).
  signIn: (url: string) => {
    location.assign(url);
    return true;
  },
};
addEventListener("pagehide", () => worker?.postMessage({ bye: true }));

/// The host, then the app: each a classic script, in order (the app runs as it loads, and finds both).
function load(src: string): Promise<void> {
  return new Promise((done, failed) => {
    const s = document.createElement("script");
    s.src = src;
    s.onload = () => done();
    s.onerror = () => failed(new Error(`${src} did not load`));
    document.body.appendChild(s);
  });
}

startWorker();

/// The files the app carries (fonts, the formulas' outlines: apps/mbui's tools/assets), fetched beside its script and
/// given to it as `globalThis.__mbassets`: the faces it starts in before it runs (its *_js.mbt read them as it starts),
/// the rest once it runs (read as they are drawn: a formula, the share card), the page drawn again as each comes. One
/// that does not come is left out: the app draws in the system's faces where its own is missing.
const assets: Record<string, Uint8Array> = {};
(globalThis as { __mbassets?: Record<string, Uint8Array> }).__mbassets = assets;
const fetchCarried = (name: string, url = `/mbui/assets/${name}?b=${BUILT_AT}`) =>
  fetch(url).then((r) => (r.ok ? r.arrayBuffer() : null), () => null)
    .then((b) => { if (b) assets[name] = new Uint8Array(b); });
const starting = Promise.all([fetchCarried("jetbrains_mono.ttf"), fetchCarried("inter.woff2", interLatin)]);

// (named by this build: a page of a newer build never runs an older app's script from the browser's cache)
await load(`/mbui/host.js?b=${BUILT_AT}`);
await starting;
await load(`/mbui/app.js?b=${BUILT_AT}`);
for (const name of ["math_glyphs.gz", "share_400.gz", "share_600.gz"])
  void fetchCarried(name).then(() => (host() as { requestFrame?(): void } | undefined)?.requestFrame?.());

/// The page's address as a link the app was opened with (mbui's system channel, `{"link": url}`: a chat's
/// /w/…/chats/… or /o/… page, as the app takes one the system opens it with), as it loads and as the browser goes back
/// or forward to another; the app's own page names nothing.
function tellLink(): void {
  if (location.pathname === "/" || location.pathname === "/mbui.html" || location.pathname === "/mbui") return;
  host()?.post("system", JSON.stringify({ link: location.href }));
}
tellLink();
addEventListener("popstate", tellLink);
