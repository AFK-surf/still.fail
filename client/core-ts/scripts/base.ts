// The base of the core: the files of src/ that stand apart from what still.fail does with them (its workspaces and
// stations' API, its locks, pairing, the cloud's credentials, the chats): the device's mesh (its iroh endpoints, the
// ways to a peer and the choice among them, links, the streams' framing) and what runs a client (the host, the runtime,
// errors, traces, wakes, the scheduler). Another program is built on these without the rest (the owner, 2026-11-14), so
// a base file imports only base files, npm packages and Node's own: as a value or as a type, `import("…")` in a type
// too. The still.fail core's own use of the mesh is src/station/mesh-wire.ts, which the mesh is given and never imports.
//
// Refused: an import in a file of BASE of a file that is not, unless it is one of STILL below, each with what takes it
// away; an import this cannot read (an `import(…)` of what is no string, a `require`); and an entry of STILL that is
// no longer so (the table only falls). STILL lists a base file's own imports only: what a file named there imports in
// turn is not held until its entry goes.
//
//   node scripts/base.ts [--check]     the faults found; --check fails on any
// Run only as a script (nothing imports it): it checks whenever it is run, however its path was said.
import { existsSync, readFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { parseSync, traverse } from "@babel/core";

const ROOT = fileURLToPath(new URL("..", import.meta.url));

/// The files that stand apart.
const BASE = [
  "src/mesh.ts",
  "src/iroh.ts",
  "src/iroh-bindings.ts",
  "src/hosts/node-iroh.ts",
  "src/host.ts",
  "src/runtime.ts",
  "src/error.ts",
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

/// What a base file still imports of the rest: [file, what it imports, what takes it away]. The file's own imports
/// only: what the imported file imports in turn is not looked at.
const STILL: [file: string, imports: string, until: string][] = [
  ["src/error.ts", "src/i18n.ts", "an error's words given by what makes it (the catalog is still.fail's: client/i18n/catalog)"],
  ["src/error.ts", "src/format.ts", "`dateClockSeconds` (a rate limit's time said) moved beside the errors that say it, or to src/util.ts"],
  ["src/mesh.ts", "src/i18n.ts", "the mesh's own words (`core-logic.mesh.*`) given to it, as the errors' are"],
  ["src/host.ts", "src/protocol.ts", "the host's `send` typed by its user's messages (a type parameter), not the still.fail UIs' protocol"],
  ["src/wake.ts", "src/protocol.ts", "as src/host.ts: `WakingHost` passes the host's messages on"],
];

/// A file's imports within this package (relative specifiers, and `#…` of package.json's `imports`), each as a path
/// from the package's root: static imports and exports from, of values and of types, `import("…")` in a type and as an
/// expression. `unread`: the imports it cannot say that of, each by its line: an `import(…)` of what is no string (a
/// template with a part worked out, a value), and a `require`.
function importsOf(file: string, code: string): { imports: string[]; unread: string[] } {
  const ast = parseSync(code, { filename: file, babelrc: false, configFile: false, parserOpts: { plugins: ["typescript"] } });
  if (!ast) throw new Error(`${file}: not parsed`);
  const out = new Set<string>();
  const add = (specifier: unknown) => {
    if (typeof specifier !== "string") return;
    if (specifier.startsWith("#")) out.add(specifier);
    else if (specifier.startsWith(".")) out.add(relative(ROOT, join(ROOT, dirname(file), specifier)));
  };
  const unread: string[] = [];
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
    CallExpression: (p) => {
      if (p.node.callee.type === "Import") dynamic(p.node, p.node.arguments[0]);
      else if (p.node.callee.type === "Identifier" && p.node.callee.name === "require") not(p.node, "a `require`");
    },
  });
  return { imports: [...out].sort(), unread: unread.sort() };
}

function found(): { refused: string[]; unused: string[] } {
  const refused: string[] = [];
  const used = new Set<number>();
  const base = new Set(BASE);
  for (const file of BASE) {
    const path = join(ROOT, file);
    if (!existsSync(path)) {
      refused.push(`BASE names a file that is not there: ${file}\n  take it out of BASE, or name where it went`);
      continue;
    }
    const { imports, unread } = importsOf(file, readFileSync(path, "utf8"));
    for (const u of unread) refused.push(`a base file imports in a way this cannot read: ${u}\n  import it by a static \`import\`, or an \`import("…")\` of a string, so that what it imports is held`);
    for (const imported of imports) {
      if (base.has(imported)) continue;
      const at = STILL.findIndex(([f, i]) => f === file && i === imported);
      if (at >= 0) used.add(at);
      else refused.push(`a base file imports what is not of the base: ${file} -> ${imported}\n  move what it needs of it into a base file, or have what uses ${file} give it (as src/station/mesh-wire.ts gives the mesh its \`MeshEnv\`); add ${imported} to BASE only if it imports nothing else of still.fail's, and nothing to STILL`);
    }
  }
  return { refused, unused: STILL.filter((_, i) => !used.has(i)).map(([f, i]) => `${f} -> ${i}`) };
}

const { refused, unused } = found();
for (const r of refused) console.log(r);
for (const u of unused) console.log(`STILL names an import that is not there any more: ${u}\n  take its entry out of STILL (the table only falls)`);
if (process.argv.includes("--check") && (refused.length > 0 || unused.length > 0)) process.exit(1);
