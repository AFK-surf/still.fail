// A chat relayed to a channel (docs/relay.md): the dialog with the connects' channels and groups (some relayed to
// before), a connect whose channels could not be read, a station with no connect. Its calls answer at once and change nothing.
import type { DemoExtension } from "../src/demo/mount.tsx";
import type { RelayConnect } from "../src/api.ts";

const CONNECTS: RelayConnect[] = [
  { id: "cl", kind: "slack", name: "Claude", team: "AFK-surf", places: [
    { id: "C1", name: "cue-dev", kind: "channel", used: 1_700_000_300_000 },
    { id: "C2", name: "design", kind: "channel", private: true },
    { id: "C3", name: "stillfail", kind: "channel", used: 1_700_000_100_000 },
    { id: "C4", name: "engineering", kind: "channel" },
    { id: "C5", name: "general", kind: "channel" },
    { id: "C6", name: "ops", kind: "channel" },
    { id: "C7", name: "random", kind: "channel" },
    { id: "C8", name: "releases", kind: "channel" },
  ] },
  { id: "fs", kind: "feishu", name: "Codex 机器人", team: "Cue 团队", places: [
    { id: "oc_1", name: "产品讨论", kind: "topics", used: 1_700_000_200_000 },
    { id: "oc_2", name: "Android 小组", kind: "group" },
  ] },
  { id: "lk", kind: "lark", name: "Codex", team: "Cue Global", places: [], error: "missing_scope: im:chat:readonly" },
];

/** One Slack workspace whose only bots run another runtime than the chat's agent: the station offers both (docs/relay.md). */
export const TWO_BOTS: RelayConnect[] = [
  { id: "cl", kind: "slack", name: "claude", team: "AFK AI", places: CONNECTS[0]!.places },
  { id: "cx", kind: "slack", name: "codex", team: "AFK AI", places: CONNECTS[0]!.places.slice(0, 5) },
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
