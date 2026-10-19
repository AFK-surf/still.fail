// What Feishu's events say, as the station takes them (docs/feishu.md「收到的内容」): someone's message in a chat or a
// topic, with its text and files, or an answer from a card's button or form.
import type { InboundFile } from "../sessions/chat.ts";

type Json = any;

const text = (v: unknown): string => (typeof v === "string" ? v : "");

/// A message as Feishu gave it, before the station puts it in a thread.
export type FeishuMessage = {
  chat: string;
  /// The topic it is in (omt_…), or null: said in the chat itself.
  topic: string | null;
  /// The topic's first message, for replying in it.
  root: string | null;
  id: string;
  user: string;
  text: string;
  /// A direct message, or one that @s the bot.
  addressed: boolean;
  /// The person asked for a new session (「新会话」, /new) with it.
  fresh: boolean;
  p2p: boolean;
  files: InboundFile[];
  /// When it was said (ms), as Feishu says.
  at: number;
};

/// A card's button pressed, or its form sent.
export type CardAnswer = { chat: string; message: string; user: string; event: string; value: Json; form: Json | null };

/// A file the station fetches later: its message, its key and Feishu's kind of resource, in `url`.
export const resourceUrl = (message: string, key: string, type: "image" | "file") => `feishu:${type}:${message}:${key}`;
export function resourceOf(url: string): { message: string; key: string; type: "image" | "file" } | null {
  const m = /^feishu:(image|file):([^:]+):(.+)$/.exec(url);
  return m ? { type: m[1] as "image" | "file", message: m[2]!, key: m[3]! } : null;
}

const NEW_SESSION = /^(新会话|新对话|new session|\/new)$/i;

/// `@_user_1` and the like as `@name`; whether the bot was among them.
function withMentions(said: string, mentions: Json[], bot: string): [string, boolean] {
  let addressed = false;
  let out = said;
  for (const m of mentions) {
    const key = text(m?.key);
    if (key === "") continue;
    const open = text(m?.id?.open_id);
    if (open !== "" && open === bot) addressed = true;
    out = out.split(key).join(`@${text(m?.name) || open}`);
  }
  return [out, addressed];
}

/// A rich text (`post`) as Markdown, its images and videos as files.
function postText(content: Json, message: string, bot: string): [string, InboundFile[], boolean] {
  // Received posts are `{title, content}`; ones of other shapes keep a language level (`{zh_cn: {title, content}}`).
  const body = Array.isArray(content?.content) ? content : (Object.values(content ?? {}).find((v: Json) => Array.isArray(v?.content)) ?? {});
  const files: InboundFile[] = [];
  let addressed = false;
  const lines: string[] = [];
  const title = text(body?.title).trim();
  if (title !== "") lines.push(`**${title}**`);
  for (const paragraph of Array.isArray(body?.content) ? body.content : []) {
    let line = "";
    for (const el of Array.isArray(paragraph) ? paragraph : []) {
      const tag = text(el?.tag);
      const styles: string[] = Array.isArray(el?.style) ? el.style : [];
      if (tag === "text") {
        let t = text(el.text);
        if (styles.includes("bold")) t = `**${t}**`;
        if (styles.includes("italic")) t = `*${t}*`;
        if (styles.includes("lineThrough")) t = `~~${t}~~`;
        line += t;
      } else if (tag === "a") line += `[${text(el.text) || text(el.href)}](${text(el.href)})`;
      else if (tag === "at") {
        const id = text(el.user_id) || text(el.open_id);
        if (id !== "" && id === bot) addressed = true;
        line += `@${text(el.user_name) || id}`;
      } else if (tag === "img") {
        const key = text(el.image_key);
        if (key !== "") files.push({ id: key, name: `${key}.png`, size: 0, url: resourceUrl(message, key, "image") });
      } else if (tag === "media") {
        const key = text(el.file_key);
        if (key !== "") files.push({ id: key, name: text(el.file_name) || `${key}.mp4`, size: 0, url: resourceUrl(message, key, "file") });
      } else if (tag === "code_block") line += `\n\`\`\`${text(el.language).toLowerCase()}\n${text(el.text).replace(/\n$/, "")}\n\`\`\`\n`;
      else if (tag === "md") line += text(el.text);
      else if (tag === "emotion") line += `[${text(el.emoji_type)}]`;
      else if (tag === "hr") line += "\n---\n";
    }
    lines.push(line);
  }
  return [lines.join("\n").trim(), files, addressed];
}

/// An `im.message.receive_v1` event as a message, or null where it is none of the station's (the bot's own, another
/// app's). `bot`: the bot's open_id.
export function messageOf(event: Json, bot: string): FeishuMessage | null {
  const sender = event?.sender ?? null;
  const m = event?.message ?? null;
  // An app's messages (this bot's own among them) are not someone talking to it.
  if (text(sender?.sender_type) !== "user") return null;
  const user = text(sender?.sender_id?.open_id);
  const id = text(m?.message_id);
  const chat = text(m?.chat_id);
  if (user === "" || id === "" || chat === "") return null;
  let content: Json = {};
  try {
    content = JSON.parse(text(m?.content) || "{}");
  } catch {}
  const kind = text(m?.message_type);
  const mentions: Json[] = Array.isArray(m?.mentions) ? m.mentions : [];
  const files: InboundFile[] = [];
  let said = "";
  let addressed = false;
  if (kind === "text") [said, addressed] = withMentions(text(content?.text), mentions, bot);
  else if (kind === "post") {
    const [t, f, a] = postText(content, id, bot);
    said = t;
    files.push(...f);
    addressed = a || mentions.some((x) => text(x?.id?.open_id) === bot);
  } else if (kind === "image") {
    const key = text(content?.image_key);
    if (key !== "") files.push({ id: key, name: `${key}.png`, size: 0, url: resourceUrl(id, key, "image") });
  } else if (kind === "file" || kind === "audio" || kind === "media") {
    const key = text(content?.file_key);
    const fallback = kind === "audio" ? `${key}.opus` : kind === "media" ? `${key}.mp4` : key;
    if (key !== "") files.push({ id: key, name: text(content?.file_name) || fallback, size: 0, url: resourceUrl(id, key, "file") });
  } else said = `[${kind || "message"}]`;
  if (kind !== "text" && kind !== "post") addressed = mentions.some((x) => text(x?.id?.open_id) === bot);
  const p2p = text(m?.chat_type) === "p2p";
  // What it says besides its mentions (a bot's name may have spaces: its placeholder is what is taken out).
  const raw = kind === "text" ? text(content?.text) : said;
  const bare = mentions.reduce((t: string, x: Json) => t.split(text(x?.key) || "\u0000").join(""), raw).replace(/@\S+/g, "").trim();
  const fresh = (addressed || p2p) && NEW_SESSION.test(bare);
  const topic = text(m?.thread_id);
  return {
    chat,
    topic: topic === "" ? null : topic,
    root: text(m?.root_id) || null,
    id,
    user,
    text: said,
    addressed: addressed || p2p,
    fresh,
    p2p,
    files,
    at: Number(text(m?.create_time)) || 0,
  };
}

/// A message as the OpenAPI lists it (`GET /im/v1/messages`) in the shape its event has: what `messageOf` reads.
export function listedAsEvent(item: Json): Json {
  const sender = item?.sender ?? {};
  return {
    sender: { sender_type: text(sender.sender_type) === "app" ? "app" : "user", sender_id: { open_id: text(sender.id) } },
    message: {
      ...item,
      content: item?.body?.content,
      message_type: item?.msg_type,
      mentions: (Array.isArray(item?.mentions) ? item.mentions : []).map((x: Json) => ({ key: x?.key, name: x?.name, id: typeof x?.id === "string" ? { open_id: x.id } : x?.id })),
    },
  };
}

/// A `card.action.trigger` event: who answered which card.
export function cardAnswerOf(event: Json, eventId: string): CardAnswer | null {
  const user = text(event?.operator?.open_id);
  const chat = text(event?.context?.open_chat_id);
  const message = text(event?.context?.open_message_id);
  if (user === "" || chat === "") return null;
  const value = event?.action?.value ?? null;
  const form = event?.action?.form_value ?? null;
  return { chat, message, user, event: eventId, value, form };
}
