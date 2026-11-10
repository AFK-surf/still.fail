// Resource progress shared by every preview transport (the `previewLoad` topic). No response bodies
// are kept.
import { topicKey, type Topic } from "./protocol.ts";
import { Marks } from "./reactive.ts";

// deno-lint-ignore no-explicit-any
type J = any;

type Page = { rows: J[]; total: number; finished: number; failed: number };
export type LoadKey = [Topic, number];

export class Loads {
  #next = 0;
  readonly #pages = new Map<string, Page>();
  /// What reads a page's progress (its topic) is made again as it changes.
  readonly #seen = new Marks();

  start(station: string, port: number, method: string, path: string, headers: [string, string][], now: number): LoadKey {
    const topic: Topic = { topic: "previewLoad", station, port };
    const key = topicKey(topic);
    const id = ++this.#next;
    if (this.#pages.size >= 32 && !this.#pages.has(key)) {
      const first = this.#pages.keys().next().value;
      if (first !== undefined) this.#pages.delete(first);
    }
    let page = this.#pages.get(key);
    if (!page) {
      page = { rows: [], total: 0, finished: 0, failed: 0 };
      this.#pages.set(key, page);
    }
    const header = (name: string) => headers.find(([k]) => k.toLowerCase() === name)?.[1];
    const dest = header("sec-fetch-dest");
    const document = dest !== undefined ? dest === "document" || dest === "iframe" : (header("accept")?.includes("text/html") ?? false);
    if (document) {
      page = { rows: [], total: 0, finished: 0, failed: 0 };
      this.#pages.set(key, page);
    }
    page.total++;
    if (page.rows.length >= 200) {
      const i = page.rows.findIndex((r) => typeof r.ended === "number");
      if (i >= 0) page.rows.splice(i, 1);
    }
    page.rows.push({ id, method, path, since: now, status: null, ended: null, error: null });
    this.#seen.touch(key);
    return [topic, id];
  }

  head(key: LoadKey, status: number): void {
    const row = this.#pages.get(topicKey(key[0]))?.rows.find((r) => r.id === key[1]);
    if (row) row.status = status;
    this.#seen.touch(topicKey(key[0]));
  }

  end(key: LoadKey, now: number, error: string | null): void {
    const page = this.#pages.get(topicKey(key[0]));
    if (!page) return;
    const row = page.rows.find((r) => r.id === key[1] && r.ended === null);
    if (!row) return;
    row.ended = now;
    row.error = error;
    page.finished++;
    if (error !== null || (typeof row.status === "number" && row.status >= 400)) page.failed++;
    this.#seen.touch(topicKey(key[0]));
  }

  value(topic: Topic): J {
    this.#seen.read(topicKey(topic));
    const page = this.#pages.get(topicKey(topic));
    if (!page) return { percent: 0, total: 0, finished: 0, failed: 0, resources: [] };
    return { percent: page.total === 0 ? 0 : Math.trunc((page.finished * 100) / page.total), total: page.total, finished: page.finished, failed: page.failed, resources: structuredClone(page.rows) };
  }
}
