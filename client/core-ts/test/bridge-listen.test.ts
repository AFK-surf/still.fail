// A login's loopback listener on a shell's bridge (hosts/bridge.ts `listen`; docs/remote-login.md), the shell here in
// JavaScript (node-shell.ts) as the Android app's is in Kotlin (Loopback.kt): what comes to it, a request at a time with
// its method, path, headers and body, answered once; the port taken there refused; closed with its scope.
import assert from "node:assert/strict";
import { request as httpRequest } from "node:http";
import { createServer } from "node:net";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Effect, Exit, Scope } from "effect";
import { Bridge, BridgeHost } from "../src/hosts/bridge.ts";
import { NodeShell } from "./node-shell.ts";

function shell() {
  const native = new NodeShell(mkdtempSync(join(tmpdir(), "bridge-listen-")));
  const bridge = new Bridge(native);
  native.bridge = bridge;
  return { native, host: new BridgeHost(bridge, "http://127.0.0.1:1", false) };
}

/// A port nothing listens on now.
const freePort = () =>
  new Promise<number>((resolve) => {
    const s = createServer().listen(0, "127.0.0.1", () => {
      const port = (s.address() as { port: number }).port;
      s.close(() => resolve(port));
    });
  });

/// What the browser does: one request to the loopback port, its answer.
const ask = (port: number, method: string, path: string, headers: Record<string, string>, body = "") =>
  new Promise<{ status: number; headers: Record<string, unknown>; body: string }>((resolve, reject) => {
    const r = httpRequest({ host: "127.0.0.1", port, method, path, headers }, (res) => {
      const parts: Buffer[] = [];
      res.on("data", (c: Buffer) => parts.push(c));
      res.on("end", () => resolve({ status: res.statusCode ?? 0, headers: res.headers, body: Buffer.concat(parts).toString() }));
    });
    r.on("error", reject);
    r.end(body);
  });

test("a loopback listener on the bridge: each request as it came, answered once; the port taken refused; closed with its scope", async () => {
  const { host, native } = shell();
  const port = await freePort();
  const scope = Effect.runSync(Scope.make());
  const pull = await Effect.runPromise(Scope.provide(host.listen(port, "127.0.0.1"), scope));
  assert.ok(native.calls.includes("listen.open"));
  // A form posted (az's form_post): its body and headers as they came.
  const answer = ask(port, "POST", "/?x=1", { Host: `localhost:${port}`, "Content-Type": "application/x-www-form-urlencoded" }, "code=c0de&state=s3");
  const r = (await Effect.runPromise(pull.take))!;
  assert.equal(r.method, "POST");
  assert.equal(r.path, "/?x=1");
  assert.deepEqual(r.headers.find(([k]) => k.toLowerCase() === "host"), ["Host", `localhost:${port}`]);
  assert.equal(new TextDecoder().decode(r.body), "code=c0de&state=s3");
  r.respond(302, [["Location", "https://example.com/done"], ["Content-Type", "text/html"]], new TextEncoder().encode("<p>signed in</p>"));
  // A second answer to the same request is let go.
  r.respond(500, [], new Uint8Array(0));
  const got = await answer;
  assert.equal(got.status, 302);
  assert.equal(got.headers.location, "https://example.com/done");
  assert.equal(got.body, "<p>signed in</p>");
  assert.equal(native.calls.filter((c) => c === "listen.respond").length, 1);
  // The next one, a GET with its query.
  const second = ask(port, "GET", "/callback?code=1&state=s", { Host: `127.0.0.1:${port}` });
  const r2 = (await Effect.runPromise(pull.take))!;
  assert.deepEqual([r2.method, r2.path, r2.body.length], ["GET", "/callback?code=1&state=s", 0]);
  r2.respond(404, [], new TextEncoder().encode("no"));
  assert.equal((await second).status, 404);
  // Taken while it listens: a second listener on the port fails, before anything is opened.
  const again = await Effect.runPromise(Effect.result(Effect.scoped(host.listen(port, "127.0.0.1"))));
  assert.equal(again._tag, "Failure");
  // Only loopback, ever.
  const anywhere = await Effect.runPromise(Effect.result(Effect.scoped(host.listen(port, "0.0.0.0"))));
  assert.equal(anywhere._tag, "Failure");
  assert.equal(native.calls.filter((c) => c === "listen.open").length, 2, "0.0.0.0 never asked of the shell");
  // Closed with its scope: the port is free again.
  await Effect.runPromise(Scope.close(scope, Exit.void));
  assert.ok(native.calls.includes("listen.close"));
  const scope2 = Effect.runSync(Scope.make());
  await Effect.runPromise(Scope.provide(host.listen(port, "127.0.0.1"), scope2));
  await Effect.runPromise(Scope.close(scope2, Exit.void));
});
