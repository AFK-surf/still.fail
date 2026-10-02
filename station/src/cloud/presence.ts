// The presence socket to still.fail cloud (mesh/station/src/main.rs `presence`, `connect`, `apply_state`): open while
// the station answers is the station online; the cloud pushes on it where the station is, its relays and roster, and
// what it takes back. Signed at connect like enrollment. Reconnects with backoff; once removed from its workspace,
// asks again only now and then, or at once when enrolled anew meanwhile.
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import WebSocket from "ws";
import { log } from "../ops/log.ts";
import { nowSecs } from "../ops/files.ts";
import type { Cloud, Revocation } from "./state.ts";
import type { StationKey } from "./key.ts";

/// The cloud expects a "ping" this often and drops a station silent for three of them.
const PING_MS = 30_000;
/// How the cloud closes the socket of a station removed from its workspace.
const CLOSE_REMOVED = 4004;
const REMOVED_RETRY_MS = 600_000;
const CONNECT_TIMEOUT_MS = 20_000;

/// REMOVED_RETRY, or STILLFAIL_REMOVED_RETRY_SECS (tests against a dev cloud).
function removedRetry(): number {
  const secs = Number(process.env.STILLFAIL_REMOVED_RETRY_SECS?.trim());
  return Number.isFinite(secs) && secs > 0 ? secs * 1000 : REMOVED_RETRY_MS;
}

/// Whether the station is online at still.fail cloud, and since when or why not: <data>/run/presence.json.
function writePresence(data: string, online: boolean, error: string | null) {
  mkdirSync(join(data, "run"), { recursive: true });
  writeFileSync(join(data, "run", "presence.json"), JSON.stringify({ online, at: nowSecs(), error }) + "\n");
}

const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

export type Presence = { stop(): void };

/// Keeps the socket while `up()` says the station answers; `version` is the station's, as the cloud is told it.
export function presence(cloud: Cloud, key: StationKey, version: string, ready: { up(): boolean; changed(f: () => void): void }): Presence {
  let stopped = false;
  let current: WebSocket | null = null;
  let wake: (() => void) | null = null;
  ready.changed(() => {
    if (!ready.up()) current?.close();
    wake?.();
  });
  const wait = (ms: number) => new Promise<void>((resolve) => {
    const t = setTimeout(resolve, ms);
    wake = () => {
      clearTimeout(t);
      resolve();
    };
  });

  (async () => {
    let backoff = 1000;
    while (!stopped) {
      if (!ready.up()) {
        await wait(2 ** 31 - 1);
        backoff = 1000;
        continue;
      }
      cloud.reload();
      if (cloud.removed()) {
        const retry = removedRetry();
        const every = retry === REMOVED_RETRY_MS ? "every 10 minutes" : `every ${retry / 1000} s`;
        writePresence(cloud.data, false, `removed from its workspace; the cloud is asked again ${every}`);
        // Enrolled again meanwhile (the file changes): ask at once.
        await new Promise<void>((resolve) => {
          const t = setTimeout(done, retry);
          const unlisten = cloud.listen(() => {
            if (!cloud.removed()) done();
          });
          function done() {
            clearTimeout(t);
            unlisten();
            resolve();
          }
        });
      }
      const started = Date.now();
      cloud.peersCurrent = false;
      let ended: string;
      try {
        ended = await connect();
        log.info("presence", ended);
      } catch (error) {
        ended = (error as Error).message;
        log.warn("presence", "no presence socket to still.fail cloud", { error: ended });
      }
      cloud.peersCurrent = false;
      writePresence(cloud.data, false, ended);
      if (Date.now() - started > 60_000) backoff = 1000;
      await sleep(backoff);
      backoff = Math.min(backoff * 2, 60_000);
    }
  })();

  /// One socket; resolves with why it ended (the cloud closing it), rejects on failure.
  function connect(): Promise<string> {
    const s = cloud.state!;
    const ts = nowSecs();
    const headers: Record<string, string> = {};
    // New clouds read the canonical proof; old clouds their original one.
    for (const prefix of ["stillfail", "ember"]) {
      headers[`x-${prefix}-station`] = s.station;
      headers[`x-${prefix}-ts`] = String(ts);
      headers[`x-${prefix}-signature`] = key.sign(`${prefix}-station-connect-v1:${s.origin}:${s.station}:${ts}`);
      headers[`x-${prefix}-version`] = version;
    }
    const url = `${s.origin.replace("http", "ws")}/v1/stations/connect`;
    return new Promise((resolve, reject) => {
      const socket = new WebSocket(url, { headers, handshakeTimeout: CONNECT_TIMEOUT_MS });
      current = socket;
      let ping: ReturnType<typeof setInterval> | undefined;
      let answered = true;
      let failed: Error | null = null;
      socket.on("unexpected-response", (_, response) => {
        if (response.statusCode === 404) {
          removed(404);
          failed = new Error("station removed");
        } else {
          failed = new Error(`still.fail cloud answered ${response.statusCode}`);
        }
        socket.terminate();
      });
      socket.on("error", (error) => (failed ??= error));
      socket.on("open", () => {
        takenBack();
        writePresence(cloud.data, true, null);
        log.info("presence", "online at still.fail cloud");
        ping = setInterval(() => {
          // No pong since the last ping: gone even if the socket has not noticed.
          if (!answered) {
            failed = new Error("still.fail cloud stopped answering");
            socket.terminate();
            return;
          }
          answered = false;
          socket.send("ping");
        }, PING_MS);
      });
      socket.on("message", (data, binary) => {
        if (binary) return;
        const text = data.toString();
        if (text === "pong") answered = true;
        else applyState(text);
      });
      socket.on("close", (code) => {
        clearInterval(ping);
        current = null;
        if (code === CLOSE_REMOVED) removed(CLOSE_REMOVED);
        if (failed) reject(failed);
        else resolve(ready.up() ? "still.fail cloud closed the presence socket" : "station not answering; went offline at still.fail cloud");
      });
    });
  }

  /// The cloud says the station is out of its workspace: marked in cloud.json, kept through restarts.
  function removed(code: number) {
    if (cloud.removed()) return;
    log.warn("presence", "this station was removed from its workspace; it stops its work and refuses connections", { code });
    cloud.update((s) => {
      s.removed_at = nowSecs();
      s.removed_code = code;
    });
  }

  /// The cloud took the socket: a station it had removed is in its workspace again.
  function takenBack() {
    if (!cloud.removed()) return;
    log.info("presence", "still.fail cloud takes this station again; back to work");
    cloud.update((s) => {
      delete s.removed_at;
      delete s.removed_code;
    });
  }

  /// What the cloud pushes: where the station is and what it is called, its relays, roster and grant keys, what it
  /// takes back.
  function applyState(text: string) {
    let body: any;
    try {
      body = JSON.parse(text);
    } catch {
      return;
    }
    if (body?.type === "state") {
      cloud.update((s) => {
        for (const k of ["workspace", "workspace_name", "name", "origin", "relay_url"] as const) {
          if (typeof body[k] === "string") s[k] = body[k];
        }
        // Missing roster means an old cloud: never keep peers from another binding.
        s.peers = Array.isArray(body.peers) ? body.peers : [];
        if (Array.isArray(body.relay_urls)) s.relay_urls = body.relay_urls.filter((u: unknown) => typeof u === "string");
        if (body.grant_keys && typeof body.grant_keys === "object" && !Array.isArray(body.grant_keys)) s.grant_keys = body.grant_keys;
        if (Array.isArray(body.revocations) && body.revocations.every(isRevocation)) s.revocations = body.revocations;
      });
      cloud.peersCurrent = Array.isArray(body.peers);
    } else if (body?.type === "revoke" && isRevocation(body)) {
      cloud.update((s) => {
        s.revocations = s.revocations.filter((r) => !(r.kind === body.kind && r.id === body.id));
        s.revocations.push({ kind: body.kind, id: body.id, at: body.at });
      });
    }
  }

  return {
    stop() {
      stopped = true;
      current?.close();
      wake?.();
    },
  };
}

const isRevocation = (r: any): r is Revocation => typeof r?.kind === "string" && typeof r?.id === "string" && Number.isInteger(r?.at) && r.at >= 0;
