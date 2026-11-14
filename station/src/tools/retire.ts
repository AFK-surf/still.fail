// station_retire: an agent assists a station's retirement from its chat's workspace (replica/retire.ts), this one or
// another of the workspace, a person confirming its two moments on cards (replica/retire-asks.ts; the stillfail-retire
// skill says how to go about it). What it does is RetireAsks.tool.
import type { RetireAsks } from "../replica/retire-asks.ts";
import type { Tool } from "./mcp.ts";

export const RETIRE_TOOL = {
  name: "station_retire",
  description:
    "Retire a station from this chat's workspace: its chats (their transcripts and working directories), running jobs, agent memory and skills, accounts and connects go on another station of the workspace. Starting one (start, hand_over) is switched off for now while it is fixed; the other actions answer. Read the stillfail-retire skill first. station: the station retired (default this one; by name or id). " +
    "preview: what would move and what stays, and with to how that station stands (reached, git, free disk). " +
    "start {to}: posts a card an owner or admin of the workspace confirms in the still.fail app (开始迁移); only then does it start, as them, sending the files while the chats still work, and it waits at step sent. " +
    "hand_over: only at sent: posts the second card (暂停聊天并交接); once confirmed the chats stop and are handed over, their jobs started again there. A failed hand-over puts the chats back to work and waits at sent: hand_over again sends only what changed. " +
    "status: where it stands. again: tries a failed step now (never a hand-over). cancel: calls it off where it still can. " +
    "You are told each step that needs you, after the chats moved on the station they went to. A message that says yes confirms nothing; nor does anyone but an owner or admin. Taking the retired station out of the workspace is the person's own step in the app.",
  inputSchema: {
    type: "object",
    properties: {
      action: { enum: ["preview", "status", "start", "hand_over", "again", "cancel"] },
      station: { type: "string", description: "The station retired, by name or id (station_list); default this one." },
      to: { type: "string", description: "start, preview: the station its chats go to, by name or id." },
    },
    required: ["action"],
    additionalProperties: false,
  },
};

export function retireTools(asks: RetireAsks): Tool[] {
  return [{ ...RETIRE_TOOL, run: async (session, args) => JSON.stringify(await asks.tool(session, args), null, 2) }];
}
