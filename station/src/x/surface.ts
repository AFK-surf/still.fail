// X as a chat surface (docs/x.md): the bot's account read for the posts that mention it, and its agents' words posted
// as replies. X has no socket a station can open for mentions (its Activity API streams them, but says nothing of
// heartbeats or of what it sends again after a cut), so the connection is a poll of the mentions timeline, kept up as a
// socket is (connects/surface.ts: tried again after a wait that doubles, its last error shown): each poll asks for what
// came after the newest mention read, so nothing said while the station was away is lost, and nothing is read twice.
// Only the people on the connect's list are heard: anyone else's mention is passed over, unanswered. One XSurface per
// connected connect.
import { readFile } from "node:fs/promises";
import { extname } from "node:path";
import { type Clock, Effect } from "effect";
import type { BotIdentity } from "../connects/connections.ts";
import { personKey } from "../connects/keys.ts";
import type { NameBook } from "../connects/names.ts";
import { StatusLine } from "../connects/status.ts";
import { ConnectedSurface } from "../connects/surface.ts";
import { wall } from "../ops/fibers.ts";
import { type Lang, stationLang, tr } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import type { Attachment } from "../store/store.ts";
import type { ChatMessage, Handler, InboundFile, Person, ThreadRef } from "../sessions/chat.ts";
import { type Includes, LEGACY_QUERY, POST_QUERY, type XPost, includesOf, messageText, plainOf, postOf, splitForX } from "./parse.ts";
import { type XThreads, later } from "./threads.ts";
import { XClient, XError, type XKeys } from "./web.ts";

type Json = any;

const text = (v: unknown): string => (typeof v === "string" ? v : "");

/// Who the bot is, as the pages are shown a connect's (`shownIdentity`): its account's name and picture, its user id,
/// its @handle where a Slack connect's workspace would be.
export async function identityOf(client: XClient): Promise<BotIdentity & { username: string }> {
  const me = (await client.api("GET", "/2/users/me", null, { "user.fields": "name,username,profile_image_url" }))?.data ?? {};
  const username = text(me.username);
  const image = text(me.profile_image_url);
  return { team: username === "" ? "" : `@${username}`, teamId: "", url: "https://x.com/", botUserId: text(me.id), botName: text(me.name) || username, botImage: image.startsWith("https://") ? image : null, botId: "", username };
}

/// Checks a connect's keys without connecting: its account read as they sign. Its problems are said in `lang`.
export async function verifyXKeys(keys: XKeys, lang: Lang = stationLang()): Promise<[(BotIdentity & { username: string }) | null, string[]]> {
  const missing = (["consumerKey", "consumerSecret", "accessToken", "accessSecret"] as const).filter((k) => keys[k].trim() === "");
  if (missing.length > 0) return [null, [tr(lang, "station.x.missingKeys", { keys: missing.join(", ") })]];
  try {
    const identity = await identityOf(new XClient(keys));
    if (identity.botUserId === "") return [null, [tr(lang, "station.x.noAccount")]];
    return [identity, []];
  } catch (e) {
    return [null, [tr(lang, "station.x.badKeys", { error: (e as Error).message })]];
  }
}

/// An account by its @handle (`GET /2/users/by/username/:username`): its id and handle as X has them, or null.
export async function userByName(client: XClient, username: string): Promise<{ id: string; username: string } | null> {
  const name = username.trim().replace(/^@/, "");
  if (!/^[A-Za-z0-9_]{1,15}$/.test(name)) return null;
  try {
    const u = (await client.api("GET", `/2/users/by/username/${encodeURIComponent(name)}`))?.data ?? {};
    return text(u.id) === "" ? null : { id: u.id, username: text(u.username) || name };
  } catch (e) {
    if (e instanceof XError && (e.status === 404 || e.status === 400)) return null;
    throw e;
  }
}

const IMAGE: Record<string, string> = { ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".gif": "image/gif", ".webp": "image/webp" };
/// The largest picture X takes in a post.
const MAX_IMAGE = 5 * 1024 * 1024;

export type XSurfaceOptions = {
  connect: string;
  keys: XKeys;
  threads: XThreads;
  /// The ids of the people it hears (the connect's list, read again for each poll).
  allowed: () => Set<string>;
  /// Whether its posts keep links as links (each such post costs $0.20 on X, one without $0.01): absent, not.
  links?: () => boolean;
  /// At most this many weighted characters per post (280; an account with X Premium takes longer ones).
  maxLength?: () => number;
  book?: NameBook | null;
  client?: XClient;
  /// How long between polls of the mentions timeline (and the first wait after a failed one).
  pollMs?: number;
  backoffMs?: number;
  clock?: Clock.Clock;
};

/// Each poll reads one page of the timeline per ask (each mention read costs $0.005 on X; an empty poll nothing).
const POLL_MS = 20_000;
/// At most this many pages a poll (100 mentions each); what is left comes with the next.
const PAGES = 5;
/// How far up a reply chain the posts before a mention are read as the conversation's start.
const CHAIN = 10;

/// X has no status line the station could change in place: nothing is said while the agent works.
class Silent extends StatusLine {
  protected async show() {
    return true;
  }
}

export class XSurface extends ConnectedSurface {
  protected readonly kind = "x";
  override readonly cards = false;
  readonly connect: string;
  readonly client: XClient;
  private threads: XThreads;
  private readonly allowed: () => Set<string>;
  private readonly links: () => boolean;
  private readonly maxLength: () => number;
  private readonly pollMs: number;
  /// The handles of the people heard of, by id.
  private usernames = new Map<string, string>();
  /// The post each mention heard replies to: where the conversation before it is read from.
  private parents = new Map<string, string | null>();
  /// The API takes only the older names of posts' fields.
  private legacy = false;

  constructor(options: XSurfaceOptions) {
    const k = options.keys;
    if (k.consumerKey === "" || k.consumerSecret === "" || k.accessToken === "" || k.accessSecret === "") throw new Error("x keys are required: consumerKey, consumerSecret, accessToken, accessSecret");
    const pollMs = options.pollMs ?? POLL_MS;
    // A poll is a socket's ping: "quiet" never applies (pingMs, staleMs are the socket's, unused here).
    super({ connect: options.connect, book: options.book, pingMs: pollMs, staleMs: pollMs * 3, backoffMs: options.backoffMs ?? pollMs, clock: options.clock });
    this.connect = options.connect;
    this.client = options.client ?? new XClient(options.keys);
    this.threads = options.threads;
    this.allowed = options.allowed;
    this.links = options.links ?? (() => false);
    this.maxLength = options.maxLength ?? (() => 280);
    this.pollMs = pollMs;
  }

  protected async identify() {
    const identity = await identityOf(this.client);
    if (identity.username !== "") this.usernames.set(identity.botUserId, identity.username);
    return identity;
  }

  protected usable(identity: BotIdentity) {
    if (identity.botUserId === "") throw new Error("these keys read no X account");
  }

  /// The mentions timeline (there is no socket's address to ask for).
  protected async address() {
    return `${this.client.base}/2/users/${this.botUserId()}/mentions`;
  }

  platform(): string {
    return "x";
  }

  mention(user: string): string {
    const name = this.usernames.get(user);
    return name === undefined ? user : `@${name}`;
  }

  /// Not said: a link costs a post twenty times over on X, and the session shows in still.fail all the same.
  sessionLink(): string | null {
    return null;
  }

  /// Nothing said while the agent works: a post that said it could not be taken back.
  override working() {}

  protected statusLine() {
    return new Silent(this.run, this.pollMs);
  }

  /// Polls until the surface stops: connected once a poll went through, failing (and tried again after a wait) when
  /// one does not.
  runSocket(_url: string, handler: Handler): Effect.Effect<void, Error> {
    const self = this;
    return Effect.gen(function* () {
      for (;;) {
        yield* Effect.tryPromise({ try: () => self.poll(handler), catch: (e) => e as Error });
        self.setStatus(true, null);
        yield* Effect.sleep(self.pollMs);
      }
    });
  }

  /// A call with posts' fields, in the names the API takes: the older ones once it refused the newer.
  private async posts(path: string, query: Record<string, string>): Promise<Json> {
    if (!this.legacy) {
      try {
        return await this.client.api("GET", path, null, { ...POST_QUERY, ...query });
      } catch (e) {
        if (!(e instanceof XError && e.status === 400 && /post\.fields|referenced_posts|note_post|parameter/i.test(e.message))) throw e;
        log.info("x", "x takes the older names of posts' fields", { connect: this.connect, error: e.message });
        this.legacy = true;
      }
    }
    return this.client.api("GET", path, null, { ...LEGACY_QUERY, ...query });
  }

  /// One poll: the mentions after the newest read (the first time, those since the connect began reading), oldest
  /// first, each heard if its author is on the list; the newest read is kept once each is.
  async poll(handler: Handler) {
    const bot = this.botUserId();
    if (bot === "") return;
    const since = this.threads.since(this.connect);
    const base: Record<string, string> = { max_results: "100" };
    if (since !== null) base.since_id = since;
    else base.start_time = new Date(this.threads.began(this.connect, wall.now())).toISOString().replace(/\.\d{3}Z$/, "Z");
    const found: { post: XPost; inc: Includes }[] = [];
    let token = "";
    for (let page = 0; page < PAGES; page++) {
      const answer = await this.posts(`/2/users/${encodeURIComponent(bot)}/mentions`, { ...base, ...(token ? { pagination_token: token } : {}) });
      const inc = includesOf(answer);
      this.learn(inc);
      for (const p of Array.isArray(answer?.data) ? answer.data : []) {
        const post = postOf(p, inc);
        if (post !== null) found.push({ post, inc });
      }
      token = text(answer?.meta?.next_token);
      if (token === "") break;
    }
    found.sort((a, b) => (a.post.id === b.post.id ? 0 : later(a.post.id, b.post.id) ? 1 : -1));
    const allowed = this.allowed();
    for (const { post, inc } of found) {
      if (post.author !== bot) {
        if (allowed.has(post.author)) await this.heard(post, inc, handler);
        else log.info("x", "a mention from someone not on the list passed over", { connect: this.connect, post: post.id, author: post.author });
      }
      this.threads.read(this.connect, post.id);
    }
  }

  /// People's names and handles from an answer's expansions, kept for the connection's lifetime.
  private learn(inc: Includes) {
    for (const u of inc.users.values()) {
      if (u.username !== "") this.usernames.set(u.id, u.username);
      this.names.set(u.id, { name: u.name !== "" && u.username !== "" ? `${u.name} (@${u.username})` : u.name || `@${u.username}`, email: "", picture: u.picture });
    }
  }

  /// A mention as a message of its conversation (a post and the replies under it): the agent's words there answer it.
  private async heard(post: XPost, inc: Includes, handler: Handler) {
    this.parents.set(post.id, post.repliesTo);
    if (this.parents.size > 2000) this.parents.delete(this.parents.keys().next().value!);
    this.threads.heard(this.connect, post.conversation, post.id);
    await handler({
      type: "message",
      message: { channel: post.conversation, threadTs: post.conversation, ts: post.id, user: post.author, text: messageText(post, inc), addressed: true, ...(post.files.length > 0 ? { files: post.files } : {}) },
    });
  }

  /// The posts a mention replies to, up the chain (at most ten): what was said in the conversation before the station
  /// was brought in.
  history(thread: ThreadRef, before: string, limit: number): Promise<ChatMessage[]> {
    return (async () => {
      const chain: ChatMessage[] = [];
      let id = this.parents.get(before) ?? null;
      while (id !== null && chain.length < Math.min(limit, CHAIN)) {
        const answer = await this.posts(`/2/tweets/${encodeURIComponent(id)}`, {});
        const inc = includesOf(answer);
        this.learn(inc);
        const post = postOf(answer?.data, inc);
        if (post === null || post.conversation !== thread.threadTs) break;
        chain.push({ ts: post.id, user: post.author, text: messageText(post, inc), fromBot: post.author === this.botUserId(), ...(post.files.length > 0 ? { files: post.files } : {}) });
        id = post.repliesTo;
      }
      return chain.reverse();
    })();
  }

  /// The agent's words as replies to the latest mention in the conversation, one under another where they take more
  /// than one post; its pictures with the first (four a post, more in posts of their own). Files that are not pictures
  /// X does not take: nothing is posted then. The first post's id stands for the whole.
  async post(thread: ThreadRef, message: string, files: Attachment[]): Promise<string> {
    const others = files.filter((f) => !(extname(f.name).toLowerCase() in IMAGE));
    if (others.length > 0) throw new Error(`X takes only pictures (png, jpg, gif, webp): ${others.map((f) => f.name).join(", ")} cannot be posted; mention them in the text instead`);
    const media: string[] = [];
    for (const file of files) {
      const bytes = await readFile(file.path);
      if (bytes.length > MAX_IMAGE) throw new Error(`${file.name} is over 5 MB, more than X takes for a picture`);
      const up = await this.client.api("POST", "/2/media/upload", { media_category: "tweet_image", media_type: IMAGE[extname(file.name).toLowerCase()]! }, undefined, [
        { field: "media", bytes, name: file.name, mime: IMAGE[extname(file.name).toLowerCase()]! },
      ]);
      const id = text(up?.data?.id) || text(up?.media_id_string);
      if (id === "") throw new Error("x gave no media id");
      media.push(id);
    }
    const words = message.trim() === "" ? [] : splitForX(plainOf(message, this.links()), this.maxLength());
    const groups: string[][] = [];
    for (let i = 0; i < media.length; i += 4) groups.push(media.slice(i, i + 4));
    const posts: { text: string; media: string[] }[] = words.map((t, i) => ({ text: t, media: groups[i] ?? [] }));
    for (const g of groups.slice(words.length)) posts.push({ text: "", media: g });
    if (posts.length === 0) throw new Error("nothing to post");
    let under = this.threads.replyTo(this.connect, thread.threadTs) ?? thread.threadTs;
    let first: string | null = null;
    for (const p of posts) {
      const body: Json = { reply: { in_reply_to_tweet_id: under } };
      if (p.text !== "") body.text = p.text;
      if (p.media.length > 0) body.media = { media_ids: p.media };
      const id = text((await this.client.api("POST", "/2/tweets", body))?.data?.id);
      if (id === "") throw new Error("x gave no post id");
      first ??= id;
      under = id;
    }
    return first!;
  }

  /// The conversation's first post on X.
  permalink(thread: ThreadRef): string | null {
    return `https://x.com/i/status/${encodeURIComponent(thread.threadTs)}`;
  }

  /// A picture of a post, from where X shows it.
  async download(file: InboundFile): Promise<Uint8Array> {
    if (file.url === null) throw new Error("X does not give its contents");
    const got = await fetch(file.url, { signal: AbortSignal.timeout(120_000) });
    if (!got.ok) throw new Error(`x media: HTTP ${got.status}`);
    return new Uint8Array(await got.arrayBuffer());
  }

  /// A person's name and handle (`GET /2/users/:id`).
  protected async lookUp(user: string): Promise<Person | null> {
    try {
      const u = (await this.client.api("GET", `/2/users/${encodeURIComponent(user)}`, null, { "user.fields": "name,username,profile_image_url" }))?.data ?? {};
      const username = text(u.username);
      if (username !== "") this.usernames.set(user, username);
      const name = text(u.name);
      if (name === "" && username === "") return null;
      return { name: name !== "" && username !== "" ? `${name} (@${username})` : name || `@${username}`, email: "", picture: text(u.profile_image_url) };
    } catch {
      return null;
    }
  }

  knownPerson(user: string): Person | null {
    if (!this.book) return this.names.get(user) ?? null;
    return this.book.person(personKey(this.connect, user), () => this.profile(user));
  }

  knownChannel(): string | null {
    return null;
  }

  /// An API call as the bot's account, for x_api: `method` is "GET /2/…" (reading only: the agent's words go with
  /// chat_post), its params the query.
  async api(method: string, params: Record<string, Json>): Promise<Json> {
    const m = /^GET\s+(\/2\/\S+)$/i.exec(method.trim());
    if (!m) throw new Error(`x_api: method is "GET /2/…" (it only reads; post with chat_post), got ${JSON.stringify(method)}`);
    const query: Record<string, string> = {};
    for (const [k, v] of Object.entries(params)) if (v !== null && v !== undefined) query[k] = typeof v === "string" ? v : String(v);
    return this.client.api("GET", m[1]!, null, query);
  }
}
