// The variables a station's owners set for what it starts for its agents (src/ops/agent-env.ts, routes/agent-env.ts;
// docs/agent-env.md): what config.json may hold, the environment the runtimes, logins and jobs get (over the station's
// own, scrubbed as before, this machine kept out of a proxy), the station's requests on a profile's behalf going through
// the proxy named (and not for this machine), and the page's PUT: owners and admins only, null removing one, one left
// out staying, a secret's value masked, the sessions told once something changed. The proxy is a local server noting
// what it is asked.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import http from "node:http";
import https from "node:https";
import net from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import tls from "node:tls";
import { checkConfig } from "../src/accounts/check.ts";
import { cleanEnv } from "../src/agents/runtime.ts";
import { agentEnvView, routes } from "../src/api/routes/agent-env.ts";
import type { Request } from "../src/api/request.ts";
import { ConfigFile } from "../src/ops/config.ts";
import { makeCa, makeLeaf, pem } from "../src/vault/x509.ts";
import { agentEnv, checkAgentEnv, keepLocal, maskValue, parseEnvText, profileFetch, readAgentEnvFrom, startEnv } from "../src/ops/agent-env.ts";

const owner: Request["viewer"] = { sub: "u", email: "o@x", name: "O", role: "owner", workspace: "w", device: "d" };
const member: Request["viewer"] = { ...owner, email: "m@x", role: "member" };

test("config.json's agentEnv is a map of variables to one-line strings", () => {
  checkAgentEnv(undefined);
  checkAgentEnv({ HTTPS_PROXY: "http://127.0.0.1:7890", no_proxy: "corp.example" });
  assert.throws(() => checkAgentEnv(["HTTPS_PROXY"]), /a map/);
  assert.throws(() => checkAgentEnv({ "1BAD": "x" }), /invalid environment variable name 1BAD/);
  assert.throws(() => checkAgentEnv({ HTTPS_PROXY: 7890 }), /agentEnv.HTTPS_PROXY: a string/);
  assert.throws(() => checkAgentEnv({ HTTPS_PROXY: "a\nb" }), /one line/);
  // As the station takes config.json.
  assert.throws(() => checkConfig({ agentEnv: { "A-B": "x" } }, "/tmp"), /invalid environment variable name A-B/);
  checkConfig({ agentEnv: { HTTPS_PROXY: "http://p:1" } }, "/tmp");
  // Read leniently: what is not a variable is left out.
  assert.deepEqual(agentEnv({ agentEnv: { OK: "1", "NO WAY": "2", N: 3 } }), { OK: "1" });
  assert.deepEqual(agentEnv({}), {});
});

test("the variables as written: a .env file's lines, a secret left masked kept, the first line wrong said", () => {
  const kept = { API_TOKEN: "tok-1234567890", HTTPS_PROXY: "http://user:pw@proxy:3128" };
  assert.deepEqual(parseEnvText([
    "# comment",
    "",
    "export HTTPS_PROXY = 'http://127.0.0.1:7890'",
    `API_TOKEN=${maskValue(kept.API_TOKEN)}`,
    "NO_PROXY=a,b",
    "NO_PROXY=c",
    "EMPTY=",
  ].join("\r\n"), kept), { HTTPS_PROXY: "http://127.0.0.1:7890", API_TOKEN: "tok-1234567890", NO_PROXY: "c", EMPTY: "" });
  // A masked value of what was not a secret is taken as written.
  assert.deepEqual(parseEnvText("PLAIN=abcde…7890", { PLAIN: "abcdefghij7890" }), { PLAIN: "abcde…7890" });
  assert.deepEqual(parseEnvText("A=1\nhttp_proxy http://x"), { line: 2, why: "notPair" });
  assert.deepEqual(parseEnvText("=x"), { line: 1, why: "notPair" });
  assert.deepEqual(parseEnvText("1A=x"), { line: 1, why: "badName", name: "1A" });
  assert.deepEqual(parseEnvText(`A=${"x".repeat(4097)}`), { line: 1, why: "tooLong", name: "A" });
  assert.deepEqual(parseEnvText(Array.from({ length: 65 }, (_, i) => `V${i}=1`).join("\n")), { line: 0, why: "tooMany" });
});

test("with a proxy, this machine is left out of it in both cases of NO_PROXY, beside what they name", () => {
  assert.deepEqual(keepLocal({ PATH: "/bin" }), { PATH: "/bin" });
  const local = "localhost,127.0.0.1,::1";
  assert.deepEqual(keepLocal({ HTTPS_PROXY: "http://p:1" }), { HTTPS_PROXY: "http://p:1", NO_PROXY: local, no_proxy: local });
  assert.deepEqual(keepLocal({ https_proxy: "http://p:1", no_proxy: "corp.example,localhost" }), { https_proxy: "http://p:1", NO_PROXY: "corp.example,localhost,127.0.0.1,::1", no_proxy: "corp.example,localhost,127.0.0.1,::1" });
  assert.deepEqual(keepLocal({ ALL_PROXY: "socks5://p:1", NO_PROXY: "*" }), { ALL_PROXY: "socks5://p:1", NO_PROXY: "*" });
});

test("what the station starts gets its variables over its own environment, scrubbed as before", (t) => {
  t.after(() => readAgentEnvFrom(() => null));
  const saved = { ...process.env };
  t.after(() => {
    for (const k of Object.keys(process.env)) if (!(k in saved)) delete process.env[k];
    Object.assign(process.env, saved);
  });
  process.env.AGENT_ENV_TEST_OWN = "own";
  process.env.AGENT_ENV_TEST_BOTH = "station's";
  let raw: any = { agentEnv: { AGENT_ENV_TEST_BOTH: "set", HTTPS_PROXY: "http://127.0.0.1:7890", OPENAI_API_KEY: "sk-not-for-runtimes" } };
  readAgentEnvFrom(() => raw);
  const env = cleanEnv(["OPENAI_API_KEY"]);
  assert.equal(env.AGENT_ENV_TEST_OWN, "own");
  assert.equal(env.AGENT_ENV_TEST_BOTH, "set");
  assert.equal(env.HTTPS_PROXY, "http://127.0.0.1:7890");
  assert.match(env.NO_PROXY!, /(^|,)127\.0\.0\.1(,|$)/);
  // A variable that would sign a runtime in as something other than its profile stays out, wherever it is set.
  assert.equal(env.OPENAI_API_KEY, undefined);
  assert.equal(startEnv().OPENAI_API_KEY, "sk-not-for-runtimes");
  // Read again at each start: removed, it is gone from the next.
  raw = {};
  assert.equal(cleanEnv([]).AGENT_ENV_TEST_BOTH, "station's");
  assert.equal(cleanEnv([]).HTTPS_PROXY, process.env.HTTPS_PROXY);
});

/// A proxy that notes each CONNECT: tunnelled to `to` (a port on this machine) when given, else turned away.
async function proxy(t: { after(f: () => void): void }, to?: number) {
  const asked: { to: string; auth: string | undefined }[] = [];
  const server = http.createServer((_q, r) => r.end());
  server.on("connect", (q, socket: net.Socket, head: Buffer) => {
    asked.push({ to: q.url ?? "", auth: q.headers["proxy-authorization"] });
    if (to === undefined) return void socket.end("HTTP/1.1 502 Bad Gateway\r\n\r\n");
    const upstream = net.connect(to, "127.0.0.1", () => {
      socket.write("HTTP/1.1 200 Connection Established\r\n\r\n");
      upstream.write(head);
      upstream.pipe(socket).pipe(upstream);
    });
    upstream.on("error", () => socket.destroy());
    socket.on("error", () => upstream.destroy());
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  t.after(() => (server.close(), server.closeAllConnections()));
  return { port: (server.address() as net.AddressInfo).port, asked };
}

test("the station's requests on a profile's behalf go through the proxy named, with its credentials, never for this machine", async (t) => {
  t.after(() => readAgentEnvFrom(() => null));
  const p = await proxy(t);
  readAgentEnvFrom(() => ({ agentEnv: { HTTPS_PROXY: `http://user:pw@127.0.0.1:${p.port}` } }));
  await assert.rejects(profileFetch("https://api.example.test/v1/models", { headers: { authorization: "Bearer k" }, signal: AbortSignal.timeout(5000) }));
  assert.deepEqual(p.asked, [{ to: "api.example.test:443", auth: `Basic ${Buffer.from("user:pw").toString("base64")}` }]);
  // This machine directly: a server that answers nothing (no TLS) refuses it, the proxy never asked.
  const silent = net.createServer((c) => c.destroy());
  await new Promise<void>((resolve) => silent.listen(0, "127.0.0.1", resolve));
  t.after(() => silent.close());
  await assert.rejects(profileFetch(`https://127.0.0.1:${(silent.address() as net.AddressInfo).port}/x`, { signal: AbortSignal.timeout(5000) }));
  assert.equal(p.asked.length, 1);
  // No proxy named: as fetch does.
  readAgentEnvFrom(() => ({}));
  const plain = http.createServer((_q, r) => r.end("plain"));
  await new Promise<void>((resolve) => plain.listen(0, "127.0.0.1", resolve));
  t.after(() => plain.close());
  const answer = await profileFetch(`http://127.0.0.1:${(plain.address() as net.AddressInfo).port}/`);
  assert.equal(await answer.text(), "plain");
  assert.equal(p.asked.length, 1);
});

test("an answer through the proxy reads as fetch's: its status, headers and body", async (t) => {
  t.after(() => readAgentEnvFrom(() => null));
  // The service, on this machine under a name the proxy tunnels to, its certificate trusted for the test.
  const ca = makeCa(Date.now(), "test ca");
  const leaf = makeLeaf(ca, "test ca", "api.example.test", Date.now());
  const trusted = tls.getCACertificates("default");
  tls.setDefaultCACertificates([...trusted, pem(ca.cert)]);
  t.after(() => tls.setDefaultCACertificates(trusted));
  const service = https.createServer({ key: leaf.key.export({ format: "pem", type: "pkcs8" }), cert: pem(leaf.cert) }, (q, r) => {
    if (q.url === "/empty") return void (r.statusCode = 204, r.end());
    let body = "";
    q.on("data", (c) => (body += c));
    q.on("end", () => {
      r.statusCode = 201;
      r.setHeader("x-one", "1");
      r.end(JSON.stringify({ method: q.method, auth: q.headers.authorization, body }));
    });
  });
  await new Promise<void>((resolve) => service.listen(0, "127.0.0.1", resolve));
  t.after(() => (service.close(), service.closeAllConnections()));
  const p = await proxy(t, (service.address() as net.AddressInfo).port);
  readAgentEnvFrom(() => ({ agentEnv: { https_proxy: `http://127.0.0.1:${p.port}` } }));
  const answer = await profileFetch("https://api.example.test/token", { method: "POST", headers: { authorization: "Bearer k", "content-type": "application/json" }, body: "{\"a\":1}", signal: AbortSignal.timeout(5000) });
  assert.equal(answer.status, 201);
  assert.equal(answer.ok, true);
  assert.equal(answer.headers.get("x-one"), "1");
  assert.deepEqual(await answer.json(), { method: "POST", auth: "Bearer k", body: "{\"a\":1}" });
  const empty = await profileFetch("https://api.example.test/empty", { signal: AbortSignal.timeout(5000) });
  assert.equal(empty.status, 204);
  assert.equal(await empty.text(), "");
  // Through the proxy each time (a tunnel may be kept for the next).
  assert.ok(p.asked.length >= 1 && p.asked.every((a) => a.to === "api.example.test:443"));
});

test("PUT /agent-env: owners and admins change the variables, a secret's value masked, the sessions told once", async (t) => {
  const data = mkdtempSync(join(tmpdir(), "agent-env-"));
  t.after(() => rmSync(data, { recursive: true, force: true }));
  const config = new ConfigFile(data);
  config.check = checkConfig;
  let restarts = 0;
  let changes = 0;
  const [put] = routes({ config, changed: () => changes++, restart: () => restarts++ });
  const ask = async (viewer: Request["viewer"], body: unknown) => {
    const answer = await put!.handle({ method: "PUT", path: "/agent-env", query: [], headers: {}, body: Buffer.from(JSON.stringify(body)), viewer, lang: "en" }, []);
    return { status: answer.status, body: JSON.parse(answer.body.toString()) };
  };
  assert.equal((await ask(member, { env: { HTTPS_PROXY: "http://p:1" } })).status, 403);
  assert.deepEqual(config.raw().agentEnv, undefined);

  const set = await ask(owner, { env: { HTTPS_PROXY: "http://user:secret-password@proxy.corp:3128", API_TOKEN: "tok-1234567890", NO_PROXY: "corp.example" } });
  assert.equal(set.status, 200);
  assert.deepEqual(config.raw().agentEnv, { HTTPS_PROXY: "http://user:secret-password@proxy.corp:3128", API_TOKEN: "tok-1234567890", NO_PROXY: "corp.example" });
  assert.deepEqual(set.body.env, [
    { key: "API_TOKEN", value: "tok-1…7890", secret: true },
    { key: "HTTPS_PROXY", value: "http:…3128", secret: true },
    { key: "NO_PROXY", value: "corp.example", secret: false },
  ]);
  assert.deepEqual([restarts, changes], [1, 1]);

  // One left out stays (a masked value is not sent back); null removes one; the same again changes nothing to restart.
  await ask(owner, { env: { API_TOKEN: null } });
  assert.deepEqual(Object.keys(config.raw().agentEnv), ["HTTPS_PROXY", "NO_PROXY"]);
  await ask(owner, { env: { NO_PROXY: "corp.example" } });
  assert.deepEqual([restarts, changes], [2, 3]);
  // All removed: the key goes from config.json.
  await ask(owner, { env: { HTTPS_PROXY: null, NO_PROXY: null } });
  assert.equal("agentEnv" in config.raw(), false);
  assert.deepEqual(agentEnvView(config.raw()), []);

  // All of them as written: the masked secret left as shown is kept, those left out are gone.
  await ask(owner, { env: { API_TOKEN: "tok-1234567890", HTTPS_PROXY: "http://p:1" } });
  const restartsBefore = restarts;
  const written = await ask(owner, { text: "API_TOKEN=tok-1…7890\nNO_PROXY=x" });
  assert.equal(written.status, 200);
  assert.deepEqual(config.raw().agentEnv, { API_TOKEN: "tok-1234567890", NO_PROXY: "x" });
  assert.equal(restarts, restartsBefore + 1);
  const wrong = await ask(owner, { text: "NO_PROXY=y\nnot a pair" });
  assert.deepEqual(wrong, { status: 400, body: { error: "Line 2 isn't in the form NAME=value" } });
  assert.deepEqual(config.raw().agentEnv, { API_TOKEN: "tok-1234567890", NO_PROXY: "x" });
  await ask(owner, { text: "" });
  assert.equal((await ask(owner, { env: { "BAD NAME": "x" } })).status, 400);
  assert.equal((await ask(owner, { env: { A: 1 } })).status, 400);
  assert.equal((await ask(owner, { env: { A: "a\nb" } })).status, 400);
  assert.equal("agentEnv" in config.raw(), false);
});
