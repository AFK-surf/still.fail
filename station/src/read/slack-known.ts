// What Slack calls people and channels, as the readers know it: the station's names book (<data>/slack-names.json,
// src/connects/names.ts, kept by the connects' connections) and the connects' Slack workspaces (config.json), each read
// again when its file changed. A name not in the book is not known yet: the connection looks it up when it hears of
// the person or channel, and the pages are told to read again then.
import { readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { NAMES_FILE, channelKey, personKey } from "../connects/keys.ts";
import type { Json, Store } from "./store.ts";

type Cached<T> = { stamp: string; value: T };
const cache = new Map<string, Cached<unknown>>();

/// A JSON file of the data directory, read again when it changed; `empty` when it is not there or does not read.
function readJson<T>(path: string, empty: T, shape: (v: Json) => T): T {
  let stamp = "none";
  try {
    const st = statSync(path);
    stamp = `${st.size}:${st.mtimeMs}:${st.ino}`;
  } catch {}
  const had = cache.get(path) as Cached<T> | undefined;
  if (had && had.stamp === stamp) return had.value;
  let value = empty;
  if (stamp !== "none") {
    try {
      value = shape(JSON.parse(readFileSync(path, "utf8")));
    } catch {}
  }
  cache.set(path, { stamp, value });
  return value;
}

/// Each connect's Slack workspace (`slack.team`), as config.json has it; a Feishu or X connect's names are keyed by the
/// connect itself (src/feishu, src/x: its people's ids are its app's or account's own), a Feishu connect's company its
/// team, an X connect's @handle.
type Team = { id: string; name: string; kind: "slack" | "feishu" | "x" };
function teams(s: Store): Map<string, Team> {
  return readJson(join(s.dataDir, "config.json"), new Map(), (raw) => {
    const out = new Map<string, Team>();
    for (const c of Array.isArray(raw?.connects) ? raw.connects : []) {
      if (typeof c?.id !== "string") continue;
      if (c?.kind === "feishu") {
        out.set(c.id, { id: c.id, name: typeof c?.feishu?.tenant?.name === "string" ? c.feishu.tenant.name : "", kind: "feishu" });
        continue;
      }
      if (c?.kind === "x") {
        out.set(c.id, { id: c.id, name: typeof c?.x?.botUsername === "string" && c.x.botUsername !== "" ? `@${c.x.botUsername}` : "", kind: "x" });
        continue;
      }
      const team = c?.slack?.team;
      if (typeof team?.id === "string" && team.id !== "") out.set(c.id, { id: team.id, name: typeof team.name === "string" ? team.name : "", kind: "slack" });
    }
    return out;
  });
}

/// The names book a connect's are in: Slack's (<data>/slack-names.json), Feishu's (feishu-names.json) or X's
/// (x-names.json).
function book(s: Store, kind: Team["kind"] = "slack"): Record<string, Json> {
  return readJson(join(s.dataDir, NAMES_FILE[kind]), {}, (v) => (v !== null && typeof v === "object" && !Array.isArray(v) ? v : {}));
}

/// A connect's Slack workspace's name, when known.
export function teamName(s: Store, connect: string): string | null {
  const name = teams(s).get(connect)?.name ?? "";
  return name === "" ? null : name;
}

/// A Slack person of a connect, as far as known: their name, email and profile picture's address ("" when not known).
export function knownPerson(s: Store, connect: string, user: string): { name: string; email: string; picture: string } | null {
  const t = teams(s).get(connect);
  const person = book(s, t?.kind)[personKey(t?.id ?? "?", user)]?.person;
  const said = (v: Json) => (typeof v === "string" ? v : "");
  return person && typeof person.name === "string" ? { name: person.name, email: said(person.email), picture: said(person.picture) } : null;
}

/// A channel's name of a connect's Slack, as far as known (null for a direct message, or not known yet).
export function knownChannel(s: Store, connect: string | null, channel: string): string | null {
  if (connect === null) return null;
  const t = teams(s).get(connect);
  const name = book(s, t?.kind)[channelKey(t?.id ?? "?", channel)]?.channel;
  return typeof name === "string" ? name : null;
}

/// A creator reference `slack:<connect>:<user>` in words (views.rs `creator`): never waits on Slack — what is known
/// now; null when the reference is not a Slack one.
export function slackCreator(s: Store, reference: string): Json | null {
  if (!reference.startsWith("slack:")) return null;
  const rest = reference.slice("slack:".length);
  const colon = rest.indexOf(":");
  if (colon <= 0 || colon >= rest.length - 1) return null;
  const [connect, user] = [rest.slice(0, colon), rest.slice(colon + 1)];
  const person = knownPerson(s, connect, user);
  const v: Json = { id: reference, name: person?.name ? person.name : user, email: person?.email ? person.email : null, via: teams(s).get(connect)?.kind ?? "slack" };
  if (person?.picture) v.picture = person.picture;
  return v;
}
