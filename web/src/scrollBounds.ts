/** Safari's rubber-band displacement is not a scroll position to save or correct. The one-pixel allowance at the
 * end accommodates fractional scrollTop against integer scrollHeight/clientHeight. */
export function outsideScroll(el: HTMLElement): boolean {
  // Resolve pending layout before reading the position: shrinking content can clamp scrollTop during that layout.
  const end = Math.max(0, el.scrollHeight - el.clientHeight);
  const top = el.scrollTop;
  return top < 0 || top > end + 1;
}

/** Follow output without repeatedly writing the same endpoint, or fighting a browser's boundary animation. */
export function scrollToEnd(el: HTMLElement): void {
  if (outsideScroll(el)) return;
  const end = Math.max(0, el.scrollHeight - el.clientHeight);
  if (Math.abs(end - el.scrollTop) > 1) el.scrollTop = end;
}
