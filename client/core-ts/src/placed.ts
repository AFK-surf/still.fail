// The files an agent's message places in its text (`![](shot.png)`, `[the report](report.pdf)`), by the file name its
// links and images give (views.ts drawn(): a message's `placed`), and the images beside one a chat's preview shows, in
// the order its page shows them (the `imageNear` view): told only for the one open, not the chat's every image.

/** The file a link or image in the text names, by its file name (the last part of its path): `shot.png`, `/w/shot.png`, `file:///w/shot.png`. */
export function nameOf(url: string): string {
  let u = url.trim().replace(/^file:\/\//, "");
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

// deno-lint-ignore no-explicit-any
type J = any;

/**
 * A chat's page (drawn: its files' `owner`, its messages' `placed`): the images before and after the one at `path`, in
 * the order the page shows them. `at` identifies the occurrence in a message when the same file is shown more than once.
 */
export function near(chat: J, path: string, at?: string): { before?: J; after?: J; beforeAt?: string; afterAt?: string; index?: number; count: number } {
  const images: { file: J; at: string }[] = [];
  const add = (files: J[], place: string) => {
    for (const f of files) if (f !== null && typeof f === "object" && typeof f.name === "string" && typeof f.owner === "string" && isImage(f.name)) images.push({ file: f, at: place });
  };
  const message = (m: J, row: string) => {
    const files: J[] = Array.isArray(m?.attachments) ? m.attachments : [];
    const quotes: J[] = Array.isArray(m?.quotes) ? m.quotes : [];
    const quoted = new Set<string>();
    quotes.forEach((q, i) => {
      if (typeof q?.file !== "string" || q.file === "") return;
      quoted.add(q.file);
      const file = files.find((f) => f?.name === q.file);
      if (file !== undefined) add([file], `${row}/q:${i}`);
    });
    // Quotes precede the files placed in the text, then the remaining files below it.
    const beside = files.filter((f) => !quoted.has(f?.name));
    const placed: string[] = Array.isArray(m?.placed) ? m.placed : [];
    const first = placed.flatMap((n) => beside.filter((f) => f?.name === n).slice(0, 1));
    add(first, `${row}/f`);
    add(beside.filter((f) => !first.includes(f)), `${row}/f`);
  };
  for (const m of Array.isArray(chat?.messages) ? chat.messages : []) {
    const row = typeof m?.outgoing === "string" && m.outgoing !== "" ? `o:${m.outgoing}` : `m:${m?.ts ?? ""}`;
    message(m, row);
  }
  for (const o of Array.isArray(chat?.outbox) ? chat.outbox : []) message(o, `o:${o?.id ?? ""}`);
  const index = images.findIndex((item) => item.file.path === path && (at === undefined || item.at === at));
  if (index < 0) return { count: images.length };
  const before = images[index - 1];
  const after = images[index + 1];
  return {
    ...(before === undefined ? {} : { before: before.file, ...(at === undefined ? {} : { beforeAt: before.at }) }),
    ...(after === undefined ? {} : { after: after.file, ...(at === undefined ? {} : { afterAt: after.at }) }),
    index, count: images.length,
  };
}
