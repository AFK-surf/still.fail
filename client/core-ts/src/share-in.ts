// What another app shares into still.fail (a link from a browser or a video app, some text): the chat it goes to, and
// sending it there (docs/share-in.md). The `shareIn` view lists the chats it can go to (the workspace's own chats on
// still.fail's page, as the sidebar has them, newest first), the one it went to last time from the same site first,
// and which is picked; `shareIn.pick` picks one (or a new chat on a station), `shareIn.send` sends it there with what
// the person added. Sending does not wait on the station: the message is in that chat's outbox at once, and goes on
// from there as any message written in the chat does (sent again after a restart).
import { Effect } from "effect";
import type { Inner, Progress } from "./core.ts";
import type { Call } from "./core/calls.ts";
import { handlers } from "./core/execute.ts";
import type { Owner } from "./core/routing.ts";
import { CoreError } from "./error.ts";
import { t } from "./i18n.ts";
import { parseTopic, topicKey, type ClientId, type RequestId, type Topic } from "./protocol.ts";
import * as refs from "./refs.ts";
import type { Value, Watch } from "./store.ts";
import type { SpanContext } from "./trace.ts";
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

/// The message a shared thing goes as: what the person added first, then the title the app gave (when the shared text
/// does not have it already), then what was shared.
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
  /// What is picked, by the sheet's topic without its query (scope and what is shared): dropped as it closes.
  readonly #picked = new Map<string, Target>();

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
    if (![...this.#watches.keys()].some((k) => this.#sheet(JSON.parse(k)) === this.#sheet(topic))) this.#picked.delete(this.#sheet(topic));
  }

  #sheet(topic: Topic): string {
    return JSON.stringify([topic.scope, topic.source]);
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

  /// Where it goes unless the person picks another: what was picked, else the chat a thing from the same site went to
  /// last, else the latest chat, else a new chat on the station new chats last started on.
  #target(scope: string, source: string, rows: J[], stations: J[]): Target | null {
    const picked = this.#picked.get(JSON.stringify([scope, source]));
    if (picked !== undefined) return picked;
    const k = keptRow(rows, kept(this.#inner, scope, siteOf(source)));
    if (k !== undefined) return { station: k.station, id: k.id };
    if (rows.length > 0) return { station: rows[0].station, id: rows[0].id };
    const last = this.#inner.choose.keptStation(scope);
    const on = stations.find((s) => s.station === `${scope}/${last}`) ?? stations[0];
    return on ? { station: on.station } : null;
  }

  compute(topic: Topic): Value | undefined {
    const scope = topic.scope as string;
    const source = String(topic.source ?? "");
    const query = String(topic.query ?? "");
    const all = this.#rows(scope);
    const stations = this.#stations(scope) ?? [];
    const site = siteOf(source);
    const view: J = { site, items: [], stations, loading: all === null };
    if (all === null) return { ok: view };
    const k = keptRow(all, kept(this.#inner, scope, site));
    const found = query.trim() === "" ? all : open(arr(refs.search({ days: [{ items: all }] }, query, null, null, undefined).items));
    const rest = found.filter((r) => r !== k);
    view.items = (k !== undefined && found.includes(k) ? [k, ...rest] : rest).slice(0, LISTED);
    if (k !== undefined) view.kept = { station: k.station, id: k.id, text: site !== null ? t("core-logic.shareIn.kept", { site }) : t("core-logic.shareIn.kept_text") };
    const target = this.#target(scope, source, all, stations);
    if (target !== null) view.picked = target.id !== undefined ? { station: target.station, id: target.id } : { station: target.station };
    // The one picked, when what is typed leaves it out of the list: shown all the same.
    if (target?.id !== undefined && !view.items.some((r: J) => r.station === target.station && r.id === target.id)) {
      const row = all.find((r) => r.station === target.station && r.id === target.id);
      if (row !== undefined && query.trim() === "") view.items = [row, ...view.items].slice(0, LISTED);
    }
    if (stations.length === 0 && all.length === 0) view.note = t("core-logic.shareIn.none");
    return { ok: view };
  }

  /// `shareIn.pick`: where what is shared goes.
  pick(scope: string, source: string, target: Target): void {
    this.#picked.set(JSON.stringify([scope, source]), target);
    this.#inner.store.invalidateAll((x) => x.topic === "shareIn" && x.scope === scope && x.source === source);
  }

  /// `shareIn.send`: what is shared, with what the person added, into the chat picked (made first for a new one). The
  /// answer says where it went (`title` for the page's note) once it is in that chat's outbox.
  send(scope: string, source: string, title: string | null, note: string | null, client: string | null, progress: Progress, at: [ClientId, RequestId], ctx: SpanContext): Effect.Effect<J, CoreError> {
    const inner = this.#inner;
    return Effect.gen({ self: this }, function* () {
      if (source.trim() === "") return yield* Effect.fail(CoreError.invalid(t("core-logic.shareIn.error.empty")));
      const rows = this.#rows(scope) ?? [];
      const target = this.#target(scope, source, rows, this.#stations(scope) ?? []);
      if (target === null) return yield* Effect.fail(CoreError.invalid(t("core-logic.shareIn.none")));
      const text = messageOf(source, title, note);
      const site = siteOf(source);
      const remember = (k: J) => inner.data.put(TABLE, `ws:${scope}:shareIn:${site ?? ""}`, k, false);
      if (target.id === undefined) {
        const made = yield* handlers.choose!(inner, { kind: "choose", name: "newChat.create", params: { station: target.station } }, progress, at, ctx);
        const key = String(get(made, "key") ?? "");
        yield* handlers.chatSendTo!(inner, { kind: "chatSendTo", station: target.station, session: key, text, attachments: [], quotes: [], client }, progress, at, ctx);
        remember({ station: target.station, clientKey: key });
        this.#picked.delete(JSON.stringify([scope, source]));
        return { station: target.station, session: key, title: t("core-logic.shareIn.new_chat") };
      }
      const row = rows.find((r) => r.station === target.station && r.id === target.id);
      if (row === undefined) return yield* Effect.fail(CoreError.invalid(t("core-views.error.no_chat")));
      // In the outbox now; it goes on from there (and after a restart) while this answers.
      const call: Call = typeof row.thread === "number"
        ? { kind: "chatSend", station: target.station, thread: row.thread, text, attachments: [], quotes: [], client }
        : { kind: "chatSendTo", station: target.station, session: row.session, text, attachments: [], quotes: [], client };
      inner.runner.fork(Effect.ignore(handlers[call.kind]!(inner, call, progress, at, ctx)));
      remember({ station: target.station, id: row.id });
      this.#picked.delete(JSON.stringify([scope, source]));
      return { station: target.station, session: row.session, ...(typeof row.thread === "number" ? { thread: row.thread } : {}), title: row.title };
    });
  }
}

export function install(inner: Inner): ShareIn {
  const share = new ShareIn(inner);
  inner.router.owners.push(share);
  handlers.shareIn = (_inner, call, progress, at, ctx) => {
    const c = call as Extract<Call, { kind: "shareIn" }>;
    if (c.target !== null) {
      const target = c.target;
      return Effect.sync(() => (share.pick(c.scope, c.source, target), null));
    }
    return share.send(c.scope, c.source, c.title, c.note, c.client, progress, at, ctx);
  };
  return share;
}
