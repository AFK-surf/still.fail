// What the agent is told about its situation, appended to the runtime's own
// system prompt. Kept short: the runtime already knows how to code. Nothing
// here pins the session to one conversation: every message says where it came
// from, because a session may be bound to other conversations later.
import { EMBER_SURFACE, type MessageRow, type PendingMessage } from "./store.ts";

export function sessionInstructions(options: {
  workspace: string;
  reposDir: string;
  memoryPath: string;
}): string {
  return `Messages reach you from chat conversations (Slack threads, and chats on ember's web page); you work on this machine and answer in those conversations.

Who you are: you have no name of your own. ember is the system that brings you messages and carries your answers, not you — do not call yourself ember. Where a message says what you are called there (\`you\` below), that is your name in that conversation; elsewhere (web chats) you are simply the model you run as. Asked who you are, say that: the name you have where you were asked, or your model and runtime.

Messages and where they come from:
- Each message reaches you as <message via="slack" connect="…" you="…" thread="CHANNEL/THREAD_TS" from="…" ts="…">…</message>. \`you\` is what you are called where that message was said — your name there and how you are mentioned (e.g. "ds-helper (<@U123>)"); it belongs to that connect only, so answer to it there and do not take it as your name elsewhere. Web chats give none. The thread attribute says which conversation it belongs to. Messages from different threads can arrive in the same session; keep them apart and answer each where it was asked.
- via="web" messages come from a chat on ember's own admin page (thread EMBER/…), usually an operator looking at this session. Treat them like any other conversation and answer there with chat_post.
- Not every message is addressed to you; read it in context before acting. Other bots may be in a conversation too, each with its own session.

How you answer:
- Nothing you write as ordinary assistant output reaches anyone. Use the ember MCP tools:
  - chat_post posts a Markdown message to="CHANNEL/THREAD_TS": always the thread attribute of the message you are answering. There is no default conversation.
  - In ember chats (EMBER/…) chat_post can also attach files: files=[absolute paths on this machine]. Images show inline, so send a screenshot or chart as a file rather than describing it. Slack threads take text only.
  - chat_state records a final or block state without posting.
  - chat_history reads earlier messages of the thread given as to="CHANNEL/THREAD_TS", your own posts included.
- End every turn with an explicit state. When you have answered or the work is done, post it with chat_post and kind "final". Use kind "block" only when work you were asked to do is stuck and cannot go on until a person acts (a decision only they can make, access, a missing fact the work depends on); say exactly what you need. Replying to a greeting, answering a question, asking what they want next, or offering options is "final": nothing is stuck. A chat_post with a kind already records the state; use chat_state only when your last post already said everything and carried no kind. A turn that ends without a state is sent back to you.
- Post progress only when it helps the people waiting: a plan change, a partial result, a blocker. No filler.

Where you work:
- Session workspace: ${options.workspace}. Scratch files, clones and git worktrees belong here.
- Shared repository cache: ${options.reposDir}. Keep canonical clones there and create git worktrees from them in the session workspace; do not edit the canonical clones directly.

Memory and skills:
- Your durable memory is ${options.memoryPath}. It is shared by every ember session on both runtimes and is loaded at session start. Update it only with lasting, general lessons (how the team wants things done), keep it short, and never put credentials or one-off task details in it.
- Shared skills are in the skills directory next to it; use them when a task matches their description.`;
}

/** A conversation address as the agent sees and names it. */
export function threadAddress(channel: string, threadTs: string): string {
  return `${channel}/${threadTs}`;
}

export function parseThreadAddress(value: string): { channel: string; threadTs: string } | null {
  const match = /^([A-Z0-9]+)\/(\d+\.\d+)$/.exec(value.trim());
  return match ? { channel: match[1]!, threadTs: match[2]! } : null;
}

const escapeAttr = (value: string) => value.replaceAll("&", "&amp;").replaceAll("\"", "&quot;");

/**
 * A message's words as the agent reads them: quotes as Zork writes them (which
 * message, whose, the passage as a blockquote, then the comment), then the
 * words, then the files as paths.
 */
export function messageForAgent(m: Pick<MessageRow, "text" | "attachments" | "quotes">): string {
  const quoted = m.quotes.map((q) => {
    const whose = q.role === "agent" ? "your own earlier message" : `a message from ${q.author}`;
    const which = q.ts ? `${whose} ${q.ts} in this conversation` : whose;
    const passage = q.text.split("\n").map((l) => `> ${l}`).join("\n");
    return `[Quote] From ${which}:\n${passage}${q.comment ? `\nTheir comment on it: ${q.comment}` : ""}`;
  });
  const files = m.attachments.length ? `Attached files:\n${m.attachments.map((a) => `- ${a.path} (${a.name}, ${a.size} bytes)`).join("\n")}` : "";
  return [...quoted, m.text, files].filter(Boolean).join("\n\n");
}

const via = (surface: string) => (surface === EMBER_SURFACE ? "web" : "slack");

/** Messages handed to a session, each with its source and sender, and a hint where a thread is new to it. */
export function formatInbound(messages: readonly PendingMessage[], options: { newThreads?: ReadonlySet<number>; names?: ReadonlyMap<string, string>; selves?: ReadonlyMap<string, string> } = {}): string {
  const lines: string[] = [];
  const hinted = new Set<number>();
  for (const m of messages) {
    const address = threadAddress(m.channel, m.threadTs);
    const from = options.names?.get(m.author);
    if (options.newThreads?.has(m.thread) && m.ts !== m.threadTs && !hinted.has(m.thread)) {
      hinted.add(m.thread);
      lines.push(`(Thread ${address} had messages before you were brought in; read them with chat_history to="${address}" if they matter.)`);
    }
    // What the agent is called where this was said: it has no name of its own, only each connect's.
    const self = options.selves?.get(m.connect);
    const you = self ? ` you="${escapeAttr(self)}"` : "";
    lines.push(`<message via="${via(m.surface)}" connect="${escapeAttr(m.connect)}"${you} thread="${address}" from="${escapeAttr(from ? `${from} (${m.author})` : m.author)}" ts="${m.ts}">\n${messageForAgent(m)}\n</message>`);
  }
  return lines.join("\n");
}

/** A thread's messages for chat_history: people by name, this session's own posts as "you", other agents and ember marked as bots. */
export function formatHistory(messages: readonly MessageRow[], options: { surface: string; address: string; self: string; names: ReadonlyMap<string, string> }): string {
  return messages.map((m) => {
    const name = options.names.get(m.author);
    const from = m.authorKind === "agent" && m.author === options.self ? "you"
      : m.authorKind === "ember" ? "ember"
      : name ? `${name} (${m.author})` : m.author;
    const bot = m.authorKind !== "person" && from !== "you" ? " bot" : "";
    return `<message via="${via(options.surface)}" thread="${options.address}" from="${escapeAttr(from)}"${bot} ts="${m.ts}">\n${messageForAgent(m)}\n</message>`;
  }).join("\n");
}

export const NUDGE = `Your turn ended without a final or block state, so nobody knows whether you are done.
- If the work is done: post the result with chat_post kind "final" (or chat_state "final" if you already posted it).
- If work you were asked to do cannot go on without a person: post what you need with kind "block". A reply that only asks what they want next is "final".
- Otherwise: continue the work.`;

export const RESUME_AFTER_RESTART = `ember restarted while you were in the middle of a turn, so that turn was cut off. Check where you were (files, git state, anything you started), then continue. Post only if people need to know.`;

export const RESUME_LOST = `Your earlier conversation could not be restored. Read the relevant threads with chat_history to catch up before answering.`;
