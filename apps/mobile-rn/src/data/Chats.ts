// What the app makes of the core's marks (data/Chats.kt). Every shape the core sends is in web/src/core/shapes.ts,
// generated from client/core-ts/src/shapes/schema.ts (scripts/shapes.sh): nothing of it is written here.
import type { Badge, ChatAgent, RowAgent, Session } from "../../../../web/src/core/shapes.ts";

/** Where an agent stands, as its badge shows it: solid orange block, hollow ring at work, red failed; done has none. */
export enum ChatState { Block = "Block", Running = "Running", Done = "Done", Failed = "Failed" }

/** A badge the core names (block | run | failed) as the app's state. */
export function badgeState(badge: Badge | null | undefined): ChatState | null {
  switch (badge) {
    case "block": return ChatState.Block;
    case "run": return ChatState.Running;
    case "failed": return ChatState.Failed;
    default: return null;
  }
}

/** Session.state, RowAgent.state (their `mark`) and ChatAgent.state (its `badge`): done when none. */
export function sessionState(s: Session): ChatState { return badgeState(s.mark) ?? ChatState.Done; }
export function rowAgentState(a: RowAgent): ChatState { return badgeState(a.mark) ?? ChatState.Done; }
export function chatAgentState(a: ChatAgent): ChatState { return badgeState(a.badge) ?? ChatState.Done; }
