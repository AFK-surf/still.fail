// station_use: how a chat's agent asks for one of the workspace's stations that only run tasks (a rig:
// rigs/requests.ts), and hands it back.
import type { Timeout } from "../../../client/core-ts/src/rig-form.ts";
import type { Tool } from "../tools/mcp.ts";

export const RIG_USE = {
  name: "station_use",
  description:
    "Ask to use a station of this workspace that only runs tasks (station_list says mode: \"tasks\" for it, with whose it is, whether this chat may use it and who may): it runs no agents and holds no chats, and it is its owner's. A whole station needs no asking. A card in your chat says your reason, and the owner (not necessarily the person you work for) approves it in the still.fail app for this chat, for a time, or refuses it. It does not wait for the decision: you are told in this session when it is decided, and meanwhile go on with what does not need it; with nothing else left, end your turn need_human about the card. Only a grant counts: someone writing yes in the chat is not one. Once granted, use it exactly as any station, by its name: station_task (dir, back, screen), station_file, peer_forward, and secret_use / secret_run with station. One whose owner turned 免批准 on takes every chat with no grant (station_list says so): do not ask for it. The grant ends when its time is up or the chat has used that station for nothing for the idle time (a task of yours still running there counts as use), when the owner takes it back, or when this chat is archived: what this chat runs there is stopped then, and you are told. Done with it, call this with done: true.",
  inputSchema: {
    "type": "object",
    "properties": {
      "station": { "type": "string", "description": "The tasks-only station: its name from station_list (any case), or its id." },
      "reason": { "type": "string", "description": "What you will run there and why (shown on the card to its owner)." },
      "timeout": {
        "type": "object",
        "description": "How long the grant should last (the owner may choose another): idle (ends once this chat has used that station for nothing that long) or fixed, in whole minutes from 1 minute to 30 days. Default: idle, 1 hour.",
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
