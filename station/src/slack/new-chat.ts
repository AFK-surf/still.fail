// `/sf` (apps.ts NEW_CHAT_COMMAND): a new chat with a model picked. Slack completes nothing typed after a command, so
// the command opens a form whose model field completes as one types (an external select: Slack asks the station for
// the options matching what is typed, `block_suggestion`; nothing typed, the few the person is offered first, the
// hub's `modelsFirst`); sent, the bot posts the words in the channel as a new thread and a session on that model takes
// it (surface.ts `newChat`, `startChat`). All of it over Socket Mode.
import { runtimeNamed, runtimeTitle } from "../sessions/config.ts";
import type { ModelChoice } from "../sessions/chat.ts";
import { type Lang, tr } from "../ops/i18n.ts";

type Json = any;

/// The form's callback id: what tells its submission from other forms'.
export const NEW_CHAT_VIEW = "stillfail-new-chat";
/// The most options Slack takes in one answer, and of words in a plain-text input.
const MAX_OPTIONS = 100;
const MAX_WORDS = 3000;

const plain = (text: string) => ({ type: "plain_text", text, emoji: true });
/// What an option's label may hold (75 characters).
const clip = (text: string, n: number) => (Array.from(text).length <= n ? text : `${Array.from(text).slice(0, n - 1).join("")}…`);

/// How a model shows in the form: its runtime as people call it, and the model (the runtime's default when none).
export function modelLabel(choice: ModelChoice, lang: Lang): string {
  const runtime = runtimeNamed(choice.runtime);
  const name = runtime === null ? choice.runtime : runtimeTitle(runtime);
  return `${name} · ${choice.model ?? tr(lang, "station.slack.newChatDefaultModel")}`;
}

/// A model as an option's value, and back (null: not one).
export const modelValue = (choice: ModelChoice) => JSON.stringify([choice.runtime, choice.model]);
export function modelOf(value: unknown): ModelChoice | null {
  try {
    const v = JSON.parse(String(value));
    if (Array.isArray(v) && v.length === 2 && typeof v[0] === "string" && v[0] !== "" && (v[1] === null || typeof v[1] === "string")) return { runtime: v[0], model: v[1] };
  } catch {}
  return null;
}

const option = (choice: ModelChoice, lang: Lang) => ({ text: plain(clip(modelLabel(choice, lang), 75)), value: modelValue(choice) });

/// The options for what is typed in the model field: those whose label has every word typed, in order given.
export function modelOptions(models: ModelChoice[], query: string, lang: Lang): Json[] {
  const words = query.toLowerCase().split(/\s+/).filter((w) => w !== "");
  return models
    .filter((m) => {
      const label = `${modelLabel(m, lang)} ${m.model ?? ""}`.toLowerCase();
      return words.every((w) => label.includes(w));
    })
    .slice(0, MAX_OPTIONS)
    .map((m) => option(m, lang));
}

/// The form `/sf` opens in `channel`: the model (the first of `models` picked), and the words (what followed the
/// command).
export function newChatView(models: ModelChoice[], channel: string, words: string, lang: Lang): Json {
  const model: Json = { type: "external_select", action_id: "model", min_query_length: 0, placeholder: plain(tr(lang, "station.slack.newChatModelHint")) };
  if (models.length > 0) model.initial_option = option(models[0]!, lang);
  const said: Json = { type: "plain_text_input", action_id: "words", multiline: true, max_length: MAX_WORDS, placeholder: plain(tr(lang, "station.slack.newChatWordsHint")) };
  const given = words.trim();
  if (given !== "") said.initial_value = Array.from(given).slice(0, MAX_WORDS).join("");
  return {
    type: "modal",
    callback_id: NEW_CHAT_VIEW,
    private_metadata: JSON.stringify({ channel }),
    title: plain(tr(lang, "station.slack.newChatTitle")),
    submit: plain(tr(lang, "station.slack.newChatSubmit")),
    close: plain(tr(lang, "station.slack.newChatCancel")),
    blocks: [
      { type: "input", block_id: "model", label: plain(tr(lang, "station.slack.newChatModel")), element: model },
      { type: "input", block_id: "words", label: plain(tr(lang, "station.slack.newChatWords")), element: said },
    ],
  };
}

/// What a sent form asks for: where, on which model, saying what. Null: not this form, or not whole.
export function submittedChat(payload: Json): { channel: string; user: string; model: ModelChoice | null; words: string } | null {
  const view = payload?.view;
  if (view?.callback_id !== NEW_CHAT_VIEW) return null;
  let channel = "";
  try {
    channel = String(JSON.parse(String(view.private_metadata ?? "")).channel ?? "");
  } catch {}
  const user = typeof payload?.user?.id === "string" ? payload.user.id : "";
  const values = view?.state?.values ?? {};
  const model = modelOf(values?.model?.model?.selected_option?.value);
  const words = typeof values?.words?.words?.value === "string" ? values.words.words.value.trim() : "";
  if (channel === "" || user === "") return null;
  return { channel, user, model, words };
}

/// The thread's first message, as the bot posts it for the person: who asked which model, then what they said.
export function newChatBlocks(user: string, choice: ModelChoice, words: string, lang: Lang): { text: string; blocks: Json[] } {
  const header = tr(lang, "station.slack.newChatBy", { who: `<@${user}>`, model: modelLabel(choice, lang) });
  return {
    text: `${header}\n${words}`,
    blocks: [
      { type: "context", elements: [{ type: "mrkdwn", text: header }] },
      { type: "markdown", text: words },
    ],
  };
}
