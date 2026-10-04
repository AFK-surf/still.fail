// The presence socket to still.fail cloud (the Rust station's main.rs `presence`, `connect`, `apply_state`): open while
// the station answers is the station online; the cloud pushes on it where the station is, its relays and roster, and
// what it takes back. Signed at connect like enrollment. Reconnects with backoff; once removed from its workspace, asks
// again only now and then, or at once when enrolled anew meanwhile.
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { Clock, Effect, Stream, SubscriptionRef } from "effect";
import WebSocket from "ws";
import { log } from "../ops/log.ts";
import { nowSecs } from "../ops/files.ts";
import { version } from "../ops/version.ts";
import { Cloud, Key, Up } from "../services.ts";
import type { Cloud as CloudState, Revocation } from "./state.ts";
import type { StationKey } from "./key.ts";
import { wall } from "../ops/fibers.ts";

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

/// Whether the station is online at still.fail cloud, and since when or why not: <data>/run/presence.json, for
/// `stillfail status`.
function writePresence(data: string, online: boolean, error: string | null) {
  mkdirSync(join(data, "run"), { recursive: true });
  writeFileSync(join(data, "run", "presence.json"), JSON.stringify({ online, at: nowSecs(), error }) + "\n");
}

/// Keeps the socket for good (until interrupted): open while the station is up.
export const presence = Effect.gen(function* () {
  const cloud = yield* Cloud;
  const key = yield* Key;
  const up = yield* Up;
  const until = (wanted: boolean) => SubscriptionRef.changes(up).pipe(Stream.filter((now) => now === wanted), Stream.runHead);
  let backoff = 1000;
  for (;;) {
    if (!(yield* SubscriptionRef.get(up))) {
      yield* until(true);
      backoff = 1000;
    }
    const s = cloud.state;
    s.reload();
    if (s.removed()) {
      const retry = removedRetry();
      const every = retry === REMOVED_RETRY_MS ? "every 10 minutes" : `every ${retry / 1000} s`;
      writePresence(s.data, false, `removed from its workspace; the cloud is asked again ${every}`);
      // Enrolled again meanwhile (the file changes): ask at once.
      yield* Effect.raceFirst(Effect.sleep(retry), cloud.changes.pipe(Stream.filter(() => !s.removed()), Stream.runHead));
    }
    const started = yield* Clock.currentTimeMillis;
    s.peersCurrent = false;
    // The socket, until it ends or the station stops answering (then it is closed: offline at the cloud).
    const ended = yield* Effect.result(Effect.raceFirst(connect(s, key), Effect.as(until(false), "station not answering; went offline at still.fail cloud")));
    s.peersCurrent = false;
    const why = ended._tag === "Success" ? ended.success : ended.failure.message;
    writePresence(s.data, false, why);
    if (ended._tag === "Success") log.info("presence", why);
    else log.warn("presence", "no presence socket to still.fail cloud", { error: why });
    // A socket that held a while starts over quickly; failing again and again backs off to a minute.
    if ((yield* Clock.currentTimeMillis) - started > 60_000) backoff = 1000;
    yield* Effect.sleep(backoff);
    backoff = Math.min(backoff * 2, 60_000);
  }
});

/// One socket, signed at connect like enrollment: succeeds with why it ended when the cloud closes it, fails when it
/// can't be had or breaks; closed when interrupted.
const connect = (s: CloudState, key: StationKey) =>
  Effect.callback<string, Error>((resume) => {
    const state = s.state!;
    const ts = nowSecs();
    const headers: Record<string, string> = {};
    // New clouds read the canonical proof; old clouds their original one.
    for (const prefix of ["stillfail", "ember"]) {
      headers[`x-${prefix}-station`] = state.station;
      headers[`x-${prefix}-ts`] = String(ts);
      headers[`x-${prefix}-signature`] = key.sign(`${prefix}-station-connect-v1:${state.origin}:${state.station}:${ts}`);
      headers[`x-${prefix}-version`] = version();
    }
    const socket = new WebSocket(`${state.origin.replace("http", "ws")}/v1/stations/connect`, { headers, handshakeTimeout: CONNECT_TIMEOUT_MS });
    let ping: (() => void) | undefined;
    let answered = true;
    let failed: Error | null = null;
    socket.on("unexpected-response", (_, response) => {
      if (response.statusCode === 404) {
        removed(s, 404);
        failed = new Error("station removed");
      } else {
        failed = new Error(`still.fail cloud answered ${response.statusCode}`);
      }
      socket.terminate();
    });
    socket.on("error", (error) => (failed ??= error));
    socket.on("open", () => {
      takenBack(s);
      writePresence(s.data, true, null);
      log.info("presence", "online at still.fail cloud");
      // The cloud's answering is in the machine's time.
      ping = wall.every(PING_MS, () => {
        // No pong since the last ping: gone even if the socket has not noticed.
        if (!answered) {
          failed = new Error("still.fail cloud stopped answering");
          socket.terminate();
          return;
        }
        answered = false;
        socket.send("ping");
      });
    });
    socket.on("message", (data, binary) => {
      if (binary) return;
      const text = data.toString();
      if (text === "pong") answered = true;
      else applyState(s, text);
    });
    socket.on("close", (code) => {
      ping?.();
      if (code === CLOSE_REMOVED) removed(s, CLOSE_REMOVED);
      resume(failed ? Effect.fail(failed) : Effect.succeed("still.fail cloud closed the presence socket"));
    });
    return Effect.sync(() => {
      ping?.();
      socket.close();
    });
  });

/// The cloud says the station is out of its workspace: marked in cloud.json, kept through restarts.
function removed(s: CloudState, code: number) {
  if (s.removed()) return;
  log.warn("presence", "this station was removed from its workspace; it stops its work and refuses connections", { code });
  s.update((st) => {
    st.removed_at = nowSecs();
    st.removed_code = code;
  });
}

/// The cloud took the socket: a station it had removed is in its workspace again.
function takenBack(s: CloudState) {
  if (!s.removed()) return;
  log.info("presence", "still.fail cloud takes this station again; back to work");
  s.update((st) => {
    delete st.removed_at;
    delete st.removed_code;
  });
}

/// What the cloud pushes: where the station is and what it is called, its relays, roster and grant keys, what it
/// takes back.
function applyState(s: CloudState, text: string) {
  let body: any;
  try {
    body = JSON.parse(text);
  } catch {
    return;
  }
  if (body?.type === "state") {
    // Current before it is told, so whoever hears of the new roster reads it as current.
    s.peersCurrent = Array.isArray(body.peers);
    s.update((st) => {
      for (const k of ["workspace", "workspace_name", "name", "origin", "relay_url"] as const) {
        if (typeof body[k] === "string") st[k] = body[k];
      }
      // Missing roster means an old cloud: never keep peers from another binding.
      st.peers = Array.isArray(body.peers) ? body.peers : [];
      if (Array.isArray(body.relay_urls)) st.relay_urls = body.relay_urls.filter((u: unknown) => typeof u === "string");
      if (body.grant_keys && typeof body.grant_keys === "object" && !Array.isArray(body.grant_keys)) st.grant_keys = body.grant_keys;
      if (Array.isArray(body.revocations) && body.revocations.every(isRevocation)) st.revocations = body.revocations;
    });
  } else if (body?.type === "revoke" && isRevocation(body)) {
    s.update((st) => {
      st.revocations = st.revocations.filter((r) => !(r.kind === body.kind && r.id === body.id));
      st.revocations.push({ kind: body.kind, id: body.id, at: body.at });
    });
  }
}

const isRevocation = (r: any): r is Revocation => typeof r?.kind === "string" && typeof r?.id === "string" && Number.isInteger(r?.at) && r.at >= 0;
