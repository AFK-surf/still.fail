// The base of the core: the files of src/ that stand apart from what still.fail does with them (its workspaces and
// stations' API, its locks, pairing, the cloud's credentials, the chats): the device's mesh (its iroh endpoints, the
// ways to a peer and the choice among them, links, the streams' framing) and what runs a client (the host, the runtime,
// errors, words in a person's language, traces, wakes, the scheduler). Another program is built on these without the
// rest (the owner, 2026-11-14), so a base file imports only base files, npm packages and Node's own: as a value or as
// a type, `import("…")` in a type too; and the JSON of the base's own words (WORDS), no other. The set is closed:
// through any number of imports, nothing of it reaches a file that is not of it. What still.fail gives it: the mesh
// its use (src/station/mesh-wire.ts), the words its catalog and product (src/i18n.ts), the host its UIs' messages
// (src/host.ts), the traces its APIs' paths (src/route.ts), the addon its places (src/hosts/node-iroh.ts).
//
// Refused: an import in a file of BASE of a file that is not (STILL, what was let be till taken away, is empty and
// stays so); an import this cannot read (an `import(…)` of what is no string, a `require`); a JSON file that is not
// one of WORDS, and one of WORDS that nothing of the base imports; and a key of still.fail's catalog said in a base
// file that WORDS' files lack (a base file says its words with nothing else loaded).
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

/// A file's imports within this package (relative specifiers, and `#…` of package.json's `imports`), each as a path
/// from the package's root: static imports and exports from, of values and of types, `import("…")` in a type and as an
/// expression. `unread`: the imports it cannot say that of, each by its line: an `import(…)` of what is no string (a
/// template with a part worked out, a value), and a `require`. `said`: the texts written in it that may be a key of
/// the catalog, each with its line: a string, and (`head`) what a template with parts worked out begins with.
function importsOf(file: string, code: string): { imports: string[]; unread: string[]; said: { text: string; head: boolean; line: number }[] } {
  const ast = parseSync(code, { filename: file, babelrc: false, configFile: false, parserOpts: { plugins: ["typescript"] } });
  if (!ast) throw new Error(`${file}: not parsed`);
  const out = new Set<string>();
  const add = (specifier: unknown) => {
    if (typeof specifier !== "string") return;
    if (specifier.startsWith("#")) out.add(specifier);
    else if (specifier.startsWith(".")) out.add(relative(ROOT, join(ROOT, dirname(file), specifier)));
  };
  const unread: string[] = [];
  const said: { text: string; head: boolean; line: number }[] = [];
  // deno-lint-ignore no-explicit-any
  const not = (node: any, what: string) => unread.push(`${file}:${node?.loc?.start.line ?? "?"}: ${what}`);
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
    else add(specifier);
  };
  traverse(ast, {
    ImportDeclaration: (p) => add(p.node.source.value),
    ExportNamedDeclaration: (p) => add(p.node.source?.value),
    ExportAllDeclaration: (p) => add(p.node.source.value),
    TSImportType: (p) => dynamic(p.node, p.node.argument),
    ImportExpression: (p) => dynamic(p.node, p.node.source),
    TSExternalModuleReference: (p) => not(p.node, "a `require`"),
    StringLiteral: (p) => void said.push({ text: p.node.value, head: false, line: p.node.loc?.start.line ?? 0 }),
    TemplateLiteral: (p) => void said.push({ text: p.node.quasis[0]?.value.cooked ?? "", head: p.node.expressions.length > 0, line: p.node.loc?.start.line ?? 0 }),
    CallExpression: (p) => {
      if (p.node.callee.type === "Import") dynamic(p.node, p.node.arguments[0]);
      else if (p.node.callee.type === "Identifier" && p.node.callee.name === "require") not(p.node, "a `require`");
    },
  });
  return { imports: [...out].sort(), unread: unread.sort(), said };
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
    const { imports, unread, said } = importsOf(file, readFileSync(path, "utf8"));
    for (const u of unread) refused.push(`a base file imports in a way this cannot read: ${u}\n  import it by a static \`import\`, or an \`import("…")\` of a string, so that what it imports is held`);
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
  for (const path of WORDS) if (existsSync(join(ROOT, path)) && !imported.has(path)) refused.push(`WORDS names a part nothing of the base imports: ${path}\n  import it in src/lang.ts, or take it out of WORDS and put its keys back in the core's part`);
  return { refused, unused: STILL.filter((_, i) => !used.has(i)).map(([f, i]) => `${f} -> ${i}`) };
}

const { refused, unused } = found();
for (const r of refused) console.log(r);
for (const u of unused) console.log(`STILL names an import that is not there any more: ${u}\n  take its entry out of STILL (the table only falls)`);
if (process.argv.includes("--check") && (refused.length > 0 || unused.length > 0)) process.exit(1);
