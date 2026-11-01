// A station's files as they are browsed on this device (docs/drive.md "Clients"): the core's part of drive-browse.ts's
// `Browsing` — the prefs it keeps and reads, the folders held, the workspace's stations with a drive — and the topics and
// calls it answers. A client draws what it is told and does what a call answers (another folder shown, an entry
// opened…).
//
// Topics:
//   driveBrowse {owner, place, view, station, root, path, write?}
//                                a folder as a place shows it (`owner`: page or tab; `place`: the client's own name for
//                                one place, as two sides of the files' page are two)
//   filesTabs {workspace}        the files' page's tabs; null before any
// Calls (drive-browse.ts CALLS):
//   drive.browse {owner, …, act, …}, drive.arrange {by?, down?, hidden?}, drive.name {name, station?, root?, path?,
//   taken?, beside?, dir?}, drive.moves {items, into, anywhere?}, files.tabs {workspace, act, pane?, id?, side?},
//   files.go {workspace, typed, station, abs}
import { Effect } from "effect";
import type { Inner } from "../core.ts";
import { handlers } from "../core/execute.ts";
import type { Call } from "../core/calls.ts";
import type { Owner } from "../core/routing.ts";
import { driveCount, kindOf } from "../drive.ts";
import { Browsing, type Named } from "../drive-browse.ts";
import { CoreError, asCoreError } from "../error.ts";
import { t } from "../i18n.ts";
import * as prefs from "../prefs.ts";
import type { Topic } from "../protocol.ts";
import { get, isObject } from "../util.ts";

type Of = Extract<Call, { kind: "browse" }>;

const str = (v: unknown): string | null => (typeof v === "string" ? v : null);
const num = (v: unknown): number => (typeof v === "number" && Number.isFinite(v) ? v : 0);
const arr = (v: unknown): unknown[] => (Array.isArray(v) ? v : []);

const mem = new WeakMap<Inner, Browsing>();

/// The device's browsing, as the core holds it.
function browsingOf(inner: Inner): Browsing {
  let b = mem.get(inner);
  if (b) return b;
  b = new Browsing({
    prefs: () => inner.data.shared({ topic: "prefs" }),
    countText: driveCount,
    collate: (names) => inner.host.collate?.(names) ?? null,
    setPrefs: (patch) => prefs.set(inner.data, patch, false, inner.host.nowMs()),
    // A folder's entries as its station said them (held), each with what opens it.
    entries: (station, root, path) => {
      const folder = inner.data.shared({ topic: "drive", station, root, path });
      if (!isObject(folder)) return null;
      return arr(folder.entries).filter(isObject).map((e) => {
        const name = str(e.name) ?? "";
        const dir = e.dir === true;
        return { name, dir, size: num(e.size), mtime: num(e.mtime), kind: dir ? "folder" : kindOf(name) };
      });
    },
    stations: (ws) =>
      arr(get(inner.data.shared({ topic: "workspace", workspace: ws }), "stations")).flatMap((s): Named[] => {
        const id = str(get(s, "id"));
        if (id === null) return [];
        const station = `${ws}/${id}`;
        const drive = get(inner.data.shared({ topic: "overview", station }), "drive");
        return isObject(drive) ? [{ station, name: str(get(s, "name")) ?? id, home: str(drive.home) }] : [];
      }),
    now: () => inner.host.nowMs(),
    newId: () => {
      const bytes = new Uint8Array(6);
      inner.host.randomBytes(bytes);
      return [...bytes].map((x) => x.toString(16).padStart(2, "0")).join("");
    },
    invalid: (what) => CoreError.invalid(t("core-misc.params.invalid", { error: what })),
    changed: (pick) => inner.store.invalidateAll((topic) => topic.topic === "driveBrowse" && pick(topic)),
  });
  mem.set(inner, b);
  return b;
}

function owner(inner: Inner): Owner {
  return {
    owns: (topic: Topic) => topic.topic === "driveBrowse" || topic.topic === "filesTabs",
    start: (topic: Topic) => {
      if (topic.topic === "driveBrowse") browsingOf(inner).started(String(topic.place));
    },
    stop: (topic: Topic) => {
      if (topic.topic === "driveBrowse") browsingOf(inner).stopped(String(topic.place));
    },
    compute: (topic: Topic) => ({ ok: topic.topic === "filesTabs" ? browsingOf(inner).tabsView(String(topic.workspace)) : browsingOf(inner).view(topic) }),
  };
}

function run(inner: Inner, c: Of): Effect.Effect<unknown, CoreError> {
  return Effect.try({ try: () => browsingOf(inner).call(c.name, c.params), catch: asCoreError });
}

export function install(inner: Inner): void {
  handlers.browse = (core, call) => run(core, call as Of);
  inner.router.owners.push(owner(inner));
  // A folder read again changes what the places that show it show; the prefs, the order and the tabs.
  inner.data.onChange((topic) => {
    if (topic.topic === "drive") inner.store.invalidateAll((x) => x.topic === "driveBrowse" && x.station === topic.station && x.root === topic.root);
    else if (topic.topic === "prefs" || topic.topic === "*") inner.store.invalidateAll((x) => x.topic === "driveBrowse" || x.topic === "filesTabs");
  });
}
