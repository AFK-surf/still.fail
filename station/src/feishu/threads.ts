// Where a Feishu chat's words go (docs/feishu.md「会话怎么分」), kept in <data>/feishu-threads.json: for each chat, the
// message its conversation began with (the thread's ts: what is said in the chat outside topics is one conversation,
// until someone starts a new one), and for each topic its first message (what the station replies to, to answer in it).
import { readFileSync, renameSync, writeFileSync } from "node:fs";
import { log } from "../ops/log.ts";

type Kept = Record<string, { chats?: Record<string, string>; topics?: Record<string, string>; seen?: Record<string, number> }>;

export class FeishuThreads {
  readonly path: string;
  private kept: Kept = {};

  constructor(path: string) {
    this.path = path;
    try {
      const v = JSON.parse(readFileSync(path, "utf8"));
      if (v !== null && typeof v === "object" && !Array.isArray(v)) this.kept = v;
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") log.warn("feishu", "feishu threads file unreadable; starting empty", { error: (error as Error).message });
    }
  }

  private of(connect: string) {
    const at = (this.kept[connect] ??= {});
    at.chats ??= {};
    at.topics ??= {};
    at.seen ??= {};
    return at as { chats: Record<string, string>; topics: Record<string, string>; seen: Record<string, number> };
  }

  private save() {
    const tmp = `${this.path}.tmp`;
    try {
      writeFileSync(tmp, JSON.stringify(this.kept));
      renameSync(tmp, this.path);
    } catch (error) {
      log.warn("feishu", "feishu threads not kept", { error: (error as Error).message });
    }
  }

  /// The conversation a chat is in now, if it has begun one.
  current(connect: string, chat: string): string | null {
    return this.kept[connect]?.chats?.[chat] ?? null;
  }

  /// A conversation of the chat begins with `message`.
  begin(connect: string, chat: string, message: string) {
    this.of(connect).chats[chat] = message;
    this.save();
  }

  /// The chats with a conversation, and when the last message heard in each was said (ms): what is read again after the
  /// station was away (Feishu does not send what was said meanwhile).
  conversations(connect: string): [string, number][] {
    const at = this.kept[connect];
    return Object.keys(at?.chats ?? {}).map((chat) => [chat, at?.seen?.[chat] ?? 0]);
  }

  /// A message said at `when` was heard in `chat` (kept when it is the latest).
  heard(connect: string, chat: string, when: number) {
    const seen = this.of(connect).seen;
    if (!(when > (seen[chat] ?? 0))) return;
    seen[chat] = when;
    this.save();
  }

  /// A topic's first message, once heard.
  topicRoot(connect: string, topic: string): string | null {
    return this.kept[connect]?.topics?.[topic] ?? null;
  }

  heardTopic(connect: string, topic: string, root: string) {
    const topics = this.of(connect).topics;
    if (topics[topic] === root) return;
    topics[topic] = root;
    this.save();
  }
}
