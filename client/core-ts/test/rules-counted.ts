// The rules (rules/js/rules.js, MoonBit built to JS) as the core's own code calls them, counted: each of its calls
// into them by name, and what those calls ask of the crypto they are given (the hashes, `sha256Hex`; the signatures,
// `sigValid` and `taggedSigValid`, whether checked in fact or answered as checked before: vault/verified.ts `verifies`
// counts those checked in fact). A module's exports cannot be wrapped once it is loaded, so the core's imports of it are
// pointed at a module that wraps it (node:module `registerHooks`) before any file of the core is loaded: a test that
// counts imports this first, alone, and the core after it with `import(…)`. What the station's code calls (a test's
// stations) goes to the rules unwrapped and is not counted.
import { registerHooks } from "node:module";

export type RulesCount = { calls: Map<string, number>; hashes: number; sigs: number };
export const rulesCount: RulesCount = { calls: new Map(), hashes: 0, sigs: 0 };

/// The rules' calls by name and the hashes and signatures they asked, made since `from` (a `snapshot`).
export const snapshot = (): { calls: Map<string, number>; hashes: number; sigs: number } => ({ calls: new Map(rulesCount.calls), hashes: rulesCount.hashes, sigs: rulesCount.sigs });
export function since(from: ReturnType<typeof snapshot>): { calls: Record<string, number>; total: number; hashes: number; sigs: number } {
  const calls: Record<string, number> = {};
  let total = 0;
  for (const [n, c] of rulesCount.calls) {
    const d = c - (from.calls.get(n) ?? 0);
    if (d > 0) (calls[n] = d), (total += d);
  }
  return { calls, total, hashes: rulesCount.hashes - from.hashes, sigs: rulesCount.sigs - from.sigs };
}

const KEY = Symbol.for("stillfail.rules-counted");
// deno-lint-ignore no-explicit-any
type J = any;
const wrapped = new WeakMap<object, object>();
/// A crypto given to the rules, counting what they ask of it (the same object for the same crypto).
function counting(x: unknown): unknown {
  if (x === null || typeof x !== "object" || typeof (x as J).sha256Hex !== "function") return x;
  const had = wrapped.get(x);
  if (had !== undefined) return had;
  const c = x as J;
  const out: J = { ...c, sha256Hex: (...a: J[]) => (rulesCount.hashes++, c.sha256Hex(...a)) };
  if (typeof c.sigValid === "function") out.sigValid = (...a: J[]) => (rulesCount.sigs++, c.sigValid(...a));
  if (typeof c.taggedSigValid === "function") out.taggedSigValid = (...a: J[]) => (rulesCount.sigs++, c.taggedSigValid(...a));
  wrapped.set(x, out);
  return out;
}
(globalThis as J)[KEY] = {
  call: (n: string) => rulesCount.calls.set(n, (rulesCount.calls.get(n) ?? 0) + 1),
  counting,
};

let installed = false;
/// Points every import of the rules from the core's `src/` at a module that counts its calls. Before the core is loaded.
export async function countRules(): Promise<void> {
  if (installed) return;
  installed = true;
  const real = new URL("../../../rules/js/rules.js", import.meta.url).href;
  const src = new URL("../src/", import.meta.url).href;
  const names = Object.keys(await import(real));
  const counted = `${real}?counted`;
  const source = [
    `import * as r from ${JSON.stringify(real)};`,
    `const c = globalThis[Symbol.for("stillfail.rules-counted")];`,
    `const w = (n) => function (...a) { c.call(n); return r[n].apply(this, a.map(c.counting)); };`,
    ...names.map((n) => `export const ${n} = typeof r.${n} === "function" ? w(${JSON.stringify(n)}) : r.${n};`),
  ].join("\n");
  registerHooks({
    resolve(specifier, context, next) {
      const r = next(specifier, context);
      return r.url === real && context.parentURL?.startsWith(src) ? { ...r, url: counted, shortCircuit: true } : r;
    },
    load(url, context, next) {
      return url === counted ? { format: "module", source, shortCircuit: true } : next(url, context);
    },
  });
}
