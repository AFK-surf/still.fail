// What a topic's value looks like as it goes out (rule 7): decorated (present.ts) and put through its
// shape (conform.ts), item by item for its keyed lists (collections.ts). An item that is as it was (the same object a
// view keeps for it, or one equal to it) is the very object that went out before: not copied, decorated, shaped or
// compared again, so a list of 2000 rows with one changed costs one row. Each is made in a computed (reactive.ts) that
// reads the clock at the grain its times in words change by (present.ts `clockAt`): a new minute makes again only the
// items that said a minute's words, one of days ago only at local midnight. What went out is marked in `shaped`
// (util.ts), and frozen when shared values are checked: nothing changes it after. A value given again as the very
// object last made, with nothing it was made of changed since, is what went out, not made again at all (#last).
import type { Product } from "../../i18n/brand.ts";
import * as brand from "./brand.ts";
import { type Spec, specOf, textOf } from "./collections.ts";
import { conformTy, keptShape, type Ty } from "./conform.ts";
import { current as lang } from "./i18n.ts";
import * as present from "./present.ts";
import type { Topic } from "./protocol.ts";
import { computed, observe, type Derived } from "./reactive.ts";
import { equal, isObject, shaped, sharedValue } from "./util.ts";
import { walked, work } from "./work.ts";

/// An item as it goes out: what it was made from, and what is made of it.
type Memo = { raw: unknown; out: Derived<unknown> };

/// One topic's items as they last went out, by their place and key.
export class Output {
  #memo = new Map<string, Memo>();
  /// The clock the items are made for now (what their computeds read when they are made again).
  #c: present.Clock = { now: 0, offsetMin: 0 };
  /// What keeps the items' computeds (and so what they made) while they are the ones that went out.
  #keep: (() => void) | null = null;
  /// Told as what went out is out of date (the clock moved on past what an item's words say): it goes out again.
  readonly #again: () => void;
  /// The value last made whole and what it was made of (`said`: what its words are said in beyond it), while what
  /// keeps it holds; and whether nothing it read has changed since (#fresh), cleared as its watch fires (an item's computed,
  /// the clock's signals, any other tracked read of its decoration). Given the same `raw` again it is what goes out:
  /// `profiles`, no keyed items, was copied, decorated and shaped whole again each time a dependency was touched and
  /// gave the same value, 5 ms in Hermes on a Mac Studio (2026-11-11).
  #last: { topic: Topic; raw: unknown; shapes: boolean; said: string; product: Product; out: { ok: unknown } } | null = null;
  #fresh = false;

  constructor(again: () => void = () => {}) {
    this.#again = again;
  }

  /// What went out last where shaping `raw` again (`c`, `shapes`) makes the same: its raw the very object, with the same
  /// shape and words, and nothing its making read changed since. Else null.
  kept(topic: Topic, raw: unknown, c: present.Clock, shapes: boolean): { ok: unknown } | null {
    const last = this.#last;
    if (last === null || !this.#fresh || last.raw !== raw || last.topic !== topic || last.shapes !== shapes) return null;
    return last.said === said(topic, c) && last.product === brand.current() ? last.out : null;
  }

  /// The value as it goes out, or the shape's error (`path: what`).
  shape(topic: Topic, raw: unknown, c: present.Clock, shapes: boolean): { ok: unknown } | { error: string } {
    this.#c = c;
    // (a minute or day moved on clears #fresh as it is set, where the last value read it)
    present.clockAt(c);
    const kept = this.kept(topic, raw, c, shapes);
    if (kept !== null) return kept;
    this.#last = null;
    this.#fresh = true;
    work.shapes++;
    const spec = specOf(topic);
    const ty = shapes ? present.shapeOf(topic) : undefined;
    const next = new Map<string, Memo>();
    let out: { ok: unknown } | { error: string } = { error: "" };
    try {
      // (made under a watch of its own, the old one let go after: the items' computeds kept as they were, those of
      // items no longer there let go with it)
      const was = this.#keep;
      const keep = observe(() => {
        const input = topic.topic === "chat" && topic.compact === true ? compactChat(raw) : raw;
        const skeleton = spec ? this.#build(topic, input, spec, ty, "", "", next) : input;
        // (as it was made beside it, where it was: the accounts' rows beside their whole value, views.ts `profiles`)
        const made = ty === undefined ? undefined : keptShape(skeleton, ty);
        if (made !== undefined) out = { ok: made };
        else {
          work.wholeShaped++;
          const v = present.decorate(topic, copy(skeleton), c);
          out = ty === undefined ? { ok: v } : conformTy(ty, v);
        }
      }, () => {
        this.#fresh = false;
        this.#again();
      });
      if ("ok" in out) {
        this.#keep = keep;
        was?.();
        this.#memo = next;
        sharedValue(out.ok);
        this.#last = { topic, raw, shapes, said: said(topic, c), product: brand.current(), out };
      } else keep();
      return out;
    } catch (e) {
      if (e instanceof ItemWrong) return { error: e.message };
      throw e;
    }
  }

  /// Lets go of what it keeps (its topic gone).
  stop(): void {
    this.#keep?.();
    this.#keep = null;
    this.#memo = new Map();
    this.#last = null;
  }

  /// The value with each keyed item put as it goes out.
  #build(topic: Topic, raw: unknown, spec: Spec, ty: Ty | undefined, at: string, path: string, next: Map<string, Memo>): unknown {
    if (spec.key && Array.isArray(raw)) {
      walked.built += raw.length;
      const itemTy = ty === undefined ? undefined : present.itemOf(ty);
      return raw.map((item, i) => {
        const here = `${path}[${i}]`;
        const place = `${at}\u0001${textOf(item, spec.key!)}`;
        // Items holding keyed lists of their own are put together anew around them (cheap: their items are done).
        const leaf = !spec.item;
        const was = leaf ? this.#memo.get(place) : undefined;
        // (the store keeps what did not change as the same object, never changed after: collections.ts share)
        if (was && (was.raw === item || equal(was.raw, item))) {
          next.set(place, was);
          return was.out.get();
        }
        const inner = spec.item ? this.#build(topic, item, spec.item, itemTy, place, here, next) : item;
        const made = computed(() => {
          // Decorated as it is, not a copy of it: an item's decoration (present.ts `decorateItem`: `session`, `times`)
          // makes a new object of what it puts something in and never writes on what it is given. A copy of each was
          // 1.3 ms of the 52 items of a chat list's first page in Hermes on a Mac Studio (2026-11-11).
          const decorated = present.decorateItem(topic, inner, this.#c);
          let out = decorated;
          if (itemTy !== undefined) {
            // (as it was made beside it, where it was: a chat list's row kept beside its record, conform.ts shapedBeside)
            const made = keptShape(decorated, itemTy);
            if (made !== undefined) out = made;
            else {
              work.conformed++;
              const shapedItem = conformTy(itemTy, decorated, here);
              if ("error" in shapedItem) throw new ItemWrong(shapedItem.error);
              out = shapedItem.ok;
            }
          }
          // (what goes out is marked as gone out, which other values that hold it take it as, shaped: never the item
          // itself, where nothing was put in it nor shaped of it, no shape or one of `Value`: a copy of it, as before)
          if (out === inner && !shaped.has(inner)) out = copy(inner);
          freeze(out);
          return out;
        });
        // What it was made from: the item itself (a store's value is never changed in place: frozen where that is checked).
        if (leaf) next.set(place, { raw: item, out: made });
        work.shaped++;
        const out = made.get();
        return out;
      });
    }
    if (spec.fields && isObject(raw)) {
      const out: Record<string, unknown> = { ...raw };
      for (const [field, inner] of Object.entries(spec.fields)) {
        if (field in raw) out[field] = this.#build(topic, raw[field], inner, ty === undefined ? undefined : present.fieldOf(ty, field), `${at}/${field}`, path === "" ? field : `${path}.${field}`, next);
      }
      return out;
    }
    return raw;
  }
}

class ItemWrong extends Error {}

/// What a value's words are said in that its making does not track: the language and the product's name (module
/// state, read as words are made), and the minute (with the offset from UTC) for a topic that says times in words.
/// Its decoration reads the clock's signals for the minute or the day, but some of it reads `c.now` alone (a job's
/// age, jobs.ts `shown`; a file's day, drive.ts): made again in another minute, as the clock's signals would say.
function said(topic: Topic, c: present.Clock): string {
  return `${lang()}\u0001${brand.name()}\u0001${present.ticks(topic) ? `${Math.floor(c.now / 60_000)}/${c.offsetMin}` : ""}`;
}

/// A page needs its agents' identities and status, not their jobs. A client that asks for the compact chat reads them
/// through their own topic (`chatJobs`); the full value stays available inside the core and to older clients. (An
/// agent's turns and threads go out to neither: its shape, ChatAgent, has them not.) Invalid fields are left for the
/// normal shape check to report.
function compactChat(value: unknown): unknown {
  if (!isObject(value) || !Array.isArray(value.agents)) return value;
  return {
    ...value,
    agents: value.agents.map((agent: unknown) => {
      if (!isObject(agent)) return agent;
      const out = { ...agent };
      if (Array.isArray(agent.jobs)) {
        out.jobs = [];
        out.hasJobs = agent.jobs.length > 0;
      }
      return out;
    }),
  };
}

/// A copy to decorate, sharing what already went out.
function copy(v: unknown): unknown {
  if (v === null || typeof v !== "object") return v;
  walked.copied++;
  if (shaped.has(v)) return v;
  if (Array.isArray(v)) return v.map(copy);
  const out: Record<string, unknown> = {};
  for (const k of Object.keys(v)) out[k] = copy((v as Record<string, unknown>)[k]);
  return out;
}

/// Kept as it went out: marked (`shaped`), and frozen when shared values are checked (util.ts `sharedValue`).
function freeze(v: unknown): void {
  if (v !== null && typeof v === "object") shaped.add(sharedValue(v));
}
