// What a topic's value looks like as it goes out (docs/core-ts.md, rule 7): decorated (present.ts) and put through its
// shape (conform.ts), item by item for its keyed lists (collections.ts). An item that is as it was (the same object a
// view keeps for it, or one equal to it) within the same minute (times in words are a minute's) is the very object
// that went out before: not copied, decorated, shaped or compared again, so a list of 2000 rows with one changed costs
// one row. What went out is frozen in `shaped` (util.ts): nothing changes it after.
import { type Spec, keyOf, specOf } from "./collections.ts";
import { conformTy, type Ty } from "./conform.ts";
import * as present from "./present.ts";
import type { Topic } from "./protocol.ts";
import { equal, isObject, shaped } from "./util.ts";

type Memo = { raw: unknown; minute: number; out: unknown };

/// One topic's items as they last went out, by their place and key.
export class Output {
  #memo = new Map<string, Memo>();

  /// The value as it goes out, or the shape's error (`path: what`).
  shape(topic: Topic, raw: unknown, c: present.Clock, shapes: boolean): { ok: unknown } | { error: string } {
    const spec = specOf(topic);
    const ty = shapes ? present.shapeOf(topic) : undefined;
    const minute = Math.floor(c.now / 60_000);
    const next = new Map<string, Memo>();
    try {
      const skeleton = spec ? this.#build(topic, raw, spec, ty, "", "", c, minute, next) : raw;
      const v = present.decorate(topic, copy(skeleton), c);
      const out = ty === undefined ? { ok: v } : conformTy(ty, v);
      if ("ok" in out) this.#memo = next;
      return out;
    } catch (e) {
      if (e instanceof ItemWrong) return { error: e.message };
      throw e;
    }
  }

  /// The value with each keyed item put as it goes out.
  #build(topic: Topic, raw: unknown, spec: Spec, ty: Ty | undefined, at: string, path: string, c: present.Clock, minute: number, next: Map<string, Memo>): unknown {
    if (spec.key && Array.isArray(raw)) {
      const itemTy = ty === undefined ? undefined : present.itemOf(ty);
      return raw.map((item, i) => {
        const here = `${path}[${i}]`;
        const place = `${at}\u0001${JSON.stringify(keyOf(item, spec.key!))}`;
        // Items holding keyed lists of their own are put together anew around them (cheap: their items are done).
        const leaf = !spec.item;
        const was = leaf ? this.#memo.get(place) : undefined;
        if (was && was.minute === minute && ((was.raw === item && Object.isFrozen(item)) || equal(was.raw, item))) {
          next.set(place, was);
          return was.out;
        }
        const inner = spec.item ? this.#build(topic, item, spec.item, itemTy, place, here, c, minute, next) : item;
        const decorated = present.decorateItem(topic, copy(inner), c);
        let out = decorated;
        if (itemTy !== undefined) {
          const shapedItem = conformTy(itemTy, decorated, here);
          if ("error" in shapedItem) throw new ItemWrong(shapedItem.error);
          out = shapedItem.ok;
        }
        freeze(out);
        // What it was made from, as it was: a frozen item is kept as it is, another copied (it may be changed in place).
        if (leaf) next.set(place, { raw: Object.isFrozen(item) ? item : structuredClone(item), minute, out });
        return out;
      });
    }
    if (spec.fields && isObject(raw)) {
      const out: Record<string, unknown> = { ...raw };
      for (const [field, inner] of Object.entries(spec.fields)) {
        if (field in raw) out[field] = this.#build(topic, raw[field], inner, ty === undefined ? undefined : present.fieldOf(ty, field), `${at}/${field}`, path === "" ? field : `${path}.${field}`, c, minute, next);
      }
      return out;
    }
    return raw;
  }
}

class ItemWrong extends Error {}

/// A copy to decorate, sharing what already went out.
function copy(v: unknown): unknown {
  if (v === null || typeof v !== "object") return v;
  if (shaped.has(v)) return v;
  if (Array.isArray(v)) return v.map(copy);
  const out: Record<string, unknown> = {};
  for (const k of Object.keys(v)) out[k] = copy((v as Record<string, unknown>)[k]);
  return out;
}

function freeze(v: unknown): void {
  if (v !== null && typeof v === "object") shaped.add(v);
}
