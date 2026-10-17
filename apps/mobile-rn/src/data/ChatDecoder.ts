// One chat subscription's messages as the page reads them (data/ChatDecoder.kt). The client applies the core's deltas
// keeping unchanged parts the same objects (web/src/core/delta.ts), so there is nothing to decode or share here: what
// is left of the Kotlin's work is having the newest messages' words parsed as they come, for the page to draw at once.
import type { ChatMessage, ChatsView, ChatView } from "../../../../web/src/core/shapes.ts";
import { prepareMarkdown } from "../ui/Markdown";

/** How many of a chat's newest messages have their words parsed as they are decoded. */
const PREPARED = 40;

/** Only the current window is retained, never every chat visited. */
export class ChatDecoder {
  #source: ChatMessage[] | null = null;

  read(value: ChatView): ChatView {
    const incoming = (value as { messages?: unknown } | null)?.messages;
    if (!Array.isArray(incoming)) return value;
    if (incoming !== this.#source) {
      // What the newest of them say, parsed here ahead of the page drawing them (ui/Markdown.tsx).
      for (const m of (incoming as ChatMessage[]).slice(-PREPARED)) if (m.authorKind === "agent") prepareMarkdown(m.text);
      this.#source = incoming as ChatMessage[];
    }
    return value;
  }
}

/**
 * One chat list subscription's rows: a row whose JSON is the instance it was (a keyed delta touches only the rows that
 * changed, and the client keeps the rest) is the same object as before already, so the list redraws only the rows that
 * changed with nothing done here (the Kotlin's decoder keeps that identity through decoding).
 */
export class ChatsDecoder {
  read(value: ChatsView): ChatsView {
    return value;
  }
}
