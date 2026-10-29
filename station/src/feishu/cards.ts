// What the station posts in Feishu, as message cards (JSON 2.0, docs/feishu.md「发出去的样子」): an agent's words in a
// markdown element (Feishu's cards read Markdown much as still.fail does), a question's buttons or field, the answer it
// got, and the line saying what the agent is doing.
import { type Lang, tr } from "../ops/i18n.ts";
import { splitForSlack } from "../sessions/chat.ts";

type Json = any;

/// The most of an agent's text one card carries (a card is at most 30 KB of JSON; Chinese is three bytes a character).
export const CARD_CHARS = 6000;

/// What a button or a form says back when pressed: the thread it answers in (`t`), and what was chosen (`l`).
export type Answer = { sf: "answer"; t: string; l?: string };

const card = (elements: Json[], summary?: string, header?: Json): Json => ({
  schema: "2.0",
  config: { update_multi: true, enable_forward: true, ...(summary ? { summary: { content: summary } } : {}) },
  ...(header ? { header } : {}),
  body: { elements },
});

const markdown = (content: string, id?: string): Json => ({ tag: "markdown", content, ...(id ? { element_id: id } : {}) });

/// A line in grey, under what it is about.
const note = (content: string): Json => markdown(`<font color='grey'>${content}</font>`);

/// An agent's message as cards: one, or several in order when it is long.
export function textCards(text: string): Json[] {
  return splitForSlack(text, CARD_CHARS)
    .filter((t) => t.trim() !== "")
    .map((t) => card([markdown(t)]));
}

/// Words as plain text (a button's label, a field's hint).
const plain = (content: string): Json => ({ tag: "plain_text", content });

/// A question's card: its text, then a button for each option (the recommended one last, as still.fail shows them, and
/// filled); or, for one to write, the text under an orange header marking it as a question and a line saying to reply
/// (with its hint), with no field, as a reply in the chat answers it. `thread`: where the answer goes.
export function questionCard(text: string, question: Json, thread: string, lang: Lang): Json {
  const elements: Json[] = [];
  if (text.trim() !== "") elements.push(markdown(text));
  if (question?.type === "options") {
    const options: Json[] = Array.isArray(question.options) ? question.options : [];
    const ordered = [...options.filter((o) => o?.recommended !== true), ...options.filter((o) => o?.recommended === true)];
    for (const o of ordered) {
      const label = String(o?.label ?? "");
      const value: Answer = { sf: "answer", t: thread, l: label };
      elements.push({ tag: "button", text: plain(label), type: o?.recommended === true ? "primary_filled" : "default", width: "fill", behaviors: [{ type: "callback", value }] });
      if (typeof o?.detail === "string" && o.detail.trim() !== "") elements.push(note(o.detail));
    }
  } else if (question?.type === "text") {
    const hint = typeof question.placeholder === "string" && question.placeholder.trim() !== "" ? ` · ${question.placeholder.trim()}` : "";
    elements.push(note(`${tr(lang, "station.feishu.replyHint")}${hint}`));
    return card(elements, undefined, { title: plain(tr(lang, "station.card.asking")), template: "orange" });
  }
  return card(elements);
}

/// A question's card once answered: its text, and who answered what; nothing to press any more.
export function answeredCard(text: string, who: string, said: string, lang: Lang): Json {
  const elements: Json[] = [];
  if (text.trim() !== "") elements.push(markdown(text));
  elements.push(note(tr(lang, "station.feishu.answered", { name: who, answer: said })));
  return card(elements);
}

/// How long a turn took, in words.
export function took(ms: number, lang: Lang): string {
  const s = Math.max(1, Math.round(ms / 1000));
  if (s < 60) return tr(lang, "station.feishu.seconds", { s });
  const m = Math.floor(s / 60);
  return tr(lang, "station.feishu.minutes", { m, s: s % 60 });
}

/// What the agent is doing, while it works.
export const workingCard = (status: string): Json => card([note(status)], status);

/// The turn over: how long it took, and where its steps can be read.
export function doneCard(ms: number, page: string | null, lang: Lang): Json {
  const line = tr(lang, "station.feishu.done", { time: took(ms, lang) });
  const history = page !== null ? ` · [${tr(lang, "station.feishu.history")}](${page})` : "";
  return card([note(`${line}${history}`)], line);
}

/// A card's JSON as a message's content: inline, or the CardKit entity it shows.
export const inline = (c: Json): string => JSON.stringify(c);
export const entity = (cardId: string): string => JSON.stringify({ type: "card", data: { card_id: cardId } });
