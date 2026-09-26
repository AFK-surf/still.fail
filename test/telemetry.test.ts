import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { createServer, type IncomingMessage } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { gunzipSync } from "node:zlib";
import { PostHog } from "posthog-node";
import { parseConfig } from "../src/config.ts";
import { log } from "../src/log.ts";
import { builtKey, ErrorReports, scrubMessage, scrubPaths, type ReportClient } from "../src/telemetry.ts";
import { pathTemplate } from "../web/src/telemetry.ts";

const HOME = "/Users/alice";

test("paths under home directories lose the home; quoted text in messages is cut", () => {
  assert.equal(scrubPaths("at /Users/alice/ember/src/hub.ts:12:3", HOME), "at ~/ember/src/hub.ts:12:3");
  assert.equal(scrubPaths("ENOENT: open '/home/bob/.ember/x.json'", HOME), "ENOENT: open '~/.ember/x.json'");
  assert.equal(scrubPaths("file:///Users/carol/a.ts", HOME), "file://~/a.ts");
  assert.equal(scrubMessage(`Unexpected token 'h', "hello there" is not valid JSON`, HOME), `Unexpected token '…', "…" is not valid JSON`);
  assert.equal(scrubMessage("没有找到「周报草稿」", HOME), "没有找到「…」");
  assert.equal(scrubMessage("session task failed", HOME), "session task failed");
});

test("station error reports are off by default", () => {
  assert.deepEqual(parseConfig({}, "/tmp/ember").telemetry, { errors: false });
  assert.deepEqual(parseConfig({ telemetry: { errors: true } }, "/tmp/ember").telemetry, { errors: true });
  let made = 0;
  const captured: unknown[] = [];
  const client: ReportClient = { captureException: (error: unknown) => void captured.push(error), shutdown: async () => undefined };
  const reports = new ErrorReports({
    key: { host: "http://127.0.0.1:9", key: "phc_test", release: "abc" }, enabled: () => false, station: () => null,
    client: () => { made++; return client; },
  });
  log.error("something failed", { error: new Error("boom") });
  assert.equal(made, 0);
  assert.equal(reports.active, false);
  assert.deepEqual(captured, []);
  void reports.shutdown();
});

test("without a key in the build nothing is reported, whatever the config says", () => {
  assert.equal(builtKey(mkdtempSync(join(tmpdir(), "ember-ui-"))), null);
  let made = 0;
  const reports = new ErrorReports({ key: null, enabled: () => true, station: () => "st1", client: () => { made++; throw new Error("unreachable"); } });
  log.error("something failed");
  assert.equal(made, 0);
  void reports.shutdown();
});

test("reports go out scrubbed, with the station and release and no log fields; turning off stops them", async () => {
  const bodies: { batch?: { event: string; distinct_id: string; properties: Record<string, any> }[] }[] = [];
  const server = createServer((req: IncomingMessage, res) => {
    const chunks: Buffer[] = [];
    req.on("data", (chunk: Buffer) => chunks.push(chunk));
    req.on("end", () => {
      const raw = Buffer.concat(chunks);
      const text = req.headers["content-encoding"] === "gzip" ? gunzipSync(raw).toString("utf8") : raw.toString("utf8");
      if (req.url?.startsWith("/batch")) bodies.push(JSON.parse(text));
      res.writeHead(200, { "content-type": "application/json" }).end("{}");
    });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address() as { port: number };
  const ui = mkdtempSync(join(tmpdir(), "ember-ui-"));
  writeFileSync(join(ui, "posthog.json"), JSON.stringify({ host: `http://127.0.0.1:${port}`, key: "phc_test", release: "abc123" }));
  let on = true;
  // The real client, with a count of what passed its before_send: building an event is asynchronous.
  let decided = 0;
  const reports = new ErrorReports({
    key: builtKey(ui), enabled: () => on, station: () => "st1", home: HOME,
    client: (key, beforeSend) => new PostHog(key.key, { host: key.host, before_send: (event) => { decided++; return beforeSend(event); } }),
  });
  assert.equal(reports.active, true);

  const error = new Error(`cannot read /Users/alice/.ember/sessions/x: "the secret plan"`);
  error.stack = `Error: cannot read /Users/alice/.ember/sessions/x: "the secret plan"\n    at run (/Users/alice/ember/src/hub.ts:10:5)`;
  log.error("session task failed", { session: "k", text: "what someone wrote", error });
  while (decided < 1) await new Promise((resolve) => setTimeout(resolve, 5));
  on = false;
  log.error("after turning off", { error: new Error("nope") });
  await reports.shutdown();
  server.close();

  const events = bodies.flatMap((b) => b.batch ?? []);
  assert.equal(events.length, 1);
  const [event] = events;
  assert.equal(event!.event, "$exception");
  assert.equal(event!.distinct_id, "station:st1");
  const props = event!.properties;
  assert.equal(props.station, "st1");
  assert.equal(props.release, "abc123");
  assert.equal(props.log, "session task failed");
  assert.equal(props.$process_person_profile, false);
  assert.equal(props.$exception_list[0].value, `cannot read ~/.ember/sessions/x: "…"`);
  const sent = JSON.stringify(event);
  assert.ok(!sent.includes("/Users/alice"), sent);
  assert.ok(!sent.includes("secret plan"), sent);
  assert.ok(!sent.includes("what someone wrote"), sent);
  assert.equal(props.$exception_list[0].stacktrace.frames[0].function, "run");
});

test("web paths lose their ids", () => {
  assert.equal(pathTemplate("/w/ws1/s/st9/chats/42"), "/w/:workspace/s/:station/chats/:thread");
  assert.equal(pathTemplate("/w/ws1/settings/stations"), "/w/:workspace/settings/stations");
  assert.equal(pathTemplate("/admin/settings/accounts/claude-a"), "/admin/settings/accounts/:profile");
  assert.equal(pathTemplate("/admin/chats"), "/admin/chats");
  assert.equal(pathTemplate("/admin/connects/cue"), "/admin/connects/:connect");
});
