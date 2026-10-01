// Private to one preview bridge (one station, port and frame). Synthetic Service Worker responses do not populate
// the browser's HTTP cache, so retain bounded static resources here, following the service's freshness/validators.
import type { Answer, Asked } from "./previewBridge.ts";

type Entry = Answer & { stored: number; lifetime: number; validate: boolean };
const MAX_BODY = 4 * 1024 * 1024;
const MAX_TOTAL = 32 * 1024 * 1024;
const MAX_ENTRIES = 256;
const directives = (value: string | null) => (value ?? "").toLowerCase().split(",").map((v) => v.trim());
const has = (parts: string[], name: string) => parts.some((p) => p === name || p.startsWith(name + "="));

function staticResponse(answer: Pick<Answer, "status" | "headers">) {
  const h = new Headers(answer.headers);
  const type = (h.get("content-type") ?? "").split(";")[0]!.trim().toLowerCase();
  return answer.status === 200 && /^(text\/(css|javascript)|application\/(javascript|x-javascript|wasm)|image\/[^;]+|font\/[^;]+)$/.test(type) &&
    !has(directives(h.get("cache-control")), "no-store") && !h.has("set-cookie") && !h.get("vary")?.split(",").some((v) => v.trim() === "*");
}

export class PreviewCache {
  private entries = new Map<string, Entry>();
  private size = 0;
  private generation = 0;

  clear() { this.entries.clear(); this.size = 0; this.generation++; }

  prepare(asked: Asked) {
    if (!["GET", "HEAD"].includes(asked.method)) this.clear();
    const headers = new Headers(asked.headers);
    const policy = directives(headers.get("cache-control"));
    // Do not combine range/explicit conditional requests, authenticated requests, or the caller's own cache policy.
    const eligible = asked.method === "GET" && asked.cache !== "no-store" && !has(policy, "no-store") &&
      !["range", "if-range", "if-none-match", "if-modified-since", "authorization", "cookie"].some((h) => headers.has(h));
    // All request headers are part of the key, a conservative superset of Vary. No cache is shared across frames.
    const key = JSON.stringify([asked.path, [...headers].sort(([a], [b]) => a.localeCompare(b))]);
    const entry = eligible ? this.entries.get(key) : undefined;
    const force = asked.cache === "reload" || asked.cache === "no-cache" || has(policy, "no-cache") ||
      has(policy, "max-age") || headers.get("pragma")?.toLowerCase().includes("no-cache");
    const fresh = entry && !force && !entry.validate && Date.now() - entry.stored < entry.lifetime;
    const previous = entry && asked.cache !== "reload" ? entry : undefined;
    const conditional = new Headers(headers);
    if (previous && !fresh) {
      const saved = new Headers(previous.headers);
      if (saved.has("etag")) conditional.set("if-none-match", saved.get("etag")!);
      else if (saved.has("last-modified")) conditional.set("if-modified-since", saved.get("last-modified")!);
    }
    const generation = this.generation;
    return {
      fresh: fresh ? { status: entry.status, headers: entry.headers, body: entry.body.slice() } : undefined,
      headers: [...conditional] as [string, string][],
      // Only a conditional request made by this cache can turn 304 into a complete response.
      revalidated: (response: Pick<Answer, "status" | "headers">): Answer | undefined => {
        if (response.status !== 304 || !previous || (!conditional.has("if-none-match") && !conditional.has("if-modified-since"))) return;
        const merged = new Headers(previous.headers);
        for (const [name, value] of response.headers) merged.set(name, value);
        return { status: 200, headers: [...merged], body: previous.body.slice() };
      },
      save: (answer: Answer) => {
        if (!eligible || generation !== this.generation) return;
        this.remove(key);
        const h = new Headers(answer.headers);
        const cc = directives(h.get("cache-control"));
        if (!staticResponse(answer) || answer.body.length > MAX_BODY) return;
        const age = Math.max(0, Number(h.get("age") ?? 0)) * 1000;
        const date = Date.parse(h.get("date") ?? "");
        const currentAge = Math.max(Number.isFinite(age) ? age : Infinity, Number.isFinite(date) ? Date.now() - date : 0);
        const maxAge = cc.find((p) => /^max-age="?\d+"?$/.test(p));
        const lifetime = maxAge ? Number(maxAge.split("=")[1]!.replaceAll('"', "")) * 1000 - currentAge : 0;
        if (!(lifetime > 0) && !h.has("etag") && !h.has("last-modified")) return;
        while (this.entries.size >= MAX_ENTRIES || this.size + answer.body.length > MAX_TOTAL) this.remove(this.entries.keys().next().value!);
        this.entries.set(key, { ...answer, body: answer.body.slice(), stored: Date.now(), lifetime, validate: has(cc, "no-cache") });
        this.size += answer.body.length;
      },
      collect: (head: Pick<Answer, "status" | "headers">) => eligible && staticResponse(head),
      discard: () => { this.remove(key); },
      maxBody: MAX_BODY,
    };
  }

  private remove(key: string) {
    const entry = this.entries.get(key);
    if (entry) this.size -= entry.body.length;
    this.entries.delete(key);
  }
}
