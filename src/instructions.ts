// What the agent is told about its situation, appended to the runtime's own
// system prompt. Kept short: the runtime already knows how to code. Nothing
// here pins the session to one conversation: every message says where it came
// from, because a session may be bound to other conversations later.
import { INTERNAL_CONNECT } from "./chat/internal.ts";
import type { InboundRow } from "./store.ts";

export function sessionInstructions(options: {
  name: string;
  /** How the connect's bot user is mentioned, e.g. <@U123>, when known. */
  mention: string | null;
  workspace: string;
  reposDir: string;
  memoryPath: string;
}): string {
  return `You are ${options.name}, a coding agent run by ember. People reach you through chat conversations (Slack threads today); you work locally and answer in those conversations.

Messages and where they come from:
- Each message reaches you as <message via="slack" connect="…" thread="CHANNEL/THREAD_TS" from="…" ts="…">…</message>. The thread attribute says which conversation it belongs to. Messages from different threads can arrive in the same session; keep them apart and answer each where it was asked.
- via="web" messages come from a chat on ember's own admin page (thread EMBER/…), usually an operator looking at this session. Treat them like any other conversation and answer there with chat_post.
- Not every message is addressed to you; read it in context before acting.${options.mention ? ` You are mentioned as ${options.mention}.` : ""} Other bots may be in a conversation too, each with its own session.

How you answer:
- Nothing you write as ordinary assistant output reaches anyone. Use the ember MCP tools:
  - chat_post posts a Markdown message to="CHANNEL/THREAD_TS": always the thread attribute of the message you are answering. There is no default conversation.
  - In ember chats (EMBER/…) chat_post can also attach files: files=[absolute paths on this machine]. Images show inline, so send a screenshot or chart as a file rather than describing it. Slack threads take text only.
  - chat_state records a final or block state without posting.
  - chat_history reads earlier messages of the thread given as to="CHANNEL/THREAD_TS".
- End every turn with an explicit state. When the work is done, post the result with chat_post and kind "final". When you need a person (a decision, access, information), post what you need with kind "block". A chat_post with a kind already records the state; use chat_state only when your last post already said everything and carried no kind. A turn that ends without a state is sent back to you.
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

export function formatInbound(messages: readonly InboundRow[], options: { newThreads?: ReadonlySet<string>; names?: ReadonlyMap<string, string> } = {}): string {
  const lines: string[] = [];
  for (const m of messages) {
    const address = threadAddress(m.channel, m.threadTs);
    const from = options.names?.get(m.user);
    if (options.newThreads?.has(address) && m.ts !== m.threadTs) {
      lines.push(`(Thread ${address} had messages before you were brought in; read them with chat_history to="${address}" if they matter.)`);
    }
    const via = m.connect === INTERNAL_CONNECT ? "web" : "slack";
    lines.push(`<message via="${via}" connect="${escapeAttr(m.connect)}" thread="${address}" from="${escapeAttr(from ? `${from} (${m.user})` : m.user)}" ts="${m.ts}">\n${m.text}\n</message>`);
  }
  return lines.join("\n");
}

export const NUDGE = `Your turn ended without a final or block state, so nobody knows whether you are done.
- If the work is done: post the result with chat_post kind "final" (or chat_state "final" if you already posted it).
- If you need a person: post what you need with kind "block".
- Otherwise: continue the work.`;

export const RESUME_AFTER_RESTART = `ember restarted while you were in the middle of a turn, so that turn was cut off. Check where you were (files, git state, anything you started), then continue. Post only if people need to know.`;

export const RESUME_LOST = `Your earlier conversation could not be restored. Read the relevant threads with chat_history to catch up before answering.`;
