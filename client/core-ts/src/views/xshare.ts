// A chat shared with the viewer's other workspaces (docs/chat-share.md): what its "…" shows of it, and `chat.xshare`,
// which changes it. The chat's station keeps who it is shared with (`PUT /sessions/:key/xshare`); each workspace newly
// given it is told, through one of its own stations, to trust that station (`PUT /xshare/hosts`). Each workspace's part
// stays its own: what was asked here and not answered yet is kept in the chat's workspace (workspace.ts `part`), and
// shown at once over what its station holds (rule 4).
import { Effect } from "effect";
import type { Inner } from "../core.ts";
import { handlers } from "../core/execute.ts";
import type { Call } from "../core/calls.ts";
import { CoreError } from "../error.ts";
import { t } from "../i18n.ts";
import { encode } from "../ops.ts";
import { StationAddr } from "../station/addr.ts";
import { arr as arrU, get as getU, isObject } from "../util.ts";
import { ofAddress } from "../workspace.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);
const str = (v: unknown): string | null => (typeof v === "string" ? v : null);

/// One of the workspaces the signed-in accounts are in, as their `/v1/me` says: its name, the account's role there.
export type Place = { id: string; name: string; role: string | null };
/// What `chat.xshare` asked: the workspaces to share with, and whether their agents may send.
export type Asked = { to: string[]; write: boolean };

const PART = "xshare";

/// What was asked of a workspace's chats and not answered yet, by station and session.
function askedOf(inner: Inner, station: string): Map<string, Asked> {
  return inner.workspaces.ofStation(station).part(PART, () => new Map<string, Asked>());
}

const askedKey = (station: string, session: string) => `${station}\t${session}`;

/// A chat's sharing asked here and not answered yet.
export function asked(inner: Inner, station: string, session: string): Asked | undefined {
  return inner.workspaces.get(ofAddress(station))?.own.has(PART) ? askedOf(inner, station).get(askedKey(station, session)) : undefined;
}

/// Every workspace the signed-in accounts are in (each once, as the account that reaches it has it).
export function places(inner: Inner): Place[] {
  const out: Place[] = [];
  for (const account of inner.accounts.list()) {
    for (const w of arr(get(inner.data.record("me", account.sub), "workspaces"))) {
      const id = str(get(w, "id"));
      if (id === null || out.some((p) => p.id === id) || inner.workspaces.owner(id) !== account.sub) continue;
      out.push({ id, name: str(get(w, "name")) ?? id, role: str(get(w, "role")) });
    }
  }
  return out;
}

/// The workspaces a chat's thread says it is shared with (none from a station before sharing), and whether to write.
function held(thread: J): { to: { workspace: string; name: string }[]; write: boolean } {
  const x = get(thread, "xshare");
  if (!isObject(x)) return { to: [], write: false };
  const to = arr(x.to).flatMap((w) => {
    const workspace = str(get(w, "workspace"));
    return workspace === null ? [] : [{ workspace, name: str(get(w, "name")) ?? workspace }];
  });
  return { to, write: x.write === true };
}

/// The session a chat's sharing is kept by on its station: its thread's own (`home`), else (a Slack thread) its first.
export function sessionOf(thread: J): string | null {
  return str(get(thread, "home")) ?? str(get(arr(get(thread, "sessions"))[0], "session"));
}

/// What a chat's "…" shows of its sharing (`ChatView.xshare`), or null: no chat or agent yet, or no other workspace.
export function shown(env: { places: Place[]; asked: (session: string) => Asked | undefined; me: string | null }, station: string, thread: J): J | null {
  const session = isObject(thread) ? sessionOf(thread) : null;
  if (!isObject(thread) || session === null) return null;
  const scope = ofAddress(station);
  const others = env.places.filter((p) => p.id !== scope);
  if (others.length === 0) return null;
  const now = held(thread);
  const nameOf = (id: string) => others.find((p) => p.id === id)?.name ?? now.to.find((w) => w.workspace === id)?.name ?? id;
  const asked = env.asked(session);
  const ids = asked ? asked.to : now.to.map((w) => w.workspace);
  const write = asked ? asked.write : now.write;
  const to = ids.map((id) => ({ workspace: id, name: nameOf(id) }));
  const role = env.places.find((p) => p.id === scope)?.role ?? null;
  const starter = env.me !== null && (str(get(get(thread, "creator"), "id")) === env.me || str(thread.createdBy) === env.me);
  const text = to.length === 0
    ? t("core-views.xshare.none")
    : `${to.map((w) => w.name).join(t("core-views.list_separator"))} · ${write ? t("core-views.xshare.write") : t("core-views.xshare.read")}`;
  return {
    session,
    text,
    to,
    write,
    may: starter || role === "owner" || role === "admin",
    places: others.map((p) => ({ workspace: p.id, name: p.name, on: ids.includes(p.id) })),
  };
}

type Of<K extends Call["kind"]> = Extract<Call, { kind: K }>;

/// Whether a failure is the station not being reached (rather than its answer): another of the workspace's is tried.
const unreached = (e: CoreError) => e.status === undefined;

/// `chat.xshare`: shared with the workspaces ticked (with those it is shared with that the viewer is not in, kept), and
/// whether their agents may send. Shown so at once; each workspace newly given it is told to trust the chat's station.
export function install(inner: Inner): void {
  handlers.chatXshare = (_inner, call, _progress, _at, ctx) => {
    const c = call as Of<"chatXshare">;
    const station = c.station;
    const key = askedKey(station, c.session);
    const invalidate = () => inner.store.invalidateAll((topic) => topic.topic === "chat" && topic.station === station);
    return Effect.gen(function* () {
      const addr = yield* Effect.try({ try: () => StationAddr.parse(station), catch: (e) => e as CoreError });
      if (c.workspace !== null && c.workspace !== addr.workspace) return yield* Effect.fail(CoreError.invalid(t("core-misc.xshare.workspace")));
      const all = places(inner);
      const here = all.find((p) => p.id === addr.workspace);
      const thread = c.thread ?? inner.views.boundThread(station, c.session);
      const kept = thread !== null ? inner.data.thread(station, thread) : undefined;
      const before = held(kept);
      // Those it is shared with that the viewer is not in stay: they are not ticked or unticked here.
      const to = [...new Set([...c.to.filter((id) => id !== addr.workspace), ...before.to.map((w) => w.workspace).filter((id) => !all.some((p) => p.id === id))])];
      const targets: { workspace: string; name: string; stations: { id: string; name: string }[] }[] = [];
      for (const id of to) {
        const place = all.find((p) => p.id === id);
        if (!place) {
          // Not the viewer's: as its station has it (its stations are its own to tell).
          const was = before.to.find((w) => w.workspace === id);
          targets.push({ workspace: id, name: was?.name ?? id, stations: [] });
          continue;
        }
        const workspace = inner.data.shared({ topic: "workspace", workspace: id });
        if (!isObject(workspace) || !Array.isArray(workspace.stations)) return yield* Effect.fail(new CoreError("not_ready", t("core-misc.xshare.notRead", { name: place.name })));
        const stations = workspace.stations.flatMap((s) => {
          const sid = str(get(s, "id"));
          return sid === null ? [] : [{ id: sid, name: str(get(s, "name")) ?? sid }];
        });
        targets.push({ workspace: id, name: place.name, stations });
      }
      askedOf(inner, station).set(key, { to, write: c.write });
      invalidate();
      const done = yield* Effect.result(
        Effect.gen(function* () {
          const answer = yield* Effect.mapError(
            inner.stations.requests.call(addr, "PUT", `/sessions/${encode(c.session)}/xshare`, { to: targets, write: c.write }, { ctx }),
            (e) => (e.status === 404 ? new CoreError("http_404", t("core-misc.xshare.oldStation"), 404) : e),
          );
          // What it says now, into its thread as held: the chat shows it without reading it again.
          if (thread !== null) {
            const now = inner.data.thread(station, thread);
            if (isObject(now)) inner.stations.putThread(station, { ...now, xshare: get(answer, "xshare") ?? null });
          }
          // Each workspace newly given it trusts the chat's station, told through one of its own that answers.
          const stationName = inner.views.stationName(station);
          for (const target of targets) {
            if (before.to.some((w) => w.workspace === target.workspace) || target.stations.length === 0) continue;
            const body = { workspace: addr.workspace, name: here?.name ?? addr.workspace, station: addr.station, stationName };
            const order = [...target.stations].sort((a, b) => Number(!inner.stations.reachable(`${target.workspace}/${a.id}`)) - Number(!inner.stations.reachable(`${target.workspace}/${b.id}`)));
            let told = false;
            for (const s of order) {
              const r = yield* Effect.result(inner.stations.requests.call(new StationAddr(target.workspace, s.id), "PUT", "/xshare/hosts", body, { ctx }));
              if (r._tag === "Success") {
                told = true;
                break;
              }
              if (!unreached(r.failure)) return yield* Effect.fail(r.failure);
            }
            if (!told) return yield* Effect.fail(new CoreError("unreached", t("core-misc.xshare.noStation", { name: target.name })));
          }
          return answer;
        }),
      );
      askedOf(inner, station).delete(key);
      invalidate();
      if (done._tag === "Failure") return yield* Effect.fail(done.failure);
      return done.success;
    });
  };
}
