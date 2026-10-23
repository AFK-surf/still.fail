// Names' places in the order people read them, by the language's own collation (Host.collate): for the hosts that run
// where Intl is whole, the page's worker and Node (the desktop app); never Hermes, which asks Java for it.
const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });

export function collate(names: readonly string[]): number[] {
  const order = names.map((n, i) => [n, i] as const).sort((a, b) => collator.compare(a[0], b[0]));
  const at = new Array<number>(names.length);
  let place = 0;
  order.forEach(([name, i], k) => {
    if (k > 0 && collator.compare(order[k - 1]![0], name) !== 0) place = k;
    at[i] = place;
  });
  return at;
}
