import assert from "node:assert/strict";
import test from "node:test";
import { exportJWK, generateKeyPair, SignJWT } from "jose";
import { harness } from "./harness.ts";

// A cron at a minute that is only the every-minute one's (not the hourly models' at :07, not a probe's): the real
// clock's minute made the hourly catalog's fetch of models.dev run in the test at :07 (2026-11-08, run 42469996303).
const EVERY_MINUTE_ONLY = new Date(Date.UTC(2026, 0, 1, 0, 1));

type Status = { now: number; days: number; services: { id: string; state: string; name?: string; relay?: string; days: (number | null)[] }[] };

test("the status page's numbers: what the cron found of each service, a failure counted down only from the second in a row", async () => {
  const beijing = "https://203.0.113.7";
  let share = 200;
  const asked: string[] = [];
  const h = await harness({
    relayUrls: beijing,
    relayNames: { [beijing]: "北京" },
    statusPages: { site: "https://site.test/", share: "https://share.test/" },
    push: (request) => {
      asked.push(`${request.method} ${request.url}`);
      return { status: request.url === "https://share.test/" ? share : 200 };
    },
  });
  try {
    const status = async () => {
      const answer = await h.fetch("/v1/status");
      assert.equal(answer.status, 200);
      // The site's page is on a host of its own.
      assert.equal(answer.headers.get("access-control-allow-origin"), "*");
      return (await answer.json()) as Status;
    };
    const api = (await h.mf.getWorker("api")) as unknown as { scheduled(options: { cron: string; scheduledTime: Date }): Promise<{ outcome: string }> };
    const cron = async () => assert.equal((await api.scheduled({ cron: "* * * * *", scheduledTime: EVERY_MINUTE_ONLY })).outcome, "ok");
    const states = (s: Status) => Object.fromEntries(s.services.map((v) => [v.name ?? v.id, v.state]));

    // Before any check there is nothing to say.
    const before = await status();
    assert.deepEqual(before.services.map((s) => s.id), ["site", "share", "api", "releases", "relay", "relay"]);
    assert.ok(before.services.every((s) => s.state === "unknown" && s.days.length === before.days && s.days.every((d) => d === null)));

    const bucket = (await h.mf.getR2Bucket("RELEASES", "api")) as unknown as { put(key: string, value: string): Promise<unknown> };
    await bucket.put("station.json", "{}");
    await cron();
    // The page checks run in parallel; either request can reach the mock first.
    assert.deepEqual([...asked].sort(), ["HEAD https://share.test/", "HEAD https://site.test/"]);
    // The first of a relay's failures is not counted as down either.
    // still.fail's own relay's counters come from the same cron; Beijing's have not come.
    const own = new URL(h.origin).host;
    assert.deepEqual(states(await status()), { site: "up", share: "up", api: "up", releases: "up", [own]: "up", 北京: "up" });
    await cron();
    assert.equal(states(await status()).北京, "down");

    const load = "relayserver_bytes_sent_total 1\n";
    assert.equal((await h.fetch("/v1/relays/load", { method: "POST", headers: { "x-stillfail-relay": beijing, "cf-connecting-ip": "203.0.113.7" }, body: load })).status, 200);
    await cron();
    const up = await status();
    assert.equal(states(up).北京, "up");
    assert.equal(up.services.find((s) => s.name === "北京")!.relay, beijing);

    // One failed check is often the check's own line; the second in a row is not.
    share = 502;
    await cron();
    assert.equal(states(await status()).share, "up");
    await cron();
    const down = await status();
    assert.equal(states(down).share, "down");
    // Today is the last day; three of its five checks passed.
    assert.equal(down.services.find((s) => s.id === "share")!.days.at(-1), 0.6);
    assert.equal(down.services.find((s) => s.id === "site")!.days.at(-1), 1);

    share = 200;
    await cron();
    assert.equal(states(await status()).share, "up");
  } finally {
    await h.close();
  }
});

test("incidents come from the repository's workflow alone, and show as its issues say: opened, then closed", async () => {
  const { publicKey, privateKey } = await generateKeyPair("RS256");
  const jwk = { ...(await exportJWK(publicKey)), kid: "actions", alg: "RS256", use: "sig" };
  const h = await harness({
    statusRepo: "o/r",
    push: (request) => {
      assert.equal(request.url, "https://token.actions.githubusercontent.com/.well-known/jwks");
      return { status: 200, body: JSON.stringify({ keys: [jwk] }) };
    },
  });
  try {
    const token = (claims: Record<string, unknown>, audience = h.origin) => new SignJWT({ repository: "o/r", workflow_ref: "o/r/.github/workflows/status-incidents.yml@refs/heads/main", ...claims })
      .setProtectedHeader({ alg: "RS256", kid: "actions" }).setIssuer("https://token.actions.githubusercontent.com").setAudience(audience).setIssuedAt().setExpirationTime("10 years").sign(privateKey);
    const send = async (bearer: string | null, issues: unknown) => (await h.fetch("/v1/status/incidents", { method: "POST", headers: bearer ? { authorization: `Bearer ${bearer}` } : {}, body: JSON.stringify(issues) })).status;
    const incidents = async () => ((await (await h.fetch("/v1/status")).json()) as { incidents: unknown[] }).incidents;

    const issue = { number: 7, html_url: "https://github.com/o/r/issues/7", title: "Stations will not open", body: "started: 2030-01-01T10:00:00Z\n\nStable apps fail on it.", created_at: "2030-01-01T11:00:00Z", closed_at: null as string | null, labels: [{ name: "incident" }, { name: "P1" }] };
    const pullRequest = { number: 8, html_url: "x", title: "a pull request", created_at: "2030-01-01T11:00:00Z", pull_request: {}, labels: [] };

    // Nobody else's: no token, another repository's, another workflow's or branch's, one meant for elsewhere.
    assert.equal(await send(null, [issue]), 401);
    assert.equal(await send(await token({ repository: "fork/r" }), [issue]), 401);
    assert.equal(await send(await token({ workflow_ref: "o/r/.github/workflows/other.yml@refs/heads/main" }), [issue]), 401);
    assert.equal(await send(await token({ workflow_ref: "o/r/.github/workflows/status-incidents.yml@refs/heads/mine" }), [issue]), 401);
    assert.equal(await send(await token({}, "https://elsewhere.example"), [issue]), 401);
    assert.deepEqual(await incidents(), []);

    const good = await token({});
    assert.equal(await send(good, { not: "a list" }), 400);
    assert.equal(await send(good, [issue, pullRequest]), 200);
    const open = { number: 7, url: issue.html_url, level: "P1", title: issue.title, body: "Stable apps fail on it.", start: "2030-01-01T10:00:00Z", end: null };
    assert.deepEqual(await incidents(), [open]);
    assert.equal(await send(good, [{ ...issue, closed_at: "2030-01-01T12:00:00Z" }]), 200);
    assert.deepEqual(await incidents(), [{ ...open, end: "2030-01-01T12:00:00Z" }]);
  } finally {
    await h.close();
  }
});
