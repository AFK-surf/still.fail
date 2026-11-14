// What a card in a chat reads of a station (a login's `machineLogin` and its station's `machineLogins`, a web
// service's `job`) is answered at once where it cannot come soon: the kept value where there is one; else, the station
// down or not in the list, that it is offline (or not listed); a job the station's lists do not have, that it is gone;
// a list of logins the station would not give, its no. So a chat that opens once its cards are answered (the app's
// sfbase chat_opens) waits only while they can still come; the station up again, they come.
import assert from "node:assert/strict";
import { test } from "node:test";
import type { HttpResponse } from "../src/host-of.ts";
import { HostError } from "../src/error.ts";
import { jsonResponse } from "../src/testing.ts";
import { t } from "../src/i18n.ts";
import { apply, subscribe, v } from "./helpers.ts";
import { base, started, stationLater, status } from "./station-fixture.ts";

const ST = "ws/st";

const device = { id: "l1", name: "gh", command: ["gh", "auth", "login"], state: "code", step: "device", url: "https://github.com/login/device", domain: "github.com", code: "1A2B-C3D4", waiting: false, by: { email: "a@x.com", name: "张三" }, startedAt: Date.UTC(2026, 9, 12, 4), expiresAt: 2 };
const job = { id: "j-web", session: "k1", name: "网页", state: "running", port: 5173, command: "pnpm dev", startedAt: 1 };

/// Each subscription's last word (`error`'s message, or "value") in what the core sent since.
const last = (emitted: [unknown, unknown][], id: number): string | undefined => {
  const m = emitted.map(([, m]) => m as any).filter((m) => m.id === id && ("error" in m || "value" in m || "delta" in m)).at(-1);
  return m === undefined ? undefined : "error" in m ? m.error.message : "value";
};

/// A core whose station is down from the start (never read), `answers` what it says once it is back.
async function downFromStart(answers: Record<string, unknown>) {
  const flag = { down: true };
  const s = await started(answers, 0, undefined, (s) => {
    stationLater(s.host, (req) => (flag.down && req.url.includes("/admin/api") ? Promise.reject(new HostError("连不上")) : undefined));
    s.gate.stream = "fail";
  });
  await s.host.time.pass(60_000, 1000);
  assert.equal((s.core.inner.stations.link(ST)?.state as { state: string }).state, "offline");
  const back = async () => {
    flag.down = false;
    s.gate.stream = "open";
    const n = s.streams.length;
    for (let waited = 0; s.streams.length <= n && waited < 20 * 60_000; waited += 250) await s.host.time.pass(250, 250);
    await s.host.time.pass(2000, 250);
  };
  return { ...s, back };
}

test("a login's topics of a station down, never read: offline at once; the station back, the login comes", async () => {
  const s = await downFromStart({ ...base(), "GET /machine-logins": { logins: [device] } });
  const ui = s.core.connect();
  subscribe(s.core, ui, 1, { topic: "machineLogin", station: ST, id: "l1" });
  subscribe(s.core, ui, 2, { topic: "machineLogins", station: ST });
  await s.host.time.pass(300, 50);
  const said = s.host.takeEmitted();
  const offline = t("core-views.station.unreachable", { name: "studio" });
  assert.equal(last(said, 1), offline);
  assert.equal(last(said, 2), offline);
  await s.back();
  const values = new Map();
  apply(s.host, values);
  assert.equal(v(values, 1).id, "l1");
  assert.equal(v(values, 2).logins.length, 1);
  s.core.close();
});

test("a login's topics of a station up that would not give its logins: its no at once, not nothing", async () => {
  const { host, core } = await started({ ...base(), "GET /machine-logins": status(500, { error: "logins unreadable", code: "io" }) });
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "machineLogin", station: ST, id: "l1" });
  await host.time.pass(300, 50);
  assert.equal(last(host.takeEmitted(), 1), "logins unreadable");
  core.close();
});

test("a web service's job: kept, shown while its station is down; never held, offline at once; gone, said so", async () => {
  // Read while up: kept.
  const kept = await downFromStart({ ...base(), "GET /jobs": [job] });
  await kept.back();
  const ui = kept.core.connect();
  subscribe(kept.core, ui, 1, { topic: "job", station: ST, id: "j-web" });
  subscribe(kept.core, ui, 2, { topic: "job", station: ST, id: "j-gone" });
  await kept.host.time.pass(300, 50);
  const up = kept.host.takeEmitted();
  assert.equal(last(up, 1), "value");
  assert.equal(last(up, 2), t("core-views.station.job_gone", { name: "studio" }), "a job its station's lists have not: gone, not nothing");
  kept.core.close();
  // Never held, the station down: offline at once; back, the job comes.
  const s = await downFromStart({ ...base(), "GET /jobs": [job] });
  const ui2 = s.core.connect();
  subscribe(s.core, ui2, 1, { topic: "job", station: ST, id: "j-web" });
  await s.host.time.pass(300, 50);
  assert.equal(last(s.host.takeEmitted(), 1), t("core-views.station.unreachable", { name: "studio" }));
  await s.back();
  const values = new Map();
  apply(s.host, values);
  assert.equal(v(values, 1).id, "j-web");
  s.core.close();
});

test("a card's topics of a station not in the list: not listed at once", async () => {
  const { host, core } = await started();
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "machineLogin", station: "ws/other", id: "l1" });
  subscribe(core, ui, 2, { topic: "job", station: "ws/other", id: "j-web" });
  await host.time.pass(300, 50);
  const said = host.takeEmitted();
  assert.equal(last(said, 1), t("core-views.station.not_listed"));
  assert.equal(last(said, 2), t("core-views.station.not_listed"));
  core.close();
});

test("a job of a station up whose jobs are not read yet: nothing, never gone; its list read, the job, or gone", async () => {
  for (const has of [true, false]) {
    let release: (r: HttpResponse) => void = () => {};
    const held = new Promise<HttpResponse>((r) => (release = r));
    let first = true;
    const { host, core } = await started({ ...base(), "GET /jobs": [] }, 0, undefined, (s) => {
      stationLater(s.host, (req) => {
        if (!first || !/\/admin\/api\/jobs(\?|$)/.test(new URL(req.url).pathname + new URL(req.url).search)) return undefined;
        first = false;
        return held;
      });
    });
    const ui = core.connect();
    subscribe(core, ui, 1, { topic: "job", station: ST, id: "j-web" });
    await host.time.pass(300, 50);
    const before = host.takeEmitted();
    assert.equal(last(before, 1), undefined, "its jobs not read yet: nothing said of it");
    release(jsonResponse(200, has ? [job] : []));
    await host.time.pass(300, 50);
    const after = host.takeEmitted();
    if (has) {
      assert.equal(last(after, 1), "value");
      assert.ok(!after.some(([, m]) => (m as any).id === 1 && "error" in (m as any)), "never gone before it came");
    } else {
      assert.equal(last(after, 1), t("core-views.station.job_gone", { name: "studio" }));
    }
    core.close();
  }
});
