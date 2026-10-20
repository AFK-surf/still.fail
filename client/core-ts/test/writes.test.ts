// scripts/writes.ts: what a function writes on that it was given (docs/core-ts.md「谁能改什么」).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { CHECKED, writesIn } from "../scripts/writes.ts";

const found = (code: string) => writesIn("x.ts", code).map((w) => w.what);

test("what_makes_the_views_writes_on_nothing_it_was_given", () => {
  const root = new URL("..", import.meta.url).pathname;
  assert.deepEqual(CHECKED.flatMap((f) => writesIn(f, readFileSync(root + f, "utf8")).map((w) => `${w.file}:${w.line}: ${w.what}`)), []);
});

test("a_write_on_what_was_given_is_found_however_it_was_reached", () => {
  // #265's drawn(), as it was: each message's agent and files written on as they came.
  assert.deepEqual(
    found(`function drawn(out) {
      const view = out.ok;
      const messages = arr(view.messages);
      for (const m of messages) {
        m.by.here = true;
        for (const f of arr(m.attachments)) f.owner = "k";
      }
      view.elsewhere = [];
      return out;
    }`),
    ["m.by.here = true", 'f.owner = "k"', "view.elsewhere = []"],
  );
  assert.deepEqual(found(`function f(p) { delete p.x; p.n++; p.list.push(1); p.list.sort(); Object.assign(p, { a: 1 }); }`), ["delete p.x", "p.n++", "p.list.push(1)", "p.list.sort()", "Object.assign(p, { a: 1 })"]);
  // A copy's own fields may be written, never what is in it.
  assert.deepEqual(found(`function f(p) { const c = { ...p }; c.x = 1; c.by.here = true; const l = p.items.map((i) => i); l.push(1); l[0].x = 1; }`), ["c.by.here = true", "l[0].x = 1"]);
  assert.deepEqual(found(`function f(p) { const { a, ...rest } = p; rest.x = 1; a.y = 1; }`), ["a.y = 1"]);
  assert.deepEqual(found(`function f(p) { const m = p.list.find((x) => x.k); m.seen = true; const g = get(p, "g"); g.x = 1; }`), ["m.seen = true", "g.x = 1"]);
});

test("what_a_function_made_itself_is_written_freely", () => {
  assert.deepEqual(
    found(`function f(p) {
      const out = { work: text(p.turns), attention: [] };
      out.attention.push(1);
      const c = structuredClone(p);
      c.deep.x = 1;
      const sorted = [...p.list].sort();
      const keys = Object.keys(p).sort();
      const made = other(p);
      made.x = 1;
      this.kept.x = 1;
    }`),
    [],
  );
});
