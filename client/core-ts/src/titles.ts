// What a chat is called, one rule for the station (station/src/read/views.ts titleOf) and the core (format.ts
// chatTitle): the name people gave it, else the one its agent gave it. A chat of still.fail's own is a new chat (新对话)
// until it has one, the same all along, never named by what is said in it. A Slack or Feishu thread is called by the
// first line a person wrote in it (Slack mentions left out, spaces collapsed), else by its channel (`#name`, a Feishu
// group by its name, 私信 for a direct message). Pure: the words for an unnamed chat and a direct message are the
// caller's, in its own language.

import { splitWhitespace, trim } from "./whitespace.ts";

export { splitWhitespace };

/// A thread as both sides hold it: its fields by the names the station's rows and the core's records give them.
export type Titled = { surface?: unknown; channel?: unknown; title?: unknown; autoTitle?: unknown };

/// What an unnamed chat and a direct message are called, in the caller's language.
export type TitleWords = { untitled: string; directMessage: string };

/// Text without Slack's `<@U123>` mentions.
export function withoutMentions(text: string): string {
  let out = "";
  let rest = text;
  for (let at = rest.indexOf("<@"); at >= 0; at = rest.indexOf("<@")) {
    out += rest.slice(0, at);
    const after = rest.slice(at + 2);
    const end = after.indexOf(">");
    if (end > 0 && /^[A-Z0-9]+$/.test(after.slice(0, end))) rest = after.slice(end + 1);
    else {
      out += "<@";
      rest = after;
    }
  }
  return out + rest;
}

const text = (t: Titled | null | undefined, k: keyof Titled): string => {
  const v = t?.[k];
  return typeof v === "string" ? trim(v) : "";
};

/// The names the station's own chats go by (station/src/sessions/internal.ts): their surface and connect, their
/// channel, and the author of the station's own notices. Each is read in the names of before too (`ember`, as stations
/// wrote them before the rename, and `stillfail`, as some records say it); new ones are written in the first.
export const OWN_SURFACES: readonly string[] = ["chat", "ember", "stillfail"];
export const OWN_CHANNELS: readonly string[] = ["CHAT", "EMBER", "STILLFAIL"];
export const STATION_AUTHORS: readonly string[] = ["station", "ember", "stillfail"];
/// Whether a surface (or a connect) is the station's own chats'.
export const isOwnSurface = (surface: unknown) => typeof surface === "string" && OWN_SURFACES.includes(surface);
/// Whether a channel is the station's own chats'.
export const isOwnChannel = (channel: unknown) => typeof channel === "string" && OWN_CHANNELS.includes(channel);
/// Whether a message's author kind (or a notice's `via`) is the station itself.
export const isStationAuthor = (kind: unknown) => typeof kind === "string" && STATION_AUTHORS.includes(kind);

/// Whether a thread is one of the station's own chats.
export const isOwnChat = (t: Titled | null | undefined) => isOwnSurface(t?.surface);

/// A Feishu chat's id (`oc_…`).
export const isFeishuChat = (channel: string) => /^oc_[A-Za-z0-9_-]+$/.test(channel);

/// The name a chat has been given: by people, else by its agent; null when neither did.
export function givenTitle(t: Titled | null | undefined): string | null {
  return text(t, "title") || text(t, "autoTitle") || null;
}

/// Where a Slack or Feishu thread is, in words: #channel, 私信, the Feishu group; null for a still.fail chat.
export function placeName(surface: string, channel: string, channelName: string, words: { directMessage: string; feishu: string }): string | null {
  if (surface.startsWith("feishu:") || isFeishuChat(channel)) return channelName || words.feishu;
  if (isOwnSurface(surface) || surface === "") return null;
  return channel.startsWith("D") ? words.directMessage : `#${channelName || channel}`;
}

/// What a chat is called (the rule above); `firstText` the first thing a person said in it, `channelName` its
/// channel's name where known.
export function chatTitle(t: Titled | null | undefined, firstText: string | null, channelName: string | null, words: TitleWords): string {
  const given = givenTitle(t);
  if (given !== null) return given;
  if (isOwnChat(t)) return words.untitled;
  const first = withoutMentions(firstText ?? "")
    .split("\n")
    .map((l) => splitWhitespace(l).join(" "))
    .find((l) => l !== "");
  if (first !== undefined) return first;
  const name = trim(channelName ?? "");
  if (name !== "") return typeof t?.surface === "string" && t.surface.startsWith("feishu:") ? name : `#${name}`;
  if (text(t, "channel").startsWith("D")) return words.directMessage;
  return words.untitled;
}
