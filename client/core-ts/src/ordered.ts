// Searches in sorted numbers, without walking the history a caller already holds.
export function lowerBound(values: readonly number[], n: number): number {
  return bound(values, n, false);
}
export function upperBound(values: readonly number[], n: number): number {
  return bound(values, n, true);
}
function bound(values: readonly number[], n: number, after: boolean): number {
  let lo = 0, hi = values.length;
  while (lo < hi) {
    const mid = lo + Math.floor((hi - lo) / 2);
    if (values[mid]! < n || (after && values[mid] === n)) lo = mid + 1;
    else hi = mid;
  }
  return lo;
}
