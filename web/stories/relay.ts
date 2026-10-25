// A chat relayed to a channel (docs/relay.md): the dialog with the connects' channels and groups (some relayed to
// before), a connect whose channels could not be read, a station with no connect. Its calls answer at once and change nothing.
import type { DemoExtension } from "../src/demo/mount.tsx";
import type { RelayConnect } from "../src/api.ts";

/** A bot's picture as Slack gives one (its app's icon). */
const BOT_IMAGE = `data:image/svg+xml,${encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48"><rect width="48" height="48" fill="#d97757"/><path d="M24 10l3 11 11 3-11 3-3 11-3-11-11-3 11-3z" fill="#fff"/></svg>')}`;

const CONNECTS: RelayConnect[] = [
  { id: "cl", kind: "slack", name: "Claude", team: "AFK-surf", botImage: BOT_IMAGE, preferred: true, places: [
    { id: "C1", name: "cue-dev", kind: "channel", used: 1_700_000_300_000 },
    { id: "C2", name: "design", kind: "channel", private: true },
    { id: "C3", name: "stillfail", kind: "channel", used: 1_700_000_100_000 },
    { id: "C4", name: "engineering", kind: "channel" },
    { id: "C5", name: "general", kind: "channel" },
    { id: "C6", name: "ops", kind: "channel" },
    { id: "C7", name: "random", kind: "channel" },
    { id: "C8", name: "releases", kind: "channel" },
    { id: "C9", name: "support", kind: "channel" },
    { id: "C10", name: "infra", kind: "channel" },
  ] },
  { id: "fs", kind: "feishu", name: "Codex 机器人", team: "Cue 团队", places: [
    { id: "oc_1", name: "产品讨论", kind: "topics", used: 1_700_000_200_000 },
    { id: "oc_2", name: "Android 小组", kind: "group" },
  ] },
  { id: "lk", kind: "lark", name: "Codex", team: "Cue Global", places: [], error: "missing_scope: im:chat:readonly" },
];

/** One Slack workspace with two bots, the chat's own (Codex) preferred. */
export const TWO_BOTS: RelayConnect[] = [
  { id: "cl", kind: "slack", name: "claude", team: "AFK AI", botImage: BOT_IMAGE, places: CONNECTS[0]!.places },
  { id: "cx", kind: "slack", name: "codex", team: "AFK AI", preferred: true, places: CONNECTS[0]!.places.slice(0, 5) },
];

/** The dialog's calls, with `connects` as the station's. */
export function relayDemo(connects: RelayConnect[] = CONNECTS): DemoExtension {
  return {
    call: (name) => {
      if (name === "chat.relayPlaces") return { connects };
      if (name === "chat.relay") return { thread: 99, to: "C1/1700.000100", place: "#cue-dev", link: null };
      return undefined;
    },
  };
}

/** A chat whose agent is in #still-fail and a Feishu group (docs/relay.md "抄送"): `on` those ticked to begin with;
 *  `chat.cc` ticks them. `one`: the Slack thread alone. */
export function ccDemo(on: number[] = [], one = false): DemoExtension {
  const ticked = new Set(on);
  const to = [{ thread: 21, place: "#still-fail", via: "slack" }, { thread: 22, place: "产品讨论", via: "feishu" }].slice(0, one ? 1 : 2);
  return {
    then: (topic, value) => (topic.topic === "chat" && value && typeof value === "object" ? { ...value, cc: to.map((o) => ({ ...o, on: ticked.has(o.thread) })) } : undefined),
    call: (name, params) => {
      if (name !== "chat.cc") return undefined;
      if (params.on === true) ticked.add(params.to as number);
      else ticked.delete(params.to as number);
      return null;
    },
  };
}
