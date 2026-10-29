// The station's log as it leaves the machine (ops/log-export.ts): scrubbed, on unless turned off, held until it can go.
import assert from "node:assert/strict";
import { test } from "node:test";
import { LogExport, record, scrubText } from "../src/ops/log-export.ts";
import type { Line } from "../src/ops/log.ts";

const HOME = "/Users/alice";
const line = (message: string, fields: Record<string, unknown> = {}, level: Line["level"] = "INFO"): Line => ({ ms: 1_000, level, at: "share", message, fields });
const attrs = (r: ReturnType<typeof record>) => Object.fromEntries(r.attributes.map((a) => [a.key, Object.values(a.value)[0]]));

test("what leaves has no home, email, key or quoted text", () => {
  assert.equal(scrubText("open /Users/alice/.stillfail/run/x.json", HOME), "open ~/.stillfail/run/x.json");
  assert.equal(scrubText("client connected by bob@example.com", HOME), "client connected by <email>");
  assert.equal(scrubText("profile zzj3720-gmail-com crashed", HOME), "profile <email> crashed");
  assert.equal(scrubText("token sk-ant-api03-abcdefghijklmnopqrstuv refused", HOME), "token <secret> refused");
  assert.equal(scrubText("bearer eyJhbGciOiJFZERTQSJ9.eyJzdWIiOiJhbGljZSJ9.c2ln", HOME), "bearer <secret>");
  assert.equal(scrubText(`Unexpected token, "my secret plan" is not valid JSON`, HOME), `Unexpected token, "…" is not valid JSON`);
  // What a station is said by stays: its id, the error's own words, numbers.
  assert.equal(scrubText("workspace peer roster is not current; waiting for the control plane", HOME), "workspace peer roster is not current; waiting for the control plane");
});

test("fields people wrote are not sent; a workspace goes by its id, not its name", () => {
  const r = record(line("a notice", { text: "the chat's words", name: "acme-customer", workspace: "Acme Inc", peer: "c3ba7d15c23f", ms: 12, error: "at /home/bob/x" }, "WARN"), HOME);
  assert.equal(r.severityText, "WARN");
  assert.equal(r.severityNumber, 13);
  assert.deepEqual(attrs(r), { "log.target": "share", "log.text": "…", "log.name": "…", "log.workspace": "…", "log.peer": "c3ba7d15c23f", "log.ms": "12", "log.error": "at ~/x" });
  assert.equal(attrs(record(line("x", { workspace: "01M3DB2N6P5SY7PJ7RG1F62TRX" }), HOME))["log.workspace"], "01M3DB2N6P5SY7PJ7RG1F62TRX");
  // Within an object too, its keys kept.
  assert.equal(attrs(record(line("x", { by: { email: "a@b.co", n: 1 } }), HOME))["log.by"], JSON.stringify({ email: "<email>", n: 1 }));
});

test("lines wait for the control plane, go in batches with the station, and stop at once when turned off", async () => {
  let on = true;
  let station: string | null = null;
  const out = new LogExport();
  out.configure({ enabled: () => on, station: () => station, version: () => "0.1.9", home: HOME });
  const sent: any[] = [];
  out.add(line("before the mesh"));
  await out.flush();
  assert.equal(sent.length, 0);
  out.sendWith(async (body) => void sent.push(JSON.parse(body)));
  await out.flush();
  assert.equal(sent.length, 0, "not enrolled yet: kept");
  station = "st1";
  out.add(line("presence: online", {}, "WARN"));
  await out.flush();
  assert.equal(sent.length, 1);
  const resource = Object.fromEntries(sent[0].resourceLogs[0].resource.attributes.map((a: any) => [a.key, a.value.stringValue]));
  assert.deepEqual(resource, { "service.name": "stillfail-station", "service.version": "0.1.9", "stillfail.station": "st1" });
  assert.deepEqual(sent[0].resourceLogs[0].scopeLogs[0].logRecords.map((r: any) => r.body.stringValue), ["before the mesh", "presence: online"]);
  on = false;
  out.add(line("after it is off"));
  await out.flush();
  assert.equal(sent.length, 1);
  await out.shutdown();
});

test("a batch that cannot go is dropped, and lines past what waits are counted", async () => {
  const out = new LogExport();
  out.configure({ enabled: () => true, station: () => "st1", version: () => "0.1.9", home: HOME });
  let fail = true;
  const sent: any[] = [];
  out.sendWith(async (body) => {
    if (fail) throw new Error("answered 503");
    sent.push(JSON.parse(body));
  });
  out.add(line("lost"));
  await out.flush();
  fail = false;
  for (let i = 0; i < 5_010; i++) out.add(line(`n${i}`));
  await out.flush();
  const records = sent.flatMap((b) => b.resourceLogs[0].scopeLogs[0].logRecords);
  assert.equal(records[0].body.stringValue, "n10");
  assert.ok(sent.every((b) => b.resourceLogs[0].scopeLogs[0].logRecords.length <= 501));
  const said = records.find((r: any) => r.body.stringValue === "log lines dropped before they could be sent");
  assert.equal(said?.attributes.find((a: any) => a.key === "log.dropped")?.value.intValue, "10");
  assert.equal(records.filter((r: any) => r.body.stringValue.startsWith("n")).length, 5_000);
  await out.shutdown();
});
