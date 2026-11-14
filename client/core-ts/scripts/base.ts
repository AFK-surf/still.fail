// The base of the core: the files of src/ that stand apart from what still.fail does with them (its workspaces and
// stations' API, its locks, pairing, the cloud's credentials, the chats): the device's mesh (its iroh endpoints, the
// ways to a peer and the choice among them, links, the streams' framing) and what runs a client (the host, the runtime,
// errors, words in a person's language, traces, wakes, the scheduler, the reader of an event stream). Another program
// is built on these without the rest (the owner, 2026-11-14), so a base file imports only base files, npm packages and
// Node's own: as a value or as a type, `import("…")` in a type too; the JSON of the base's own words (WORDS: the
// two files beside src/lang.ts, which name no program), no other, nothing of still.fail's catalog; and the base in
// MoonBit as it is built for JavaScript (MADE: libs/base/js, of no program either, which imports nothing). The set is closed:
// through any number of imports, nothing of it reaches a file that is not of it. Nor does it say still.fail's names:
// what is named so is given it. What still.fail gives it: the mesh its use, a station's protocol and what its hello
// says (src/station/mesh-wire.ts), the words its catalog, over the base's own, and its product (src/i18n.ts), the
// host its UIs' messages and the header that asks a request twice (src/host.ts), the traces their names and its APIs'
// paths (src/route.ts), the addon its places (src/hosts/node-iroh.ts).
//
// Refused: an import in a file of BASE of a file that is not (STILL, what was let be till taken away, is empty and
// stays so; but one of MADE, which is refused where it is not there, imports anything, says still.fail's name or is
// imported by no base file); an import this cannot read (an `import(…)` of what is no string, a `require`, `createRequire`, a name
// the app's bundler resolves: ALIASES); a JSON file that is not one of WORDS, and one of WORDS that nothing of the
// base imports; the base's words not the same in every language (a key one lacks, a `{name}` one lacks), naming
// still.fail, or having a key no base file says; a key a base file says that they lack (one it asks `t` or `tr` for,
// and any text in it that is a key of still.fail's catalog: a base file says its words with nothing else loaded);
// a word asked for as a base file is loaded (outside any function: a program's own are given after that);
// still.fail's name in a base file but where NAMED lets it be, each as often as it says and no more, which only
// falls; in the rest of src/ and in what else is built into the apps with it (CARRIED: the mbui app's core entry, the
// web's sources), an import of src/lang.ts by any file but src/i18n.ts, however the import spells it (what says a
// word of the catalog imports src/i18n.ts, so the catalog and the product's name are given before it asks); in every
// code file of the repository that git tracks, outside the base (TypeScript's and JavaScript's), loading a base file
// that says a word (src/lang.ts and what loads it) without src/i18n.ts among what the file's own static imports
// load: run from there, a program of still.fail's would say the base's words ("the server") where it says its
// catalog's ("station") now, and nothing would fail (`unsaid` says what that holds and what it does not: an import
// cycle, an import it cannot read). Only ALONE's files may (the base's own test, as another program has it). And a
// file it has to read that does not parse, by its name and what the parser said.
//
//   node scripts/base.ts [--check]     the faults found; --check fails on any
// Run only as a script (nothing imports it): it checks whenever it is run, however its path was said.
import { execFileSync } from "node:child_process";
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

/// What a base file imports that is neither a file of BASE nor a package: the base in MoonBit built for JavaScript
/// (libs/base/js, built and committed by libs/base/build.sh), each file from the package's root. A part of the base
/// written once there, for a core in MoonBit and for this one (libs/base/AGENTS.md: src/sse.ts is its reader of an
/// event stream). It is of no program by that library's own check, over its source (scripts/mb-base.ts: it names
/// neither still.fail nor a program, and imports MoonBit's core and mbui's effect alone), and is what that source
/// builds to by scripts/check.sh (`libs/base/build.sh --check`). Held here, of the built file itself: that it is
/// there, imports nothing (so the set stays closed), says still.fail's name nowhere, and is imported by a base file.
const MADE = ["../../libs/base/js/base.js"];

/// The base's own words, a file a language, beside src/lang.ts, which imports them and no other JSON: every key a
/// base file says, in words that name no program (the peer is "the server", what runs the base "the app"). A program
/// gives its own over them (src/lang.ts `words`): still.fail's are its catalog's, where each of these keys is written
/// as still.fail says it (src/i18n.ts; test/base-words.test.ts holds every one of them to the catalog's text there).
const WORDS = ["src/lang.zh.json", "src/lang.en.json"];

/// The catalog still.fail's words are in, a directory a language. Nothing of the base imports it; it is read here for
/// its keys alone: one of them said in a base file is the base's to say, so in WORDS.
const CATALOG = "../i18n/catalog";

/// What a base file still imports of the rest: [file, what it imports, what takes it away]. Nothing: the last five
/// went with the words, the host's messages and `dateClockSeconds` given their own place. It stays empty.
const STILL: [file: string, imports: string, until: string][] = [];

/// What an import begins with that the app's bundler resolves to a directory (apps/mbui/scripts/core.sh `--alias`):
/// which file one names is not said where it is written, so a base file imports by none. `@core` is this package's
/// src/ (ALIAS_SRC: an import by it is read as the file it names, for what is held of the files outside the base).
/// `@stillfail` is the checkout (ALIAS_REPO), read so too.
const ALIASES = ["@core", "@stillfail"];
const ALIAS_SRC = "@core";
const ALIAS_REPO = "@stillfail";

/// The base's words, and the one file of the rest that imports them: it gives them the core's catalog, over their
/// own, and the product's name as it is first run, and says again what of them says a word and sets the language
/// (`words` and `saidBy`, by which a program gives its catalog, are its alone to call). Any other file that imported
/// LANG alone could say a word before that: missing, unbranded, or the base's own where still.fail has its own.
const LANG = "src/lang.ts";
const SAYS = "src/i18n.ts";

/// Where the files are that are built into an app with the core's (from the package's root), each held to importing
/// LANG through SAYS: the core's own, the mbui app's entry of it (apps/mbui/core), the web's sources.
const CARRIED = ["src", "../../apps/mbui/core", "../../web/src"];

/// The repository, from the package's root: every code file of it that git tracks, outside the base, that loads a
/// base file which says a word is held to loading SAYS too (`unsaid`).
const REPO = "../..";

/// The files outside the base that load the base's words without SAYS, on purpose: [file, why]. Only what tests the
/// base as a program built on it alone has it; nothing still.fail runs. One that does not need it is refused.
const ALONE: [file: string, why: string][] = [
  ["test/base-words.test.ts", "the base's own words, as a program on the base alone is said them; still.fail's are given over them only by its last test, with an `import(…)`"],
];

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
/// the catalog, each with its line: a string, and (`head`) what a template with parts worked out begins with;
/// `asked` those of them given to `t` or `tr` as the key (`top`: outside any function, so as the file is loaded). `loads`: the imports that run the file they name as this
/// one is (a static import or export from, but one of types alone, `import type`: Node and the bundlers take that
/// out; one that names a type among values is kept, `import { type A }`), `later` those that run it once reached (an
/// `import("…")` expression).
type Said = { text: string; head: boolean; line: number };
type Imports = { imports: string[]; loads: string[]; later: string[]; unread: string[]; said: Said[]; asked: (Said & { top: boolean })[] };
function importsOf(file: string, code: string): Imports {
  // (a JavaScript file is read as one: `.js`, `.mjs`, `.cjs`, `.jsx`, with JSX where it may have it)
  const plugins = /\.[cm]?ts$/.test(file) ? ["typescript"] : file.endsWith(".tsx") ? ["typescript", "jsx"] : /\.[cm]js$/.test(file) ? [] : ["jsx"];
  const ast = parseSync(code, { filename: file, babelrc: false, configFile: false, sourceType: /\.[cm]?tsx?$/.test(file) ? "module" : "unambiguous", parserOpts: { plugins } });
  if (!ast) throw new Error(`${file}: not parsed`);
  const out = new Set<string>();
  const loads = new Set<string>();
  const later = new Set<string>();
  const unread = new Set<string>();
  const said: Said[] = [];
  const asked: (Said & { top: boolean })[] = [];
  // deno-lint-ignore no-explicit-any
  const not = (node: any, what: string) => unread.add(`${file}:${node?.loc?.start.line ?? "?"}: ${what}`);
  // deno-lint-ignore no-explicit-any
  const add = (said: unknown, at: any, how: "type" | "static" | "later") => {
    if (typeof said !== "string") return;
    // (`./mesh.ts?worker`, `./mesh.ts#x`: the same file, loaded once more)
    const specifier = said.replace(/[?#].*$/, "");
    let to: string | null = null;
    if (specifier.startsWith("#")) to = specifier;
    else if (specifier.startsWith(".")) to = fileNamed(relative(ROOT, join(ROOT, dirname(file), specifier)));
    else if (ALIASES.some((alias) => specifier === alias || specifier.startsWith(`${alias}/`))) {
      not(at, `\`${specifier}\`, a name the app's bundler resolves`);
      if (specifier.startsWith(`${ALIAS_SRC}/`)) to = fileNamed(join("src", specifier.slice(ALIAS_SRC.length + 1)));
      else if (specifier.startsWith(`${ALIAS_REPO}/`)) to = fileNamed(relative(ROOT, join(ROOT, REPO, specifier.slice(ALIAS_REPO.length + 1))));
    }
    if (to === null) return;
    out.add(to);
    if (how === "static") loads.add(to);
    else if (how === "later") later.add(to);
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
  const dynamic = (at: any, node: any, how: "type" | "later") => {
    const specifier = literal(node);
    if (specifier === null) not(at, "an `import(…)` of what is no string");
    else add(specifier, at, how);
  };
  /// A key given to `t` (its first argument) or `tr` (its second), where it is written there.
  // deno-lint-ignore no-explicit-any
  const key = (node: any, top: boolean) => {
    const line = node?.loc?.start.line ?? 0;
    if (node?.type === "StringLiteral") asked.push({ text: node.value, head: false, line, top });
    else if (node?.type === "TemplateLiteral") asked.push({ text: node.quasis[0]?.value.cooked ?? "", head: node.expressions.length > 0, line, top });
  };
  /// A `require` taken of something (`x.require`, `x["require"]`).
  // deno-lint-ignore no-explicit-any
  const taken = (node: any) => {
    const of = node.property;
    if ((!node.computed && of.type === "Identifier" && of.name === "require") || (of.type === "StringLiteral" && of.value === "require")) not(node, "a `require`");
  };
  traverse(ast, {
    ImportDeclaration: (p) => add(p.node.source.value, p.node, p.node.importKind === "type" ? "type" : "static"),
    ExportNamedDeclaration: (p) => add(p.node.source?.value, p.node, p.node.exportKind === "type" ? "type" : "static"),
    ExportAllDeclaration: (p) => add(p.node.source.value, p.node, p.node.exportKind === "type" ? "type" : "static"),
    TSImportType: (p) => dynamic(p.node, p.node.argument, "type"),
    ImportExpression: (p) => dynamic(p.node, p.node.source, "later"),
    TSExternalModuleReference: (p) => not(p.node, "a `require`"),
    StringLiteral: (p) => void said.push({ text: p.node.value, head: false, line: p.node.loc?.start.line ?? 0 }),
    TemplateLiteral: (p) => void said.push({ text: p.node.quasis[0]?.value.cooked ?? "", head: p.node.expressions.length > 0, line: p.node.loc?.start.line ?? 0 }),
    CallExpression: (p) => {
      if (p.node.callee.type === "Import") dynamic(p.node, p.node.arguments[0], "later");
      else if (p.node.callee.type === "Identifier" && p.node.callee.name === "require") {
        not(p.node, "a `require`");
        // (refused in a base file; outside it, what one of a string names is loaded once it is reached)
        add(literal(p.node.arguments[0]), p.node, "later");
      } else if (p.node.callee.type === "Identifier" && p.node.callee.name === "t") key(p.node.arguments[0], p.getFunctionParent() === null);
      else if (p.node.callee.type === "Identifier" && p.node.callee.name === "tr") key(p.node.arguments[1], p.getFunctionParent() === null);
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
  return { imports: [...out].sort(), loads: [...loads].sort(), later: [...later].sort(), unread: [...unread].sort(), said, asked };
}

/// What this could not read: a file that does not parse, each with what the parser said, in a line. Refused as any
/// fault, by the file's name: what it imports is not known.
const UNREAD: string[] = [];
function unreadable(file: string, e: unknown): void {
  // (the parser's first line, without the file's name again, which Babel says first and whole)
  const said = (e instanceof Error ? e.message : String(e)).split("\n")[0]!;
  UNREAD.push(`${file}: ${said.replace(/^\S*[\\/][^\s:]+: /, "")}`);
}

/// A file's text, read once.
const TEXT = new Map<string, string>();
function textOf(file: string): string {
  if (!TEXT.has(file)) TEXT.set(file, readFileSync(join(ROOT, file), "utf8"));
  return TEXT.get(file)!;
}

/// What a file is read as code by: TypeScript's endings and JavaScript's.
const CODE = /\.[cm]?[jt]sx?$/;

/// A file's imports, read once; none of what is no code here (a package's name, JSON, a file not there), nor of a
/// file that does not parse (`UNREAD` says it).
const READ = new Map<string, Imports | null>();
function read(file: string): Imports | null {
  if (READ.has(file)) return READ.get(file)!;
  let of: Imports | null = null;
  if (CODE.test(file) && existsSync(join(ROOT, file))) {
    try {
      of = importsOf(file, textOf(file));
    } catch (e) {
      unreadable(file, e);
    }
  }
  READ.set(file, of);
  return of;
}

/// A file of words as it is written; null where it does not parse (`UNREAD` says it, once).
const WRITTEN = new Map<string, Record<string, unknown> | null>();
function wordsIn(path: string): Record<string, unknown> | null {
  if (WRITTEN.has(path)) return WRITTEN.get(path)!;
  let words: Record<string, unknown> | null = null;
  try {
    words = JSON.parse(readFileSync(join(ROOT, path), "utf8"));
  } catch (e) {
    unreadable(path, e);
  }
  WRITTEN.set(path, words);
  return words;
}

/// What the head of a file says it loads, without parsing it: the static imports and exports from, of values, written
/// in the lines before the first one that is none of an empty line, a line that begins `//`, an import or export from
/// in one line, the lines of one over several (`import {`, a name a line, `} from "…";`); nor, but a comment, a line
/// with a backtick, a `/*` or a `\` at its end. Every such line is a statement or a comment whole (nothing before it
/// opened a template, a comment or a string it could be inside), so each import found is one the file has: a part of
/// its imports, never more. Of types alone (`import type`), none, as `importsOf`.
const HEADS = new Map<string, string[]>();
function headLoads(file: string): string[] {
  if (HEADS.has(file)) return HEADS.get(file)!;
  const loads: string[] = [];
  HEADS.set(file, loads);
  if (!CODE.test(file) || !existsSync(join(ROOT, file))) return loads;
  const add = (specifier: string) => {
    const bare = specifier.replace(/[?#].*$/, "");
    if (bare.startsWith(".")) loads.push(fileNamed(relative(ROOT, join(ROOT, dirname(file), bare))));
    else if (bare.startsWith(`${ALIAS_SRC}/`)) loads.push(fileNamed(join("src", bare.slice(ALIAS_SRC.length + 1))));
  };
  /// In an import over several lines: whether of values.
  let open: boolean | null = null;
  for (const line of textOf(file).split("\n")) {
    // (a line that begins a comment where nothing is open is one whole, whatever it has in it)
    if (open === null && (line.trim() === "" || line.startsWith("//"))) continue;
    if (line.includes("`") || line.includes("/*") || line.endsWith("\\")) break;
    if (open !== null) {
      const end = /^\} from (["'])([^"']+)\1;?\s*$/.exec(line);
      if (end) {
        if (open) add(end[2]!);
        open = null;
      } else if (!/^\s+(type )?[\w$]+( as [\w$]+)?,?\s*$/.test(line)) break;
      continue;
    }
    const one = /^(?:import (type )?(?:(?:\* as [\w$]+|[\w$]+|\{[^{}"']*\}|[\w$]+, \{[^{}"']*\}) from )?|export (type )?(?:\*|\* as [\w$]+|\{[^{}"']*\}) from )(["'])([^"']+)\3;?\s*$/.exec(line);
    if (one) {
      if (one[1] === undefined && one[2] === undefined) add(one[4]!);
      continue;
    }
    const several = /^(?:import|export) (type )?\{\s*$/.exec(line);
    if (!several) break;
    open = several[1] === undefined;
  }
  return loads;
}

/// The repository's code files that git tracks (as `scripts/agents-paths.ts` lists the repository: a file not added
/// yet is nobody's but its writer's, and is read once it is staged; not the patched upstream code of vendor/), each
/// as a path from the package's root.
function repoFiles(): string[] {
  const listed = execFileSync("git", ["ls-files", "-z", "--", "*.ts", "*.tsx", "*.mts", "*.cts", "*.js", "*.jsx", "*.mjs", "*.cjs"], { cwd: join(ROOT, REPO), encoding: "utf8", maxBuffer: 1 << 28 });
  return listed.split("\0").filter((f) => f !== "" && !f.startsWith("vendor/") && existsSync(join(ROOT, REPO, f))).map((f) => relative(ROOT, join(ROOT, REPO, f))).sort();
}

/// The files outside the base that load a base file which says a word and not SAYS: [file, the base file]. A base
/// file says a word where it is LANG or loads it, now or later (`saying`: the set is closed, so what it loads is
/// base). A file is held where it names one of those itself, by a static import, an `import("…")` or a `require("…")`
/// of a string: any way from a program's first file to the base's words ends in such a file, since only base files
/// are past it. It loads SAYS where its static imports reach it.
///
/// What that holds: SAYS is among what is loaded with the file, so it has run by the time the load that brought the
/// file is over (a program's start; the `import(…)` that asked for it), and every word asked for after that, by
/// anything, is still.fail's. What it does not hold:
/// - a word asked for while files are still being loaded (a file's own top-level code), where the file reaches SAYS
///   only through a file that is itself still being loaded, an import cycle (`a.ts`: `import "./b.ts"; import
///   "./i18n.ts"`, `b.ts`: `import "./a.ts"` and a word said as it is loaded, run from `a.ts`: `b.ts` is run before
///   SAYS). Without a cycle on the way SAYS is run before the file's own code. (A base file asking for one as it is
///   loaded is refused where it asks `t` itself; not where it calls, as it is loaded, something that asks.)
/// - an import this cannot read outside the base: `import(…)` or `require(…)` of what is no string, and a name a
///   bundler or a tsconfig resolves other than ALIASES';
/// - a file git does not track, and what is no code file (`CODE`) or is outside this repository.
function unsaid(base: Set<string>): { faults: [file: string, to: string][]; saying: Set<string> } {
  const saying = new Set([LANG]);
  for (let grew = true; grew; ) {
    grew = false;
    for (const file of base) {
      if (saying.has(file)) continue;
      const of = read(file);
      if (of === null || ![...of.loads, ...of.later].some((to) => saying.has(to))) continue;
      saying.add(file);
      grew = true;
    }
  }
  /// The files found to reach SAYS by static imports, and those found not to.
  const does = new Set([SAYS]);
  const doesNot = new Set<string>();
  /// Whether `file` reaches SAYS by `loads`, asked of each file it comes to before the next is looked at; `whole`:
  /// `loads` gives every static import of a file, so where none leads there, none of the files seen reaches it.
  const walk = (file: string, loads: (file: string) => string[], whole: boolean): boolean => {
    if (does.has(file)) return true;
    if (doesNot.has(file)) return false;
    const seen = new Set([file]);
    const queue = [file];
    for (let i = 0; i < queue.length; i++) {
      for (const to of loads(queue[i]!)) {
        if (seen.has(to) || doesNot.has(to)) continue;
        if (does.has(to) || (whole && byHead(to))) {
          does.add(file);
          return true;
        }
        seen.add(to);
        queue.push(to);
      }
    }
    if (whole) for (const f of seen) doesNot.add(f);
    return false;
  };
  /// By the files' heads first, which costs no parse and finds most (a file of the core imports SAYS in its head, or
  /// a file that does); then by every import of each file whose head did not lead there.
  const byHead = (file: string): boolean => walk(file, headLoads, false);
  const reaches = (file: string) => byHead(file) || walk(file, (at) => read(at)?.loads ?? [], true);
  // (looked at only where it may: a file that names none of them by any spelling, before a quote or a `?`, loads none)
  const named = new RegExp(`/(${[...saying].map((f) => f.slice(f.lastIndexOf("/") + 1).replace(/\.ts$/, "").replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|")})(\\.[cm]?[jt]s)?[?#"'\`]`);
  const faults: [string, string][] = [];
  for (const file of repoFiles()) {
    if (base.has(file) || file === SAYS) continue;
    if (!named.test(textOf(file))) continue;
    // (one that reaches SAYS is held whatever it loads: not parsed)
    if (byHead(file)) continue;
    const of = read(file);
    if (of === null) continue;
    const to = [...of.loads, ...of.later].find((to) => saying.has(to));
    if (to !== undefined && !reaches(file)) faults.push([file, to]);
  }
  return { faults, saying };
}

/// The `{names}` a word takes, each once, sorted.
function namesIn(value: unknown): string[] {
  const texts = typeof value === "string" ? [value] : value !== null && typeof value === "object" ? Object.values(value).filter((v) => typeof v === "string") : [];
  return [...new Set(texts.flatMap((s) => [...s.matchAll(/\{([A-Za-z0-9_]+)\}/g)].map((m) => m[1]!)))].sort();
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
  for (const path of paths) if (existsSync(join(ROOT, path))) for (const key of Object.keys(wordsIn(path) ?? {})) keys.add(key);
  return keys;
}

function found(): { refused: string[]; unused: string[] } {
  const refused: string[] = [];
  const used = new Set<number>();
  const base = new Set(BASE);
  const words = new Set(WORDS);
  const made = new Set(MADE);
  const taken = new Set<string>();
  const imported = new Set<string>();
  const own = keysOf(WORDS);
  const all = keysOf(["zh", "en"].flatMap((lang) => readdirSync(join(ROOT, CATALOG, lang)).filter((f) => f.endsWith(".json")).map((f) => `${CATALOG}/${lang}/${f}`)));
  /// Every text written in a base file, to find the keys of WORDS nothing says.
  const texts: Said[] = [];
  for (const path of WORDS) if (!existsSync(join(ROOT, path))) refused.push(`WORDS names a file that is not there: ${path}\n  take it out of WORDS, or name where it went`);
  // The base's words are the same words in every language, and name no program.
  // (one that does not parse is said so, not held to the keys of the other)
  const written = WORDS.flatMap((path) => {
    const words = existsSync(join(ROOT, path)) ? wordsIn(path) : null;
    return words === null ? [] : [[path, words] as const];
  });
  for (const [path, part] of written) {
    for (const key of own) {
      if (!(key in part)) {
        refused.push(`the base's words lack a key in a language: ${path}: ${key}\n  write it there too: a key of the base's is said in every language (WORDS)`);
        continue;
      }
      const other = written.find(([, p]) => key in p && namesIn(p[key]).join() !== namesIn(part[key]).join());
      if (other !== undefined && other[0] > path) refused.push(`the base's words take other names in another language: ${key}: {${namesIn(part[key])}} in ${path}, {${namesIn(other[1][key])}} in ${other[0]}\n  write the same \`{names}\` in each: what says the key gives them once`);
      if (/still\.?fail/i.test(JSON.stringify(part[key]))) refused.push(`the base's words name still.fail: ${path}: ${key}\n  say it of no program ("the app", "the server"): still.fail's own text is its catalog's (${CATALOG}), which ${SAYS} gives over this one`);
    }
  }
  for (const file of BASE) {
    const path = join(ROOT, file);
    if (!existsSync(path)) {
      refused.push(`BASE names a file that is not there: ${file}\n  take it out of BASE, or name where it went`);
      continue;
    }
    const code = textOf(file);
    const of = read(file);
    if (of === null) continue;
    const { imports, unread, said, asked } = of;
    texts.push(...said);
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
      if (made.has(to)) {
        taken.add(to);
        continue;
      }
      if (to.endsWith(".json")) {
        if (words.has(to)) imported.add(to);
        else refused.push(`a base file imports JSON that is not the base's own words: ${file} -> ${to}\n  the base carries only its own words (WORDS, beside ${LANG}), which name no program: write there, in every language, what it says, and leave still.fail's text in its catalog, which ${SAYS} gives over them`);
        continue;
      }
      const at = STILL.findIndex(([f, i]) => f === file && i === to);
      if (at >= 0) used.add(at);
      else refused.push(`a base file imports what is not of the base: ${file} -> ${to}\n  move what it needs of it into a base file, or have what uses ${file} give it (as src/station/mesh-wire.ts gives the mesh its \`MeshEnv\`, src/i18n.ts the words its catalog); add ${to} to BASE only if it imports nothing else of still.fail's, and nothing to STILL`);
    }
    for (const { text, head, line } of said) {
      const lacking = head ? (text.includes(".") ? [...all].filter((key) => key.startsWith(text) && !own.has(key)) : []) : all.has(text) && !own.has(text) ? [text] : [];
      if (lacking.length > 0) refused.push(`a base file says words that are not the base's: ${file}:${line}: ${lacking.join(", ")}\n  write each key in the base's own words too, in every language and of no program (WORDS, beside ${LANG}), so the base says it with nothing else loaded; in still.fail's catalog it goes to a part ${SAYS} gives (a part of the base's keys is named by more of the key: core-logic.mesh.json), still.fail's text as it is`);
    }
    // (only where the file has the words' own \`t\` and \`tr\`: it imports LANG)
    if (imports.includes(LANG)) {
      for (const { text, head, line, top } of asked) {
        if (top) refused.push(`a base file asks for a word as it is loaded: ${file}:${line}: ${text}${head ? "…" : ""}\n  ask for it in the function that says it: a program gives its own words once the base is loaded (still.fail's: ${SAYS}), and one asked for before that is the base's own whatever the program`);
        if (head ? [...own].some((key) => key.startsWith(text)) : own.has(text)) continue;
        refused.push(`a base file asks for a word the base's own lack: ${file}:${line}: ${text}${head ? "…" : ""}\n  write the key in the base's own words, in every language and of no program (WORDS, beside ${LANG}): with nothing else loaded it would be shown as the key`);
      }
    }
  }
  for (const file of MADE) {
    if (!existsSync(join(ROOT, file))) {
      refused.push(`MADE names a file that is not there: ${file}\n  build it (sh libs/base/build.sh, which needs MoonBit) and commit it, or take it out of MADE`);
      continue;
    }
    if (!taken.has(file)) refused.push(`MADE names a file no base file imports: ${file}\n  take it out of MADE`);
    const of = read(file);
    if (of === null) continue;
    for (const to of [...of.imports, ...of.unread]) refused.push(`the base in MoonBit built for JavaScript imports: ${file} -> ${to}\n  what a base file takes of it is one file, whole: have libs/base/src/js reach nothing that loads a script, and build it again (libs/base/build.sh)`);
    if (/still\.?fail/i.test(textOf(file).replace(/^\/\/ Built by [^\n]*\n/, ""))) refused.push(`the base in MoonBit built for JavaScript says still.fail's name: ${file}\n  it is of no program: take the name out of libs/base/src (scripts/mb-base.ts holds that) and build it again (libs/base/build.sh)`);
  }
  for (const [file] of NAMED) if (!base.has(file)) refused.push(`NAMED names a file that is not of the base: ${file}\n  take its entry out of NAMED`);
  for (const file of CARRIED.flatMap(filesUnder)) {
    if (base.has(file) || file === SAYS) continue;
    // (parsed only where it may: few files name a file called so, by any of its spellings)
    if (!/\blang(\.[cm]?[jt]s)?[?#"'`]/.test(textOf(file)) || !(read(file)?.imports.includes(LANG) ?? false)) continue;
    refused.push(`a file built into the apps imports the base's words past ${SAYS}: ${file} -> ${LANG}\n  import ${SAYS} in its place (it says again what of ${LANG} says a word and sets the language: \`t\`, \`tr\`, \`has\`, \`current\`…; \`words\` and \`saidBy\` are its alone to call): it gives the words the core's catalog and the product's name as it is first run, so nothing says one of them missing or unbranded before that`);
  }
  for (const path of WORDS) if (existsSync(join(ROOT, path)) && !imported.has(path)) refused.push(`WORDS names a file nothing of the base imports: ${path}\n  import it in ${LANG}, or take it out of WORDS`);
  for (const key of own) {
    if (!texts.some(({ text, head }) => (head ? text.includes(".") && key.startsWith(text) : text === key))) refused.push(`the base's words have a key no base file says: ${key}\n  take it out of every file of WORDS: they are what the base says and no more (still.fail's catalog keeps its own)`);
  }
  // What loads the base's words loads still.fail's over them.
  const { faults, saying } = unsaid(base);
  const alone = new Set<string>();
  for (const [file, to] of faults) {
    if (ALONE.some(([f]) => f === file)) alone.add(file);
    else refused.push(`a file loads the base's words without still.fail's: ${file} -> ${to}\n  import ${SAYS} in it (\`import "./i18n.ts";\`, by its path from there), or what it needs of ${to} through a file that does: ${to} ${to === LANG ? "is" : "loads"} the base's own words (WORDS: "the server"), and still.fail's catalog is over them only once ${SAYS} is run; a program run from this file, or from one that loads no more than it, would say the base's words where still.fail says its own, and nothing would fail`);
  }
  for (const said of UNREAD.sort()) refused.push(`a file this reads does not parse: ${said}\n  mend it (a merge's markers left in it?): what it imports, or the words it has, cannot be held until it is read`);
  for (const [file] of ALONE) if (!alone.has(file)) refused.push(`ALONE names a file that loads ${SAYS}, or no base file that says a word (${[...saying].sort().join(", ")}): ${file}\n  take its entry out of ALONE`);
  return { refused, unused: STILL.filter((_, i) => !used.has(i)).map(([f, i]) => `${f} -> ${i}`) };
}

const { refused, unused } = found();
for (const r of refused) console.log(r);
for (const u of unused) console.log(`STILL names an import that is not there any more: ${u}\n  take its entry out of STILL (the table only falls)`);
if (process.argv.includes("--check") && (refused.length > 0 || unused.length > 0)) process.exit(1);
