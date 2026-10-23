// The core's answers to its pure calls (`markdown`, `code.ink`, `reader.book`, `reader.text`, `reader.search`,
// `commands.find`), worked
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
import { tr, type Lang } from "../src/i18n.ts";

const target = new URL("../../../apps/mbui/src/sfkept/kept.mbt", import.meta.url);
const HEAD = "// Made by client/core-ts/scripts/kept-answers.ts with the real core, from what the app's runs asked (scripts/kept).\n///|\nlet kept_answers : String =\n  #|";

const args = process.argv.slice(2);
const check = args.includes("--check");
const fresh = args.includes("--fresh");
const outputs = args.filter((a) => !a.startsWith("--"));

type Kept = {
  markdown: Record<string, unknown>;
  "code.ink": Record<string, unknown>;
  "reader.book": Record<string, { answer?: unknown; text?: string; search?: Record<string, unknown> }>;
  "commands.find": Record<string, unknown>;
};
const before = readFileSync(target, "utf8");
const was = (fresh ? {} : JSON.parse(before.slice(before.indexOf("#|") + 2))) as Partial<Kept>;

// What is asked: the texts, the codes by their language, the books by whether they are Markdown, each book's searches.
const texts = new Set(Object.keys(was.markdown ?? {}));
const codes = new Set(Object.keys(was["code.ink"] ?? {}));
const searches = new Map<string, Set<string>>();
for (const [key, entry] of Object.entries(was["reader.book"] ?? {})) searches.set(key, new Set(Object.keys(entry.search ?? {})));
// ⌘K's: by what was asked as the app said it (its query, what it offered, its language).
const finds = new Set(Object.keys(was["commands.find"] ?? {}));
const bookKey = (md: unknown, text: unknown) => `${md === true ? "md" : "txt"}\u0001${String(text ?? "")}`;
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
    else throw new Error(`kept-answers: no such pure call: ${line}`);
  }
}

// Each worked out by the core as it is now.
const sorted = (keys: Iterable<string>) => [...keys].sort();
const kept: Kept = { markdown: {}, "code.ink": {}, "reader.book": {}, "commands.find": {} };
for (const text of sorted(texts)) kept.markdown[text] = markdown(text);
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
const content = HEAD + JSON.stringify(kept) + "\n";
const counts = `${texts.size} texts, ${codes.size} codes, ${searches.size} books, ${finds.size} lists`;
if (check) {
  if (content !== before) {
    console.error(`kept-answers: the core answers otherwise now than apps/mbui/src/sfkept/kept.mbt keeps: run client/core-ts/scripts/kept-answers.ts (${counts})`);
    process.exit(1);
  }
  console.log(`kept-answers: ${counts}, as the core answers them`);
} else {
  writeFileSync(target, content);
  console.log(`kept-answers: ${asked} asked; ${counts} kept`);
}
