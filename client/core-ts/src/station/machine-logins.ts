// A station's logins to the command-line tools its agents use (docs/remote-login.md): what the core holds of them and
// shows (the `machineLogins`, `machineLogin` and `machineLoginScreen` topics), and the loopback relay (`machineLogin.open`
// on a host that can listen: the desktop app). Held in the link's memory as the station says them (kept, memory.ts:
// there as the app opens again): read when its stream opens (GET /machine-logins; a station from before answers 404,
// and has none), told as they change (`machine-logins`); a terminal's screen told while it is shown (`login-screen`, on
// the same stream), in memory alone.
//
// The relay: a login whose browser comes back to a loopback port (gcloud, aws, az…) has this device listen on that port,
// on loopback only, from the moment it is opened here; the first request with the login's path and state (and Host) goes
// to the station, which hands it to the command; anything else is answered 404 and never sent (one wrong request ends
// most such commands). After it, the page is told the login is done here, and the listener closes ten seconds later, or
// as the login ends.
import { Effect, Exit, type Fiber, Scope } from "effect";
import type { Inner } from "../core.ts";
import { CoreError } from "../error.ts";
import { clock, local, localDay } from "../format.ts";
import type { LoopbackRequest, Pull } from "../host.ts";
import { t } from "../i18n.ts";
import { param } from "../asks.ts";
import { encode } from "../ops.ts";
import { base64, fromBase64, get, isObject } from "../util.ts";
import { StationAddr } from "./addr.ts";
import type { Link } from "./link.ts";

type J = any;

/// What a link holds of its station's logins (Link.memory).
export const HELD = "machineLogins";
/// A login's screen in Link.memory.
export const screenKey = (id: string) => `machineLoginScreen\n${id}`;
/// The listener of a relay stays this long after its one request was relayed (the browser's favicon, a success page
/// that comes back to another path).
export const AFTER_MS = 10_000;
/// At most this long, whatever happens.
export const RELAY_MOST_MS = 15 * 60_000;

/// `supported`: null until read; false for a station from before (404).
export type Held = { supported: boolean | null; logins: J[] };

const str = (v: unknown): string | null => (typeof v === "string" ? v : null);

export function held(link: Link | undefined): Held {
  const h = link?.memory.get(HELD) as Held | undefined;
  return h ?? { supported: null, logins: [] };
}

/// The station's list read whole: what it holds now.
export function putList(link: Link, answer: unknown): void {
  const logins = Array.isArray(get(answer, "logins")) ? (get(answer, "logins") as J[]).filter(isObject) : [];
  link.memory.set(HELD, { supported: true, logins } satisfies Held);
}

/// A station from before remote login: none.
export function unsupported(link: Link): void {
  link.memory.set(HELD, { supported: false, logins: [] } satisfies Held);
}

/// One login as the station says it now: in place (new ones first).
export function putLogin(link: Link, login: unknown): boolean {
  const id = str(get(login, "id"));
  if (id === null || !isObject(login)) return false;
  const h = held(link);
  const at = h.logins.findIndex((l) => l.id === id);
  const logins = at >= 0 ? h.logins.map((l, i) => (i === at ? login : l)) : [login, ...h.logins];
  link.memory.set(HELD, { ...h, supported: h.supported ?? true, logins });
  return true;
}

/// A login's screen as its station told it: all of it (`full`), or the rows that changed.
export function putScreen(link: Link, told: unknown): string | null {
  const id = str(get(told, "id"));
  if (id === null) return null;
  const key = screenKey(id);
  const before = link.memory.get(key) as J | undefined;
  const rows: string[] = get(told, "full") === true || !before ? [] : [...before.rows];
  const changed = get(told, "rows");
  if (isObject(changed)) for (const [i, row] of Object.entries(changed)) if (typeof row === "string" && /^\d+$/.test(i)) rows[Number(i)] = row;
  for (let i = 0; i < rows.length; i++) rows[i] ??= "";
  const cursor = get(told, "cursor");
  // (a terminal as it is now, shown while it is watched: not kept)
  link.memory.hold(key, {
    rows,
    cursorX: typeof get(cursor, "x") === "number" ? get(cursor, "x") : 0,
    cursorY: typeof get(cursor, "y") === "number" ? get(cursor, "y") : 0,
    echo: get(told, "echo") !== false,
    live: get(told, "live") !== false,
  });
  return id;
}

// ── as shown ──

/// When, in words: 14:05 today, 10/16 14:05 before.
export function when(ms: number, now: number, offsetMin: number): string {
  const [, month, d] = local(ms, offsetMin);
  const time = clock(ms, offsetMin);
  return localDay(ms, offsetMin) === localDay(now, offsetMin) ? time : `${month}/${d} ${time}`;
}
const person = (by: J) => str(get(by, "name")) || str(get(by, "email")) || "";
/// Only an https page is opened.
const https = (url: unknown) => (typeof url === "string" && url.startsWith("https://") ? url : null);

/// A login as the panel and the card show it. `listening`: this device takes its callback now; `refused`: why it could
/// not, the last time it was opened here.
export function loginShown(l: J, station: string, stationName: string, now: number, offsetMin: number, listening: boolean, refused: string | null = null): J {
  const state = str(l.state) ?? "starting";
  const step = str(l.step);
  const active = l.endedAt === undefined || l.endedAt === null;
  const code = str(l.code);
  const name = str(l.name) ?? "";
  // Waiting for what its page gives (a code): the person's to enter, from the card, not its agent's to answer.
  const paste = l.paste === true && active && step === "open" && https(l.url) !== null;
  const waiting = l.waiting === true && active && !paste;
  const statusText = !active
    ? state === "done"
      ? t("core-logic.machineLogin.done")
      : state === "cancelled"
        ? t("core-logic.machineLogin.cancelled")
        : l.timedOut === true ? t("core-logic.machineLogin.timedOut") : t("core-logic.machineLogin.failed")
    : waiting || state === "input"
      ? t("core-logic.machineLogin.waiting")
      : state === "verifying"
        ? t("core-logic.machineLogin.verifying")
        : step === "device" && code !== null
          ? t("core-logic.machineLogin.code", { code })
          : step === "loopback"
            ? listening ? t("core-logic.machineLogin.comingBack") : t("core-logic.machineLogin.openBrowser")
            : step === "open"
              ? paste ? t("core-logic.machineLogin.paste") : t("core-logic.machineLogin.finishInBrowser")
              : t("core-logic.machineLogin.starting");
  const url = https(l.url);
  const command = Array.isArray(l.command) ? l.command.filter((w: unknown) => typeof w === "string").join(" ") : String(l.command ?? "");
  return {
    id: String(l.id),
    station,
    stationName,
    name,
    title: t("core-logic.machineLogin.title", { name, station: stationName }),
    command,
    state,
    ...(step !== null && active ? { step } : {}),
    active,
    ...(url !== null ? { url } : {}),
    ...(str(l.domain) !== null ? { domain: l.domain } : {}),
    ...(code !== null && active ? { code } : {}),
    ...(https(l.codeUrl) !== null && active ? { codeUrl: l.codeUrl } : {}),
    ...(typeof get(l.callback, "port") === "number" ? { port: get(l.callback, "port") } : {}),
    // Its page in the station's own browser: offered while it can be, back to its tab while that is open.
    ...(l.browser === true && active
      ? { browser: true, ...(str(l.screen) !== null ? { screen: l.screen } : {}), browserText: t(str(l.screen) !== null ? "common.login.backToStation" : "common.login.openInStation", { station: stationName }) }
      : {}),
    waiting,
    ...(paste ? { paste: true } : {}),
    listening: listening && active,
    ...(refused !== null && active && !listening && step === "loopback" ? { relayText: refused } : {}),
    statusText,
    ...(str(l.error) !== null && !active ? { error: l.error } : {}),
    ...(person(l.by) !== "" ? { byText: person(l.by) } : {}),
    ...(str(l.chat) !== null ? { chat: l.chat } : {}),
    ...(str(l.chatTitle) !== null ? { chatTitle: l.chatTitle } : {}),
    // Who ended it and how, in words (张三 完成, 张三 取消): only where it is known, and only for one done or cancelled.
    ...(isObject(l.doneBy) && person(l.doneBy) !== "" && (state === "done" || state === "cancelled")
      ? { doneByText: t(state === "done" ? "core-logic.machineLogin.doneBy" : "core-logic.machineLogin.cancelledBy", { name: person(l.doneBy) }) }
      : {}),
    ...(!active ? { endedText: endedText(state, l, name, stationName) } : {}),
    whenText: typeof l.startedAt === "number" ? when(l.startedAt, now, offsetMin) : "",
    startedAt: typeof l.startedAt === "number" ? l.startedAt : 0,
    expiresAt: typeof l.expiresAt === "number" ? l.expiresAt : 0,
    ...(typeof l.endedAt === "number" ? { endedAt: l.endedAt } : {}),
  };
}

/// An ended login in a line, as its card shows it then: 已在 studio 上登录 gh; 张三 取消了在 studio 上登录 gh; 在 studio 上登录 gh
/// 失败：<the line of its error that says why>; …超时了.
function endedText(state: string, l: J, name: string, station: string): string {
  const what = { name, station };
  if (state === "done") return t("core-logic.machineLogin.endedDone", what);
  if (state === "cancelled") {
    const who = isObject(l.doneBy) ? person(l.doneBy) : "";
    return who !== "" ? t("core-logic.machineLogin.endedCancelledBy", { ...what, who }) : t("core-logic.machineLogin.endedCancelled", what);
  }
  if (l.timedOut === true) return t("core-logic.machineLogin.endedTimedOut", what);
  // Why, short: the line of its last words that says an error, else the last of them.
  const lines = (str(l.error) ?? "").split("\n").map((s) => s.trim()).filter((s) => s !== "");
  const why = lines.find((s) => /\b(error|failed|failure|denied|expired|invalid|unauthori[sz]ed)\b/i.test(s)) ?? lines.at(-1) ?? "";
  const reason = why.length > 80 ? `${why.slice(0, 79)}…` : why;
  return reason !== "" ? t("core-logic.machineLogin.endedFailedWhy", { ...what, reason }) : t("core-logic.machineLogin.endedFailed", what);
}

/// The logins that ended, a row per program (用户定 2026-10-31: a row per attempt buried the page in 已取消), in the order of
/// each one's latest: who last logged in to it and when (else that nobody has yet, and how its latest ended), from which
/// chat, how many tries, and the tries themselves. `ended`: each as the station holds it and as shown, newest first.
export function toolsShown(ended: [J, J][]): J[] {
  const by = new Map<string, [J, J][]>();
  for (const pair of ended) {
    const tries = by.get(pair[1].name);
    if (tries) tries.push(pair);
    else by.set(pair[1].name, [pair]);
  }
  return [...by].map(([name, tries]) => {
    const done = tries.find(([, s]) => s.state === "done");
    const [raw, s] = done ?? tries[0]!;
    const who = done && isObject(raw.doneBy) ? person(raw.doneBy) : "";
    const said = done
      ? who !== "" ? t("core-logic.machineLogin.loggedInBy", { name: who }) : s.statusText
      : t("core-logic.machineLogin.neverDone", { status: s.statusText });
    return {
      name,
      summaryText: [said, s.whenText].filter((w) => w !== "").join(" · "),
      failed: !done && s.state === "failed",
      ...(s.chat !== undefined ? { chat: s.chat } : {}),
      ...(s.chatTitle !== undefined ? { chatTitle: s.chatTitle } : {}),
      countText: t("core-logic.machineLogin.tries", { n: tries.length }),
      tries: tries.map(([, shown]) => shown),
    };
  });
}

// ── the relay ──

/// Where a login's callback is to come: its port and the loopback addresses to listen on (localhost: both, for the
/// browser may try either), its path, its state, and whether it is a form posted.
export type Expect = { port: number; hosts: string[]; path: string; state: string; post: boolean };

export function expectOf(login: J): Expect | null {
  const c = get(login, "callback");
  const port = get(c, "port");
  const state = str(get(c, "state"));
  if (typeof port !== "number" || state === null) return null;
  const host = str(get(c, "host")) ?? "localhost";
  const hosts = host === "localhost" ? ["127.0.0.1", "::1"] : host === "[::1]" || host === "::1" ? ["::1"] : ["127.0.0.1"];
  return { port, hosts, path: str(get(c, "path")) ?? "/", state, post: get(c, "post") === true };
}

/// Whether a request that came to the listener is the login's callback: its Host (a page elsewhere cannot make the
/// browser send one here: DNS rebinding), its method, its path and its state.
export function isCallback(expect: Expect, request: { method: string; path: string; headers: [string, string][]; body: Uint8Array }): boolean {
  const host = request.headers.find(([k]) => k.toLowerCase() === "host")?.[1] ?? "";
  if (![`localhost:${expect.port}`, `127.0.0.1:${expect.port}`, `[::1]:${expect.port}`].includes(host.toLowerCase())) return false;
  if (request.method.toUpperCase() !== (expect.post ? "POST" : "GET")) return false;
  const at = request.path.indexOf("?");
  const path = at < 0 ? request.path : request.path.slice(0, at);
  if ((path === "" ? "/" : path) !== expect.path) return false;
  // By hand (asks.ts param): Android's engine (Hermes) has no URLSearchParams; using it there ended the core at the
  // browser's first request (found by the real check on the emulator, 2026-10-18).
  const query = at < 0 ? "" : request.path.slice(at + 1);
  const state = expect.post ? (param(new TextDecoder().decode(request.body), "state") ?? param(query, "state")) : param(query, "state");
  return state === expect.state;
}

const page = (title: string, words: string) =>
  new TextEncoder().encode(`<!doctype html><meta charset="utf-8"><title>${title}</title><body style="font:16px system-ui;margin:48px;color:#333"><h1 style="font-size:20px">${title}</h1><p>${words}</p></body>`);
const HTML: [string, string][] = [["content-type", "text/html; charset=utf-8"], ["cache-control", "no-store"]];

/// The loopback listeners of logins this device relays, by station and login.
export class Relays {
  readonly #core: Inner;
  readonly #open = new Map<string, { fiber: Fiber.Fiber<void, never> | null; relayed: boolean }>();
  /// Why this device could not listen for a login's callback when it was last opened here (the port taken: 本机 8085
  /// 端口被占用), said on its card until it is opened again.
  readonly #refused = new Map<string, string>();
  /// Told as a relay starts and stops (the login's `listening`), and as one is refused.
  onChange: (station: string, id: string) => void = () => {};

  constructor(core: Inner) {
    this.#core = core;
  }

  listening(station: string, id: string): boolean {
    return this.#open.has(`${station}\n${id}`);
  }

  /// Why a login's callback could not be listened for here, the last time it was opened (null: it was, or it was not
  /// opened here).
  refused(station: string, id: string): string | null {
    return this.#refused.get(`${station}\n${id}`) ?? null;
  }

  /// Listens for a login's callback, until it is relayed (and AFTER_MS after), the login ends, or RELAY_MOST_MS. Fails
  /// (the port taken on this device) before anything is opened.
  start(station: string, id: string, expect: Expect): Effect.Effect<void, CoreError> {
    const key = `${station}\n${id}`;
    const core = this.#core;
    const listen = core.host.listen;
    if (!listen) return Effect.fail(new CoreError("unsupported", t("core-logic.machineLogin.cannotRelay")));
    if (this.#open.has(key)) return Effect.void;
    const self = this;
    return Effect.gen(function* () {
      const addr = yield* Effect.try({ try: () => StationAddr.parse(station), catch: () => CoreError.invalid(t("core-misc.params.missing", { field: "station" })) });
      const scope = yield* Scope.make();
      const listeners: Pull<LoopbackRequest>[] = [];
      for (const [i, host] of expect.hosts.entries()) {
        const opened = yield* Effect.result(Scope.provide(listen(expect.port, host), scope));
        if (opened._tag === "Success") listeners.push(opened.success);
        // The first address refused is this device's port taken (another program on it); the second (::1 for
        // localhost) may be a machine without IPv6.
        else if (i === 0) {
          yield* Scope.close(scope, Exit.void);
          const why = t("core-logic.machineLogin.portTaken", { port: expect.port });
          self.#refused.set(key, why);
          self.onChange(station, id);
          return yield* Effect.fail(new CoreError("port_taken", why));
        }
      }
      self.#refused.delete(key);
      const entry: { fiber: Fiber.Fiber<void, never> | null; relayed: boolean } = { fiber: null, relayed: false };
      const answer = (r: LoopbackRequest) =>
        Effect.gen(function* () {
          if (entry.relayed) return r.respond(200, HTML, page(t("core-logic.machineLogin.pageDoneTitle"), t("core-logic.machineLogin.pageDone")));
          if (!isCallback(expect, r)) return r.respond(404, HTML, page(t("core-logic.machineLogin.pageNotTitle"), t("core-logic.machineLogin.pageNot")));
          entry.relayed = true;
          core.runner.fork(Effect.andThen(Effect.sleep(AFTER_MS), Effect.sync(() => self.stop(station, id))));
          const headers = Object.fromEntries(r.headers.map(([k, v]) => [k.toLowerCase(), v]));
          const sent = yield* Effect.result(
            core.stations.requests.call(addr, "POST", `/machine-logins/${encode(id)}/callback`, { method: r.method, path: r.path, headers, ...(r.body.length > 0 ? { body: base64(r.body) } : {}) }, { quiet: true }),
          );
          if (sent._tag === "Failure") return r.respond(502, HTML, page(t("core-logic.machineLogin.pageFailedTitle"), sent.failure.message.replaceAll("<", "&lt;")));
          const got = sent.success;
          const told = isObject(get(got, "headers")) ? Object.entries(get(got, "headers") as Record<string, unknown>).filter((e): e is [string, string] => typeof e[1] === "string") : [];
          r.respond(typeof get(got, "status") === "number" ? (get(got, "status") as number) : 502, told, fromBase64(str(get(got, "body")) ?? "") ?? new Uint8Array());
        });
      const serve = (requests: Pull<LoopbackRequest>) =>
        Effect.gen(function* () {
          for (;;) {
            const r = yield* Effect.orElseSucceed(requests.take, () => null);
            if (r === null) return;
            yield* answer(r);
          }
        });
      const run = Effect.raceFirst(Effect.sleep(RELAY_MOST_MS), Effect.all(listeners.map(serve), { concurrency: "unbounded", discard: true })).pipe(
        Effect.ensuring(Scope.close(scope, Exit.void)),
        Effect.ensuring(
          Effect.sync(() => {
            if (self.#open.get(key) === entry) self.#open.delete(key);
            self.onChange(station, id);
          }),
        ),
      );
      self.#open.set(key, entry);
      entry.fiber = core.runner.fork(run);
      self.onChange(station, id);
    });
  }

  /// A relay stopped: its listeners closed.
  stop(station: string, id: string): void {
    const key = `${station}\n${id}`;
    const entry = this.#open.get(key);
    if (!entry) return;
    this.#open.delete(key);
    if (entry.fiber) this.#core.runner.interrupt(entry.fiber as Fiber.Fiber<unknown, unknown>);
    this.onChange(station, id);
  }

  /// The login ended: its relay stops, unless its callback was relayed (it stays the AFTER_MS after, for the pages
  /// that follow it).
  ended(station: string, id: string): void {
    if (this.#open.get(`${station}\n${id}`)?.relayed === false) this.stop(station, id);
  }

  /// Lets go of every relay (the core closes).
  close(): void {
    this.#refused.clear();
    for (const [key, entry] of [...this.#open]) {
      this.#open.delete(key);
      if (entry.fiber) this.#core.runner.interrupt(entry.fiber as Fiber.Fiber<unknown, unknown>);
    }
  }
}
