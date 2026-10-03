// What a UI asks the core to find out (asks.rs): where one of still.fail's links opens in the app, whether a newer
// app is out, a picture (fetched once), the buddies a Slack app can wear, a dev cloud's sign-in.
import { Deferred, Effect } from "effect";
import buddiesList from "../../../web/public/avatars/index.json" with { type: "json" };
import { encodeComponent, type Accounts } from "./accounts.ts";
import type { Ask } from "./asks-parse.ts";
import { conform } from "./conform.ts";
import { CoreError } from "./error.ts";
import { header, type Host } from "./host.ts";
import { t } from "./i18n.ts";
import { base64, fromUtf8, parseJson } from "./util.ts";

// deno-lint-ignore no-explicit-any
type J = any;

const CLOUD_HOSTS = ["app.still.fail", "ember.3720.org"];
const UPDATE_EVERY_MS = 60 * 60 * 1000;
const PICTURES = 256;

type Picture = Deferred.Deferred<[string, Uint8Array], CoreError>;

export class Asks {
  readonly #host: Host;
  readonly #releases = new Map<string, [number, J]>();
  readonly #pictures = new Map<string, Picture>();

  constructor(host: Host) {
    this.#host = host;
  }

  run(ask: Ask, accounts: Accounts): Effect.Effect<unknown, CoreError> {
    switch (ask.kind) {
      case "linkParse":
        return Effect.succeed(linkTarget(ask.url, this.#host.cloudOrigin()));
      case "appUpdate":
        return this.update(ask.platform, ask.version, ask.now, this.#host.beta());
      case "picture":
        return Effect.map(this.picture(ask.url), ([kind, bytes]) => ({ type: kind, bytes: base64(bytes) }));
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

  /// The newest build of `platform`'s feed when newer than `version`.
  update(platform: string, version: number, now: boolean, beta: boolean): Effect.Effect<J, CoreError> {
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
      const release = shaped !== null && "ok" in shaped ? shaped.ok : null;
      if (now && release === null) return yield* Effect.fail(new CoreError("app_update", t("core-misc.ask.update_retry")));
      if (release !== null) this.#releases.set(feed, [time, release]);
      return newer(this.#releases.get(feed)![1]);
    });
  }

  /// A picture by its address, fetched once (those asking together share the one fetch).
  picture(url: string): Effect.Effect<[string, Uint8Array], CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (!(url.startsWith("https://") || url.startsWith("http://"))) return yield* Effect.fail(CoreError.invalid(t("core-misc.ask.bad_picture_url")));
      let picture = this.#pictures.get(url);
      if (!picture) {
        const made = Deferred.makeUnsafe<[string, Uint8Array], CoreError>();
        if (this.#pictures.size >= PICTURES) this.#pictures.clear();
        this.#pictures.set(url, made);
        picture = made;
        const fetched = yield* Effect.result(
          Effect.flatMap(
            Effect.mapError(this.#host.fetch({ method: "GET", url, headers: [], body: null }), (e) => new CoreError("picture", t("core-misc.ask.picture_failed", { error: e.message }))),
            (r) => (r.status !== 200 ? Effect.fail(new CoreError("picture", t("core-misc.ask.picture_failed", { error: r.status }))) : Effect.succeed([header(r, "content-type") ?? "", r.body] as [string, Uint8Array])),
          ),
        );
        Deferred.doneUnsafe(made, fetched._tag === "Success" ? Effect.succeed(fetched.success) : Effect.fail(fetched.failure));
      }
      const got = yield* Effect.result(Deferred.await(picture));
      if (got._tag === "Failure") {
        if (this.#pictures.get(url) === picture) this.#pictures.delete(url);
        return yield* Effect.fail(got.failure);
      }
      return got.success;
    });
  }
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

/// What one of still.fail's own links opens in the app; null for any other link.
export function linkTarget(url: string, origin: string): J {
  const u = splitUrl(url);
  const o = splitUrl(origin);
  if (u === null || o === null) return null;
  const same = u.scheme === o.scheme && u.host === o.host && u.port === o.port;
  const sameCloud = CLOUD_HOSTS.includes(o.host) && u.scheme === "https" && CLOUD_HOSTS.includes(u.host) && u.port === null;
  if (!(same || sameCloud)) return null;
  const s = u.segments;
  if (s.length === 1 && s[0] === "invite" && u.fragment !== "") return { opens: "invite", token: u.fragment };
  if (s.length === 6 && s[0] === "w" && s[2] === "s" && s[4] === "chats") return { opens: "chat", workspace: s[1], station: s[3], chat: s[5] };
  if (s.length === 5 && s[0] === "w" && s[2] === "s" && s[4] === "adb") return { opens: "adbShare", workspace: s[1], station: s[3] };
  if (s.length === 4 && s[0] === "o") {
    let service: string | null = null;
    for (const kv of u.query.split("&")) {
      const i = kv.indexOf("=");
      if (i < 0) continue;
      if (kv.slice(0, i) === "service") {
        service = decode(kv.slice(i + 1).replaceAll("+", " "));
        break;
      }
    }
    return { opens: "item", workspace: s[1], station: s[2], session: s[3], service: service !== null && service !== "" ? service : null };
  }
  return null;
}
