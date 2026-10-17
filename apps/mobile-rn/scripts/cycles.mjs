// Values a module reads from another while it loads (outside any function) where the other is in an import cycle
// with it: the other may not have run yet, and what is read is undefined (a class extended, `new` of it, a context's
// default). Run with node in apps/mobile-rn: `node scripts/cycles.mjs`.
import ts from "typescript";
import fs from "node:fs";
import path from "node:path";

const roots = ["src", "app", "modules"];
const files = [];
const walk = (d) => { for (const e of fs.readdirSync(d, { withFileTypes: true })) { const p = path.join(d, e.name); if (e.isDirectory()) { if (!["node_modules", "android", "ios"].includes(e.name)) walk(p); } else if (/\.(ts|tsx)$/.test(e.name) && !e.name.endsWith(".d.ts")) files.push(path.resolve(p)); } };
for (const r of roots) if (fs.existsSync(r)) walk(r);
const resolve = (from, spec) => {
  if (!spec.startsWith(".")) return null;
  const p = path.resolve(path.dirname(from), spec);
  for (const c of [p, p + ".ts", p + ".tsx", p + "/index.ts", p + "/index.tsx"]) if (fs.existsSync(c) && fs.statSync(c).isFile()) return c;
  return null;
};
const graph = new Map(); const parsed = new Map();
for (const f of files) {
  const sf = ts.createSourceFile(f, fs.readFileSync(f, "utf8"), ts.ScriptTarget.Latest, true, f.endsWith("x") ? ts.ScriptKind.TSX : ts.ScriptKind.TS);
  const deps = new Set(); const names = new Map();
  for (const st of sf.statements) {
    if ((ts.isImportDeclaration(st) || ts.isExportDeclaration(st)) && st.moduleSpecifier && ts.isStringLiteral(st.moduleSpecifier)) {
      const r = resolve(f, st.moduleSpecifier.text); if (!r) continue;
      if (ts.isImportDeclaration(st) && st.importClause?.isTypeOnly) continue;
      if (ts.isExportDeclaration(st) && st.isTypeOnly) continue;
      deps.add(r);
      const c = ts.isImportDeclaration(st) ? st.importClause : null;
      if (c?.name) names.set(c.name.text, r);
      const b = c?.namedBindings;
      if (b && ts.isNamespaceImport(b)) names.set(b.name.text, r);
      if (b && ts.isNamedImports(b)) for (const e of b.elements) if (!e.isTypeOnly) names.set(e.name.text, r);
    }
  }
  graph.set(f, deps); parsed.set(f, { sf, names });
}
const reaches = (a, b) => { const seen = new Set(); const st = [a]; while (st.length) { const x = st.pop(); if (x === b) return true; if (seen.has(x)) continue; seen.add(x); for (const y of graph.get(x) ?? []) st.push(y); } return false; };
const deferred = (n) => ts.isFunctionLike(n) || (ts.isPropertyDeclaration(n) && !n.modifiers?.some((m) => m.kind === ts.SyntaxKind.StaticKeyword)) || ts.isTypeNode(n) || ts.isImportDeclaration(n) || ts.isExportDeclaration(n) || ts.isInterfaceDeclaration(n) || ts.isTypeAliasDeclaration(n);
let found = 0;
for (const [f, { sf, names }] of parsed) {
  const visit = (n) => {
    if (deferred(n)) return;
    if (ts.isIdentifier(n) && names.has(n.text)) {
      const p = n.parent;
      const isProp = (ts.isPropertyAccessExpression(p) && p.name === n) || (ts.isPropertyAssignment(p) && p.name === n);
      if (!isProp && reaches(names.get(n.text), f)) {
        const { line } = sf.getLineAndCharacterOfPosition(n.getStart());
        console.log(`${path.relative(process.cwd(), f)}:${line + 1}: ${n.text} from ${path.relative(process.cwd(), names.get(n.text))}  | ${sf.text.split("\n")[line].trim().slice(0, 120)}`);
        found++;
      }
    }
    ts.forEachChild(n, visit);
  };
  for (const st of sf.statements) visit(st);
}
console.log(`${found} found`);
