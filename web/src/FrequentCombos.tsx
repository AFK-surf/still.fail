// The core ranks, filters and labels these; the view only offers its choices.
import type { FrequentCombo } from "./core/shapes.ts";
import type { PickPatch } from "./pick.ts";
import * as css from "./FrequentCombos.css.ts";

export function FrequentCombos({ items, onPick }: { items: FrequentCombo[] | undefined; onPick(patch: PickPatch): void }) {
  if (!items?.length) return null;
  return <div className={css.frequent} aria-label="常用搭配" data-made-leave="fade">
    <span className={css.label}>常用</span>
    <div className={css.choices}>{items.map((c) => <button type="button" key={`${c.runtime}:${c.model}:${c.effort ?? ""}`}
      className={css.combo} aria-pressed={c.selected} onClick={() => onPick({ model: c.model, runtime: c.runtime, effort: c.effort ?? null })}>
      {c.label}
    </button>)}</div>
  </div>;
}
