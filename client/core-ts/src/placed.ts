// The files an agent's message places in its text (`![](shot.png)`, `[the report](report.pdf)`), by the file name its
// links and images give, and a chat's images in the order its page shows them (the preview steps through those). The
// core decides both (views.ts drawn()): the web draws a message's files by them, and the Android app the same.

/** The file a link or image in the text names, by its file name (the last part of its path): `shot.png`, `/w/shot.png`, `ember-file://…/shot.png`. */
export function nameOf(url: string): string {
  let u = url.trim().replace(/^(ember-)?file:\/\//, "");
  try { u = decodeURIComponent(u); } catch { /* kept as written */ }
  return u.slice(u.lastIndexOf("/") + 1);
}

/**
 * Which of a message's files its text places, by the name its links and images give, in the order it names them, and
 * the rest, shown below the text. Code is passed over: a name in it places nothing.
 */
export function placeFiles<F extends { name: string }>(text: string, files: F[] | undefined): { placed: Map<string, F>; rest: F[] } {
  const placed = new Map<string, F>();
  if (!files?.length || !text) return { placed, rest: files ?? [] };
  const prose = text.replace(/^ {0,3}(`{3,}|~{3,})[^]*?(^ {0,3}\1|(?![^]))/gm, "").replace(/(`+)[^]*?\1/g, "");
  for (const [, url] of prose.matchAll(/\]\(\s*<?([^)\s>]+)>?(?:\s+(?:"[^"]*"|'[^']*'))?\s*\)/g)) {
    const name = nameOf(url!);
    const file = files.find((f) => f.name === name);
    if (file) placed.set(name, file);
  }
  const used = new Set<F>(placed.values());
  return { placed, rest: files.filter((f) => !used.has(f)) };
}

const IMAGE = /\.(png|jpe?g|gif|webp|svg|avif|bmp|ico)$/i;

/** A file the preview shows as an image (and steps between). */
export const isImage = (name: string): boolean => IMAGE.test(name);
