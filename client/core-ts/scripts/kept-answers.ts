// The core's answers to its pure calls (`markdown`, `code.ink`, `reader.book`, `reader.text`, `reader.search`,
// `commands.find`, a chat's side panel's tabs: chat-tabs.ts, where a chat's find goes:
// chat-find.ts, what a chat's relay picker shows: relay-pick.ts), and to each step of a device's browsing (drive-browse.ts
// `Browsing`: a topic of it or a call, given what it held before and what it reads, answering with what it holds
// after; and the rail as drawn from the prefs kept, `railView`), worked
// out by the real core and kept for the mbui app's runs without one (apps/mbui/src/sfkept: its Tester's tests, the
// screenshots' app, the replays of tapes older than a call), so no client reads Markdown or code itself. What those
// runs ask comes from their output, where an answer asked and not kept is said as `kept-answers-ask {…}`
// (apps/mbui/scripts/kept runs the tests and hands it here); every kept answer is worked out again each time, and
// `--check` fails where the core would answer otherwise now (scripts/check.sh).
//
//   node client/core-ts/scripts/kept-answers.ts [--check] [--fresh] [output of a run…]
//   (--fresh: none of the answers kept before, only those asked now)
import { readFileSync, writeFileSync } from "node:fs";
import { inkKept } from "../src/highlight.ts";
import { markdown } from "../src/markdown.ts";
import { book, bookAnswer, searchBook } from "../src/reader.ts";
import { find } from "../src/commands.ts";
import { railView } from "../src/rail.ts";
import { changed, tabsOf, type Change } from "../src/chat-tabs.ts";
import { findGo, type FindAt, type FindHit } from "../src/chat-find.ts";
import { readConnects, relayView } from "../src/relay-pick.ts";
import { toolCall, toolResult, type ToolPart } from "../src/tool-step.ts";
import { wordsAnswer } from "../src/words.ts";
import { tr, type Lang } from "../src/i18n.ts";
import { Browsing, withDrive, type BrowsingState, type Ordered } from "../src/drive-browse.ts";

const target = new URL("../../../apps/mbui/src/sfkept/kept.mbt", import.meta.url);
// The browsing's steps asked, by their key (the made-up core's hash of the ask): what each is worked out from again.
const browseAsks = new URL("../../../apps/mbui/src/sfkept/browse_asks.json", import.meta.url);
// An answer a line (`[call, key, answer]` as JSON, by call and then by key), so that two branches keeping answers
// of their own change lines of their own and git merges them, as it could not one line of all of them.
const HEAD = "// Made by client/core-ts/scripts/kept-answers.ts with the real core, from what the app's runs asked (scripts/kept):\n// an answer a line, [call, key, answer].\n///|\nlet kept_answers : String =\n";

const args = process.argv.slice(2);
const check = args.includes("--check");
const fresh = args.includes("--fresh");
const outputs = args.filter((a) => !a.startsWith("--"));

type Kept = {
  markdown: Record<string, unknown>;
  "code.ink": Record<string, unknown>;
  "reader.book": Record<string, { answer?: unknown; text?: string; search?: Record<string, unknown> }>;
  "commands.find": Record<string, unknown>;
  "chat.tabs": Record<string, unknown>;
  "chat.find.go": Record<string, unknown>;
  "chat.relayView": Record<string, unknown>;
  "history.tool": Record<string, unknown>;
  words: Record<string, unknown>;
  browse: Record<string, unknown>;
  railView: Record<string, unknown>;
};
const before = readFileSync(target, "utf8");
const was = (fresh ? {} : keptOf(before)) as Partial<Kept>;

// What is asked: the texts, the codes by their language, the books by whether they are Markdown, each book's searches.
const texts = new Set(Object.keys(was.markdown ?? {}));
const codes = new Set(Object.keys(was["code.ink"] ?? {}));
const searches = new Map<string, Set<string>>();
for (const [key, entry] of Object.entries(was["reader.book"] ?? {})) searches.set(key, new Set(Object.keys(entry.search ?? {})));
// ⌘K's: by what was asked as the app said it (its query, what it offered, its language).
const finds = new Set(Object.keys(was["commands.find"] ?? {}));
// A chat's tabs: by what was asked (what is kept for it, its agents, whether it has a chat yet, its session, a change).
const tabs = new Set(Object.keys(was["chat.tabs"] ?? {}));
// Where a chat's find goes: by what was asked (what was found, where the reader is, which way, what shows).
const goes = new Set(Object.keys(was["chat.find.go"] ?? {}));
// What a chat's relay picker shows: by what was asked (the connects read, what was typed, all asked for, the bot).
const relays = new Set(Object.keys(was["chat.relayView"] ?? {}));
// What a history step is: by what was asked (its name, call, result, whether it failed, whether its words show).
const tools = new Set(Object.keys(was["history.tool"] ?? {}));
// What is written, read (ref.at, ref.before, ref.marks, ref.pasted, paste.info, drive.check): by what was asked (the
// call, the words, the caret, the station it is written on).
const words = new Set(Object.keys(was.words ?? {}));
// the prefs a rail is drawn from, as JSON (the app's runs say them in Chinese, as its fixtures are)
const rails = new Set(Object.keys(was.railView ?? {}));
const bookKey = (md: unknown, text: unknown) => `${md === true ? "md" : "txt"}\u0001${String(text ?? "")}`;
const steps = new Map<string, Step>(fresh ? [] : Object.entries(JSON.parse(readFileSync(browseAsks, "utf8")) as Record<string, Step>));
let asked = 0;
for (const file of outputs) {
  for (const line of readFileSync(file === "-" ? 0 : file, "utf8").split("\n")) {
    const at = line.indexOf("kept-answers-ask {");
    if (at < 0) continue;
    const ask = JSON.parse(line.slice(at + "kept-answers-ask ".length)) as Record<string, unknown>;
    asked++;
    if (ask.call === "markdown") texts.add(String(ask.text ?? ""));
    else if (ask.call === "code.ink") codes.add(`${String(ask.lang ?? "")}\u0001${String(ask.code ?? "")}`);
    else if (ask.call === "reader.book" || ask.call === "reader.search") {
      const key = bookKey(ask.markdown, ask.text);
      const queries = searches.get(key) ?? new Set<string>();
      if (ask.call === "reader.search") queries.add(String(ask.query ?? ""));
      searches.set(key, queries);
    } else if (ask.call === "commands.find") finds.add(String(ask.key ?? ""));
    else if (ask.call === "chat.tabs") tabs.add(String(ask.key ?? ""));
    else if (ask.call === "chat.find.go") goes.add(String(ask.key ?? ""));
    else if (ask.call === "chat.relayView") relays.add(String(ask.key ?? ""));
    else if (ask.call === "history.tool") tools.add(String(ask.key ?? ""));
    else if (ask.call === "words") words.add(String(ask.key ?? ""));
    else if (ask.call === "railView") rails.add(JSON.stringify(ask.prefs ?? {}));
    else if (ask.call === "browse") {
      const { call: _call, key, ...step } = ask;
      steps.set(String(key), step as unknown as Step);
    } else throw new Error(`kept-answers: no such pure call: ${line}`);
  }
}

// Each worked out by the core as it is now.
const sorted = (keys: Iterable<string>) => [...keys].sort();
const kept: Kept = { markdown: {}, "code.ink": {}, "reader.book": {}, "commands.find": {}, "chat.tabs": {}, "chat.find.go": {}, "chat.relayView": {}, "history.tool": {}, words: {}, browse: {}, railView: {} };
for (const text of sorted(texts)) kept.markdown[text] = markdown(text);
for (const key of sorted(rails)) kept.railView[key] = railView(JSON.parse(key) as { rail?: unknown; rails?: unknown }, "zh");
for (const key of sorted(codes)) {
  const cut = key.indexOf("\u0001");
  kept["code.ink"][key] = inkKept(key.slice(cut + 1), key.slice(0, cut));
}
for (const key of sorted(searches.keys())) {
  const cut = key.indexOf("\u0001");
  const text = key.slice(cut + 1);
  const b = book(text, key.slice(0, cut) === "md");
  const { id: _id, ...answer } = bookAnswer(0, b, text, { tree: true });
  const search: Record<string, number[]> = {};
  for (const q of sorted(searches.get(key)!)) search[q] = searchBook(b, q);
  kept["reader.book"][key] = { answer, ...(b.text !== text ? { text: b.text } : {}), search };
}

for (const key of sorted(finds)) {
  const ask = JSON.parse(key) as { query?: unknown; offered?: unknown; lang?: unknown };
  const lang: Lang = ask.lang === "en" ? "en" : "zh";
  kept["commands.find"][key] = find(String(ask.query ?? ""), Array.isArray(ask.offered) ? ask.offered : [], (k, a) => tr(lang, k, a));
}
// The tabs shown for what is kept, or (`change`) what is kept after it (`next`: null where nothing changes) with the
// tabs shown then (`tabs`: the chat's view after it, so a run's next step is not one more ask away).
for (const key of sorted(tabs)) {
  const ask = JSON.parse(key) as { kept?: unknown; agents?: unknown; noChat?: unknown; session?: unknown; change?: Change };
  const agents = Array.isArray(ask.agents) ? ask.agents : [];
  const noChat = ask.noChat === true;
  const session = typeof ask.session === "string" ? ask.session : null;
  if (ask.change) {
    const next = changed(ask.kept, agents, noChat, session, ask.change);
    kept["chat.tabs"][key] = { next, tabs: tabsOf(next ?? ask.kept, agents, noChat, session) };
  } else kept["chat.tabs"][key] = tabsOf(ask.kept, agents, noChat, session);
}
for (const key of sorted(words)) {
  const ask = JSON.parse(key) as { call?: unknown; text?: unknown; caret?: unknown; here?: unknown };
  const text = String(ask.text ?? "");
  kept.words[key] = wordsAnswer(String(ask.call ?? ""), text, typeof ask.caret === "number" ? ask.caret : text.length, String(ask.here ?? ""));
}
for (const key of sorted(goes)) {
  const ask = JSON.parse(key) as { hits?: FindHit[]; at?: FindAt | null; by?: -1 | 0 | 1; from?: number | null; to?: number | null; drawn?: Record<string, number> };
  kept["chat.find.go"][key] = findGo(ask.hits ?? [], ask.at ?? null, ask.by ?? 0, ask.from ?? null, ask.to ?? null, ask.drawn ?? {});
}
for (const key of sorted(relays)) {
  const ask = JSON.parse(key) as { connects?: unknown; query?: unknown; all?: unknown; bot?: unknown };
  kept["chat.relayView"][key] = relayView(readConnects(ask.connects), String(ask.query ?? ""), ask.all === true, typeof ask.bot === "string" ? ask.bot : null, (k, a) => tr("zh", k, a));
}
for (const key of sorted(tools)) {
  const ask = JSON.parse(key) as { name?: string; call?: string; result?: string; failed?: boolean; said?: boolean };
  const say = (k: string, a?: Record<string, string | number>) => tr("zh", k, a);
  const withMd = (parts: ToolPart[]) => parts.map((p) => (p.kind === "markdown" ? { ...p, md: markdown(p.text) } : p));
  kept["history.tool"][key] = {
    call: withMd(toolCall(ask.name ?? "", ask.call ?? "", ask.said === true, say)),
    result: typeof ask.result === "string" ? withMd(toolResult(ask.name ?? "", ask.call ?? "", ask.result, ask.failed === true, say)) : null,
  };
}
const keys = sorted(steps.keys());
for (const key of keys) kept.browse[key] = browseStep(steps.get(key)!);
const content = HEAD + Object.entries(kept).flatMap(([call, answers]) => sorted(Object.keys(answers)).map((key) => `  #|${JSON.stringify([call, key, (answers as Record<string, unknown>)[key]])}\n`)).join("");
// (a step a line: what changes of them reads as the steps that came or went)
const askedSteps = `{\n${keys.map((k) => `${JSON.stringify(k)}: ${JSON.stringify(steps.get(k))}`).join(",\n")}\n}\n`;
const counts = `${texts.size} texts, ${codes.size} codes, ${searches.size} books, ${finds.size} lists, ${tabs.size} tabs, ${steps.size} browsing steps, ${rails.size} rails`;
if (check) {
  if (content !== before || askedSteps !== readFileSync(browseAsks, "utf8")) {
    console.error(`kept-answers: the core answers otherwise now than apps/mbui/src/sfkept/kept.mbt keeps: run client/core-ts/scripts/kept-answers.ts (${counts})`);
    process.exit(1);
  }
  console.log(`kept-answers: ${counts}, as the core answers them`);
} else {
  writeFileSync(target, content);
  writeFileSync(browseAsks, askedSteps);
  console.log(`kept-answers: ${asked} asked; ${counts} kept`);
}

// ── a step of a device's browsing ──

/// A step as the made-up core asks it: what the browsing held before (null: nothing yet), the prefs it reads (`driveViews`,
/// `filesTabs`), each folder's entries it was given (by station, root and path, a line between; null: not read), the
/// workspaces' stations with a drive, the time, the number the next new id is made of; and what is done: a topic's value
/// (`topic`: driveBrowse or filesTabs, its params) or a call (`name`, `params`); or the stations a workspace lists, those
/// with a drive (`withDrive`, as the `stations` topic asked with `drive` gives them).
interface Step {
  state: BrowsingState | null;
  prefs: Record<string, unknown>;
  folders: Record<string, Ordered[] | null>;
  stations: Record<string, { station: string; name: string; home: string | null }[]>;
  now: number;
  id: number;
  op: { topic: Record<string, unknown> } | { name: string; params: Record<string, unknown> } | { withDrive: { stations: { station: string; overview?: unknown }[]; here: string | null } };
}

/// A step worked out: the topic's value or the call's answer (`error`: its message), what the browsing holds after it,
/// the prefs it changed (each patch, in order); `need`: the folders it read that were not given (asked again with them,
/// nothing else of it kept).
function browseStep(step: Step): unknown {
  // the stations with a drive, this machine's first (the `stations` topic asked with `drive`)
  if ("withDrive" in step.op) return { value: withDrive(step.op.withDrive.stations, step.op.withDrive.here) };
  const need = new Set<string>();
  const patches: unknown[] = [];
  let id = step.id;
  const b = new Browsing({
    prefs: () => step.prefs,
    setPrefs: (patch) => void patches.push(patch),
    entries: (station, root, path) => {
      const key = [station, root, path].join("\n");
      if (!(key in step.folders)) need.add(key);
      return step.folders[key] ?? null;
    },
    stations: (ws) => step.stations[ws] ?? [],
    now: () => step.now,
    newId: () => `t${id++}`,
    invalid: (what) => new Error(`invalid: ${what}`),
    changed: () => {},
  }, step.state ?? undefined);
  let value: unknown;
  let error: string | null = null;
  try {
    value = "topic" in step.op
      ? (step.op.topic.topic === "filesTabs" ? b.tabsView(String(step.op.topic.workspace)) : b.view(step.op.topic))
      : b.call(step.op.name, step.op.params);
  } catch (e) {
    error = e instanceof Error ? e.message : String(e);
  }
  if (need.size) return { need: sorted(need) };
  return { ...(error !== null ? { error } : { value: value ?? null }), state: b.snapshot(), prefs: patches, id };
}

/// What kept.mbt keeps, by call: each `#|` line one answer (as written above). A file of before that (all of it as one
/// object on one line) is read too, once, as it is written anew.
function keptOf(text: string): Record<string, Record<string, unknown>> {
  const out: Record<string, Record<string, unknown>> = {};
  for (const line of text.split("\n")) {
    const at = line.indexOf("#|");
    if (at < 0) continue;
    const v = JSON.parse(line.slice(at + 2)) as unknown;
    if (Array.isArray(v)) {
      const [call, key, answer] = v as [string, string, unknown];
      (out[call] ??= {})[key] = answer;
    } else Object.assign(out, v as Record<string, Record<string, unknown>>);
  }
  return out;
}
