/**
 * The yellow "at work" ring as a background image for a `size`px box: a faint full track and a solid arc with round
 * ends, its gap on the right (a border can only cut the gap square). The round ends reach half the stroke past the
 * arc, so the arc is shortened by as much to keep the gap a quarter. Turned by the box's spin animation.
 */
export function busyRing(size: number, stroke = 2): string {
  const c = size / 2, r = c - stroke / 2;
  const a = (45 + (stroke / 2 / r) * 180 / Math.PI) * Math.PI / 180;
  const at = (t: number) => `${(c + r * Math.cos(t)).toFixed(3)} ${(c + r * Math.sin(t)).toFixed(3)}`;
  const svg = `<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 ${size} ${size}' fill='none' stroke='%23f2b01e' stroke-width='${stroke}'>`
    + `<circle cx='${c}' cy='${c}' r='${r}' stroke-opacity='.25'/>`
    + `<path d='M${at(a)}A${r} ${r} 0 1 1 ${at(-a)}' stroke-linecap='round'/></svg>`;
  return `url("data:image/svg+xml,${svg}")`;
}
