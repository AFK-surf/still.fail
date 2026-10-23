// The scale a usage page's bars stand in (views/usage.ts, and the web's made-up station): with nothing else here, so
// what draws made-up days takes the same.

/// The scale a day's bar stands in, for the most a day cost (`max`): a round `top` at or above it, cut into two or
/// three steps of 1, 2, 2.5, 5 or 10 times a power of ten, each step's line said short (2k, 4k, 6k · 10, 20, 30 · 0.5, 1).
export function scale(max: number): { top: number; ticks: { value: number; label: string }[] } {
  if (!(max > 0)) return { top: 0, ticks: [] };
  const rough = max / 3;
  const mag = 10 ** Math.floor(Math.log10(rough));
  const step = [1, 2, 2.5, 5, 10].map((k) => k * mag).find((s) => s >= rough) ?? 10 * mag;
  const steps = Math.ceil(max / step - 1e-9);
  const ticks = Array.from({ length: steps }, (_, i) => {
    const value = Number(((i + 1) * step).toPrecision(12));
    return { value, label: short(value) };
  });
  return { top: ticks[ticks.length - 1]!.value, ticks };
}

/// A step's value said short: 500 · 2k · 2.5k · 1.2M · 0.5.
function short(v: number): string {
  const cut = (n: number) => String(Number(n.toFixed(1)));
  if (v >= 1e6) return `${cut(v / 1e6)}M`;
  if (v >= 1000) return `${cut(v / 1000)}k`;
  return v >= 1 ? String(Number(v.toFixed(1))) : String(Number(v.toPrecision(2)));
}
