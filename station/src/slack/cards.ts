// A question in Slack, as Block Kit (docs/operations.md「在 Slack 里使用」): the agent's words, then the options as radio
// buttons with the recommended one last and chosen already, and a button that sends the answer; or, for one to write,
// the words marked as a question, answered by a reply in the thread; or, for a login whose page gives a code, a field for
// that code and a button that hands it to the login, never said in the thread. Pressed, a button comes over Socket Mode
// (an `interactive` envelope) and the message is changed to say who answered what.
import { type Lang, tr } from "../ops/i18n.ts";

type Json = any;

/// The most a message's Markdown, and an option's label or description, may hold (Slack refuses more).
export const MARKDOWN_CHARS = 12_000;
const OPTION_CHARS = 75;
/// The most a button's value may hold.
const VALUE_CHARS = 2000;

/// The button that sends a card's answer, and what it carries: the options' labels in order, as each option's value is
/// only its place (a label may be longer than a value may be).
export const SEND = "sf_answer";
const PICK = "sf_pick";
const FIELD = "sf_text";
/// A login card's field and its button.
const CODE = "sf_code";
export const LOGIN = "sf_login";
type Sent = { l?: string[] };

const plain = (text: string): Json => ({ type: "plain_text", text, emoji: true });
const cut = (s: string, most: number) => ([...s].length <= most ? s : `${[...s].slice(0, most - 1).join("")}…`);
/// Words written into mrkdwn as they are: Slack reads &, < and > as its own.
const escape = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

/// Words as a markdown block: Slack draws it as still.fail does (bold, links, lists, headings, tables, code).
export const markdown = (text: string): Json => ({ type: "markdown", text });

/// A question's blocks. Options: radio buttons, the recommended one last and chosen, each option's detail under it; a
/// label or detail too long for an option is shown whole above them, the option keeping its start; with a button that
/// sends the answer. Text: the words under a heading that marks them as a question, and a line saying to reply in the
/// thread (with its hint); no field, as a reply in the thread answers it.
export function questionBlocks(text: string, question: Json, lang: Lang): Json[] {
  const blocks: Json[] = [];
  const said: string[] = text.trim() === "" ? [] : [text];
  if (question?.type === "options") {
    const given: Json[] = Array.isArray(question.options) ? question.options : [];
    const ordered = [...given.filter((o) => o?.recommended !== true), ...given.filter((o) => o?.recommended === true)];
    const labels = ordered.map((o) => String(o?.label ?? ""));
    const details = ordered.map((o) => (typeof o?.detail === "string" ? o.detail.trim() : ""));
    const long = labels.some((l) => [...l].length > OPTION_CHARS) || details.some((d) => [...d].length > OPTION_CHARS);
    if (long) said.push(labels.map((l, i) => `**${l}**${details[i] !== "" ? `\n${details[i]}` : ""}`).join("\n\n"));
    const options = labels.map((l, i) => ({ text: plain(cut(l, OPTION_CHARS)), value: String(i), ...(!long && details[i] !== "" ? { description: plain(details[i]!) } : {}) }));
    const chosen = ordered.findIndex((o) => o?.recommended === true);
    // Radio buttons take 10 options; a card has 6 at most.
    const pick: Json = { type: "radio_buttons", action_id: PICK, options };
    if (chosen >= 0) pick.initial_option = options[chosen];
    let sent: Sent = { l: labels };
    // Labels too long to carry are read from the option chosen instead (its start, as shown).
    if (JSON.stringify(sent).length > VALUE_CHARS) sent = {};
    blocks.push(markdownOf(said));
    blocks.push({ type: "actions", elements: [pick, { type: "button", action_id: SEND, text: plain(tr(lang, "station.slack.confirm")), style: "primary", value: JSON.stringify(sent) }] });
  } else if (question?.type === "text") {
    blocks.push({ type: "header", text: plain(tr(lang, "station.card.asking")) });
    blocks.push(markdownOf(said));
    const hint = typeof question.placeholder === "string" && question.placeholder.trim() !== "" ? ` · ${question.placeholder.trim()}` : "";
    blocks.push({ type: "context", elements: [{ type: "mrkdwn", text: escape(`${tr(lang, "station.slack.replyHint")}${hint}`) }] });
  }
  return blocks.filter((b) => b !== null);
}

/// A login card (a login whose page gives a code to enter, docs/remote-login.md): the agent's words (with the page's
/// link), a field for the code, and a button that hands it to the login's command; the code is never said in the thread.
export function loginBlocks(text: string, lang: Lang): Json[] {
  return [
    markdownOf(text.trim() === "" ? [] : [text]),
    { type: "input", block_id: CODE, dispatch_action: false, label: plain(tr(lang, "station.slack.loginCode")), element: { type: "plain_text_input", action_id: CODE, placeholder: plain(tr(lang, "station.slack.loginCodeHint")) } },
    { type: "actions", elements: [{ type: "button", action_id: LOGIN, text: plain(tr(lang, "station.slack.loginSubmit")), style: "primary" }] },
  ].filter((b) => b !== null);
}

/// A login card once its code was handed over: its words, and who entered it; no field any more.
export function loginEnteredBlocks(text: string, who: string, lang: Lang): Json[] {
  const entered = { type: "context", elements: [{ type: "mrkdwn", text: `✓ ${escape(tr(lang, "station.slack.loginEntered", { name: who }))}` }] };
  return [markdownOf(text.trim() === "" ? [] : [text]), entered].filter((b) => b !== null);
}

/// What a press of a login card's button hands over: the field's words ("" when empty). Null for any other action.
export function loginCodeOf(payload: Json): string | null {
  const pressed = (Array.isArray(payload?.actions) ? payload.actions : []).some((a: Json) => a?.action_id === LOGIN);
  if (!pressed) return null;
  const values: Json[] = Object.values(payload?.state?.values ?? {});
  const field = values.map((v) => v?.[CODE]).find((v) => v !== undefined);
  return typeof field?.value === "string" ? field.value.trim() : "";
}

/// What a card says above its buttons, in one markdown block (none when it says nothing); the most Slack takes.
const markdownOf = (parts: string[]): Json | null => (parts.length === 0 ? null : markdown(cut(parts.join("\n\n"), MARKDOWN_CHARS)));

/// A question once answered: its words, and who answered what; nothing to press any more.
export function answeredBlocks(text: string, who: string, said: string, lang: Lang): Json[] {
  const answered = { type: "context", elements: [{ type: "mrkdwn", text: `✓ ${escape(tr(lang, "station.feishu.answered", { name: who, answer: said }))}` }] };
  return [markdownOf(text.trim() === "" ? [] : [text]), answered].filter((b) => b !== null);
}

/// Where a thread stands once its agent's turn ended (the line still.fail's chat shows at its end, and its row): done,
/// or what it needs of a person; in small grey words under its last message (a context block), led as the app leads it.
export type Stands = { kind: "done" | "need"; words: string | null };
export function standsBlock(stands: Stands, lang: Lang): Json {
  return { type: "context", elements: [{ type: "mrkdwn", text: escape(standsText(stands, lang)) }] };
}
export function standsText(stands: Stands, lang: Lang): string {
  const words = stands.words?.trim() ?? "";
  const [mark, key, name] = stands.kind === "done" ? ["✓", "station.slack.standsDone", "done"] : ["🔔", "station.slack.standsNeed", "need"];
  return `${mark} ${words === "" ? tr(lang, `${key}Bare`) : tr(lang, key, { [name]: cut(words, STANDS_CHARS) })}`;
}
/// The most of its words the line carries: a context block's text holds 3,000 characters, escaped (& goes as &amp;).
const STANDS_CHARS = 500;

/// What a press of a card's send button answers: the option chosen (its label) or the words in the field (a text card
/// posted before they went without one), "" when
/// nothing was chosen or written. Null for any other action (choosing an option before sending it).
export function answerOf(payload: Json): { said: string; field: boolean } | null {
  const action = (Array.isArray(payload?.actions) ? payload.actions : []).find((a: Json) => a?.action_id === SEND);
  if (!action) return null;
  let sent: Sent = {};
  try {
    sent = JSON.parse(typeof action.value === "string" ? action.value : "{}") ?? {};
  } catch {}
  const values: Json[] = Object.values(payload?.state?.values ?? {});
  const field = values.map((v) => v?.[FIELD]).find((v) => v !== undefined);
  if (field !== undefined) return { said: typeof field?.value === "string" ? field.value.trim() : "", field: true };
  const option = values.map((v) => v?.[PICK]?.selected_option).find((v) => v !== undefined && v !== null);
  const label = option && Array.isArray(sent.l) ? sent.l[Number(option.value)] : undefined;
  const said = typeof label === "string" ? label : typeof option?.text?.text === "string" ? option.text.text : "";
  return { said, field: false };
}
