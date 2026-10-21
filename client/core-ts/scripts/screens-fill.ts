// A screen's JSON (client/fixtures/screens/NAME.json) put in the core's shape: each topic's value through its shape
// (present.ts conformTopic), each field it lacks filled with its type's plainest value ("", 0, false, [], {}, an
// enum's first word), until the shape takes it; then the value as conformed (what the shape does not declare dropped),
// written back. For a screen made from words written by hand or another app's made-up data (test/fixture-screens.test.ts holds
// every screen to the shape). What it fills is said, field by field, so a value that matters is written in by hand.
//   node scripts/screens-fill.ts NAME…
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { conformTopic, shapeOf } from "../src/present.ts";
import { SHAPES } from "../src/shapes/schema.ts";
import type { Ty } from "../src/shapes/dsl.ts";

type J = Record<string, unknown>;
const dir = join(import.meta.dirname, "../../fixtures/screens");

/// The plainest value of a type.
function plain(ty: Ty): unknown {
  if (typeof ty === "object") return "opt" in ty ? null : "vec" in ty ? [] : "map" in ty ? {} : ty.tuple.map(plain);
  if (ty === "String") return "";
  if (ty === "bool") return false;
  if (/^[iuf](8|16|32|54|64|size)$/.test(ty) || ty === "I54") return 0;
  const shape = SHAPES[ty];
  if (shape?.kind === "enum") return shape.default ?? shape.values[0];
  if (shape?.kind === "tagged") {
    const [word, inner] = Object.entries(shape.variants)[0];
    return { [shape.tag]: word, [shape.content]: plain(inner) };
  }
  return {};
}

/// The type at `path` ("days[0].items[3]", "." the whole) of a value of type `ty`, and the value there.
function at(ty: Ty, value: unknown, path: string): [Ty, unknown] {
  for (const step of path.replace(/^\./, "").split(/\.|(?=\[)/).filter((s) => s !== "")) {
    while (typeof ty === "object" && "opt" in ty) ty = ty.opt;
    const index = /^\[(\d+)\]$/.exec(step);
    if (index) {
      if (typeof ty === "object" && "vec" in ty) ty = ty.vec;
      value = (value as unknown[])[Number(index[1])];
      continue;
    }
    if (typeof ty === "object" && "map" in ty) {
      ty = ty.map;
    } else if (typeof ty === "string" && SHAPES[ty]?.kind === "tagged") {
      const shape = SHAPES[ty] as { tag: string; content: string; variants: Record<string, Ty> };
      ty = shape.variants[(value as J)[shape.tag] as string];
      value = (value as J)[shape.content];
      if (step === shape.content) continue;
    } else {
      const shape = SHAPES[ty as string];
      if (shape?.kind !== "struct") throw new Error(`${path}: not a struct at ${step}`);
      ty = shape.fields.find((f) => f.name === step)!.ty;
    }
    value = (value as J)[step];
  }
  while (typeof ty === "object" && "opt" in ty) ty = ty.opt;
  return [ty, value];
}

for (const name of process.argv.slice(2)) {
  const file = join(dir, `${name}.json`);
  const screen = JSON.parse(readFileSync(file, "utf8"));
  for (const t of screen.topics) {
    const ty = shapeOf(t.topic);
    if (ty === undefined) continue;
    for (let n = 0; ; n++) {
      const shaped = conformTopic(t.topic, t.value);
      if ("ok" in shaped) {
        t.value = shaped.ok;
        break;
      }
      const missing = /^(.*): missing field `([^`]+)`$/.exec(shaped.error);
      if (!missing || n > 500) throw new Error(`${name}: ${JSON.stringify(t.topic)}: ${shaped.error}`);
      const [where, field] = [missing[1], missing[2]];
      const [wty, obj] = at(ty, t.value, where);
      const shape = SHAPES[wty as string];
      const fty = shape?.kind === "struct" ? shape.fields.find((f) => f.name === field)?.ty : undefined;
      if (fty === undefined) throw new Error(`${name}: ${JSON.stringify(t.topic)}: ${where}: no field ${field} in ${JSON.stringify(wty)}`);
      (obj as J)[field] = plain(fty);
      console.log(`${name}: ${t.topic.topic} ${where === "." ? "" : where + "."}${field} = ${JSON.stringify((obj as J)[field])}`);
    }
  }
  writeFileSync(file, JSON.stringify(screen, null, 2) + "\n");
}
