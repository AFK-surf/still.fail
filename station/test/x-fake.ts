// A stand-in for X's API v2 on a local port (docs/x.md「测试」): the bot's account, people looked up by handle, posts the
// test says were made (its mentions timeline answers those that mention the bot, after since_id, newest first, in pages
// like X's), and the posts and pictures the station makes. Each call is recorded, its OAuth signature checked against
// the keys it was given. Nothing reaches the real X.
import { createServer, type IncomingMessage, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { oauthHeader, type XKeys } from "../src/x/web.ts";

type Json = any;

export type Seen = { method: string; path: string; query: Record<string, string>; body: Json; signed: boolean };

export const KEYS: XKeys = { consumerKey: "ck", consumerSecret: "cs", accessToken: "at", accessSecret: "as" };

export class FakeX {
  readonly server: Server;
  base = "";
  seen: Seen[] = [];
  bot = { id: "100", name: "Comma Bot", username: "commabot", profile_image_url: "https://pbs.example.test/bot.png" };
  users = new Map<string, Json>([
    ["200", { id: "200", name: "Ada", username: "ada" }],
    ["300", { id: "300", name: "Mallory", username: "mallory" }],
  ]);
  /// Every post, by id: those the test made and those the station posted.
  posts = new Map<string, Json>();
  /// The mentions timeline's page size (X's max_results is at most 100).
  pageSize = 100;
  /// Refuse posts' newer field names, as an API from before they were called posts.
  legacyOnly = false;
  private n = 900;

  constructor() {
    this.server = createServer((req, res) => {
      void this.take(req).then(
        ([status, body]) => res.writeHead(status, { "content-type": "application/json" }).end(JSON.stringify(body)),
        (error) => res.writeHead(500).end(String(error)),
      );
    });
  }

  static async start(): Promise<FakeX> {
    const fake = new FakeX();
    await new Promise<void>((resolve) => fake.server.listen(0, "127.0.0.1", resolve));
    fake.base = `http://127.0.0.1:${(fake.server.address() as AddressInfo).port}`;
    return fake;
  }

  calls(method: string, path: string | RegExp): Seen[] {
    return this.seen.filter((s) => s.method === method && (typeof path === "string" ? s.path === path : path.test(s.path)));
  }

  /// A post by `author` (mentioning the bot unless `mention` is false), replying to `replyTo` (its conversation's) or
  /// beginning one: its id.
  say(o: { author: string; text: string; replyTo?: string; mention?: boolean; quotes?: string; media?: string[]; at?: string }): string {
    const id = String(this.n++);
    const parent = o.replyTo === undefined ? null : this.posts.get(o.replyTo);
    const refs = [...(parent ? [{ type: "replied_to", id: parent.id }] : []), ...(o.quotes ? [{ type: "quoted", id: o.quotes }] : [])];
    this.posts.set(id, {
      id,
      author_id: o.author,
      text: o.mention === false ? o.text : `@${this.bot.username} ${o.text}`,
      conversation_id: parent ? parent.conversation_id : id,
      created_at: o.at ?? new Date().toISOString(),
      ...(refs.length > 0 ? { referenced_tweets: refs, referenced_posts: refs } : {}),
      ...(o.media ? { attachments: { media_keys: o.media } } : {}),
      mentions: o.mention !== false,
    });
    return id;
  }

  async close() {
    this.server.closeAllConnections();
    await new Promise<void>((resolve) => this.server.close(() => resolve()));
  }

  private later = (a: string, b: string) => (a.length !== b.length ? a.length > b.length : a > b);

  /// A post as an answer carries it, in the names asked for.
  private shown(p: Json, legacy: boolean): Json {
    const { mentions: _, referenced_tweets, referenced_posts, ...rest } = p;
    return { ...rest, ...(referenced_posts ? (legacy ? { referenced_tweets } : { referenced_posts }) : {}) };
  }

  private includes(posts: Json[], legacy: boolean): Json {
    const users = new Map<string, Json>();
    const refs = new Map<string, Json>();
    const media: Json[] = [];
    for (const p of posts) {
      const u = p.author_id === this.bot.id ? this.bot : this.users.get(p.author_id);
      if (u) users.set(u.id, u);
      for (const r of p.referenced_posts ?? []) {
        const q = this.posts.get(r.id);
        if (q) refs.set(q.id, this.shown(q, legacy));
        const qu = q && this.users.get(q.author_id);
        if (qu) users.set(qu.id, qu);
      }
      for (const key of p.attachments?.media_keys ?? []) media.push({ media_key: key, type: "photo", url: `${this.base}/media/${key}.png` });
    }
    return { users: [...users.values()], [legacy ? "tweets" : "posts"]: [...refs.values()], media };
  }

  private async take(req: IncomingMessage): Promise<[number, Json]> {
    const chunks: Buffer[] = [];
    for await (const chunk of req) chunks.push(chunk as Buffer);
    const raw = Buffer.concat(chunks);
    const url = new URL(req.url ?? "/", this.base);
    const contentType = String(req.headers["content-type"] ?? "");
    let body: Json = null;
    if (contentType.startsWith("application/json")) body = JSON.parse(raw.toString("utf8") || "null");
    else if (contentType.startsWith("multipart/form-data")) {
      const form = await new Response(raw, { headers: { "content-type": contentType } }).formData();
      body = {};
      for (const [k, v] of form) body[k] = typeof v === "string" ? v : `<file ${(v as File).name}>`;
    }
    // Signed as the station signs: the same header from its own nonce and timestamp.
    const auth = String(req.headers.authorization ?? "");
    const field = (k: string) => decodeURIComponent(new RegExp(`${k}="([^"]*)"`).exec(auth)?.[1] ?? "");
    const signed = auth === oauthHeader(KEYS, req.method ?? "GET", url, { nonce: field("oauth_nonce"), timestamp: Number(field("oauth_timestamp")) });
    const seen: Seen = { method: req.method ?? "GET", path: url.pathname, query: Object.fromEntries(url.searchParams), body, signed };
    if (url.pathname.startsWith("/media/")) return [200, {}];
    this.seen.push(seen);
    if (!signed) return [401, { title: "Unauthorized", detail: "Unauthorized", status: 401 }];
    const legacy = "tweet.fields" in seen.query;
    if (this.legacyOnly && "post.fields" in seen.query) return [400, { errors: [{ parameters: { "post.fields": [""] }, message: "The query parameter [post.fields] is not one of [...]" }], title: "Invalid Request", detail: "One or more parameters to your request was invalid." }];
    if (seen.path === "/2/users/me") return [200, { data: this.bot }];
    let m = /^\/2\/users\/by\/username\/([^/]+)$/.exec(seen.path);
    if (m) {
      const u = [...this.users.values()].find((u) => u.username.toLowerCase() === m![1]!.toLowerCase());
      return u ? [200, { data: u }] : [200, { errors: [{ title: "Not Found Error", detail: `Could not find user with username: [${m[1]}].` }] }];
    }
    m = /^\/2\/users\/([0-9]+)\/mentions$/.exec(seen.path);
    if (m) {
      let found = [...this.posts.values()].filter((p) => p.mentions && p.author_id !== m![1]);
      if (seen.query.since_id) found = found.filter((p) => this.later(p.id, seen.query.since_id!));
      if (seen.query.start_time) found = found.filter((p) => Date.parse(p.created_at) >= Date.parse(seen.query.start_time!));
      found.sort((a, b) => (this.later(a.id, b.id) ? -1 : 1));
      const from = Number(seen.query.pagination_token ?? "0");
      const page = found.slice(from, from + this.pageSize);
      const meta: Json = { result_count: page.length };
      if (from + this.pageSize < found.length) meta.next_token = String(from + this.pageSize);
      if (page.length === 0) return [200, { meta }];
      return [200, { data: page.map((p) => this.shown(p, legacy)), includes: this.includes(page, legacy), meta }];
    }
    m = /^\/2\/users\/([0-9]+)$/.exec(seen.path);
    if (m) return this.users.has(m[1]!) ? [200, { data: this.users.get(m[1]!) }] : [404, { title: "Not Found Error", status: 404 }];
    m = /^\/2\/tweets\/([0-9]+)$/.exec(seen.path);
    if (m && seen.method === "GET") {
      const p = this.posts.get(m[1]!);
      return p ? [200, { data: this.shown(p, legacy), includes: this.includes([p], legacy) }] : [200, { errors: [{ title: "Not Found Error" }] }];
    }
    if (seen.path === "/2/tweets" && seen.method === "POST") {
      const id = String(this.n++);
      const parent = this.posts.get(body?.reply?.in_reply_to_tweet_id ?? "");
      this.posts.set(id, { id, author_id: this.bot.id, text: body?.text ?? "", conversation_id: parent?.conversation_id ?? id, mentions: false, media: body?.media?.media_ids });
      return [201, { data: { id, text: body?.text ?? "" } }];
    }
    if (seen.path === "/2/media/upload" && seen.method === "POST") return [200, { data: { id: `m${this.n++}`, media_key: "3_1" } }];
    return [404, { title: "Not Found Error", status: 404 }];
  }
}
