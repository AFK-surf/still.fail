// What a row of a message list is going to stand at, while something in it closes in one motion (settling.tsx): told to
// the list (virtual/list.tsx reads it as the row's height), so the pane goes once, along with it, to where it will be,
// instead of after each frame's height: following its end, it went up for what came below and was then pulled down,
// frame by frame, as the box above closed.

/** How many closings each row has under way. */
const under = new WeakMap<HTMLElement, number>();

/**
 * `box` closing by `by` pixels in its row of a list (the element with `data-vk` round it): the row is told to the list
 * at its height to come (`data-settles-to`) until what this answers is called, as the closing ends or is undone. Two at
 * once in a row add up.
 */
export function closing(box: HTMLElement, by: number): () => void {
  const row = box.closest<HTMLElement>("[data-vk]");
  if (!row || by < 0.5) return () => {};
  const now = row.dataset.settlesTo !== undefined ? Number(row.dataset.settlesTo) : row.getBoundingClientRect().height;
  row.dataset.settlesTo = String(Math.max(0, now - by));
  under.set(row, (under.get(row) ?? 0) + 1);
  let over = false;
  return () => {
    if (over) return;
    over = true;
    const left = (under.get(row) ?? 1) - 1;
    if (left > 0) return void under.set(row, left);
    under.delete(row);
    delete row.dataset.settlesTo;
  };
}

