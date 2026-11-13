// The base of the core: the files of src/ that stand apart from what still.fail does with them (its workspaces and
// stations' API, its locks, pairing, the cloud's credentials, the chats): the device's mesh (its iroh endpoints, the
// ways to a peer and the choice among them, links, the streams' framing) and what runs a client (the host, the runtime,
// errors, words in a person's language, traces, wakes, the scheduler, the reader of an event stream). Another program
// is built on these without the rest (the owner, 2026-11-14), so a base file imports only base files, npm packages and
// Node's own: as a value or as a type, `import("…")` in a type too; and the JSON of the base's own words (WORDS), no
// other. The set is closed:
// through any number of imports, nothing of it reaches a file that is not of it. Nor does it say still.fail's names:
// what is named so is given it. What still.fail gives it: the mesh its use, a station's protocol and what its hello
// says (src/station/mesh-wire.ts), the words its catalog and product (src/i18n.ts), the host its UIs' messages and
// the header that asks a request twice (src/host.ts), the traces their names and its APIs' paths (src/route.ts), the
// addon its places (src/hosts/node-iroh.ts).
//
// Refused: an import in a file of BASE of a file that is not (STILL, what was let be till taken away, is empty and
// stays so); an import this cannot read (an `import(…)` of what is no string, a `require`, `createRequire`, a name
// the app's bundler resolves: ALIASES); a JSON file that is not one of WORDS, and one of WORDS that nothing of the
// base imports; a key of still.fail's catalog said in a base file that WORDS' files lack (a base file says its words
// with nothing else loaded); still.fail's name in a base file but where NAMED lets it be, each as often as it says
// and no more, which only falls; and, in the rest of src/ and in what else is built into the apps with it (CARRIED:
// the mbui app's core entry, the web's sources), an import of src/lang.ts by any file but src/i18n.ts, however the
// import spells it (what says a word of the catalog imports src/i18n.ts, so the catalog and the product's name are
// given before it asks).
//
//   node scripts/base.ts [--check]     the faults found; --check fails on any
// Run only as a script (nothing imports it): it checks whenever it is run, however its path was said.
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { parseSync, traverse } from "@babel/core";

const ROOT = fileURLToPath(new URL("..", import.meta.url));

/// The files that stand apart.
const BASE = [
  "src/mesh.ts",
  "src/iroh.ts",
  "src/iroh-bindings.ts",
  "src/hosts/node-addon.ts",
  "src/host-of.ts",
  "src/runtime.ts",
  "src/error.ts",
  "src/lang.ts",
  "src/trace.ts",
  "src/record.ts",
  "src/wake.ts",
  "src/wake-words.ts",
  "src/util.ts",
  "src/work.ts",
  "src/clock.ts",
  "src/reactive.ts",
  "src/sync/scheduler.ts",
  "src/sse.ts",
];

/// The catalog still.fail's words are in, a directory a language.
const CATALOG = "../i18n/catalog";

/// The base's own words: the parts of the catalog that are its, each in every language (src/lang.ts imports them).
/// A part is named by what its keys start with (test/catalog.test.ts), so the base's are apart from the core's by a
/// longer name (core-misc.wake.json beside core-misc.json), and a key is in one part alone.
const WORDS = ["zh", "en"].flatMap((lang) =>
  ["core-logic.format", "core-logic.mesh", "core-misc.call", "core-misc.error", "core-misc.host", "core-misc.secure", "core-misc.wake"].map((part) => `${CATALOG}/${lang}/${part}.json`),
);

/// What a base file still imports of the rest: [file, what it imports, what takes it away]. Nothing: the last five
/// went with the words, the host's messages and `dateClockSeconds` given their own place. It stays empty.
const STILL: [file: string, imports: string, until: string][] = [];

/// What an import begins with that the app's bundler resolves to a directory (apps/mbui/scripts/core.sh `--alias`):
/// which file one names is not said where it is written, so a base file imports by none. `@core` is this package's
/// src/ (ALIAS_SRC: an import by it is read as the file it names, for what is held of the files outside the base).
const ALIASES = ["@core", "@stillfail"];
const ALIAS_SRC = "@core";

/// The base's words, and the one file of the rest that imports them: it gives them the core's catalog and the
/// product's name as it is first run, and says again what of them says a word and sets the language (`words` and
/// `saidBy`, by which a program gives its catalog, are its alone to call). Any other file that imported LANG alone
/// could say a word before that, missing or unbranded.
const LANG = "src/lang.ts";
const SAYS = "src/i18n.ts";

/// Where the files are that are built into an app with the core's (from the package's root), each held to importing
/// LANG through SAYS: the core's own, the mbui app's entry of it (apps/mbui/core), the web's sources.
const CARRIED = ["src", "../../apps/mbui/core", "../../web/src"];

/// Where a base file still says still.fail's name (`stillfail`, in whatever case; in its code or a comment): [file,
/// the text it is said in, how many times the file says it, what takes it away]. The text is let be only whole (not
/// as part of a longer name: `__stillfail_later_ms` is another), and as many times as said here: once more is
/// refused, once fewer lowers the count. The rest was given: the mesh's protocol and its hello's `protocol`, the key
/// its stations' addresses are kept under, the traces' names, the header that asks a request twice. This table only
/// falls. (With its dot, still.fail, a comment says whose a thing given is: let be.)
const NAMED: [file: string, text: string, times: number, until: string][] = [
  ["src/mesh.ts", '"stillfail/relay-endpoint/1\\0"', 1, "the label the key of a relay's own endpoint is made under (`pinnedKey`) given as a field of `MeshEnv` by src/station/mesh-wire.ts, the same bytes: another label is another key, and every id the stations saw of a device's endpoints on a relay changes"],
  ["src/runtime.ts", "__stillfail_later", 2, "`laterSleep` telling a function its host's clock gives it, in place of a global the mbui app's clock reads (apps/mbui/core/clock.ts, which is run before the core's modules: what the app's bundle runs first changes with it)"],
  ["src/util.ts", "STILLFAIL_CHECK_SHARED", 2, "whether shared values are frozen (`sharedValue`) said by what starts the core (a test's setup, the web's development build), in place of a variable of the environment read here"],
];

/// A file's imports within this package (relative specifiers, `#…` of package.json's `imports`, and what ALIAS_SRC
/// names), each as a path from the package's root, by the file it names however it is spelt (`./lang.js` and
/// `./lang` are `./lang.ts` where that is the file there): static imports and exports from, of values and of types,
/// `import("…")` in a type and as an expression. `unread`: the imports it cannot say that of, each by its line: an `import(…)` of what is no string (a
/// template with a part worked out, a value), a `require` (called, or taken of a module: `module.require`,
/// `module?.require`), `createRequire`, and a name the app's bundler resolves (ALIASES). `said`: the texts written in it that may be a key of
/// the catalog, each with its line: a string, and (`head`) what a template with parts worked out begins with.
function importsOf(file: string, code: string): { imports: string[]; unread: string[]; said: { text: string; head: boolean; line: number }[] } {
  const ast = parseSync(code, { filename: file, babelrc: false, configFile: false, parserOpts: { plugins: file.endsWith(".tsx") ? ["typescript", "jsx"] : ["typescript"] } });
  if (!ast) throw new Error(`${file}: not parsed`);
  const out = new Set<string>();
  const unread = new Set<string>();
  const said: { text: string; head: boolean; line: number }[] = [];
  // deno-lint-ignore no-explicit-any
  const not = (node: any, what: string) => unread.add(`${file}:${node?.loc?.start.line ?? "?"}: ${what}`);
  // deno-lint-ignore no-explicit-any
  const add = (specifier: unknown, at: any) => {
    if (typeof specifier !== "string") return;
    if (specifier.startsWith("#")) out.add(specifier);
    else if (specifier.startsWith(".")) out.add(fileNamed(relative(ROOT, join(ROOT, dirname(file), specifier))));
    else if (ALIASES.some((alias) => specifier === alias || specifier.startsWith(`${alias}/`))) {
      not(at, `\`${specifier}\`, a name the app's bundler resolves`);
      if (specifier.startsWith(`${ALIAS_SRC}/`)) out.add(fileNamed(join("src", specifier.slice(ALIAS_SRC.length + 1))));
    }
  };
  /// The string an `import(…)` names: a string, or a template that is all text.
  // deno-lint-ignore no-explicit-any
  const literal = (node: any): string | null => {
    if (node?.type === "TSLiteralType") return literal(node.literal);
    if (node?.type === "StringLiteral") return node.value;
    if (node?.type === "TemplateLiteral" && node.expressions.length === 0) return node.quasis[0].value.cooked ?? null;
    return null;
  };
  // deno-lint-ignore no-explicit-any
  const dynamic = (at: any, node: any) => {
    const specifier = literal(node);
    if (specifier === null) not(at, "an `import(…)` of what is no string");
    else add(specifier, at);
  };
  /// A `require` taken of something (`x.require`, `x["require"]`).
  // deno-lint-ignore no-explicit-any
  const taken = (node: any) => {
    const of = node.property;
    if ((!node.computed && of.type === "Identifier" && of.name === "require") || (of.type === "StringLiteral" && of.value === "require")) not(node, "a `require`");
  };
  traverse(ast, {
    ImportDeclaration: (p) => add(p.node.source.value, p.node),
    ExportNamedDeclaration: (p) => add(p.node.source?.value, p.node),
    ExportAllDeclaration: (p) => add(p.node.source.value, p.node),
    TSImportType: (p) => dynamic(p.node, p.node.argument),
    ImportExpression: (p) => dynamic(p.node, p.node.source),
    TSExternalModuleReference: (p) => not(p.node, "a `require`"),
    StringLiteral: (p) => void said.push({ text: p.node.value, head: false, line: p.node.loc?.start.line ?? 0 }),
    TemplateLiteral: (p) => void said.push({ text: p.node.quasis[0]?.value.cooked ?? "", head: p.node.expressions.length > 0, line: p.node.loc?.start.line ?? 0 }),
    CallExpression: (p) => {
      if (p.node.callee.type === "Import") dynamic(p.node, p.node.arguments[0]);
      else if (p.node.callee.type === "Identifier" && p.node.callee.name === "require") not(p.node, "a `require`");
    },
    // (`require?.("…")`)
    OptionalCallExpression: (p) => {
      if (p.node.callee.type === "Identifier" && p.node.callee.name === "require") not(p.node, "a `require`");
    },
    Identifier: (p) => {
      if (p.node.name === "createRequire") not(p.node, "`createRequire`");
    },
    MemberExpression: (p) => taken(p.node),
    // (`module?.require`)
    OptionalMemberExpression: (p) => taken(p.node),
  });
  return { imports: [...out].sort(), unread: [...unread].sort(), said };
}

/// The file a path from the package's root names: itself, or where it is spelt as JavaScript's (`.js`, `.mjs`) or
/// with no ending, the `.ts` beside it that is there.
function fileNamed(path: string): string {
  const bare = path.replace(/\.m?js$/, "");
  const ts = `${bare}.ts`;
  return (bare !== path || !existsSync(join(ROOT, path))) && existsSync(join(ROOT, ts)) ? ts : path;
}

/// Every `.ts` and `.tsx` file under `dir` (none where it is not there), each as a path from the package's root.
function filesUnder(dir: string): string[] {
  if (!existsSync(join(ROOT, dir))) return [];
  return (readdirSync(join(ROOT, dir), { recursive: true }) as string[]).filter((f) => /\.tsx?$/.test(f) && !f.split(/[\\/]/).includes("node_modules")).map((f) => join(dir, f)).sort();
}

/// How many times `code` says `text` whole (not within a longer name), and `code` without those.
function saidWhole(code: string, text: string): { times: number; rest: string } {
  const whole = new RegExp(`(?<![A-Za-z0-9_$])${text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(?![A-Za-z0-9_$])`, "g");
  return { times: code.match(whole)?.length ?? 0, rest: code.replace(whole, (said) => " ".repeat(said.length)) };
}

/// The keys of the catalog's parts at `paths` (from the package's root); a part that is not there has none.
function keysOf(paths: string[]): Set<string> {
  const keys = new Set<string>();
  for (const path of paths) if (existsSync(join(ROOT, path))) for (const key of Object.keys(JSON.parse(readFileSync(join(ROOT, path), "utf8")))) keys.add(key);
  return keys;
}

function found(): { refused: string[]; unused: string[] } {
  const refused: string[] = [];
  const used = new Set<number>();
  const base = new Set(BASE);
  const words = new Set(WORDS);
  const imported = new Set<string>();
  const own = keysOf(WORDS);
  const all = keysOf(["zh", "en"].flatMap((lang) => readdirSync(join(ROOT, CATALOG, lang)).filter((f) => f.endsWith(".json")).map((f) => `${CATALOG}/${lang}/${f}`)));
  for (const path of WORDS) if (!existsSync(join(ROOT, path))) refused.push(`WORDS names a file that is not there: ${path}\n  take it out of WORDS, or name where it went`);
  for (const file of BASE) {
    const path = join(ROOT, file);
    if (!existsSync(path)) {
      refused.push(`BASE names a file that is not there: ${file}\n  take it out of BASE, or name where it went`);
      continue;
    }
    const code = readFileSync(path, "utf8");
    const { imports, unread, said } = importsOf(file, code);
    for (const u of unread) refused.push(`a base file imports in a way this cannot read: ${u}\n  import it by a static \`import\`, or an \`import("…")\` of a string, of a file by its relative path, so that what it imports is held`);
    // What NAMED lets be is taken out first, each text whole and counted: what is left says the name nowhere.
    let rest = code;
    for (const [f, text, times] of NAMED) {
      if (f !== file) continue;
      const said = saidWhole(rest, text);
      rest = said.rest;
      if (said.times > times) refused.push(`a base file says still.fail's name more than NAMED lets it: ${file}: ${text}, ${said.times} times for ${times}\n  have what uses ${file} give it what is named so, with the value it had; the count in NAMED is not raised (the table only falls)`);
      else if (said.times < times) refused.push(`NAMED names what is said less, or not any more: ${file}: ${text}, ${said.times} times for ${times}\n  lower its count in NAMED to ${said.times}${said.times === 0 ? ", which takes its entry out" : ""} (the table only falls)`);
    }
    const lines = code.split("\n");
    rest.split("\n").forEach((left, i) => {
      const line = lines[i]!;
      if (/stillfail/i.test(left)) refused.push(`a base file says still.fail's name: ${file}:${i + 1}: ${line.trim().slice(0, 120)}\n  have what uses ${file} give it what is named so, with the value it had (a field of what it is made with: as src/station/mesh-wire.ts gives the mesh a station's protocol, src/route.ts the traces their names); a comment says whose it is as still.fail's; nothing is added to NAMED`);
    });
    for (const to of imports) {
      if (base.has(to)) continue;
      if (to.endsWith(".json")) {
        if (words.has(to)) imported.add(to);
        else refused.push(`a base file imports JSON that is not the base's own words: ${file} -> ${to}\n  the base carries only the parts of WORDS: put the words it says in one of them (a part of their own, named by what their keys start with, in every language), never the core's parts whole`);
        continue;
      }
      const at = STILL.findIndex(([f, i]) => f === file && i === to);
      if (at >= 0) used.add(at);
      else refused.push(`a base file imports what is not of the base: ${file} -> ${to}\n  move what it needs of it into a base file, or have what uses ${file} give it (as src/station/mesh-wire.ts gives the mesh its \`MeshEnv\`, src/i18n.ts the words its catalog); add ${to} to BASE only if it imports nothing else of still.fail's, and nothing to STILL`);
    }
    for (const { text, head, line } of said) {
      const lacking = head ? (text.includes(".") ? [...all].filter((key) => key.startsWith(text) && !own.has(key)) : []) : all.has(text) && !own.has(text) ? [text] : [];
      if (lacking.length > 0) refused.push(`a base file says words that are not the base's: ${file}:${line}: ${lacking.join(", ")}\n  move each key, in every language, from the core's part into the base's part its name starts with (WORDS; a new part is named by more of the key and imported by src/lang.ts), so the base says it with nothing else loaded`);
    }
  }
  for (const [file] of NAMED) if (!base.has(file)) refused.push(`NAMED names a file that is not of the base: ${file}\n  take its entry out of NAMED`);
  for (const file of CARRIED.flatMap(filesUnder)) {
    if (base.has(file) || file === SAYS) continue;
    const code = readFileSync(join(ROOT, file), "utf8");
    // (parsed only where it may: few files name a file called so, by any of its spellings)
    if (!/\blang(\.[cm]?[jt]s)?["'`]/.test(code) || !importsOf(file, code).imports.includes(LANG)) continue;
    refused.push(`a file built into the apps imports the base's words past ${SAYS}: ${file} -> ${LANG}\n  import ${SAYS} in its place (it says again what of ${LANG} says a word and sets the language: \`t\`, \`tr\`, \`has\`, \`current\`…; \`words\` and \`saidBy\` are its alone to call): it gives the words the core's catalog and the product's name as it is first run, so nothing says one of them missing or unbranded before that`);
  }
  for (const path of WORDS) if (existsSync(join(ROOT, path)) && !imported.has(path)) refused.push(`WORDS names a part nothing of the base imports: ${path}\n  import it in src/lang.ts, or take it out of WORDS and put its keys back in the core's part`);
  return { refused, unused: STILL.filter((_, i) => !used.has(i)).map(([f, i]) => `${f} -> ${i}`) };
}

const { refused, unused } = found();
for (const r of refused) console.log(r);
for (const u of unused) console.log(`STILL names an import that is not there any more: ${u}\n  take its entry out of STILL (the table only falls)`);
if (process.argv.includes("--check") && (refused.length > 0 || unused.length > 0)) process.exit(1);
