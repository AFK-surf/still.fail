// The X connect (docs/x.md): its calls' signatures, what the agent writes as X's posts, the mentions timeline polled
// (only the list's people heard, nothing lost or read twice across a restart), replies and their chains, the hub's
// conversations of it, and its routes, against a stand-in for X (x-fake.ts).
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Effect, Exit, Scope } from "effect";
import { TestClock } from "effect/testing";
import type { ChatEvent } from "../src/sessions/chat.ts";
import { plainOf, splitForX, weightOf } from "../src/x/parse.ts";
import { XSurface } from "../src/x/surface.ts";
import { XThreads } from "../src/x/threads.ts";
import { XClient, oauthHeader } from "../src/x/web.ts";
import { Rig, settle } from "./hub-fakes.ts";
import { FakeX, KEYS } from "./x-fake.ts";

type Json = any;

const testClock = () => {
  const scope = Effect.runSync(Scope.make());
  const clock = Effect.runSync(Scope.provide(TestClock.make(), scope));
  return { clock, adjust: (ms: number) => Effect.runPromise(clock.adjust(`${ms} millis`)), close: () => Effect.runPromise(Scope.close(scope, Exit.void)) };
};

const until = async (f: () => boolean) => {
  for (let i = 0; !f(); i++) {
    if (i > 500) throw new Error("waited too long");
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
};

test("oauth: a call is signed as X's own example signs it (RFC 5849, HMAC-SHA1)", () => {
  // developer.x.com's "Creating a signature": its body parameter given in the query signs the same.
  const url = new URL("https://api.twitter.com/1.1/statuses/update.json");
  url.searchParams.set("include_entities", "true");
  url.searchParams.set("status", "Hello Ladies + Gentlemen, a signed OAuth request!");
  const header = oauthHeader(
    { consumerKey: "xvz1evFS4wEEPTGEFPHBog", consumerSecret: "kAcSOqF21Fu85e7zjz7ZN2U4ZRhfV3WpwPAoE3Z7kBw", accessToken: "370773112-GmHxMAgYyLbNEtIKZeRNFsMKPR9EyMZeS9weJAEb", accessSecret: "LswwdoUaIvS8ltyTt5jkRh4J50vUPVVHtR2YPi5kE" },
    "POST",
    url,
    { nonce: "kYjzVBB8Y0ZFabxSWbWovY3uYSQ2pTgmZeNu2VS4cg", timestamp: 1318622958 },
  );
  assert.match(header, /^OAuth /);
  assert.ok(header.includes(`oauth_signature="${encodeURIComponent("hCtSmYh+iHYCEqBWrE7C7hYmtUk=")}"`), header);
});

test("posts: Markdown as plain text, links left unlinked unless taken, CJK weighing two, long words split into posts of 280", () => {
  assert.equal(plainOf("## Done\n\n**Merged** `abc` in [the PR](https://github.com/a/b/pull/1)\n- one\n- two", true), "Done\n\nMerged abc in the PR (https://github.com/a/b/pull/1)\n• one\n• two");
  assert.equal(plainOf("see https://still.fail/chats/x and still.fail", false), "see still[.]fail/chats/x and still[.]fail");
  assert.equal(plainOf("| a | b |\n|---|---|\n| 1 | 2 |", false), "a · b\n\n1 · 2".replace("\n\n", "\n"));
  assert.equal(weightOf("abc"), 3);
  assert.equal(weightOf("中文"), 4);
  assert.equal(weightOf("go https://example.com/a/very/long/path/indeed"), 3 + 23);
  const long = Array.from({ length: 100 }, (_, i) => `word${i}`).join(" ");
  const posts = splitForX(long);
  assert.ok(posts.length > 1 && posts.every((p) => weightOf(p) <= 280), JSON.stringify(posts.map(weightOf)));
  assert.equal(posts.join(" "), long);
  const cjk = "字".repeat(200);
  assert.deepEqual(splitForX(cjk).map((p) => Array.from(p).length), [140, 60]);
  assert.deepEqual(splitForX("short"), ["short"]);
});

/// A surface on X's stand-in, polling every second on a test clock, hearing the people `allow` names.
async function surfaceRig(o: { allow?: string[]; threads?: XThreads; fake?: FakeX; dir?: string } = {}) {
  const fake = o.fake ?? (await FakeX.start());
  const dir = o.dir ?? mkdtempSync(join(tmpdir(), "x-"));
  const t = testClock();
  const threads = o.threads ?? new XThreads(join(dir, "threads.json"));
  const allow = new Set(o.allow ?? ["200"]);
  const surface = new XSurface({ connect: "xc", keys: KEYS, threads, allowed: () => allow, client: new XClient(KEYS, fake.base), pollMs: 1000, clock: t.clock });
  const events: ChatEvent[] = [];
  const polls = () => fake.calls("GET", "/2/users/100/mentions").length;
  await surface.start(async (e) => void events.push(e));
  await until(() => surface.socket().connected);
  /// The next poll, done.
  const poll = async () => {
    const before = polls();
    await t.adjust(1000);
    await until(() => polls() > before && surface.socket().connected);
    await settle();
  };
  return {
    fake, surface, events, threads, t, dir, allow, poll,
    close: async (keep = false) => {
      await surface.stop();
      await t.close();
      if (!keep) {
        await fake.close();
        rmSync(dir, { recursive: true, force: true });
      }
    },
  };
}

const messages = (events: ChatEvent[]) => events.flatMap((e) => (e.type === "message" ? [e.message] : []));

test("surface: the list's mentions are heard as their conversation's messages, others passed over; each read once, and none from before it began", async () => {
  const fake = await FakeX.start();
  const early = fake.say({ author: "200", text: "before the connect", at: "2026-01-01T00:00:00.000Z" });
  const r = await surfaceRig({ fake });
  try {
    assert.equal(r.surface.botUserId(), "100");
    assert.equal(r.surface.identity()!.team, "@commabot");
    const first = fake.calls("GET", "/2/users/100/mentions")[0]!;
    assert.ok(first.signed && first.query.start_time !== undefined && first.query.since_id === undefined, JSON.stringify(first.query));
    assert.ok(first.query["post.fields"]!.includes("conversation_id"));
    assert.equal(messages(r.events).length, 0, "the mention from before it began reading is not heard");
    const a = fake.say({ author: "200", text: "帮我看看" });
    const m = fake.say({ author: "300", text: "me too" });
    await r.poll();
    assert.deepEqual(messages(r.events).map((x) => [x.channel, x.threadTs, x.ts, x.user, x.text, x.addressed]), [[a, a, a, "200", "帮我看看", true]]);
    assert.equal(r.threads.since("xc"), m, "the newest read, whoever's");
    assert.equal(r.surface.knownPerson("200")?.name, "Ada (@ada)");
    assert.equal(r.surface.mention("200"), "@ada");
    // A reply in the conversation is heard in it.
    const reply = fake.say({ author: "200", text: "还有这个", replyTo: a });
    await r.poll();
    assert.equal(fake.calls("GET", "/2/users/100/mentions").at(-1)!.query.since_id, m, "asked for what came after");
    assert.deepEqual(messages(r.events).at(-1)!.threadTs, a);
    assert.equal(messages(r.events).at(-1)!.ts, reply);
    assert.equal(r.threads.replyTo("xc", a), reply);
    // Someone added to the list is heard from the next poll.
    r.allow.add("300");
    fake.say({ author: "300", text: "now me" });
    await r.poll();
    assert.equal(messages(r.events).at(-1)!.user, "300");
    assert.ok(!messages(r.events).some((x) => x.ts === early));
  } finally {
    await r.close();
  }
});

test("surface: what was said while the station was away is read once it is back, page by page, oldest first", async () => {
  const r = await surfaceRig();
  try {
    const a = r.fake.say({ author: "200", text: "one" });
    await r.poll();
    await r.close(true);
    const said = Array.from({ length: 5 }, (_, i) => r.fake.say({ author: "200", text: `away ${i}`, replyTo: a }));
    r.fake.pageSize = 2;
    const again = await surfaceRig({ fake: r.fake, dir: r.dir, threads: new XThreads(join(r.dir, "threads.json")) });
    try {
      assert.deepEqual(messages(again.events).map((x) => x.ts), said);
      assert.equal(r.fake.calls("GET", "/2/users/100/mentions").at(-1)!.query.pagination_token, "4");
      await again.poll();
      assert.equal(messages(again.events).length, 5, "nothing twice");
    } finally {
      await again.close();
    }
  } finally {
    rmSync(r.dir, { recursive: true, force: true });
  }
});

test("surface: an API that takes only the older names of posts' fields is asked in those", async () => {
  const fake = await FakeX.start();
  fake.legacyOnly = true;
  const r = await surfaceRig({ fake });
  try {
    const q = fake.say({ author: "300", text: "quoted words", mention: false });
    const a = fake.say({ author: "200", text: "what about this", quotes: q });
    await r.poll();
    const last = fake.calls("GET", "/2/users/100/mentions").at(-1)!;
    assert.ok("tweet.fields" in last.query && !("post.fields" in last.query));
    assert.equal(messages(r.events).at(-1)!.ts, a);
    assert.equal(messages(r.events).at(-1)!.text, "what about this\n\n[Quoting @mallory]\n> quoted words");
  } finally {
    await r.close();
  }
});

test("surface: the agent's words reply to the latest mention, long ones as a chain, with their pictures; other files are refused", async () => {
  const r = await surfaceRig();
  const dir = mkdtempSync(join(tmpdir(), "xf-"));
  try {
    const a = r.fake.say({ author: "200", text: "hi" });
    const b = r.fake.say({ author: "200", text: "and?", replyTo: a });
    await r.poll();
    const png = join(dir, "shot.png");
    writeFileSync(png, Buffer.from([0x89, 0x50, 0x4e, 0x47]));
    const words = `**Done.** ${"lorem ipsum ".repeat(30)}`;
    const first = await r.surface.post({ channel: a, threadTs: a }, words, [{ name: "shot.png", path: png, size: 4 }]);
    const made = r.fake.calls("POST", "/2/tweets").map((c) => c.body);
    assert.equal(made.length, 2);
    assert.equal(made[0].reply.in_reply_to_tweet_id, b);
    assert.equal(made[1].reply.in_reply_to_tweet_id, first);
    assert.ok(made[0].text.startsWith("Done. lorem") && made[0].media.media_ids.length === 1 && made[1].media === undefined);
    assert.equal(r.fake.calls("POST", "/2/media/upload")[0]!.body.media_category, "tweet_image");
    await assert.rejects(r.surface.post({ channel: a, threadTs: a }, "report", [{ name: "r.pdf", path: png, size: 4 }]), /only pictures/);
    assert.equal(r.fake.calls("POST", "/2/tweets").length, 2, "nothing posted");
    assert.equal(r.surface.sessionLink(), null);
    assert.equal(r.surface.cards, false);
  } finally {
    rmSync(dir, { recursive: true, force: true });
    await r.close();
  }
});

test("hub: an X conversation is a session on the connect's own surface, begun by a mention mid-thread with the posts above it; no cards", async () => {
  const rig = new Rig();
  const r = await surfaceRig();
  try {
    rig.edit((raw) => raw.connects.push({ id: "xc", kind: "x", x: { ...KEYS }, bind: { runtime: "claude" } }));
    await rig.hub.shutdown();
    rig.hub = rig.newHub({ chats: (id) => (id === "xc" ? r.surface : undefined) });
    // Its surface's events go to the hub from now on.
    const root = r.fake.say({ author: "300", text: "a thread about something", mention: false });
    const mid = r.fake.say({ author: "300", text: "more", replyTo: root, mention: false });
    const ask = r.fake.say({ author: "200", text: "summarise this", replyTo: mid });
    for (const e of r.events.splice(0)) await rig.hub.receive("xc", e);
    await r.poll();
    for (const e of r.events.splice(0)) await rig.hub.receive("xc", e);
    await settle();
    const key = `xc:${root}:${root}`;
    assert.ok(rig.store.getSession(key));
    const thread = rig.store.threadAt("x:xc", root, root)!;
    assert.deepEqual(rig.said(thread.id).map((m) => [m.ts, m.text]), [[root, "a thread about something"], [mid, "more"], [ask, "summarise this"]]);
    assert.equal(r.fake.calls("POST", "/2/tweets").length, 0, "no session link posted");
    const answer = await rig.call(key, "chat_post", { to: `${root}/${root}`, text: "Here it is.", kind: "all_done", done: "summarised" });
    assert.ok(answer.startsWith(`Posted to ${root}/${root}`), answer);
    assert.equal(r.fake.calls("POST", "/2/tweets")[0]!.body.reply.in_reply_to_tweet_id, ask);
    assert.match(await rig.refused(key, "chat_post", { to: `${root}/${root}`, text: "pick", card: { type: "options", options: [{ label: "A" }] } }), /cards .* are not shown here/);
  } finally {
    await r.close();
    await rig.close();
  }
});

test("routes: a connect of an account's keys with its list looked up by handle; the list replaced; keys of another account refused", async () => {
  const fake = await FakeX.start();
  const was = process.env.STILLFAIL_X_API;
  process.env.STILLFAIL_X_API = fake.base;
  const data = mkdtempSync(join(tmpdir(), "xr-"));
  delete process.env.STILLFAIL_CONFIG;
  delete process.env.EMBER_CONFIG;
  writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [{ id: "cc", runtime: "claude", home: "homes/cc" }], connects: [] }));
  const { ConfigFile } = await import("../src/ops/config.ts");
  const { Store } = await import("../src/store/store.ts");
  const { makeX } = await import("../src/x/index.ts");
  const { xRoutes } = await import("../src/api/routes/x.ts");
  const config = new ConfigFile(data);
  const store = Store.open(":memory:", null);
  const x = makeX({ data, store, config, receive: async () => {}, bound: () => true });
  const viewer = { sub: "s", email: "owner@example.com", name: "Owner", role: "owner", workspace: "ws", device: "d" } as Json;
  const table = xRoutes({ config, data, hub: () => undefined, overview: () => ({ connects: config.raw().connects }) });
  const ask = async (method: string, path: string, body?: unknown): Promise<[number, Json]> => {
    for (const route of table) {
      const found = route.method === method ? route.pattern.exec(path) : null;
      if (found) {
        const a = await route.handle({ method, path, query: [], headers: {}, body: Buffer.from(body === undefined ? "" : JSON.stringify(body)), viewer, lang: "zh" }, found.slice(1));
        return [a.status, JSON.parse(String(a.body))];
      }
    }
    return [404, null];
  };
  try {
    const [, missing] = await ask("POST", "/x/verify", { consumerKey: "ck" });
    assert.deepEqual([missing.identity, missing.errors], [null, ["请填写 consumerSecret, accessToken, accessSecret"]]);
    const [, wrong] = await ask("POST", "/x/verify", { ...KEYS, accessSecret: "nope" });
    assert.match(wrong.errors[0], /^X 不认这组 key：x GET \/2\/users\/me: 401/);
    const [, right] = await ask("POST", "/x/verify", KEYS);
    assert.deepEqual(right, { identity: { botName: "Comma Bot", botImage: "https://pbs.example.test/bot.png", botUserId: "100", username: "commabot" }, errors: [] });
    const [refused, said] = await ask("POST", "/x/connects", { x: { ...KEYS, allow: "@ada @nobody" }, bind: { runtime: "claude" } });
    assert.deepEqual([refused, said.error ?? said], [400, "X 上没有 @nobody 这个账号"]);
    const [made, answer] = await ask("POST", "/x/connects", { x: { ...KEYS, allow: ["@Ada", "https://x.com/ada"] }, bind: { runtime: "claude" } });
    assert.equal(made, 200, JSON.stringify(answer));
    assert.equal(answer.id, "commabot");
    const kept = config.raw().connects[0];
    assert.deepEqual([kept.kind, kept.x.accessToken, kept.x.botUserId, kept.x.botUsername, kept.x.allow], ["x", "at", "100", "commabot", [{ id: "200", username: "ada" }]]);
    await until(() => x.state("commabot")?.state === "connected");
    const shown = x.shown(kept);
    assert.deepEqual([shown.name, shown.team, (shown.x as Json).accessSecret, (shown.x as Json).allow], ["Comma Bot", "@commabot", "••••", [{ id: "200", username: "ada" }]]);
    const [listed] = await ask("PUT", "/x/connects/commabot/allow", { allow: "ada, mallory" });
    assert.equal(listed, 200);
    assert.deepEqual(config.raw().connects[0].x.allow.map((a: Json) => a.username), ["ada", "mallory"]);
    // An edit of what every connect has keeps its keys and list.
    const { connectEdits } = await import("../src/api/routes/connects.ts");
    const { xEntry } = await import("../src/api/routes/x.ts");
    await connectEdits({ config, data, hub: () => undefined, overview: () => ({}), entry: (kind) => (kind === "x" ? xEntry : undefined) }).putConnect({ method: "PUT", path: "", query: [], headers: {}, body: Buffer.from(""), viewer, lang: "zh" }, "commabot", { enabled: false, x: { links: true } });
    assert.deepEqual([config.raw().connects[0].enabled, config.raw().connects[0].x.consumerKey, config.raw().connects[0].x.allow.length, config.raw().connects[0].x.links], [false, "ck", 2, true]);
    fake.bot = { ...fake.bot, id: "101", username: "other" };
    const [other, no] = await ask("PUT", "/x/connects/commabot/keys", { accessToken: "at" });
    assert.deepEqual([other, no.error ?? no], [400, "这组 key 对应的是另一个账号 @other，请另建一个 connect"]);
  } finally {
    if (was === undefined) delete process.env.STILLFAIL_X_API;
    else process.env.STILLFAIL_X_API = was;
    await x.close();
    store.close();
    await fake.close();
    rmSync(data, { recursive: true, force: true });
  }
});
