// A chat made public (docs/public-share.md): the snapshots its station keeps of it, as its "…" lists them
// (`ChatView.publish`, each with its link put together here), and the calls that make and revoke one:
// `chat.publishPreview` (what a snapshot would hold now, nothing kept), `chat.publish` (kept, with its link) and
// `chat.unpublish`. Only people publish; the station keeps the snapshot and its key. Done, the thread as held says so
// at once (as xshare.ts's). A revoke shows at once: what is being revoked is kept in the chat's workspace
// (workspace.ts `part`) and left out of the list until its station answers (rule 4).
import { Effect } from "effect";
import type { Inner } from "../core.ts";
import { handlers } from "../core/execute.ts";
import type { Call } from "../core/calls.ts";
import { CoreError } from "../error.ts";
import * as format from "../format.ts";
import { t } from "../i18n.ts";
import { markdown } from "../markdown.ts";
import { encode } from "../ops.ts";
import { placeFiles } from "../placed.ts";
import * as present from "../present.ts";
import { StationAddr, stationId } from "../station/addr.ts";
import { arr as arrU, base64url, get as getU, isObject } from "../util.ts";
import { ofAddress } from "../workspace.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);
const str = (v: unknown): string | null => (typeof v === "string" ? v : null);
const num = (v: unknown): number => (typeof v === "number" && Number.isFinite(v) ? v : 0);

/// Where a snapshot's link opens: still.fail's viewer, which reads it from the station itself, never through the cloud.
export const SHARE_ORIGIN = "https://share.still.fail";

const PART = "publish";

/// The snapshots of a workspace's chats being revoked here, not answered yet (`station\tid`).
function revokingOf(inner: Inner, station: string): Set<string> {
  return inner.workspaces.ofStation(station).part(PART, () => new Set<string>());
}

const revokingKey = (station: string, id: string) => `${station}\t${id}`;

/// Whether a snapshot is being revoked here.
export function revoking(inner: Inner, station: string, id: string): boolean {
  return inner.workspaces.get(ofAddress(station))?.own.has(PART) === true && revokingOf(inner, station).has(revokingKey(station, id));
}

/// A station's iroh key as a link has it: its 32 bytes in base64url (43 characters), from the hex of its id (anything
/// else as it is).
export function linkStation(key: string): string {
  if (!/^[0-9a-f]{64}$/i.test(key)) return key;
  const bytes = new Uint8Array(32);
  for (let i = 0; i < 32; i++) bytes[i] = parseInt(key.slice(i * 2, i * 2 + 2), 16);
  return base64url(bytes);
}

/// A snapshot's link, by the id of the station that keeps it: everything after `#`, so neither still.fail nor its logs
/// ever see what it opens.
export function linkOf(station: string, id: string, key: string): string {
  return `${SHARE_ORIGIN}/#${linkStation(station)}.${id}.${key}`;
}

/// The snapshots a thread says its station keeps of it (none from a station before publishing), newest first.
function heldOf(thread: J): J[] {
  return arr(get(thread, "published")).filter((p) => isObject(p) && typeof p.id === "string" && typeof p.key === "string");
}

/// A snapshot as a chat's "…" lists it: its link (by its station's address: its id is its key), when and by whom, and
/// whether the viewer may revoke it.
function linkShown(p: J, station: string, may: (by: string | null) => boolean): J {
  const by = str(p.by);
  return {
    id: p.id,
    link: linkOf(stationId(station), p.id, p.key),
    createdAt: num(p.at),
    byName: str(p.byName) ?? (by !== null ? by.split("@")[0] : ""),
    mayRevoke: may(by),
  };
}

/// What a chat's "…" shows of its public snapshots (`ChatView.publish`), or null while it has no chat. `me`: the
/// viewer's email; `role`: theirs in the chat's workspace. A read-only member (`viewer`) publishes nothing; a snapshot
/// is revoked by whoever published it, or an owner or admin.
export function shown(env: { me: string | null; role: string | null; revoking: (id: string) => boolean }, station: string, thread: J): J | null {
  if (!isObject(thread)) return null;
  const manager = env.role === "owner" || env.role === "admin";
  const mine = (by: string | null) => by !== null && env.me !== null && by.toLowerCase() === env.me.toLowerCase();
  const links = heldOf(thread)
    .filter((p) => !env.revoking(p.id))
    .sort((a, b) => num(b.at) - num(a.at))
    .map((p) => linkShown(p, station, (by) => manager || mine(by)));
  return { may: env.role !== "viewer", links };
}

/// The names the snapshot gives people (`{email: name}`), from the chat's workspace's members: none while not read.
function namesOf(inner: Inner, station: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const m of arr(get(inner.data.shared({ topic: "workspace", workspace: ofAddress(station) }), "members"))) {
    const email = str(get(m, "email"));
    const name = str(get(m, "name"));
    if (email !== null && name !== null && name.trim() !== "") out[email] = name;
  }
  return out;
}

/// A member's picture by their address, as the workspace has it.
function pictureOf(members: J[], email: string | null): string | null {
  if (email === null) return null;
  const member = members.find((m) => typeof get(m, "email") === "string" && (get(m, "email") as string).toLowerCase() === email.toLowerCase());
  const picture = str(get(member, "picture"));
  return picture !== null && picture !== "" ? picture : null;
}

/// What a station answers a preview with (`POST /threads/:thread/publish/preview`), for the panel that publishes it:
/// its messages, each with how many things in it were hidden and its attachments (as the chat has them, to show alike),
/// and all its attachments together.
export function previewShown(answer: J, clock: present.Clock, members: J[] = []): J {
  const hiddenAt = new Map<number, number>();
  for (const r of arr(get(answer, "redacted"))) hiddenAt.set(num(get(r, "n")), (hiddenAt.get(num(get(r, "n"))) ?? 0) + num(get(r, "count")));
  const files = arr(get(answer, "files")).map((f) => {
    const size = num(f.size);
    const name = str(f.name) ?? "";
    // As the chat's messages have their attachments (a station from before `path` and `owner` gives none: a card only).
    const file: J = { name, path: str(f.path) ?? "", size };
    for (const key of ["width", "height"] as const) if (typeof f[key] === "number") file[key] = f[key];
    if (typeof f.thumbhash === "string") file.thumbhash = f.thumbhash;
    if (typeof f.owner === "string") file.owner = f.owner;
    return { k: str(f.k) ?? "", name, size, sizeText: format.bytes(size), type: str(f.type) ?? "", n: num(f.n), file };
  });
  const messages = arr(get(answer, "entries")).map((e) => {
    const hidden = hiddenAt.get(num(e.n)) ?? 0;
    const agent = e.authorKind === "agent";
    const text = str(e.text) ?? "";
    const own = arr(e.files).flatMap((k) => files.filter((f) => f.k === k));
    // An agent's words are Markdown, read here as the chat's are, with the files they place (placed.ts).
    const placed = agent ? [...placeFiles(text, own).placed.keys()] : [];
    return {
      n: num(e.n),
      author: str(e.author) ?? "",
      agent,
      // Who said it drawn as the chat draws them: an agent's maker's mark, a person's picture.
      ...(present.maker(str(e.model)) ? { maker: present.maker(str(e.model)) } : {}),
      ...(str(e.runtime) !== null ? { runtime: str(e.runtime) } : {}),
      ...(pictureOf(members, str(e.person)) !== null ? { picture: pictureOf(members, str(e.person)) } : {}),
      text,
      ...(agent ? { md: markdown(text) } : {}),
      files: own,
      ...(placed.length > 0 ? { placed } : {}),
      hidden,
      ...(hidden > 0 ? { hiddenText: t("core-views.publish.hidden", { n: hidden }) } : {}),
      createdAt: num(e.at),
    };
  });
  const hidden = [...hiddenAt.values()].reduce((a, b) => a + b, 0);
  return present.times({
    upto: num(get(answer, "upto")),
    title: str(get(answer, "title")) ?? "",
    messages,
    files,
    hidden,
    ...(hidden > 0 ? { hiddenText: t("core-views.publish.hiddenAll", { n: hidden }) } : {}),
  }, clock);
}

type Of<K extends Call["kind"]> = Extract<Call, { kind: K }>;

/// A station from before publishing has none of its routes (an unknown chat is its own 404, said as the station says it).
const oldStation = (e: CoreError) => (e.status === 404 && e.message.startsWith("no route ") ? new CoreError("http_404", t("core-misc.publish.oldStation"), 404) : e);

/// `chat.publishPreview`: what a snapshot of the chat would hold now. `chat.publish`: one kept, up to the message the
/// preview ended at, with the attachments ticked; its link answered and its thread shows it at once.
/// `chat.unpublish`: one revoked, gone from the list at once.
export function install(inner: Inner): void {
  const clock = (): present.Clock => {
    const now = inner.host.nowMs();
    return { now, offsetMin: inner.host.utcOffsetMin(now) };
  };
  const invalidate = (station: string) => inner.store.invalidateAll((topic) => topic.topic === "chat" && topic.station === station);
  /// Puts what a thread's snapshots are now into it as held: the chat shows it without reading it again.
  const putHeld = (station: string, thread: number, change: (was: J[]) => J[]) => {
    const now = inner.data.thread(station, thread);
    if (!isObject(now)) return;
    const next = change(heldOf(now));
    const { published: _, ...rest } = now as J;
    inner.stations.putThread(station, next.length > 0 ? { ...rest, published: next } : rest);
  };
  const addr = (station: string) => Effect.try({ try: () => StationAddr.parse(station), catch: (e) => e as CoreError });

  handlers.chatPublishPreview = (_inner, call, _progress, _at, ctx) => {
    const c = call as Of<"chatPublishPreview">;
    return Effect.gen(function* () {
      const at = yield* addr(c.station);
      const answer = yield* Effect.mapError(
        inner.stations.requests.call(at, "POST", `/threads/${c.thread}/publish/preview`, { names: namesOf(inner, c.station) }, { ctx }),
        oldStation,
      );
      return previewShown(answer, clock(), arr(get(inner.data.shared({ topic: "workspace", workspace: ofAddress(c.station) }), "members")));
    });
  };
  handlers.chatPublish = (_inner, call, _progress, _at, ctx) => {
    const c = call as Of<"chatPublish">;
    return Effect.gen(function* () {
      const at = yield* addr(c.station);
      const answer = yield* Effect.mapError(
        inner.stations.requests.call(at, "POST", `/threads/${c.thread}/publish`, { upto: c.upto, files: c.files, names: namesOf(inner, c.station) }, { ctx }),
        oldStation,
      );
      const made = get(answer, "published");
      if (!isObject(made) || typeof made.id !== "string" || typeof made.key !== "string") return yield* Effect.fail(new CoreError("bad_reply", t("core-misc.publish.badReply")));
      putHeld(c.station, c.thread, (was) => [made, ...was.filter((p) => p.id !== made.id)]);
      invalidate(c.station);
      return present.times(linkShown(made, c.station, () => true), clock());
    });
  };
  handlers.chatUnpublish = (_inner, call, _progress, _at, ctx) => {
    const c = call as Of<"chatUnpublish">;
    const key = revokingKey(c.station, c.id);
    return Effect.gen(function* () {
      const at = yield* addr(c.station);
      revokingOf(inner, c.station).add(key);
      invalidate(c.station);
      const done = yield* Effect.result(inner.stations.requests.call(at, "DELETE", `/published/${encode(c.id)}`, null, { ctx }));
      revokingOf(inner, c.station).delete(key);
      // Gone already (taken down from elsewhere): gone all the same. Not told its thread, the
      // station's change to it says so.
      if ((done._tag === "Success" || done.failure.status === 404) && c.thread !== null) putHeld(c.station, c.thread, (was) => was.filter((p) => p.id !== c.id));
      invalidate(c.station);
      if (done._tag === "Failure" && done.failure.status !== 404) return yield* Effect.fail(done.failure);
      return { ok: true };
    });
  };
}

