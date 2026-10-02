// The station's error reports (telemetry.rs's tests): scrubbed, off by default, only with a built key.
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { ErrorReports, builtKey, scrubMessage, scrubPaths } from "../src/ops/telemetry.ts";

const HOME = "/Users/alice";

test("paths under home directories lose the home; quoted text in messages is cut", () => {
  assert.equal(scrubPaths("at /Users/alice/ember/src/hub.ts:12:3", HOME), "at ~/ember/src/hub.ts:12:3");
  assert.equal(scrubPaths("ENOENT: open '/home/bob/.ember/x.json'", HOME), "ENOENT: open '~/.ember/x.json'");
  assert.equal(scrubPaths("file:///Users/carol/a.ts", HOME), "file://~/a.ts");
  assert.equal(scrubMessage(`Unexpected token 'h', "hello there" is not valid JSON`, HOME), `Unexpected token '…', "…" is not valid JSON`);
  assert.equal(scrubMessage("没有找到「周报草稿」", HOME), "没有找到「…」");
  assert.equal(scrubMessage("session task failed", HOME), "session task failed");
});

test("without a key in the build, or turned off, nothing is reported", async () => {
  assert.equal(builtKey(mkdtempSync(join(tmpdir(), "ui-"))), null);
  const none = new ErrorReports({ key: null, enabled: () => true, station: () => "st1", home: HOME });
  assert.equal(none.active(), false);
  const off = new ErrorReports({ key: { host: "http://127.0.0.1:9", key: "k", release: "r" }, enabled: () => false, station: () => "st1", home: HOME });
  off.report("x", "y");
  assert.equal(off.active(), false);
  await off.shutdown();
});

test("reports go out scrubbed, with the station and release; turning off stops them", async () => {
  const bodies: any[] = [];
  const server = createServer((req, res) => {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      bodies.push(JSON.parse(body));
      res.writeHead(200, { "content-type": "application/json" }).end("{}");
    });
  }).listen(0, "127.0.0.1");
  await new Promise((r) => server.once("listening", r));
  const ui = mkdtempSync(join(tmpdir(), "ui-"));
  writeFileSync(join(ui, "posthog.json"), JSON.stringify({ host: `http://127.0.0.1:${(server.address() as AddressInfo).port}`, key: "phc_test", release: "abc123" }));
  let on = true;
  const reports = new ErrorReports({ key: builtKey(ui), enabled: () => on, station: () => "st1", home: HOME });
  assert.ok(reports.active());
  reports.report("session task failed", `cannot read /Users/alice/.ember/sessions/x: "the secret plan"`);
  on = false;
  reports.report("after turning off", "nope");
  await reports.shutdown();
  server.close();
  const events = bodies.flatMap((b) => b.batch);
  assert.equal(events.length, 1);
  const [event] = events;
  assert.deepEqual([event.event, event.distinct_id], ["$exception", "station:st1"]);
  assert.deepEqual([event.properties.station, event.properties.release, event.properties.log], ["st1", "abc123", "session task failed"]);
  assert.equal(event.properties.$process_person_profile, false);
  assert.equal(event.properties.$exception_list[0].value, `cannot read ~/.ember/sessions/x: "…"`);
  const sent = JSON.stringify(event);
  assert.ok(!sent.includes("/Users/alice") && !sent.includes("secret plan"), sent);
  assert.equal(bodies[0].api_key, "phc_test");
});
