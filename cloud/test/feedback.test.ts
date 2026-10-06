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
  const enrollment = (await (await alice("POST", `/v1/workspaces/${id}/enrollments`, { name: "studio" })).json()) as any;
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
  context: { version: "0.1.1309", session: "ember:c-1", runtime: "claude" },
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
    assert.deepEqual(one.station, { id: station.id, name: "studio" });
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
    await send(h, station, report({ context: { session: "ember:c-1", thread: "EMBER/1.1" } }));
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
    assert.equal(out[0].session, "ember:c-1");
    assert.equal(out[0].thread, "EMBER/1.1");
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
    await bucket.put("desktop/stillfail-mac.yml", "version: 0.1.1300\npath: x.zip\n");
    const stable = (await (await h.fetch("/v1/changelog")).json()) as any;
    assert.equal(stable.entries[0].text[0], "新功能：更新日志");
    assert.deepEqual(stable.released, { station: null, android: null, desktop: 1300, web: 1338 });
    const beta = (await (await h.fetch("/v1/changelog", { headers: { "x-stillfail-channel": "beta" } })).json()) as any;
    assert.equal(beta.released.web, 1340);
  } finally {
    await h.close();
  }
});
