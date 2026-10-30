// What a UI asks the core to find out (asks.rs): where one of still.fail's links opens in the app, whether a newer
// app is out, a picture (fetched once and kept on the device), the buddies a Slack app can wear, a dev cloud's sign-in.
import { Deferred, Effect, Semaphore } from "effect";
import buddiesList from "../../../web/public/avatars/index.json" with { type: "json" };
import { RELEASE_KEYS } from "../../../station/src/updates/keys.ts";
import { winReleaseUnverified } from "./app-release.ts";
import { encodeComponent } from "./accounts.ts";
import type { AccountSessions } from "./account-provider.ts";
import type { Ask } from "./asks-parse.ts";
import * as brand from "./brand.ts";
import { conform } from "./conform.ts";
import { CoreError } from "./error.ts";
import { header, type Host } from "./host.ts";
import { t } from "./i18n.ts";
import { Beside } from "./protocol.ts";
import { fromUtf8, hex, isObject, parseJson, sha256, toJsonBytes, utf8 } from "./util.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// still.fail cloud under its names: the released app's, the test channel's (youdid.wtf), ember's from before the rename.
const CLOUD_HOSTS = ["app.still.fail", "app.youdid.wtf", "ember.3720.org"];
const UPDATE_EVERY_MS = 60 * 60 * 1000;
const PICTURES = 256;
/// A picture that could not be fetched is not asked for again for this long: a Google account's, where Google cannot be
/// reached, waited 15 s each time it was drawn, about half of a phone's.
export const PICTURE_RETRY_MS = 10 * 60_000;
/// Pictures kept on the device past the app's life, so a face is there before (or without) the network: each under
/// `picture-<sha256 of its address>` (its kind, a newline, its bytes); `pictures` lists them, the least lately had
/// first, with what stands in for an address not had yet (an account's picture changed: its last one). An address
/// names one picture for good (still.fail cloud's icons are by their hash, a Google account's changes with its
/// picture), so one kept is never fetched again. Past either bound the least lately had go.
export const PICTURES_KEY = "pictures";
export const PICTURES_KEPT = 256;
export const PICTURES_BYTES = 32 * 1024 * 1024;

type Picture = Deferred.Deferred<[string, Uint8Array], CoreError>;
/// What is kept: each picture's name and size, the least lately had first; the name of the one standing in for each
/// not had yet.
type Kept = { kept: [string, number][]; standIn: Record<string, string> };

/// What build `to` brings this app at build `from`: the changelog's lines for it (Changelog.brings).
export type Brings = (from: number, to: number) => Effect.Effect<string[]>;

export class Asks {
  readonly #host: Host;
  readonly #brings: Brings;
  readonly #releases = new Map<string, [number, J]>();
  readonly #pictures = new Map<string, Picture>();
  /// Pictures that could not be fetched: when, and why.
  readonly #pictureFailed = new Map<string, [number, CoreError]>();
  /// What is kept on the device, read once.
  #kept: Kept | null = null;
  /// The accounts' pictures changed (`[before, now]`), not yet among what is kept: taken in turn, before any picture
  /// is answered for one not had.
  readonly #changed: [string, string][] = [];
  readonly #taking = Semaphore.makeUnsafe(1);

  constructor(host: Host, brings: Brings) {
    this.#host = host;
    this.#brings = brings;
  }

  run(ask: Ask, accounts: AccountSessions): Effect.Effect<unknown, CoreError> {
    switch (ask.kind) {
      case "linkParse":
        return Effect.succeed(linkTarget(ask.url, this.#host.cloudOrigin()));
      case "appUpdate":
        // (youdid.wtf's builds are its platform's beta feed; an app of its own on the test channel names its feed whole)
        return this.update(ask.platform, ask.version, ask.now, brand.testApp(), ask.keys);
      case "picture":
        return Effect.map(this.picture(ask.url), ([kind, bytes]) => new Beside({ type: kind }, bytes));
      case "buddies":
        return Effect.succeed(buddies());
      case "devSignIn":
        return Effect.gen({ self: this }, function* () {
          const origin = this.#host.cloudOrigin();
          if (!devCloud(origin)) return yield* Effect.fail(CoreError.invalid(t("core-misc.ask.dev_only")));
          const url = `${origin}/__dev/account?user=${encodeComponent(ask.user)}`;
          const response = yield* Effect.mapError(this.#host.fetch({ method: "GET", url, headers: [], body: null }), (e) => new CoreError("dev_cloud", t("core-misc.ask.dev_cloud", { error: e.message })));
          const account = response.status === 200 ? parseJson(response.body) : undefined;
          if (account === undefined) return yield* Effect.fail(new CoreError("dev_cloud", t("core-misc.ask.dev_cloud", { error: response.status })));
          yield* accounts.migrate([account]);
          return null;
        });
    }
  }

  /// The newest build of `platform`'s feed (its beta feed, `<platform>/beta`, where `beta`) when newer than `version`,
  /// with what it brings this app (`news`: the changelog's lines for it after `version`; the app's home offers a build
  /// only with some). A Windows build signed by one of `keys` is taken too (app-release.ts).
  update(platform: string, version: number, now: boolean, beta: boolean, keys: readonly string[] = []): Effect.Effect<J, CoreError> {
    return Effect.flatMap(this.#newest(platform, version, now, beta, keys), (release) =>
      release === null ? Effect.succeed(null) : Effect.map(this.#brings(version, release.versionCode), (news) => ({ ...release, news })),
    );
  }

  #newest(platform: string, version: number, now: boolean, beta: boolean, keys: readonly string[]): Effect.Effect<J, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const feed = beta ? `${platform}/beta` : platform;
      const newer = (release: J) => (release !== null && release !== undefined && typeof release.versionCode === "number" && release.versionCode > version ? release : null);
      const time = this.#host.nowMs();
      const kept = this.#releases.get(feed);
      if (kept && !now && time - kept[0] < UPDATE_EVERY_MS) return newer(kept[1]);
      this.#releases.set(feed, [time, kept?.[1] ?? null]);
      const url = `${this.#host.cloudOrigin()}/releases/${feed}/latest.json`;
      const response = yield* Effect.result(this.#host.fetch({ method: "GET", url, headers: [["cache-control", "no-cache"]], body: null }));
      if (response._tag === "Failure") {
        if (now) return yield* Effect.fail(new CoreError("app_update", t("core-misc.ask.update_failed", { error: response.failure.message })));
        return newer(this.#releases.get(feed)![1]);
      }
      const raw = response.success.status === 200 ? parseJson(response.success.body) : undefined;
      const shaped = raw !== undefined ? conform("AppRelease", raw) : null;
      let release = shaped !== null && "ok" in shaped ? shaped.ok : null;
      // the Windows app's installer taken only as its signed words say it (app-release.ts): else none is offered
      const unverified = release !== null && platform.split("/")[0] === "win" ? winReleaseUnverified(raw, [...RELEASE_KEYS, ...keys]) : "";
      if (unverified !== "") {
        console.warn(`app.update: ${feed}: ${unverified}`);
        if (now) return yield* Effect.fail(new CoreError("app_update", t("core-misc.ask.update_unsigned")));
        release = null;
      }
      if (now && release === null) return yield* Effect.fail(new CoreError("app_update", t("core-misc.ask.update_retry")));
      if (release !== null) this.#releases.set(feed, [time, release]);
      return newer(this.#releases.get(feed)![1]);
    });
  }

  /// A picture by its address, fetched once (those asking together share the one fetch) and kept: one kept is answered
  /// from the device. One that cannot be had is answered with what stands in for it, when something does.
  picture(url: string): Effect.Effect<[string, Uint8Array], CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (!(url.startsWith("https://") || url.startsWith("http://"))) return yield* Effect.fail(CoreError.invalid(t("core-misc.ask.bad_picture_url")));
      const failed = this.#pictureFailed.get(url);
      if (failed !== undefined && this.#host.nowMs() - failed[0] < PICTURE_RETRY_MS) return yield* this.#standIn(url, failed[1]);
      let picture = this.#pictures.get(url);
      if (!picture) {
        const made = Deferred.makeUnsafe<[string, Uint8Array], CoreError>();
        if (this.#pictures.size >= PICTURES) this.#pictures.clear();
        this.#pictures.set(url, made);
        picture = made;
        const fetched = yield* Effect.result(
          Effect.flatMap(this.#keptPicture(pictureName(url)), (kept) =>
            kept !== null
              ? Effect.succeed(kept)
              : Effect.flatMap(
                  Effect.mapError(this.#host.fetch({ method: "GET", url, headers: [], body: null }), (e) => new CoreError("picture", t("core-misc.ask.picture_failed", { error: e.message }))),
                  (r) => (r.status !== 200 ? Effect.fail(new CoreError("picture", t("core-misc.ask.picture_failed", { error: r.status }))) : Effect.as(this.#keep(url, header(r, "content-type") ?? "", r.body), [header(r, "content-type") ?? "", r.body] as [string, Uint8Array])),
                ),
          ),
        );
        Deferred.doneUnsafe(made, fetched._tag === "Success" ? Effect.succeed(fetched.success) : Effect.fail(fetched.failure));
      }
      const got = yield* Effect.result(Deferred.await(picture));
      if (got._tag === "Failure") {
        if (this.#pictures.get(url) === picture) this.#pictures.delete(url);
        if (this.#pictureFailed.size >= PICTURES) this.#pictureFailed.clear();
        this.#pictureFailed.set(url, [this.#host.nowMs(), got.failure]);
        return yield* this.#standIn(url, got.failure);
      }
      this.#pictureFailed.delete(url);
      return got.success;
    });
  }

  /// Follows the accounts' pictures: one changed has its last one stand in for it until it is had (its new address
  /// not reached yet, as a Google account's where Google cannot be).
  follow(accounts: AccountSessions): void {
    const was = new Map(accounts.list().map((a) => [a.sub, a.picture]));
    accounts.onChange(() => {
      for (const a of accounts.list()) {
        const before = was.get(a.sub);
        was.set(a.sub, a.picture);
        if (before === undefined || before === "" || a.picture === "" || before === a.picture) continue;
        this.#changed.push([before, a.picture]);
        Effect.runFork(this.#takeChanged());
      }
    });
  }

  #takeChanged(): Effect.Effect<void> {
    return this.#taking.withPermits(1)(Effect.suspend(() => Effect.forEach(this.#changed.splice(0), ([before, now]) => this.replaced(before, now), { discard: true })));
  }

  /// `now` is the picture `before` was: until `now` is had, `before` (when kept) is answered for it.
  replaced(before: string, now: string): Effect.Effect<void> {
    return Effect.flatMap(this.#index(), (kept) => {
      const [from, to] = [pictureName(before), pictureName(now)];
      const has = (name: string) => kept.kept.some(([n]) => n === name);
      // `before` itself, else what stood in for it (never had either): the last picture had.
      const other = has(from) ? from : kept.standIn[from];
      if (other === undefined || has(to)) return Effect.void;
      kept.standIn[to] = other;
      return this.#writeIndex(kept);
    });
  }

  /// What stands in for `url`, or `error`.
  #standIn(url: string, error: CoreError): Effect.Effect<[string, Uint8Array], CoreError> {
    return Effect.flatMap(Effect.andThen(this.#takeChanged(), this.#index()), (kept) => {
      const other = kept.standIn[pictureName(url)];
      if (other === undefined) return Effect.fail(error);
      return Effect.flatMap(this.#keptPicture(other), (picture) => (picture === null ? Effect.fail(error) : Effect.succeed(picture)));
    });
  }

  /// A kept picture by its name, now the most lately had; null when none is.
  #keptPicture(name: string): Effect.Effect<[string, Uint8Array] | null> {
    return Effect.flatMap(this.#index(), (kept) => {
      const at = kept.kept.findIndex(([n]) => n === name);
      if (at < 0) return Effect.succeed(null);
      return Effect.map(Effect.orElseSucceed(this.#host.storageGet(`picture-${name}`), () => null), (bytes) => {
        const cut = bytes === null ? -1 : bytes.indexOf(10);
        if (bytes === null || cut < 0) return null;
        // (Written down with the next one kept: a picture had is not a write.)
        kept.kept.push(...kept.kept.splice(at, 1));
        return [fromUtf8(bytes.subarray(0, cut)), bytes.slice(cut + 1)] as [string, Uint8Array];
      });
    });
  }

  /// Keeps a picture fetched, best effort: the least lately had go past the bounds.
  #keep(url: string, kind: string, body: Uint8Array): Effect.Effect<void> {
    return Effect.flatMap(this.#index(), (kept) =>
      Effect.gen({ self: this }, function* () {
        const name = pictureName(url);
        const head = utf8(`${kind.replaceAll("\n", "")}\n`);
        const bytes = new Uint8Array(head.length + body.length);
        bytes.set(head);
        bytes.set(body, head.length);
        if (bytes.length > PICTURES_BYTES) return;
        const written = yield* Effect.result(this.#host.storageSet(`picture-${name}`, bytes));
        if (written._tag === "Failure") return;
        kept.kept = kept.kept.filter(([n]) => n !== name);
        kept.kept.push([name, bytes.length]);
        delete kept.standIn[name];
        let total = kept.kept.reduce((sum, [, size]) => sum + size, 0);
        while (kept.kept.length > PICTURES_KEPT || total > PICTURES_BYTES) {
          const [gone, size] = kept.kept.shift()!;
          total -= size;
          yield* Effect.ignore(this.#host.storageDelete(`picture-${gone}`), { log: "Unhandled", message: "asked picture removed" });
        }
        yield* this.#writeIndex(kept);
      }),
    );
  }

  #index(): Effect.Effect<Kept> {
    return Effect.suspend(() => {
      if (this.#kept !== null) return Effect.succeed(this.#kept);
      return Effect.map(Effect.orElseSucceed(this.#host.storageGet(PICTURES_KEY), () => null), (bytes) => {
        if (this.#kept === null) this.#kept = readKept(parseJson(bytes));
        return this.#kept;
      });
    });
  }

  /// Writes what is kept down, what stands in for none kept left out.
  #writeIndex(kept: Kept): Effect.Effect<void> {
    const names = new Set(kept.kept.map(([name]) => name));
    for (const [name, other] of Object.entries(kept.standIn)) if (!names.has(other)) delete kept.standIn[name];
    return Effect.ignore(this.#host.storageSet(PICTURES_KEY, toJsonBytes(kept)), { log: "Unhandled", message: "asked pictures kept" });
  }
}

/// A picture's name among those kept: its address's sha256.
function pictureName(url: string): string {
  return hex(sha256(utf8(url)));
}

function readKept(raw: unknown): Kept {
  const kept: Kept = { kept: [], standIn: {} };
  if (!isObject(raw)) return kept;
  if (Array.isArray(raw.kept)) for (const e of raw.kept) if (Array.isArray(e) && typeof e[0] === "string" && typeof e[1] === "number") kept.kept.push([e[0], e[1]]);
  if (isObject(raw.standIn)) for (const [name, other] of Object.entries(raw.standIn)) if (typeof other === "string") kept.standIn[name] = other;
  return kept;
}

/// A dev cloud on this machine or the emulator's host.
export function devCloud(origin: string): boolean {
  if (!origin.startsWith("http://")) return false;
  const rest = origin.slice(7);
  const at = rest.indexOf(":");
  if (at < 0) return false;
  const host = rest.slice(0, at);
  const port = rest.slice(at + 1);
  return ["127.0.0.1", "localhost", "10.0.2.2"].includes(host) && port !== "" && /^[0-9]+$/.test(port);
}

export function buddies(): J {
  return structuredClone(buddiesList);
}

type Url = { scheme: string; host: string; port: string | null; segments: string[]; query: string; fragment: string };

function splitUrl(url: string): Url | null {
  const at = url.indexOf("://");
  if (at < 0) return null;
  const scheme = url.slice(0, at);
  let rest = url.slice(at + 3);
  const cut = (s: string, c: string): [string, string] => {
    const i = s.indexOf(c);
    return i < 0 ? [s, ""] : [s.slice(0, i), s.slice(i + 1)];
  };
  let fragment: string;
  let query: string;
  [rest, fragment] = cut(rest, "#");
  [rest, query] = cut(rest, "?");
  const [authorityAll, path] = cut(rest, "/");
  const atSign = authorityAll.lastIndexOf("@");
  const authority = atSign >= 0 ? authorityAll.slice(atSign + 1) : authorityAll;
  const colon = authority.lastIndexOf(":");
  let host = authority;
  let port: string | null = null;
  if (colon >= 0) {
    const p = authority.slice(colon + 1);
    if (p !== "" && /^[0-9]+$/.test(p)) {
      host = authority.slice(0, colon);
      port = p;
    }
  }
  return {
    scheme: scheme.toLowerCase(),
    host: host.toLowerCase(),
    port,
    segments: path.split("/").filter((s) => s !== "").map(decode),
    query,
    fragment: decode(fragment),
  };
}

function decode(s: string): string {
  const bytes = new TextEncoder().encode(s);
  const out: number[] = [];
  const hex = (b: number | undefined) => (b === undefined ? null : /[0-9a-fA-F]/.test(String.fromCharCode(b)) ? parseInt(String.fromCharCode(b), 16) : null);
  for (let i = 0; i < bytes.length; ) {
    const a = hex(bytes[i + 1]);
    const b = hex(bytes[i + 2]);
    if (bytes[i] === 37 && a !== null && b !== null) {
      out.push(a * 16 + b);
      i += 3;
    } else {
      out.push(bytes[i]);
      i++;
    }
  }
  return fromUtf8(new Uint8Array(out));
}

/// A query's value of `name` (its first), decoded; null when it has none. By hand: Android's engine (Hermes) has no
/// URLSearchParams.
export function param(query: string, name: string): string | null {
  for (const kv of query.split("&")) {
    const i = kv.indexOf("=");
    if (i >= 0 && kv.slice(0, i) === name) return decode(kv.slice(i + 1).replaceAll("+", " "));
  }
  return null;
}

/// The agent's execution history a link names (`?history=<session>&entry=<n>`): `history`, and `entry` when it says
/// one; nothing for a link that names none.
function historyOf(query: string): { history?: string; entry?: number } {
  const history = param(query, "history");
  if (history === null || history === "") return {};
  const entry = param(query, "entry");
  return entry !== null && /^\d{1,15}$/.test(entry) ? { history, entry: Number(entry) } : { history };
}

/// A message destination is a positive, exactly representable sequence number.
function messageOf(query: string): { message?: number } {
  const value = param(query, "message");
  return value !== null && /^[1-9]\d{0,14}$/.test(value) ? { message: Number(value) } : {};
}

/// What one of still.fail's own links opens in the app; null for any other link. A chat's page or an item, with
/// `history` (and `entry`) when it names one of its agents' execution history; a link of only that (`?history=…`, as
/// a chat's notes write it) opens it in the chat it is in (`history`).
export function linkTarget(url: string, origin: string): J {
  if (url.startsWith("?")) {
    const h = historyOf(url.slice(1).split("#")[0]!);
    return h.history === undefined ? null : { opens: "history", ...h };
  }
  // A path with no host of its own (`/w/…/adb`, as a message may write one) is the cloud's own, as the cards the
  // library draws for such links read it (refLinks.ts: `adbOfLink`, `screenOfLink`), so that one shown is one opened
  // (2026-10-30: a 共享调试 link's card was drawn, and its 详情 opened nothing).
  const u = splitUrl(url.startsWith("/") && !url.startsWith("//") ? `${origin.replace(/\/+$/, "")}${url}` : url);
  const o = splitUrl(origin);
  if (u === null || o === null) return null;
  const same = u.scheme === o.scheme && u.host === o.host && u.port === o.port;
  const sameCloud = CLOUD_HOSTS.includes(o.host) && u.scheme === "https" && CLOUD_HOSTS.includes(u.host) && u.port === null;
  if (!(same || sameCloud)) return null;
  const s = u.segments;
  if (s.length === 1 && s[0] === "invite" && u.fragment !== "") return { opens: "invite", token: u.fragment };
  if (s.length === 6 && s[0] === "w" && s[2] === "s" && s[4] === "chats") return { opens: "chat", workspace: s[1], station: s[3], chat: s[5], ...historyOf(u.query), ...messageOf(u.query) };
  if (s.length === 5 && s[0] === "w" && s[2] === "s" && s[4] === "adb") return { opens: "adbShare", workspace: s[1], station: s[3] };
  // One of a station's screens (docs/remote-screens.md), as its agents' `screen` tool links it.
  if (s.length === 6 && s[0] === "w" && s[2] === "s" && s[4] === "screen" && s[5] !== "") return { opens: "screen", workspace: s[1], station: s[3], screen: s[5] };
  // A login an agent started on a station (docs/remote-login.md), as its `login` tool links it: its card on the
  // station's page.
  if (s.length === 6 && s[0] === "w" && s[2] === "s" && s[4] === "login" && s[5] !== "") return { opens: "login", workspace: s[1], station: s[3], login: s[5] };
  if (s.length === 4 && s[0] === "o") {
    const service = param(u.query, "service");
    return { opens: "item", workspace: s[1], station: s[2], session: s[3], service: service !== null && service !== "" ? service : null, ...historyOf(u.query), ...messageOf(u.query) };
  }
  return null;
}
