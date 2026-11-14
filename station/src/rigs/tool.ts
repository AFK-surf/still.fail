// station_use: how a chat's agent asks for one of the workspace's stations that only run tasks (a rig:
// rigs/requests.ts), and hands it back.
import type { Timeout } from "../../../client/core-ts/src/rig-form.ts";
import type { Tool } from "../tools/mcp.ts";

export const RIG_USE = {
  name: "station_use",
  description:
    "Ask to use a station of this workspace that only runs tasks (station_list says mode: \"tasks\" for it, with whose it is and whether this chat may use it). A whole station needs no asking, nor one whose owner turned 免批准 on. A card in your chat says your reason, and its owner (not necessarily the person you work for) approves it for this chat, for a time, or refuses it. It does not wait: you are told in this session when it is decided, and only a grant counts, not a yes written in the chat. Once granted, use it as any station, by its name, until the grant ends: what this chat runs there is stopped then. Skill stillfail-jobs (Another station) says more.",
  inputSchema: {
    "type": "object",
    "properties": {
      "station": { "type": "string", "description": "The tasks-only station: its name from station_list (any case), or its id." },
      "reason": { "type": "string", "description": "What you will run there and why (shown on the card to its owner)." },
      "timeout": {
        "type": "object",
        "description": "How long the grant should last (the owner may choose another): idle (ends once this chat has not used that station that long) or fixed, in whole minutes from 1 minute to 30 days. Default: idle, 1 hour.",
        "properties": { "kind": { "enum": ["idle", "fixed"] }, "seconds": { "type": "integer" } },
        "required": ["kind", "seconds"],
        "additionalProperties": false
      },
      "done": { "type": "boolean", "description": "Hand it back: end this chat's grant of it (or its request still pending). With no station named, every one this chat holds." }
    },
    "additionalProperties": false
  },
};

export type RigUse = {
  /// What the agent is told of its request (asked now, or already open).
  ask(session: string, rig: string, reason: string, timeout: Timeout | undefined, signal?: AbortSignal): Promise<string>;
  done(session: string, rig: string): string;
};

export function rigTools(use: RigUse): Tool[] {
  return [{
    ...RIG_USE,
    run: async (session, args, signal) => {
      const rig = typeof args.station === "string" ? args.station.trim() : "";
      if (args.done === true) return use.done(session, rig);
      if (rig === "") throw new Error("station is required (its name from station_list)");
      const t = args.timeout as { kind?: unknown; seconds?: unknown } | undefined;
      const timeout = t !== undefined && t !== null && typeof t === "object" ? ({ kind: t.kind, seconds: t.seconds } as Timeout) : undefined;
      return use.ask(session, rig, typeof args.reason === "string" ? args.reason : "", timeout, signal);
    },
  }];
}
