// The still.fail station, in TypeScript (docs/station-ts.md). This file is the composition root: every part is made
// here and handed what it needs; nothing registers itself anywhere. Commands as the Rust station takes them:
//
//   run --app DIR [--port N] [--data DIR] [--with-parent] [--launcher-fds a,b,c]
//   enroll <cloud> <token> [--data DIR]   status [--data DIR]   id [--data DIR]
import { readFileSync } from "node:fs";
import { createServer } from "node:http";
import { join } from "node:path";
import { Admin } from "./api/admin.ts";
import { enroll, id, status } from "./cli.ts";
import { loadKey } from "./cloud/key.ts";
import { presence } from "./cloud/presence.ts";
import { Cloud } from "./cloud/state.ts";
import { loadMesh } from "./mesh/native.ts";
import { keepRelays } from "./mesh/relays.ts";
import { ALPN, FORMER_ALPN, serve } from "./mesh/serve.ts";
import { dataDir, flag } from "./ops/files.ts";
import { setStationLang } from "./ops/i18n.ts";
import { launcher } from "./ops/launcher.ts";
import { log } from "./ops/log.ts";
import { version } from "./ops/version.ts";
import { Readers } from "./read/pool.ts";

const args = process.argv.slice(2);
const data = dataDir(args);
const command = args.find((a, i) => !a.startsWith("--") && !(i > 0 && args[i - 1].startsWith("--") && args[i - 1] !== "--with-parent"));

// What it says on this machine is in the station's language (config.json `language`).
try {
  const config = process.env.STILLFAIL_CONFIG || process.env.EMBER_CONFIG || join(data, "config.json");
  setStationLang(JSON.parse(readFileSync(config, "utf8")).language);
} catch {}

switch (command) {
  case "run":
    await run();
    break;
  case "enroll": {
    const [, origin, token] = args.filter((a, i) => !a.startsWith("--") && !(i > 0 && args[i - 1] === "--data"));
    if (!origin || !token) usage();
    await enroll(data, origin.replace(/\/+$/, ""), token);
    break;
  }
  case "status":
    console.log(status(data));
    break;
  case "id":
    id(data);
    break;
  default:
    usage();
}

function usage(): never {
  console.error("usage: stillfail-station run --app DIR [--port N] [--data DIR] | enroll <cloud> <token> | status | id");
  process.exit(2);
}

async function run() {
  if (!flag(args, "--app")) usage();
  const control = launcher(args);
  const cloud = new Cloud(data);
  const key = loadKey(data);
  const readers = new Readers(data);
  const admin = new Admin(readers);
  let up = false;
  const readyListeners: (() => void)[] = [];
  const setUp = (now: boolean) => {
    up = now;
    readyListeners.forEach((f) => f());
  };

  // The loopback port: whether the station answers (`/healthz`), for `bin/stillfail` and the desktop app.
  const loopback = createServer((req, res) => {
    if (req.url === "/healthz") {
      res.writeHead(up ? 200 : 503).end(up ? "ok" : "starting");
    } else {
      res.writeHead(404).end();
    }
  });
  if (control.loopbackFd !== undefined) loopback.listen({ fd: control.loopbackFd });
  else loopback.listen(Number(flag(args, "--port") ?? 4760), "127.0.0.1");

  // The mesh once the station is in a workspace (enrolled: cloud.json there).
  const mesh = loadMesh();
  let stopMesh: (() => Promise<void>) | undefined;
  const startMesh = async () => {
    if (stopMesh || !cloud.state) return;
    const endpoint = await mesh.bind({ secretKey: key.seed, alpns: [ALPN, FORMER_ALPN], relayUrls: cloud.relays(), discovery: process.env.STILLFAIL_NO_DISCOVERY !== "1" });
    log.info("mesh", "mesh listening", { station: endpoint.id(), workspace: cloud.state.workspace_name, sockets: endpoint.sockets() });
    const stopRelays = keepRelays(endpoint, cloud);
    // Online at the cloud only once a relay can reach the station: a device that saw "online" and connected before
    // the relay link was up had its first packets dropped (~3 s of retransmits).
    await Promise.race([endpoint.online(), new Promise((resolve) => setTimeout(resolve, 15_000))]);
    const online = presence(cloud, key, version(), { up: () => up, changed: (f) => readyListeners.push(f) });
    let accepting = true;
    void (async () => {
      for (let conn = await endpoint.accept(); conn && accepting; conn = await endpoint.accept()) {
        const c = conn;
        serve({ cloud, admin, up: () => up }, c).catch((e) => log.info("mesh", "connection ended", { error: (e as Error).message }));
      }
    })();
    stopMesh = async () => {
      accepting = false;
      online.stop();
      stopRelays();
      await endpoint.close();
    };
  };
  cloud.listen(() => void startMesh());
  await startMesh();

  setUp(true);
  control.ready(version());
  log.info("station", "station up", { version: version(), data });

  let stopping = false;
  const stop = async (why: string) => {
    if (stopping) return;
    stopping = true;
    log.info("station", "stopping", { why });
    setUp(false);
    await stopMesh?.();
    loopback.close();
    readers.close();
    process.exit(0);
  };
  control.on("stop", () => void stop("asked to stop"));
  control.on("handover", () => void stop("handed over to the next station process"));
  // Nothing runs yet that a drain would wait for.
  control.on("drain", () => control.drained("idle"));
}
