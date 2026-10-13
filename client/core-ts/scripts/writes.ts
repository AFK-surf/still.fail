// What a function writes on that it was given (docs/core-ts.md「谁能改什么」): a function changes only what it
// made itself; what it is given (a parameter, and what is reached from one) may be what the core keeps and shares, and
// it makes a new value with what changes instead. This finds every write on such a value in the files it checks.
//
// A value is followed within the file by what it is made from:
// - given:   a parameter, an element of one, or anything read from one (`p.x`, `arr(p.items)`, `p.list[0]`,
//            `p.find(f)`, `p.get(k)`);
// - copied:  a new container holding what was given (`{ ...p }`, `[...p]`, `p.map(f)`, `p.slice()`): its own fields
//            may be written (`c.x = 1`, `c.push(y)`), never what is in them (`c.x.y = 1`, `c[0].z = 1`);
// - made:    anything else (a literal, `structuredClone(p)`, `JSON.parse`, what another function returned, `this`'s
//            fields): written freely. What is kept shared outside parameters (the store, the data, caches) is frozen
//            where it is shared when shared values are checked (util.ts `sharedValue`), so writing on it throws in tests.
// A write is an assignment to a field or element, `delete`, `++`/`--`, a method that changes an array in place
// (push, pop, shift, unshift, splice, sort, reverse, fill, copyWithin) or `Object.assign(x, …)`.
//
//   node scripts/writes.ts [--check] [files…]     the writes found (default: the files below); --check fails on any
import { readFileSync } from "node:fs";
import { relative, resolve } from "node:path";
import { parseSync, traverse, types as t, type NodePath } from "@babel/core";

const ROOT = new URL("..", import.meta.url).pathname;

/// What makes a view or what goes out: what is shared passes through here.
export const CHECKED = [
  "src/views/views.ts",
  "src/views/archive.ts",
  "src/views/brief.ts",
  "src/views/marks.ts",
  "src/views/models.ts",
  "src/views/profiles.ts",
  "src/views/usage.ts",
  "src/views/xshare.ts",
  "src/present.ts",
  "src/decisions.ts",
  "src/attend.ts",
  "src/entries.ts",
  "src/jobs.ts",
  "src/footprint.ts",
  "src/output.ts",
];

const IN_PLACE = new Set(["push", "pop", "shift", "unshift", "splice", "sort", "reverse", "fill", "copyWithin"]);
/// Methods that return a new array (of the same elements).
const NEW_ARRAY = new Set(["map", "filter", "slice", "concat", "flatMap", "flat", "toSorted", "toReversed", "toSpliced", "with"]);
/// Calls that return a value made anew all through.
const DEEP_COPY = new Set(["structuredClone", "clone"]);
/// Functions that return a part of what they are given (util.ts and its local wrappers).
const READERS = new Set(["get", "arr", "obj", "getU", "arrU", "pointer"]);

type State = "made" | "copied" | "given";
const worse = (a: State, b: State): State => (a === "given" || b === "given" ? "given" : a === "copied" || b === "copied" ? "copied" : "made");

export type Write = { file: string; line: number; what: string };

export function writesIn(file: string, code: string): Write[] {
  const ast = parseSync(code, { filename: file, babelrc: false, configFile: false, parserOpts: { plugins: ["typescript"] } });
  if (!ast) throw new Error(`${file}: not parsed`);
  const states = new Map<object, State>();
  const stateOfBinding = (path: NodePath, name: string): State => {
    const binding = path.scope.getBinding(name);
    if (!binding) return "made";
    if (binding.kind === "param") return "given";
    return states.get(binding) ?? "made";
  };
  const unwrap = (path: NodePath): NodePath => {
    let p = path;
    while (p.isTSAsExpression() || p.isTSNonNullExpression() || p.isParenthesizedExpression() || p.isTSSatisfiesExpression() || p.isTSTypeAssertion()) p = p.get("expression") as NodePath;
    return p;
  };
  /// Whether anything given or copied is read within an expression.
  const mentions = (path: NodePath): State => {
    let s: State = "made";
    const look = (p: NodePath) => {
      if (p.isIdentifier() && p.isReferencedIdentifier()) s = worse(s, stateOfBinding(p, p.node.name));
    };
    look(path);
    path.traverse({
      Identifier: look,
      // What a function made inside says of its own parameters, not of this value.
      Function(p) {
        p.skip();
      },
    });
    return s;
  };
  /// What a value an expression gives is.
  const stateOf = (raw: NodePath): State => {
    const path = unwrap(raw);
    if (path.isThisExpression() || path.isLiteral() || path.isTemplateLiteral() || path.isFunction() || path.isNewExpression()) return "made";
    if (path.isIdentifier()) return stateOfBinding(path, path.node.name);
    if (path.isObjectExpression() || path.isArrayExpression()) {
      // A new container: what is in it is what each of its parts is.
      const parts = (path.isObjectExpression() ? path.get("properties") : path.get("elements")) as NodePath[];
      for (const part of parts) {
        if (!part || !part.node) continue;
        const inner = part.isSpreadElement() ? part.get("argument") : part.isObjectProperty() ? part.get("value") : part.isObjectMethod() ? null : part;
        if (inner && stateOf(inner as NodePath) !== "made") return "copied";
      }
      return "made";
    }
    if (path.isConditionalExpression()) return worse(stateOf(path.get("consequent")), stateOf(path.get("alternate")));
    if (path.isLogicalExpression()) return worse(stateOf(path.get("left")), stateOf(path.get("right")));
    if (path.isAssignmentExpression()) return stateOf(path.get("right"));
    if (path.isSequenceExpression()) {
      const all = path.get("expressions");
      return stateOf(all[all.length - 1]);
    }
    if (path.isCallExpression() || path.isOptionalCallExpression()) {
      const callee = unwrap(path.get("callee") as NodePath);
      const args = path.get("arguments") as NodePath[];
      if (callee.isIdentifier()) {
        const name = callee.node.name;
        if (DEEP_COPY.has(name)) return "made";
        // A part of what it reads (`get(p, "x")`, `arr(p.list)`): what was given, if that was.
        if (READERS.has(name) && args.length > 0) return stateOf(args[0]) === "made" ? "made" : "given";
        return "made";
      }
      if ((callee.isMemberExpression() || callee.isOptionalMemberExpression()) && !callee.node.computed && t.isIdentifier(callee.node.property)) {
        const name = callee.node.property.name;
        const object = unwrap(callee.get("object") as NodePath);
        if (t.isIdentifier(object.node) && object.node.name === "JSON" && name === "parse") return "made";
        if (t.isIdentifier(object.node) && (object.node.name === "Object" || object.node.name === "Array") && (name === "fromEntries" || name === "keys" || name === "entries" || name === "values" || name === "from")) {
          return mentions(path) === "made" ? "made" : "copied";
        }
        const receiver = stateOf(object);
        if (NEW_ARRAY.has(name)) return receiver === "made" ? "made" : "copied";
        // What a method gives is its receiver's (`list.find(…)`, `map.get(k)`), or the receiver itself (`a.sort()`).
        return receiver === "made" ? "made" : "given";
      }
      return "made";
    }
    if (path.isMemberExpression() || path.isOptionalMemberExpression()) {
      const object = stateOf(path.get("object") as NodePath);
      return object === "made" ? "made" : "given";
    }
    if (path.isAwaitExpression() || path.isUnaryExpression() || path.isBinaryExpression() || path.isUpdateExpression()) return "made";
    return mentions(path) === "made" ? "made" : "given";
  };

  // What each variable is, worked out until nothing changes (a variable may be made from one declared after it).
  for (let round = 0, changed = true; changed && round < 10; round++) {
    changed = false;
    const set = (binding: object | undefined, s: State) => {
      if (!binding) return;
      const was = states.get(binding) ?? "made";
      const now = worse(was, s);
      if (now !== was) {
        states.set(binding, now);
        changed = true;
      }
    };
    traverse(ast, {
      VariableDeclarator(p) {
        const id = p.get("id");
        const init = p.get("init");
        const parent = p.parentPath.parentPath;
        let s: State;
        if (parent && (parent.isForOfStatement() || parent.isForInStatement()) && parent.node.left === p.parent) {
          // What a loop takes from what was given or copied is what was given.
          s = stateOf(parent.get("right") as NodePath) === "made" ? "made" : "given";
        } else if (init.node) s = stateOf(init as NodePath);
        else return;
        if (id.isIdentifier()) set(p.scope.getBinding(id.node.name), s);
        else {
          // `const { a, ...rest } = given`: `rest` is a new object of what was given, `a` what was given.
          const rest = id.isObjectPattern() ? id.node.properties.find((q: { type: string }) => q.type === "RestElement") : undefined;
          for (const name of Object.keys(t.getBindingIdentifiers(id.node))) {
            const copied = rest !== undefined && t.isIdentifier(rest.argument) && rest.argument.name === name;
            set(p.scope.getBinding(name), s === "made" ? "made" : copied ? "copied" : "given");
          }
        }
      },
      AssignmentExpression(p) {
        const left = p.get("left");
        if (left.isIdentifier()) set(p.scope.getBinding(left.node.name), stateOf(p.get("right")));
      },
    });
  }

  const out: Write[] = [];
  const say = (p: NodePath, target: NodePath, deep: boolean) => {
    const s = stateOf(target);
    if (s === "given" || (s === "copied" && deep)) out.push({ file, line: p.node.loc?.start.line ?? 0, what: code.slice(p.node.start ?? 0, Math.min(p.node.end ?? 0, (p.node.start ?? 0) + 80)).split("\n")[0] });
  };
  /// The object a written member belongs to, and whether it is reached through another (`a.b.c = …` writes on `a.b`).
  const written = (p: NodePath, member: NodePath) => {
    const object = unwrap(member.get("object") as NodePath);
    say(p, object, object.isMemberExpression() || object.isOptionalMemberExpression());
  };
  traverse(ast, {
    AssignmentExpression(p) {
      const left = unwrap(p.get("left") as NodePath);
      if (left.isMemberExpression()) written(p, left);
    },
    UpdateExpression(p) {
      const arg = unwrap(p.get("argument"));
      if (arg.isMemberExpression()) written(p, arg);
    },
    UnaryExpression(p) {
      if (p.node.operator !== "delete") return;
      const arg = unwrap(p.get("argument"));
      if (arg.isMemberExpression()) written(p, arg);
    },
    CallExpression(p) {
      const callee = unwrap(p.get("callee") as NodePath);
      if (!callee.isMemberExpression() || callee.node.computed || !t.isIdentifier(callee.node.property)) return;
      const name = callee.node.property.name;
      const object = unwrap(callee.get("object") as NodePath);
      if (IN_PLACE.has(name)) say(p, object, object.isMemberExpression() || object.isOptionalMemberExpression()); else if (name === "assign" && t.isIdentifier(object.node) && object.node.name === "Object") {
        const first = p.get("arguments")[0];
        if (first && !unwrap(first).isObjectExpression()) say(p, unwrap(first), false);
      }
    },
  });
  return out;
}

if (import.meta.main) {
  const args = process.argv.slice(2);
  const check = args.includes("--check");
  const files = args.filter((a) => a !== "--check");
  const all: Write[] = [];
  for (const f of files.length > 0 ? files : CHECKED.map((c) => resolve(ROOT, c))) all.push(...writesIn(relative(ROOT, resolve(f)), readFileSync(f, "utf8")));
  for (const w of all) console.log(`client/core-ts/${w.file}:${w.line}: ${w.what}`);
  if (all.length > 0) {
    console.error(`${all.length} write(s) on what a function was given (docs/core-ts.md「谁能改什么」): make a new value instead`);
    if (check) process.exit(1);
  }
}
