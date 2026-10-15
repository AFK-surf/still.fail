import assert from "node:assert/strict";
import { test } from "node:test";
import { sizesOf, Virtual, type Item, type Layout } from "../web/src/virtual/model.ts";

const GAP = 14;
const list = (from: number, to: number, estimate = 100): Item[] => Array.from({ length: to - from }, (_, i) => ({ key: `m:${from + i}`, estimate }));
const made = (v: Virtual, height = 600, width = 400) => { v.setViewport(height, width); v.widen(); return v; };
/** A deterministic random source (mulberry32). */
function random(seed: number): () => number {
  let a = seed;
  return () => { a |= 0; a = (a + 0x6d2b79f5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
/** What must hold after anything: the rows and the room around them add up, cover the pane, and one of them shows. */
function sound(v: Virtual, items: Item[], height: number, heightOf: (key: string) => number, lead = 0, trail = 0): Layout {
  const l = v.layout();
  let y = lead;
  let showing = false;
  let before = -1;
  for (const row of l.rows) {
    assert.ok(row.index > before, "rows in order");
    before = row.index;
    assert.equal(row.key, items[row.index]!.key);
    assert.ok(row.space >= 0, `room above a row is not negative (${row.space})`);
    y += row.space;
    const h = heightOf(row.key);
    if (y < l.scrollTop + height && y + h > l.scrollTop) showing = true;
    y += h;
  }
  assert.ok(l.after >= -1e-6, `room after the rows is not negative (${l.after})`);
  assert.ok(Math.abs(y + l.after + trail - l.total) < 1e-4, `rows and room add up to the whole (${y + l.after + trail} / ${l.total})`);
  assert.ok(l.scrollTop >= 0 && l.scrollTop <= Math.max(0, l.total - height) + 1e-6, `scrolled within what there is (${l.scrollTop} of ${l.total - height})`);
  if (items.length && height > 0) assert.ok(showing, `an item shows in the pane (at ${l.scrollTop} of ${l.total})`);
  // Every item reaching into the pane is made.
  const rows = new Set(l.rows.map((r) => r.index));
  let top = lead - l.drift;
  items.forEach((item, i) => {
    const h = heightOf(item.key);
    // By more than a rounding's worth: an item that ends where the pane starts is not in it.
    if (top < l.scrollTop + height - 1e-6 && top + h > l.scrollTop + 1e-6) assert.ok(rows.has(i), `item ${i} in the pane is made`);
    top += h + GAP;
  });
  return l;
}

test("virtual_opens_at_its_end_making_only_what_shows_there", () => {
  const items = list(0, 200);
  const v = made(new Virtual({ gap: GAP, overscan: 300 }));
  v.setItems(items);
  const l = sound(v, items, 600, () => 100);
  assert.equal(l.total, 200 * 100 + 199 * GAP);
  assert.equal(l.scrollTop, l.total - 600);
  assert.ok(l.rows.length <= 10, `${l.rows.length} rows made`);
  assert.equal(l.rows.at(-1)!.index, 199);
  assert.equal(l.after, 0);
});

test("virtual_following_stays_at_the_end_as_items_come_and_are_measured", () => {
  let items = list(0, 50);
  const v = made(new Virtual({ gap: GAP, overscan: 300 }));
  v.setItems(items);
  v.measured(v.layout().rows.map((r) => [r.key, 180] as const));
  let l = v.layout();
  assert.equal(l.scrollTop, l.total - 600);
  items = [...items, ...list(50, 53)];
  v.setItems(items);
  l = v.layout();
  assert.equal(l.scrollTop, l.total - 600);
  assert.equal(v.mode.kind, "follow");
});

test("virtual_a_reader_s_place_is_kept_as_older_items_come_above_and_heights_turn_out_other_than_guessed", () => {
  let items = list(100, 200);
  const v = made(new Virtual({ gap: GAP, overscan: 300 }));
  v.setItems(items);
  v.scrolled(3000);
  v.rested();
  const a = v.mode;
  assert.equal(a.kind, "read");
  if (a.kind !== "read") return;
  const offset = v.offsetOf(a.key)!;
  // An older page above.
  items = [...list(50, 100), ...items];
  v.setItems(items);
  assert.equal(v.offsetOf(a.key), offset);
  assert.equal(v.layout().scrollTop, 3000 + 50 * (100 + GAP));
  // What is above it measured taller, what is below it shorter.
  v.measured([["m:60", 400], ["m:61", 20], ["m:190", 30]]);
  assert.equal(v.offsetOf(a.key), offset);
  // The pane narrower: every height stands until measured again.
  v.setViewport(600, 300);
  v.measured(items.slice(0, 40).map((item) => [item.key, 133] as const));
  assert.equal(v.offsetOf(a.key), offset);
});

test("virtual_goes_to_an_item_when_it_comes_and_reads_from_there", () => {
  let items = list(100, 200);
  const v = made(new Virtual({ gap: GAP, overscan: 300 }));
  v.setViewport(600, 400, 40);
  v.setItems(items);
  const end = v.layout().scrollTop;
  // Not among the items yet: the pane stays.
  assert.equal(v.goto("m:70", "start", 8), false);
  assert.equal(v.layout().scrollTop, end);
  items = [...list(50, 100), ...items];
  v.setItems(items);
  assert.equal(v.offsetOf("m:70"), 48);
  // Still on its way there until what shows there is measured: then the reader's place.
  assert.equal(v.mode.kind, "goto");
  v.measured(v.layout().rows.map((r) => [r.key, 100] as const));
  assert.deepEqual(v.mode, { kind: "read", key: "m:70", offset: 48 });
  // Where it was left: its top that far below the pane's.
  assert.equal(v.goto("m:90", "at", -30), true);
  assert.equal(v.offsetOf("m:90"), -30);
  // Its middle at the pane's middle.
  assert.equal(v.goto("m:120", "center"), true);
  assert.equal(v.offsetOf("m:120"), 250);
});

test("virtual_gone_to_a_line_near_the_end_the_pane_is_at_the_end_once_what_follows_it_is_measured_short", () => {
  // The unread line, a reply after it guessed taller than it is: near the top as far as there is to scroll, no further.
  const items: Item[] = [...list(0, 60), { key: "line", estimate: 20 }, { key: "m:60", estimate: 900 }];
  const v = made(new Virtual({ gap: GAP, overscan: 300 }));
  v.goto("line", "start", 92);
  v.setItems(items);
  assert.equal(v.offsetOf("line"), 92);
  v.measured(v.layout().rows.map((r) => [r.key, r.key === "line" ? 20 : 100] as const));
  v.measured(v.layout().rows.map((r) => [r.key, r.key === "line" ? 20 : 100] as const));
  const l = v.layout();
  assert.equal(l.scrollTop, l.total - 600);
  assert.equal(v.offsetOf("line"), 600 - 100 - GAP - 20);
  // At the very end: followed from there (the reply's buttons coming under it do not leave the pane short).
  assert.equal(v.mode.kind, "follow");
  v.measured([["m:60", 150]]);
  assert.equal(v.layout().scrollTop, v.layout().total - 600);
});

test("virtual_what_leaves_the_end_leaves_its_room_down_to_the_pane_s_bottom_and_never_a_blank_pane", () => {
  const items = [...list(0, 30), { key: "a:agent", estimate: 220 }];
  const v = made(new Virtual({ gap: GAP, overscan: 300 }));
  v.setItems(items);
  const before = v.layout();
  // An activity folds away: nothing above it drops down.
  v.setItems(items.slice(0, 30));
  let l = sound(v, items.slice(0, 30), 600, () => 100);
  assert.equal(l.scrollTop, before.scrollTop);
  assert.equal(l.total, before.total);
  assert.equal(l.after, 220 + GAP);
  // Scrolled up, it is let go.
  v.scrolled(l.scrollTop - 50);
  l = sound(v, items.slice(0, 30), 600, () => 100);
  assert.equal(l.after, 0);
  // Every item but the first shrinks to nothing like the list a browser skipped: what shows is the list, not held room.
  const w = made(new Virtual({ gap: GAP, overscan: 300 }));
  const many = list(0, 200);
  w.setItems(many);
  w.measured(many.map((item) => [item.key, 1] as const));
  l = sound(w, many, 600, () => 1);
  assert.ok(l.scrollTop + 600 > l.total - 600, "the pane is within a pane of the list's own end");
});

test("virtual_what_leaves_the_end_as_a_message_comes_leaves_its_room_too", () => {
  // A message's buttons go as the reader answers, their own message coming after it: nothing drops down meanwhile.
  let items: Item[] = [...list(0, 30), { key: "a:agent", estimate: 80 }];
  const v = made(new Virtual({ gap: GAP, overscan: 300 }));
  v.setItems(items);
  v.measured(v.layout().rows.map((r) => [r.key, r.key === "a:agent" ? 80 : 100] as const));
  const before = v.layout();
  v.glide(true);
  items = [...list(0, 30), { key: "o:1", estimate: 20 }];
  v.setItems(items);
  v.follow("o:1");
  const l = sound(v, items, 600, (key) => (key === "o:1" ? 20 : 100));
  assert.equal(l.scrollTop, before.scrollTop);
  assert.equal(l.after, 60);
});

test("virtual_what_the_reader_opens_at_the_end_is_not_followed_their_place_is_kept", () => {
  const items = list(0, 40);
  const v = made(new Virtual({ gap: GAP, overscan: 300 }));
  v.setItems(items);
  v.measured(v.layout().rows.map((r) => [r.key, 100] as const));
  const top = v.layout().scrollTop;
  v.stay();
  assert.equal(v.mode.kind, "read");
  v.measured([["m:39", 900]]);
  assert.equal(v.layout().scrollTop, top);
});

test("virtual_a_reader_at_the_very_top_is_at_the_first_message_what_loads_comes_above_it", () => {
  const head: Item = { key: "older", estimate: 30, place: false };
  let items = [head, ...list(100, 200)];
  const v = made(new Virtual({ gap: GAP, overscan: 300 }));
  v.setItems(items);
  v.scrolled(0);
  v.rested();
  assert.deepEqual(v.mode, { kind: "read", key: "m:100", offset: 30 + GAP });
  // An older page comes in after the line that said it was loading: the reader's message stays where it is.
  items = [head, ...list(50, 100), ...list(100, 200)];
  v.setItems(items);
  assert.equal(v.offsetOf("m:100"), 30 + GAP);
  assert.equal(v.layout().scrollTop, 50 * (100 + GAP));
});

test("virtual_a_list_that_holds_no_room_stays_at_the_end_of_what_there_is", () => {
  const items = list(0, 40);
  const v = made(new Virtual({ gap: GAP, overscan: 300, holds: false }));
  v.setItems(items);
  v.measured(v.layout().rows.map((r) => [r.key, 300] as const));
  // Measured again shorter (a text folded): no room after the last, the pane at the end.
  v.measured(v.layout().rows.map((r) => [r.key, 110] as const));
  const l = sound(v, items, 600, (key) => v.sizes.get(key)?.height ?? 100 * v.scaled);
  assert.equal(l.after, 0);
  assert.equal(l.scrollTop, l.total - 600);
});

test("virtual_the_pane_itself_changing_holds_no_room_following_it_stays_at_its_end", () => {
  const items = list(0, 100);
  const v = made(new Virtual({ gap: GAP, overscan: 300, lead: 24, trail: 260 }));
  v.setItems(items);
  v.measured(v.layout().rows.map((r) => [r.key, 100] as const));
  // What is under the list gets shorter (a composer back to one line), then the pane taller.
  v.setEdges(24, 140);
  let l = v.layout();
  assert.equal(l.after, 0);
  assert.equal(l.scrollTop, l.total - 600);
  v.setViewport(800, 400);
  l = v.layout();
  assert.equal(l.after, 0);
  assert.equal(l.scrollTop, l.total - 800);
});

test("virtual_gliding_to_what_came_the_pane_is_not_carried_by_what_changes_above_it", () => {
  let items = list(0, 100);
  const v = made(new Virtual({ gap: GAP, overscan: 300 }));
  v.setItems(items);
  v.measured(v.layout().rows.map((r) => [r.key, 100] as const));
  const before = v.layout();
  const eye = before.rows.find((r) => v.offsetOf(r.key)! >= 0)!;
  const offset = v.offsetOf(eye.key)!;
  // A message comes at the end as rows far above turn out taller: what shows stays put, the pane short of its end by
  // what came.
  v.glide(true);
  items = [...items, ...list(100, 101)];
  v.setItems(items);
  v.measured([["m:3", 500], ["m:4", 500]]);
  assert.equal(v.offsetOf(eye.key), offset);
  const left = v.target() - v.layout().scrollTop;
  assert.ok(left >= 100 + GAP && left < 300, `short of its end by the message come (${left})`);
  // Its steps take it there, each from where the last left it.
  v.place(v.layout().scrollTop + left / 2);
  v.measured([["m:5", 300]]);
  assert.ok(Math.abs(v.offsetOf(eye.key)! - (offset - left / 2)) < 1e-6);
  v.place(v.target());
  assert.equal(v.target(), v.layout().scrollTop);
});

test("virtual_rows_measured_shorter_than_they_were_guessed_leave_no_room_held_at_the_end", () => {
  const items = list(0, 100);
  const v = made(new Virtual({ gap: GAP, overscan: 300 }));
  v.setItems(items);
  v.measured(v.layout().rows.map((r) => [r.key, 60] as const));
  v.measured(v.layout().rows.map((r) => [r.key, 60] as const));
  const l = v.layout();
  assert.equal(l.after, 0);
  assert.equal(l.scrollTop, l.total - 600);
  assert.equal(l.rows.at(-1)!.index, 99);
});

test("virtual_a_message_come_is_followed_to_its_top_and_read_from_there_when_longer_than_the_pane", () => {
  let items = list(0, 30);
  const v = made(new Virtual({ gap: GAP, overscan: 300 }));
  v.setItems(items);
  items = [...items, { key: "m:30", estimate: 2000 }];
  v.setItems(items);
  v.follow("m:30");
  assert.equal(v.offsetOf("m:30"), 12);
  assert.deepEqual(v.mode, { kind: "read", key: "m:30", offset: 12 });
  // What comes after does not take the reader away.
  v.setItems([...items, ...list(31, 33)]);
  assert.equal(v.offsetOf("m:30"), 12);
});

test("virtual_following_what_came_below_the_pane_is_made_down_to_the_list_s_end", () => {
  let items = list(0, 30);
  const v = made(new Virtual({ gap: GAP, overscan: 100 }));
  v.setItems(items);
  v.measured(v.layout().rows.map((r) => [r.key, 100] as const));
  // A long message of the reader's own, its agent's activity after it: the pane not there yet (it glides), both made.
  v.glide(true);
  items = [...items, { key: "o:1", estimate: 2000 }, { key: "a:agent", estimate: 24 }];
  v.setItems(items);
  v.follow("a:agent");
  const rows = v.layout().rows.map((r) => r.key);
  assert.ok(rows.includes("o:1") && rows.includes("a:agent"), rows.join(" "));
  // To the end, where the activity is: not held at the long message's top.
  assert.equal(v.target(), v.layout().total - 600);
  // The reader gone up, only what is near the pane.
  v.scrolled(500);
  assert.ok(!v.layout().rows.some((r) => r.key === "a:agent"));
});

test("virtual_a_window_short_of_the_end_is_never_followed", () => {
  const items = list(0, 100);
  const v = made(new Virtual({ gap: GAP, overscan: 300 }));
  v.setShort(true);
  v.setItems(items);
  assert.equal(v.mode.kind, "read");
  v.scrolled(100 * 100 + 99 * GAP - 600);
  assert.equal(v.mode.kind, "read");
  v.follow();
  assert.equal(v.mode.kind, "read");
});

test("virtual_a_pinned_item_stays_made_out_of_view_with_the_room_between", () => {
  const items = list(0, 200);
  const v = made(new Virtual({ gap: GAP, overscan: 100 }));
  v.setItems(items);
  v.pin("m:3");
  const l = sound(v, items, 600, () => 100);
  assert.equal(l.rows[0]!.index, 3);
  assert.equal(l.rows[0]!.space, 3 * (100 + GAP));
  assert.ok(l.rows[1]!.space > 100, "the items not made between them are room above the next row");
});

test("virtual_more_is_made_ahead_of_a_scroll_under_way", () => {
  const items = list(0, 400);
  const v = made(new Virtual({ gap: GAP, overscan: 100, boost: 2000 }));
  v.setItems(items);
  v.scrolled(20000);
  v.rested();
  const still = v.layout().rows;
  v.scrolled(19400);
  const moving = v.layout().rows;
  assert.ok(19400 - (moving[0]!.index * (100 + GAP)) > 1500, "made well above the pane while it goes up");
  assert.ok(moving.length > still.length);
});

test("virtual_anything_done_in_any_order_keeps_the_reader_s_place_and_a_pane_with_items_in_it", () => {
  for (let seed = 1; seed <= 300; seed++) {
    const rnd = random(seed);
    const pick = (n: number) => Math.floor(rnd() * n);
    const real = new Map<string, number>();
    let height = 300 + pick(600);
    let width = 300 + pick(3) * 100;
    let first = 500;
    let last = 500 + 5 + pick(120);
    const estimate = () => 40 + pick(200);
    let items: Item[] = Array.from({ length: last - first }, (_, i) => ({ key: `m:${first + i}`, estimate: estimate() }));
    const v = new Virtual({ gap: GAP, overscan: pick(400), boost: 1000 });
    v.setViewport(height, width, pick(2) * 40);
    v.setItems(items);
    // An item not measured stands as tall as its estimate, by as much as those measured are off theirs.
    const heightOf = (key: string) => v.sizes.get(key)?.height ?? items.find((item) => item.key === key)!.estimate * v.scaled;
    // What the page last measured (`real`), and which of it the pane's width has made stale.
    const stale = new Set<string>();
    const measure = () => {
      const rows = v.layout().rows.filter(() => rnd() < 0.8).map((r) => {
        if (!real.has(r.key) || stale.delete(r.key)) real.set(r.key, 20 + pick(500));
        return [r.key, real.get(r.key)!] as const;
      });
      v.measured(rows);
    };
    for (let step = 0; step < 60; step++) {
      const mode = v.mode;
      const place = mode.kind === "read" ? v.offsetOf(mode.key) : undefined;
      const before = v.layout();
      const op = pick(9);
      let scrolled = false;
      if (op === 0) { const n = 1 + pick(40); first -= n; items = [...Array.from({ length: n }, (_, i) => ({ key: `m:${first + i}`, estimate: estimate() })), ...items]; v.setItems(items); }
      else if (op === 1) { const n = 1 + pick(5); items = [...items, ...Array.from({ length: n }, (_, i) => ({ key: `m:${last + i}`, estimate: estimate() }))]; last += n; v.setItems(items); }
      else if (op === 2) measure();
      else if (op === 3) { width = 300 + pick(3) * 100; height = 300 + pick(600); for (const key of real.keys()) if (rnd() < 0.5) stale.add(key); v.setViewport(height, width); }
      else if (op === 4) { scrolled = true; v.scrolled(Math.max(0, Math.min(before.total - height, before.scrollTop + pick(4000) - 2000))); if (rnd() < 0.5) v.rested(); }
      else if (op === 5 && items.length > 60) { const n = 1 + pick(30); if (rnd() < 0.5) { items = items.slice(n); first += n; } else { items = items.slice(0, -n); last -= n; } v.setItems(items, true); }
      else if (op === 6) { scrolled = true; v.goto(items[pick(items.length)]!.key, rnd() < 0.5 ? "start" : "center", pick(30)); }
      else if (op === 7) { scrolled = true; v.follow(); }
      else if (op === 8 && items.length > 3) { items = items.slice(0, -1); last -= 1; v.setItems(items); }
      let l: Layout;
      try { l = sound(v, items, height, heightOf); } catch (e) { throw new Error(`seed ${seed} step ${step} op ${op}: ${(e as Error).message}`); }
      // The reader's place: the same, unless the pane cannot scroll that far or their item left.
      const after = v.mode;
      if (!scrolled && mode.kind === "read" && after.kind === "read" && after.key === mode.key && place !== undefined) {
        const now = v.offsetOf(mode.key)!;
        const bound = l.scrollTop <= 1e-6 || l.scrollTop >= l.total - height - 1e-6;
        assert.ok(bound || Math.abs(now - mode.offset) < 1e-6, `seed ${seed} step ${step} op ${op}: the reader's item ${mode.offset} below the pane's top, now ${now}`);
      }
      if (after.kind === "follow" && after.to === null && !scrolled) {
        // Following: at the end of what there is, held room included.
        assert.ok(Math.abs(l.scrollTop - Math.max(0, l.total - height)) < 1e-6, `seed ${seed} step ${step} op ${op}: following, at ${l.scrollTop} of ${l.total - height}`);
      }
    }
  }
});

test("virtual_under_a_scroll_the_pane_is_not_moved_what_would_move_it_is_held_until_it_rests", () => {
  const items = list(0, 200);
  const v = made(new Virtual({ gap: GAP, overscan: 300 }));
  v.setItems(items);
  v.scrolled(10000);
  const a = v.mode;
  assert.equal(a.kind, "read");
  if (a.kind !== "read") return;
  const offset = v.offsetOf(a.key)!;
  const first = v.layout().rows[0]!;
  // A row above the reader's measured 150 taller: their item where it was, the pane not moved, the room above less.
  v.measured([[first.key, 250]]);
  let l = v.layout();
  assert.equal(l.scrollTop, 10000);
  assert.equal(l.drift, 150);
  assert.equal(l.rows[0]!.space, first.space - 150);
  assert.equal(v.offsetOf(a.key), offset);
  // At rest: the pane where it should be, the room back.
  v.rested();
  l = v.layout();
  assert.equal(l.scrollTop, 10150);
  assert.equal(l.drift, 0);
  assert.equal(v.offsetOf(a.key), offset);
  // The scroll goes on from where the pane is, whatever is held.
  v.scrolled(10100);
  v.measured([[v.layout().rows[0]!.key, 300]]);
  v.scrolled(9900);
  assert.equal(v.layout().scrollTop, 9900);
});

test("virtual_a_list_opening_makes_only_what_shows_the_rows_past_its_edges_once_asked", () => {
  const items = list(0, 200);
  const v = new Virtual({ gap: GAP, overscan: 300 });
  v.setViewport(600, 400);
  v.setItems(items);
  const first = v.layout().rows;
  assert.ok(first.length <= 6, `${first.length} rows as it opens`);
  v.widen();
  assert.ok(v.layout().rows.length > first.length);
});

test("virtual_sizes_are_kept_for_the_lists_lately_shown", () => {
  const a = sizesOf("a");
  a.set("m:1", { height: 10, width: 400 });
  for (let i = 0; i < 19; i++) sizesOf(`other ${i}`);
  assert.equal(sizesOf("a"), a);
  for (let i = 0; i < 20; i++) sizesOf(`more ${i}`);
  assert.notEqual(sizesOf("a"), a);
});

test("virtual_a_reader_looking_for_something_is_not_moved_by_what_comes_at_the_end", () => {
  let items = list(0, 50);
  const v = made(new Virtual({ gap: GAP, overscan: 300 }));
  v.setItems(items);
  v.measured(v.layout().rows.map((r) => [r.key, 180] as const));
  const at = v.layout().scrollTop;
  const kind = (): string => v.mode.kind;
  assert.equal(kind(), "follow");
  // Looking (a find bar open): at the end, yet what comes there is not followed.
  v.reads(true);
  assert.equal(kind(), "read");
  items = [...items, ...list(50, 53)];
  v.setItems(items);
  assert.equal(v.layout().scrollTop, at);
  // Nor is it by scrolling to the end, or going to its last item.
  v.measured(v.layout().rows.map((r) => [r.key, 180] as const));
  let l = v.layout();
  v.scrolled(l.total - 600);
  v.rested();
  assert.equal(kind(), "read");
  items = [...items, ...list(53, 54)];
  v.setItems(items);
  assert.equal(v.layout().scrollTop, l.total - 600);
  // Done looking at the end, it is followed again; short of it, the place is kept.
  v.measured(v.layout().rows.map((r) => [r.key, 180] as const));
  l = v.layout();
  v.scrolled(l.total - 600);
  v.rested();
  v.reads(false);
  assert.equal(kind(), "follow");
  v.reads(true);
  v.scrolled(1000);
  v.rested();
  v.reads(false);
  assert.equal(kind(), "read");
});

test("virtual_following_goes_once_to_where_what_closes_leaves_it_and_keeps_following", () => {
  const items = list(0, 30);
  const v = made(new Virtual({ gap: GAP, overscan: 300 }));
  v.setItems(items);
  v.measured(items.map((i) => [i.key, 100] as const));
  const end = v.layout().scrollTop;
  // The last row is going to be 60 shorter (something in it closing): the pane is sent there at once, gliding down,
  // still as far as there is to go now; a message come meanwhile, followed from its top, as it closes.
  v.glide(true);
  v.measured([["m:29", 100, 40]]);
  assert.equal(v.target(), end - 60);
  assert.equal(v.where, end, "not ahead of what is there yet");
  const more = [...items, { key: "m:30", estimate: 40 }];
  v.setItems(more);
  v.measured([["m:30", 40]]);
  v.follow("m:30");
  assert.equal(v.target(), end - 60 + 40 + GAP);
  // Step by step there, as it closes: each row's share closed, the pane placed on toward where it goes.
  for (let h = 100; h > 40; h -= 10) {
    v.measured([["m:29", h, 40]]);
    v.place(v.where + (v.target() - v.where) / 2);
  }
  v.measured([["m:29", 40]]);
  v.place(v.target());
  assert.equal(v.mode.kind, "follow", "the message come is short: the list goes on following its end");
  assert.equal(v.where, v.target());
  // What the activity below went along with: the closing, all of it.
  assert.equal(v.closedBefore("m:30"), 60);
});
