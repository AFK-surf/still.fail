import assert from "node:assert/strict";
import test from "node:test";
import { harness } from "./harness.ts";

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
    const api = (await h.mf.getWorker("api")) as unknown as { scheduled(options: { cron: string }): Promise<{ outcome: string }> };
    const cron = async () => assert.equal((await api.scheduled({ cron: "* * * * *" })).outcome, "ok");
    const states = (s: Status) => Object.fromEntries(s.services.map((v) => [v.name ?? v.id, v.state]));

    // Before any check there is nothing to say.
    const before = await status();
    assert.deepEqual(before.services.map((s) => s.id), ["site", "share", "api", "releases", "relay", "relay"]);
    assert.ok(before.services.every((s) => s.state === "unknown" && s.days.length === before.days && s.days.every((d) => d === null)));

    const bucket = (await h.mf.getR2Bucket("RELEASES", "api")) as unknown as { put(key: string, value: string): Promise<unknown> };
    await bucket.put("station.json", "{}");
    await cron();
    assert.deepEqual(asked, ["HEAD https://site.test/", "HEAD https://share.test/"]);
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
