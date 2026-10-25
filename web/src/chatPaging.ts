/** The core keeps three pages and drops records at the opposite edge when another arrives. Extra lookahead is
 * safe only while the entire viewport is in the approaching half of that record window. Heights alone cannot say
 * this: one tall message may occupy the half of the screen whose records would be dropped. Unknown/folded rows
 * keep the ordinary one-screen trigger. */
export function chatPageAhead(edge: "top" | "bottom", first: number | undefined, last: number | undefined, visible: string[]): boolean {
  // station/topics.ts caps paged windows at 3 * 50 entries. A live window can grow beyond that before paging;
  // its midpoint no longer guarantees that the next bounded page keeps it, so use the ordinary trigger there.
  if (first === undefined || last === undefined || last - first >= 150 || !visible.length) return false;
  const middle = (first + last) / 2;
  return visible.every(key => {
    const match = /^m:(\d+)$/.exec(key);
    if (!match) return false;
    const seq = Number(match[1]);
    return seq >= first && seq <= last && (edge === "top" ? seq <= middle : seq >= middle);
  });
}
