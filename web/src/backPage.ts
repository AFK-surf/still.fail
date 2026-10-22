// Back a page of this app's own, past what frames in it left in the browser's history.

/** The browser's Navigation API, where there is one (Safari from 26.2). */
interface HistoryNav {
  currentEntry: { index: number } | null;
  entries(): { key: string; sameDocument?: boolean }[];
  traverseTo(key: string): { finished: Promise<unknown> };
}

/** A back of this page on its way: another asked meanwhile (a second tap, Safari's swipe and the page's own) is it. */
let going = false;

/**
 * Back to the page before this one. The browser's back steps a frame's history first: a service's page in the preview
 * that moved itself (a link, its own routes) left entries of its own after this page's, and back went back through
 * those, the page staying where it was. The Navigation API sees only this document's entries, and goes to the one
 * before past whatever the frames left; without it, `fallback` (the browser's back).
 *
 * The entries before this page loaded (it was loaded again: pulled down, a newer build) are still in the history, and
 * going to one loads the whole page again, from its splash: `outside` instead when the one before is such an entry.
 */
export function backPage(fallback: () => void, outside: () => void) {
  if (going) return;
  const nav = (window as { navigation?: HistoryNav }).navigation;
  const at = nav?.currentEntry?.index ?? -1;
  const before = at > 0 ? nav!.entries()[at - 1] : undefined;
  if (!before) return fallback();
  if (before.sameDocument === false) return outside();
  going = true;
  // A back another move cut short (a page pushed meanwhile) has nothing more to do.
  nav!.traverseTo(before.key).finished.catch(() => {}).finally(() => { going = false; });
}
