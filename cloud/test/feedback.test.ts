import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import { harness } from "./harness.ts";

type Harness = Awaited<ReturnType<typeof harness>>;
const hex = (bytes: ArrayBuffer) => Buffer.from(bytes).toString("hex");

async function key() {
  const pair = (await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const id = hex((await crypto.subtle.exportKey("raw", pair.publicKey)) as ArrayBuffer);
  const sign = async (message: string) => hex(await crypto.subtle.sign("Ed25519", pair.privateKey, new TextEncoder().encode(message)));
  return { id, sign };
}
type Station = Awaited<ReturnType<typeof key>>;

/** Alice's workspace with a station in it. */
async function workspace(h: Harness) {
  const aliceTokens = await h.login("alice");
  const alice = h.as(aliceTokens);
  const id = ((await (await alice("POST", "/v1/workspaces", { name: "Home" })).json()) as any).id as string;
  const enrollment = (await (await alice("POST", `/v1/workspaces/${id}/enrollments`, { name: "willow" })).json()) as any;
  const station = await key();
  const response = await h.fetch("/v1/stations/enroll", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ token: enrollment.token, station: station.id, signature: await station.sign(`stillfail-station-enroll-v1:${h.origin}:${enrollment.token}:${station.id}`) }),
  });
  assert.equal(response.status, 200);
  return { id, station, aliceTokens };
}

/** Sends a report as the station, signed (with another tag, or as the test channel, when a test says). */
async function send(h: Harness, station: Station, report: unknown, options: { tag?: string; channel?: string; path?: string } = {}) {
  const body = JSON.stringify(report);
  const ts = h.now();
  const digest = createHash("sha256").update(body).digest("hex");
  const headers: Record<string, string> = {
    "content-type": "application/json",
    "x-stillfail-station": station.id,
    "x-stillfail-ts": String(ts),
    "x-stillfail-signature": await station.sign(`${options.tag ?? "stillfail-station-feedback-v1"}:${h.origin}:${station.id}:${ts}:${digest}`),
  };
  if (options.channel) headers["x-stillfail-channel"] = options.channel;
  return h.fetch(options.path ?? "/v1/feedback", { method: "POST", headers, body });
}

/** Asks which of the station's reports are fixed and out, saying those it told of. */
async function fixed(h: Harness, station: Station, told: string[] = []) {
  const response = await send(h, station, { told }, { path: "/v1/feedback/fixed", tag: "stillfail-station-feedback-fixed-v1" });
  assert.equal(response.status, 200);
  return ((await response.json()) as any).fixed as any[];
}

const report = (extra: Record<string, unknown> = {}) => ({
  key: "k1",
  title: "chat_post 发不出去",
  body: "chat_post 回了 500，消息没出现在 thread 里。",
  area: "station",
  reporter: "Ada, Slack #ops",
  context: { version: "0.1.1309", session: "chat:c-1", runtime: "claude" },
  logs: "ERROR chat_post: 500",
  ...extra,
});

test("a station's report is kept once, numbered, and listed in the console with where it came from", async () => {
  const h = await harness();
  try {
    const { id, station, aliceTokens } = await workspace(h);
    const first = await send(h, station, report());
    assert.equal(first.status, 201);
    const made = (await first.json()) as any;
    assert.equal(made.number, 1);
    assert.equal(made.duplicate, false);
    // Sent again (a retry): the same one.
    const again = await send(h, station, report());
    assert.equal(again.status, 200);
    assert.deepEqual(await again.json(), { ...made, duplicate: true });
    assert.equal(((await (await send(h, station, report({ key: "k2", area: "nonsense" }), { channel: "beta" })).json()) as any).number, 2);

    const admin = h.as(aliceTokens, "admin");
    const listed = (await (await admin("GET", "/v1/admin/feedback")).json()) as any;
    assert.deepEqual(listed.feedback.map((f: any) => [f.number, f.channel, f.area]), [[2, "beta", "unknown"], [1, "stable", "station"]]);
    const one = listed.feedback[1];
    assert.deepEqual(one.station, { id: station.id, name: "willow" });
    assert.deepEqual(one.workspace, { id, name: "Home" });
    assert.equal(one.account, null);
    assert.equal(one.title, "chat_post 发不出去");
    assert.equal(one.reporter, "Ada, Slack #ops");
    assert.deepEqual(one.context, report().context);
    assert.equal(one.logs, "ERROR chat_post: 500");
    assert.equal(one.status, "new");

    assert.equal((await admin("POST", `/v1/admin/feedback/${one.id}/status`, { status: "fixed" })).status, 200);
    assert.equal((await admin("POST", `/v1/admin/feedback/${one.id}/status`, { status: "gone" })).status, 400);
    assert.equal((await admin("POST", `/v1/admin/feedback/${"0".repeat(26)}/status`, { status: "fixed" })).status, 404);
    const after = (await (await admin("GET", "/v1/admin/feedback")).json()) as any;
    assert.equal(after.feedback[1].status, "fixed");
  } finally {
    await h.close();
  }
});

test("the feedback monitor reads the console's list with its token, and that token does nothing else", async () => {
  const h = await harness();
  try {
    const { station } = await workspace(h);
    assert.equal((await send(h, station, report())).status, 201);
    const list = (token: string, path = "/v1/admin/feedback/list") => h.fetch(path, { method: "POST", headers: { authorization: `Bearer ${token}`, "content-type": "application/json" }, body: "{}" });
    const listed = (await (await list(h.feedbackToken)).json()) as any;
    assert.deepEqual(listed.feedback.map((f: any) => [f.number, f.title, f.station?.name]), [[1, "chat_post 发不出去", "willow"]]);
    assert.equal((await list(h.adminToken)).status, 401, "not the admin token");
    assert.equal((await list("x".repeat(43))).status, 401);
    assert.equal((await list(h.feedbackToken, "/v1/admin/workspaces/list")).status, 401, "nothing else");
  } finally {
    await h.close();
  }
});

test("the feedback monitor marks where a report is with its token, as the console does", async () => {
  const h = await harness();
  try {
    const { station, aliceTokens } = await workspace(h);
    assert.equal((await send(h, station, report())).status, 201);
    const admin = h.as(aliceTokens, "admin");
    const id = ((await (await admin("GET", "/v1/admin/feedback")).json()) as any).feedback[0].id as string;
    const mark = (token: string, status: unknown, which = id) =>
      h.fetch(`/v1/admin/feedback/${which}/status`, { method: "POST", headers: { authorization: `Bearer ${token}`, "content-type": "application/json" }, body: JSON.stringify({ status }) });
    const now = async () => ((await (await admin("GET", "/v1/admin/feedback")).json()) as any).feedback[0].status;

    assert.equal((await mark(h.feedbackToken, "triaged")).status, 200);
    assert.equal(await now(), "triaged");
    assert.equal((await mark(h.feedbackToken, "gone")).status, 400);
    assert.equal((await mark(h.feedbackToken, undefined)).status, 400);
    assert.equal((await mark(h.feedbackToken, "fixed", "0".repeat(26))).status, 404);
    assert.equal(await now(), "triaged");

    // Not the admin token's, nor a made-up one's: they fall to the console's sign-in, which they are not.
    assert.notEqual((await mark(h.adminToken, "wontfix")).status, 200, "not the admin token");
    assert.notEqual((await mark("x".repeat(43), "wontfix")).status, 200);
    assert.equal(await now(), "triaged");

    // The console's admin marks it as before.
    assert.equal((await admin("POST", `/v1/admin/feedback/${id}/status`, { status: "wontfix" })).status, 200);
    assert.equal(await now(), "wontfix");
  } finally {
    await h.close();
  }
});

test("reports signed wrong, not signed, by a station not enrolled, or without a title are refused", async () => {
  const h = await harness();
  try {
    const { station } = await workspace(h);
    assert.equal((await send(h, station, report(), { tag: "stillfail-station-notify-v1" })).status, 401, "a notice's signature");
    assert.equal((await send(h, await key(), report())).status, 401, "not enrolled");
    assert.equal((await h.fetch("/v1/feedback", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(report()) })).status, 401, "not signed");
    assert.equal((await send(h, station, report({ title: " " }))).status, 400);
    assert.equal((await send(h, station, report({ key: "no spaces allowed" }))).status, 400);
  } finally {
    await h.close();
  }
});

test("a signed-in account may report too; the console's list is the admin's only", async () => {
  const h = await harness();
  try {
    const bobTokens = await h.login("bob");
    const bob = h.as(bobTokens);
    assert.equal((await bob("POST", "/v1/feedback", report())).status, 201);
    assert.equal((await h.as(bobTokens, "admin")("GET", "/v1/admin/feedback")).status, 404, "not the admin");
    const alice = h.as(await h.login("alice"), "admin");
    const listed = (await (await alice("GET", "/v1/admin/feedback")).json()) as any;
    assert.equal(listed.feedback[0].account.email, "bob@example.test");
    assert.equal(listed.feedback[0].station, null);
  } finally {
    await h.close();
  }
});

test("a sender may send twenty reports a day", async () => {
  const h = await harness();
  try {
    const { station } = await workspace(h);
    for (let i = 0; i < 20; i++) assert.equal((await send(h, station, report({ key: `k${i}` }))).status, 201);
    assert.equal((await send(h, station, report({ key: "k20" }))).status, 429);
  } finally {
    await h.close();
  }
});

test("a report the changelog fixes is marked fixed, and its station told once the fix is out on its channel", async () => {
  const h = await harness();
  try {
    const { station, aliceTokens } = await workspace(h);
    await send(h, station, report({ context: { session: "chat:c-1", thread: "CHAT/1.1" } }));
    await send(h, station, report({ key: "k2", title: "安卓列表跳动" }));
    const bucket = (await h.mf.getR2Bucket("RELEASES", "api")) as unknown as { put(key: string, value: string): Promise<unknown> };
    // Nothing in the changelog yet: nothing fixed.
    assert.deepEqual(await fixed(h, station), []);
    await bucket.put("changelog.json", JSON.stringify([
      { version: 1340, commit: "b", at: 2, text: ["修复：安卓列表跳动"], fixes: [2], parts: ["android"] },
      { version: 1330, commit: "a", at: 1, text: ["修复：chat_post 发不出去"], fixes: [1], parts: ["station"] },
    ]));
    // Fixed, but no station release has it yet.
    assert.deepEqual(await fixed(h, station), []);
    const admin = h.as(aliceTokens, "admin");
    const listed = (await (await admin("GET", "/v1/admin/feedback")).json()) as any;
    assert.deepEqual(listed.feedback.map((f: any) => [f.number, f.status, f.fixed_in]), [[2, "fixed", 1340], [1, "fixed", 1330]]);

    await bucket.put("station.json", JSON.stringify({ version: "0.1.1335", build: 1335 }));
    await bucket.put("android/latest.json", JSON.stringify({ versionCode: 1339 }));
    const out = await fixed(h, station);
    assert.equal(out.length, 1);
    assert.equal(out[0].number, 1);
    assert.equal(out[0].version, 1330);
    assert.deepEqual(out[0].parts, ["station"]);
    assert.equal(out[0].released.station, 1335);
    assert.equal(out[0].session, "chat:c-1");
    assert.equal(out[0].thread, "CHAT/1.1");
    // Told: not again.
    assert.deepEqual(await fixed(h, station, [out[0].id]), []);
    await bucket.put("android/latest.json", JSON.stringify({ versionCode: 1341 }));
    assert.deepEqual((await fixed(h, station)).map((f) => f.number), [2]);

    // Another station does not hear of them; a beta release is not the stable one's.
    assert.equal((await send(h, station, { told: [] }, { path: "/v1/feedback/fixed" })).status, 401, "a report's signature");
  } finally {
    await h.close();
  }
});

test("the changelog is anyone's to read, with what each part has out on the host's channel", async () => {
  const h = await harness();
  try {
    const empty = (await (await h.fetch("/v1/changelog")).json()) as any;
    assert.deepEqual(empty, { entries: [], released: { station: null, android: null, desktop: null, web: null } });
    const bucket = (await h.mf.getR2Bucket("RELEASES", "api")) as unknown as { put(key: string, value: string): Promise<unknown> };
    await bucket.put("changelog.json", JSON.stringify([{ version: 1340, commit: "b", at: 2, text: ["新功能：更新日志"], fixes: [], parts: ["web", "android"] }]));
    await bucket.put("web.json", JSON.stringify({ build: 1338 }));
    await bucket.put("web-beta.json", JSON.stringify({ build: 1340 }));
    await bucket.put("mac/latest.json", JSON.stringify({ versionCode: 1300, file: "desktop/stillfail-0.1.1300-arm64-mac.zip" }));
    const stable = (await (await h.fetch("/v1/changelog")).json()) as any;
    assert.equal(stable.entries[0].text[0], "新功能：更新日志");
    assert.deepEqual(stable.released, { station: null, android: null, desktop: 1300, web: 1338 });
    const beta = (await (await h.fetch("/v1/changelog", { headers: { "x-stillfail-channel": "beta" } })).json()) as any;
    assert.equal(beta.released.web, 1340);
  } finally {
    await h.close();
  }
});

/** A device's events socket; `take`: the events since the last take (h.heard). */
async function listen(h: Harness, token: string) {
  const response = await h.fetch("/v1/events", { headers: { upgrade: "websocket", "sec-websocket-protocol": `stillfail-events, stillfail-token.${token}` } });
  assert.equal(response.status, 101);
  const ws = response.webSocket!;
  ws.accept();
  const got: any[] = [];
  ws.addEventListener("message", (event) => void (event.data === "pong" || got.push(JSON.parse(event.data as string))));
  return { ws, take: async () => (await h.heard(ws), got.splice(0)) };
}

/** The station's presence socket, its frames kept (the pongs aside). */
async function connect(h: Harness, station: Station) {
  const ts = h.now();
  const signature = await station.sign(`stillfail-station-connect-v1:${h.origin}:${station.id}:${ts}`);
  const response = await h.fetch("/v1/stations/connect", {
    headers: { upgrade: "websocket", "x-stillfail-station": station.id, "x-stillfail-ts": String(ts), "x-stillfail-signature": signature, "x-stillfail-version": "0.2.0" },
  });
  assert.equal(response.status, 101);
  const ws = response.webSocket!;
  const frames: any[] = [];
  ws.addEventListener("message", (event) => void (event.data === "pong" || frames.push(JSON.parse(event.data as string))));
  ws.accept();
  return { ws, frames, ping: () => h.heard(ws) };
}

/** The station joins another workspace of `owner`'s (a token it redeems as stations do). */
async function join(h: Harness, owner: ReturnType<Harness["as"]>, workspace: string, station: Station) {
  const made = (await (await owner("POST", `/v1/workspaces/${workspace}/enrollments`, { name: "lab box" })).json()) as any;
  const response = await h.fetch("/v1/stations/join", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ token: made.token, station: station.id, signature: await station.sign(`stillfail-station-enroll-v1:${h.origin}:${made.token}:${station.id}`), version: "0.5.0" }),
  });
  assert.equal(response.status, 200);
}

/** The team replies, as the console's admin or with the feedback monitor's token. */
const teamReply = (h: Harness, id: string, text: unknown, token = h.feedbackToken) =>
  h.fetch(`/v1/admin/feedback/${id}/reply`, { method: "POST", headers: { authorization: `Bearer ${token}`, "content-type": "application/json" }, body: JSON.stringify({ text }) });

/** The reporter's agent answers a report, as its station. */
const answer = (h: Harness, station: Station, value: unknown) => send(h, station, value, { path: "/v1/feedback/reply", tag: "stillfail-station-feedback-reply-v1" });

test("the team's reply is shown to the members of the chat's workspace, told on their events, and never to the station", async () => {
  const h = await harness();
  try {
    const { id: home, station, aliceTokens } = await workspace(h);
    const alice = h.as(aliceTokens);
    const carolTokens = await h.login("carol");
    await send(h, station, report({ context: { session: "chat:c-1", thread: "CHAT/1.1", workspace: home } }));
    const admin = h.as(aliceTokens, "admin");
    const listed = async () => ((await (await admin("GET", "/v1/admin/feedback")).json()) as any).feedback[0];
    const fb = (await listed()).id as string;
    assert.deepEqual((await listed()).replies, []);
    assert.deepEqual(((await (await alice("GET", `/v1/workspaces/${home}/feedback`)).json()) as any).feedback, [], "none replied on yet");

    const socket = await connect(h, station);
    const events = await listen(h, aliceTokens.access_token);
    const carol = await listen(h, carolTokens.access_token);
    await events.take();
    const made = await admin("POST", `/v1/admin/feedback/${fb}/reply`, { text: "  能发一下出错时的日志吗？ " });
    assert.equal(made.status, 201);
    const reply = (await made.json()) as any;
    assert.equal(reply.delivery, "pending");
    await h.settled();
    assert.deepEqual(await events.take(), [{ type: "feedback", workspace: home }]);
    assert.deepEqual(await carol.take(), [], "not a member");
    await socket.ping();
    assert.ok(!socket.frames.some((f) => f.type === "feedback" || JSON.stringify(f).includes("日志")), "nothing to the station");
    assert.equal((await send(h, station, { told: [] }, { path: "/v1/feedback/replies", tag: "stillfail-station-feedback-replies-v1" })).status, 404, "no way for a station to read them");

    const kept = (await listed()).replies;
    assert.deepEqual(kept.map((r: any) => [r.from, r.by, r.text, r.created_at, r.delivery]), [["team", "alice@example.test", "能发一下出错时的日志吗？", h.now(), "pending"]]);
    assert.equal((await listed()).updated_at, h.now());

    // A member's app reads it, which marks it delivered.
    const shown = ((await (await alice("GET", `/v1/workspaces/${home}/feedback`)).json()) as any).feedback;
    assert.deepEqual(shown.map((f: any) => [f.number, f.title, f.station, f.session, f.thread]), [[1, "chat_post 发不出去", station.id, "chat:c-1", "CHAT/1.1"]]);
    assert.deepEqual(shown[0].replies.map((r: any) => [r.from, r.name, r.text]), [["team", "", "能发一下出错时的日志吗？"]], "the team's, not the admin's email");
    assert.equal((await listed()).replies[0].delivery, "delivered");
    assert.equal((await h.as(carolTokens)("GET", `/v1/workspaces/${home}/feedback`)).status, 404, "not to one outside it");

    // The monitor replies with its token; the console's token and a made-up one are not it.
    assert.equal((await teamReply(h, fb, "绕过：重开一次 chat。")).status, 201);
    assert.notEqual((await teamReply(h, fb, "x", h.adminToken)).status, 201);
    assert.notEqual((await teamReply(h, fb, "x", "x".repeat(43))).status, 201);
    assert.deepEqual((await listed()).replies.map((r: any) => r.by), ["alice@example.test", "feedback-monitor"]);
    assert.equal((await teamReply(h, fb, " ")).status, 400);
    assert.equal((await teamReply(h, "0".repeat(26), "hi")).status, 404);
    socket.ws.close(1000);
  } finally {
    await h.close();
  }
});

test("a report from a chat of a workspace the station joined is that workspace's, not the station's home's", async () => {
  const h = await harness();
  try {
    const { id: home, station, aliceTokens } = await workspace(h);
    const bobTokens = await h.login("bob");
    const bob = h.as(bobTokens);
    const lab = ((await (await bob("POST", "/v1/workspaces", { name: "Lab" })).json()) as any).id as string;
    await join(h, bob, lab, station);
    // As a station from before says it: no workspace in its context, its chat's in the link; the report is its home's.
    await send(h, station, report({ context: { session: "chat:c-9", thread: "CHAT/9.9", link: `${h.origin}/o/${lab}/${station.id}/chat%3Ac-9` } }));
    // As stations say it now: the chat's workspace in the context.
    await send(h, station, report({ key: "k2", context: { session: "chat:c-8", workspace: lab } }));
    const admin = h.as(aliceTokens, "admin");
    const all = ((await (await admin("GET", "/v1/admin/feedback")).json()) as any).feedback;
    assert.deepEqual(all.map((f: any) => f.workspace.id), [home, home], "the reports' own workspace: the station's home");
    const bobEvents = await listen(h, bobTokens.access_token);
    const aliceEvents = await listen(h, aliceTokens.access_token);
    await bobEvents.take();
    await aliceEvents.take();
    for (const f of all) assert.equal((await teamReply(h, f.id, `看看 FB-${f.number}`)).status, 201);
    await h.settled();
    assert.deepEqual(await bobEvents.take(), [{ type: "feedback", workspace: lab }, { type: "feedback", workspace: lab }]);
    assert.deepEqual(await aliceEvents.take(), [], "the home's members are not the chat's");
    const shown = ((await (await bob("GET", `/v1/workspaces/${lab}/feedback`)).json()) as any).feedback;
    assert.deepEqual(shown.map((f: any) => [f.number, f.session]), [[2, "chat:c-8"], [1, "chat:c-9"]]);
    assert.deepEqual(((await (await h.as(aliceTokens)("GET", `/v1/workspaces/${home}/feedback`)).json()) as any).feedback, []);
  } finally {
    await h.close();
  }
});

test("a reply cannot reach a report from an account, or one whose chat cannot be told: refused as undeliverable", async () => {
  const h = await harness();
  try {
    const { station } = await workspace(h);
    const bob = h.as(await h.login("bob"));
    assert.equal((await bob("POST", "/v1/feedback", report())).status, 201);
    // From before stations said their chat's workspace, its link cut away.
    await send(h, station, report({ key: "k2", context: { session: "chat:c-1" } }));
    const outside = ((await (await bob("POST", "/v1/workspaces", { name: "Elsewhere" })).json()) as any).id as string;
    // Naming a workspace the station is not in.
    await send(h, station, report({ key: "k3", context: { session: "chat:c-2", workspace: outside } }));
    const admin = h.as(await h.login("alice"), "admin");
    const all = ((await (await admin("GET", "/v1/admin/feedback")).json()) as any).feedback;
    const [k3, k2, account] = all;
    assert.equal(account.station, null);
    for (const [f, reason] of [[account, "no_station"], [k2, "no_chat"], [k3, "no_chat"]] as const) {
      const refused = await admin("POST", `/v1/admin/feedback/${f.id}/reply`, { text: "能再说说吗？" });
      assert.equal(refused.status, 409);
      assert.deepEqual(await refused.json(), { error: "undeliverable", reason });
    }
    assert.ok(((await (await admin("GET", "/v1/admin/feedback")).json()) as any).feedback.every((f: any) => f.replies.length === 0), "none kept");
  } finally {
    await h.close();
  }
});

test("the chat's people answer in the app, or their agent answers for them: kept with the team's replies, the report updated", async () => {
  const h = await harness();
  try {
    const { id: home, station, aliceTokens } = await workspace(h);
    const alice = h.as(aliceTokens);
    await send(h, station, report({ context: { session: "chat:c-1", thread: "CHAT/1.1", workspace: home } }));
    const admin = h.as(aliceTokens, "admin");
    const fb = ((await (await admin("GET", "/v1/admin/feedback")).json()) as any).feedback[0].id as string;
    assert.equal((await teamReply(h, fb, "能发一下日志吗？")).status, 201);

    const events = await listen(h, aliceTokens.access_token);
    await events.take();
    const mine = await alice("POST", `/v1/workspaces/${home}/feedback/${fb}/reply`, { text: " 昨天下午三点左右 " });
    assert.equal(mine.status, 200);
    assert.match(((await mine.json()) as any).id, /^[0-9A-Z]{26}$/);
    const answered = await answer(h, station, { number: 1, text: "日志：ERROR chat_post 500", session: "chat:c-1" });
    assert.equal(answered.status, 201);
    await h.settled();
    assert.deepEqual(await events.take(), [{ type: "feedback", workspace: home }, { type: "feedback", workspace: home }]);

    const one = ((await (await admin("GET", "/v1/admin/feedback")).json()) as any).feedback[0];
    assert.deepEqual(one.replies.map((r: any) => [r.from, r.by, r.text]), [
      ["team", "feedback-monitor", "能发一下日志吗？"],
      ["reporter", `account:${one.replies[1].by.slice("account:".length)}`, "昨天下午三点左右"],
      ["reporter", "session:chat:c-1", "日志：ERROR chat_post 500"],
    ]);
    assert.equal(one.updated_at, h.now());
    const listed = (await (await h.fetch("/v1/admin/feedback/list", { method: "POST", headers: { authorization: `Bearer ${h.feedbackToken}`, "content-type": "application/json" }, body: "{}" })).json()) as any;
    assert.equal(listed.feedback[0].replies.length, 3, "the monitor reads them too");
    const shown = ((await (await alice("GET", `/v1/workspaces/${home}/feedback`)).json()) as any).feedback[0];
    assert.deepEqual(shown.replies.map((r: any) => [r.from, r.name]), [["team", ""], ["person", "Name of alice"], ["agent", ""]]);

    assert.equal((await alice("POST", `/v1/workspaces/${home}/feedback/${fb}/reply`, { text: " " })).status, 400);
    const carol = h.as(await h.login("carol"));
    assert.equal((await carol("POST", `/v1/workspaces/${home}/feedback/${fb}/reply`, { text: "hi" })).status, 404, "not a member");
    assert.equal((await answer(h, station, { number: 2, text: "hi" })).status, 404, "no such report");
    assert.equal((await answer(h, station, { number: 1, text: " " })).status, 400);
    const { station: other } = await workspace(h);
    assert.equal((await answer(h, other, { number: 1, text: "hi" })).status, 404, "another station's report");
  } finally {
    await h.close();
  }
});
