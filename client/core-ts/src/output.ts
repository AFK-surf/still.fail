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

/// An item of a keyed list as it goes out: what it was made from, its key, what is made of it, and the keyed lists it
/// holds as they went out (an item holding them: a chat list's day); `still`, what was made where making it read
/// nothing that can change (no time in words, no list of its own): taken as it is, its computed not read again.
type Memo = { raw: unknown; key: string; out: Derived<unknown>; lists: Lists; still?: { out: unknown } };
/// A keyed list as it went out: the array it was made of, what is made of it (its items as they go out), and its
/// items by the object each was made of and by their key.
type Made = { raw: unknown[]; out: Derived<unknown[]>; byItem: Map<unknown, Memo>; byKey: Map<string, Memo> };
/// The keyed lists of a value or of an item, by the fields that lead to each from it.
type Lists = Map<string, Made>;

/// One topic's keyed lists and their items as they last went out. (Its own: what one topic made of an object is never
/// another's, whose shape may differ.)
export class Output {
  #lists: Lists = new Map();
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
    const next: Lists = new Map();
    let out: { ok: unknown } | { error: string } = { error: "" };
    try {
      // (made under a watch of its own, the old one let go after: the items' computeds kept as they were, those of
      // items no longer there let go with it)
      const was = this.#keep;
      const keep = observe(() => {
        const input = topic.topic === "chat" && topic.compact === true ? compactChat(raw) : raw;
        const skeleton = spec ? this.#build(topic, input, spec, ty, "", "", this.#lists, next) : input;
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
        this.#lists = next;
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
    this.#lists = new Map();
    this.#last = null;
  }

  /// The value with each keyed list put as it goes out (`was`: its lists as they went out last; `now` takes them as they
  /// go out now). A list that is the very array that went out is what was made of it, its items not looked at; in
  /// another, an item that is the very object an item was made of is what was made of it (and an item holding keyed
  /// lists of its own, a chat list's day, is with them), one lookup by the object, nothing of it walked. Only the others
  /// are found by their key: one equal to the item made with that key is as it went, the rest are made.
  #build(topic: Topic, raw: unknown, spec: Spec, ty: Ty | undefined, path: string, fields: string, was: Lists, now: Lists): unknown {
    if (spec.key && Array.isArray(raw)) {
      const before = was.get(fields);
      if (before !== undefined && before.raw === raw) {
        walked.same++;
        now.set(fields, before);
        return before.out.get();
      }
      const itemTy = ty === undefined ? undefined : present.itemOf(ty);
      const byItem = new Map<unknown, Memo>();
      const byKey = new Map<string, Memo>();
      const memos = new Array<Memo>(raw.length);
      let looked = 0;
      for (let i = 0; i < raw.length; i++) {
        const item = raw[i];
        // (the store keeps what did not change as the same object, never changed after: collections.ts share)
        let m = before?.byItem.get(item);
        if (m === undefined) {
          looked++;
          const key = textOf(item, spec.key);
          const had = before?.byKey.get(key);
          const here = `${path}[${i}]`;
          if (spec.item) m = this.#holder(topic, item, key, spec.item, itemTy, here, had);
          else if (had !== undefined && (had.raw === item || equal(had.raw, item))) m = had;
          else m = { raw: item, key, out: this.#made(topic, () => item, itemTy, here), lists: new Map() };
        }
        memos[i] = m;
        byItem.set(item, m);
        byKey.set(m.key, m);
      }
      walked.same += raw.length - looked;
      walked.built += looked;
      // (gone out as it is, as its items: copy and fit take it so)
      const out = computed(() => {
        const items = new Array<unknown>(memos.length);
        for (let i = 0; i < memos.length; i++) {
          const m = memos[i]!;
          if (m.still !== undefined) items[i] = m.still.out;
          else {
            items[i] = m.out.get();
            if (m.out.deps === undefined) m.still = { out: items[i] };
          }
        }
        freeze(items);
        return items;
      });
      now.set(fields, { raw, out, byItem, byKey });
      return out.get();
    }
    if (spec.fields && isObject(raw)) {
      const out: Record<string, unknown> = { ...raw };
      for (const [field, inner] of Object.entries(spec.fields)) {
        if (field in raw) out[field] = this.#build(topic, raw[field], inner, ty === undefined ? undefined : present.fieldOf(ty, field), path === "" ? field : `${path}.${field}`, `${fields}/${field}`, was, now);
      }
      return out;
    }
    return raw;
  }

  /// An item holding keyed lists of its own (`spec`), made of `item`: its lists found in those of the item of its key
  /// before (`had`), and made again with it as one of their items is (the clock moving on past its words).
  #holder(topic: Topic, item: unknown, key: string, spec: Spec, itemTy: Ty | undefined, here: string, had: Memo | undefined): Memo {
    const m: Memo = { raw: item, key, out: undefined!, lists: had?.lists ?? new Map() };
    m.out = this.#made(topic, () => {
      const lists: Lists = new Map();
      const inner = this.#build(topic, item, spec, itemTy, here, "", m.lists, lists);
      m.lists = lists;
      return inner;
    }, itemTy, here);
    return m;
  }

  /// What an item goes out as, made of what `inner` gives.
  #made(topic: Topic, inner: () => unknown, itemTy: Ty | undefined, here: string): Derived<unknown> {
    work.shaped++;
    return computed(() => {
      const raw = inner();
      // Decorated as it is, not a copy of it: an item's decoration (present.ts `decorateItem`: `session`, `times`)
      // makes a new object of what it puts something in and never writes on what it is given. A copy of each was
      // 1.3 ms of the 52 items of a chat list's first page in Hermes on a Mac Studio (2026-11-11).
      const decorated = present.decorateItem(topic, raw, this.#c);
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
      if (out === raw && !shaped.has(raw as object)) out = copy(raw);
      freeze(out);
      return out;
    });
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
  if (shaped.has(v)) {
    walked.same++;
    return v;
  }
  walked.copied++;
  if (Array.isArray(v)) return v.map(copy);
  const out: Record<string, unknown> = {};
  for (const k of Object.keys(v)) out[k] = copy((v as Record<string, unknown>)[k]);
  return out;
}

/// Kept as it went out: marked (`shaped`), and frozen when shared values are checked (util.ts `sharedValue`).
function freeze(v: unknown): void {
  if (v !== null && typeof v === "object") shaped.add(sharedValue(v));
}
