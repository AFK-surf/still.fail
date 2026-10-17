// What another app shares into still.fail (a link from a browser or a video app, some text): the chat it goes to
// (docs/share-in.md). The `shareIn` view lists the chats it can go to (the workspace's own chats on still.fail's page,
// as the sidebar has them, newest first), the one it went to last time from the same site first; `shareIn.open` puts
// it in the composer of the one picked (or of a new chat on a station), where the person adds to it and sends it as
// anything written there: the page opens that chat. One composer, not one of the sheet's own beside the chat's.
import { Effect } from "effect";
import type { Inner } from "./core.ts";
import type { Call } from "./core/calls.ts";
import { handlers } from "./core/execute.ts";
import type { Owner } from "./core/routing.ts";
import { asCoreError, CoreError } from "./error.ts";
import { t } from "./i18n.ts";
import { parseTopic, topicKey, type Topic } from "./protocol.ts";
import * as refs from "./refs.ts";
import type { Value, Watch } from "./store.ts";
import { arr as arrU, get as getU, isObject } from "./util.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);

const TABLE = "choice";
/// At most this many chats are offered (the search finds among all of them).
export const LISTED = 30;

/// Where a shared thing goes: a chat (its row's `id`) or, without one, a new chat on `station`.
export type Target = { station: string; id?: string };

/// Sites that share links under a short host of their own, by the site they are of.
const SHORT: Record<string, string> = {
  "youtu.be": "youtube.com",
  "b23.tv": "bilibili.com",
  "xhslink.com": "xiaohongshu.com",
  "v.douyin.com": "douyin.com",
  "t.co": "x.com",
  "twitter.com": "x.com",
  "vm.tiktok.com": "tiktok.com",
};

/// The site of the first link in what is shared (`youtube.com`), its www./m. left out; null when it has none.
export function siteOf(source: string): string | null {
  const m = /https?:\/\/[^\s<>"'）)】」]+/i.exec(source);
  if (m === null) return null;
  let host: string;
  try {
    host = new URL(m[0]).hostname.toLowerCase();
  } catch {
    return null;
  }
  if (host === "") return null;
  if (SHORT[host]) return SHORT[host];
  host = host.replace(/^(www|m|mobile)\./, "");
  return SHORT[host] ?? host;
}

/// The words a shared thing goes into a composer as: what the person added first (none from a sheet: they add it in the
/// composer), then the title the app gave (when the shared text does not have it already), then what was shared.
export function messageOf(source: string, title: string | null, note: string | null): string {
  const parts: string[] = [];
  const n = note?.trim() ?? "";
  if (n !== "") parts.push(n);
  const s = source.trim();
  const tt = title?.trim() ?? "";
  parts.push(tt !== "" && !s.includes(tt) ? `${tt}\n${s}` : s);
  return parts.join("\n\n");
}

/// The rows a shared thing can go to, of a `chats` view's: the workspace's own chats on still.fail's page (a Slack
/// chat takes no message from here), not one still being made.
function open(rows: J[]): J[] {
  return rows.filter((r) => (r.origin === undefined || r.origin === null) && r.pending !== true && (typeof r.outside !== "string" || r.outside === ""));
}

const kept = (inner: Inner, scope: string, site: string | null): J => inner.data.record(TABLE, `ws:${scope}:shareIn:${site ?? ""}`);

/// The row of a chat kept as where a site's things went: by its id, or by the key it went by while it was being made.
function keptRow(rows: J[], k: J): J | undefined {
  if (!isObject(k) || typeof k.station !== "string") return undefined;
  return rows.find((r) => r.station === k.station && ((typeof k.id === "string" && (r.id === k.id || r.session === k.id)) || (typeof k.clientKey === "string" && r.clientKey === k.clientKey)));
}

export class ShareIn implements Owner {
  readonly #inner: Inner;
  readonly #watches = new Map<string, Watch[]>();

  constructor(inner: Inner) {
    this.#inner = inner;
  }

  owns(topic: Topic): boolean {
    return topic.topic === "shareIn";
  }

  start(topic: Topic): void {
    const store = this.#inner.store;
    const scope = topic.scope as string;
    const sources = [parseTopic({ topic: "chats", scope }), parseTopic({ topic: "stations", scope })].filter((x): x is Topic => x !== null);
    this.#watches.set(topicKey(topic), sources.map((s) => store.watch(s, () => store.invalidate(topic))));
  }

  stop(topic: Topic): void {
    for (const w of this.#watches.get(topicKey(topic)) ?? []) w.drop();
    this.#watches.delete(topicKey(topic));
  }

  #rows(scope: string): J[] | null {
    const chats = this.#inner.store.value(parseTopic({ topic: "chats", scope })!);
    if (chats === undefined || !("ok" in chats)) return null;
    return open(arr(refs.search(chats.ok, "", null, null, undefined).items));
  }

  /// The scope's stations up now, each `{ station, name }`; null while not known.
  #stations(scope: string): J[] | null {
    const v = this.#inner.store.value({ topic: "stations", scope });
    if (v === undefined || !("ok" in v)) return null;
    return arr(v.ok).filter((s) => s.online === true).map((s) => ({ station: s.station, name: typeof s.name === "string" && s.name !== "" ? s.name : s.id }));
  }

  compute(topic: Topic): Value | undefined {
    const scope = topic.scope as string;
    const source = String(topic.source ?? "");
    const query = String(topic.query ?? "");
    const all = this.#rows(scope);
    const stations = this.#stations(scope) ?? [];
    const site = siteOf(source);
    const view: J = { site, items: [], stations, loading: all === null };
    // Where a new chat starts unless another station is picked: where the scope's new chats last started.
    const last = this.#inner.choose.keptStation(scope);
    const on = stations.find((s) => s.station === `${scope}/${last}`) ?? stations[0];
    if (on !== undefined) view.newOn = on.station;
    if (all === null) return { ok: view };
    const k = keptRow(all, kept(this.#inner, scope, site));
    const found = query.trim() === "" ? all : open(arr(refs.search({ days: [{ items: all }] }, query, null, null, undefined).items));
    const rest = found.filter((r) => r !== k);
    view.items = (k !== undefined && found.includes(k) ? [k, ...rest] : rest).slice(0, LISTED);
    if (k !== undefined) view.kept = { station: k.station, id: k.id, text: site !== null ? t("core-logic.shareIn.kept", { site }) : t("core-logic.shareIn.kept_text") };
    if (stations.length === 0 && all.length === 0) view.note = t("core-logic.shareIn.none");
    return { ok: view };
  }

  /// `shareIn.open`: what is shared into the composer of the chat it goes to (a chat by its row's `id`, else a new chat
  /// on `station`, made the station new chats start on: `new:<station>`, or `newKey`, the key the page that opens it
  /// keeps a new chat's words by), after what is written there already, once; the page opens that chat and the person
  /// sends it from its composer. The chat is kept as where that site's things go.
  open(scope: string, source: string, title: string | null, target: Target, newKey: string | null = null): J {
    if (source.trim() === "") throw CoreError.invalid(t("core-logic.shareIn.error.empty"));
    const words = messageOf(source, title, null);
    if (target.id === undefined) {
      this.#inner.choose.pickNew(scope, { station: target.station.slice(target.station.lastIndexOf("/") + 1) });
      const key = newKey ?? `new:${target.station}`;
      this.#inner.composers.offer(key, words);
      return { station: target.station, key };
    }
    const row = (this.#rows(scope) ?? []).find((r) => r.station === target.station && r.id === target.id);
    if (row === undefined) throw CoreError.invalid(t("core-views.error.no_chat"));
    const key = `${target.station}:${row.session}`;
    this.#inner.composers.offer(key, words);
    this.#inner.data.put(TABLE, `ws:${scope}:shareIn:${siteOf(source) ?? ""}`, { station: target.station, id: row.id }, false);
    this.#inner.store.invalidateAll((x) => x.topic === "shareIn" && x.scope === scope);
    return { station: target.station, key, session: row.session, ...(typeof row.thread === "number" ? { thread: row.thread } : {}), title: row.title };
  }
}

export function install(inner: Inner): ShareIn {
  const share = new ShareIn(inner);
  inner.router.owners.push(share);
  handlers.shareIn = (_inner, call) => {
    const c = call as Extract<Call, { kind: "shareIn" }>;
    return Effect.try({ try: () => share.open(c.scope, c.source, c.title, c.target, c.key), catch: asCoreError });
  };
  return share;
}
