import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { createSocket } from "node:dgram";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { createServer } from "node:https";
import type { TLSSocket } from "node:tls";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { once } from "node:events";
import { test } from "node:test";

test("the native store uses CI's DNS without changing the host, TLS, ranges or redirect destinations", async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "native-store-test-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const key = join(dir, "key.pem"), cert = join(dir, "cert.pem");
  const certResult = spawnSync("openssl", ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert,
    "-days", "1", "-subj", "/CN=app.still.fail", "-addext", "subjectAltName=DNS:app.still.fail,IP:127.0.0.1"], { encoding: "utf8" });
  assert.equal(certResult.status, 0, certResult.stderr);
  const requests: { host: string | undefined; range: string | undefined; servername: string | false | null }[] = [];
  const https = createServer({ key: readFileSync(key), cert: readFileSync(cert) }, (req, res) => {
    requests.push({ host: req.headers.host, range: req.headers.range, servername: (req.socket as TLSSocket).servername });
    if (req.url === "/redirect") {
      res.writeHead(302, { location: `https://127.0.0.1:${(https.address() as { port: number }).port}/other` }).end();
    } else if (req.headers.range) {
      res.writeHead(206).end("a");
    } else {
      res.end("artifact");
    }
  });
  https.listen(0, "127.0.0.1");
  await once(https, "listening");
  t.after(() => https.close());
  const dns = createSocket("udp4");
  const queries: string[] = [];
  dns.on("message", (msg, peer) => {
    const labels: string[] = [];
    for (let at = 12; msg[at];) {
      const size = msg[at]!;
      labels.push(msg.subarray(at + 1, at + 1 + size).toString());
      at += size + 1;
    }
    queries.push(labels.join("."));
    const header = Buffer.from(msg.subarray(0, 12));
    header.writeUInt16BE(0x8180, 2); header.writeUInt16BE(1, 6); header.writeUInt16BE(0, 8); header.writeUInt16BE(0, 10);
    const answer = Buffer.from([0xc0, 0x0c, 0, 1, 0, 1, 0, 0, 0, 30, 0, 4, 127, 0, 0, 1]);
    dns.send(Buffer.concat([header, msg.subarray(12), answer]), peer.port, peer.address);
  });
  dns.bind(0, "127.0.0.1");
  await once(dns, "listening");
  t.after(() => dns.close());
  const httpsPort = (https.address() as { port: number }).port;
  const dnsPort = dns.address().port;
  const script = `
    import { fetchNative } from './scripts/native.ts';
    const url = 'https://app.still.fail:${httpsPort}';
    const one = await fetchNative(url + '/artifact');
    const range = await fetchNative(url + '/range', { headers: { Range: 'bytes=0-0' } });
    const redirected = await fetchNative(url + '/redirect');
    const results = [one.status, await one.text(), range.status, await range.text(), redirected.status, await redirected.text()];
    process.env.STILLFAIL_DIRECT_DNS = 'invalid';
    globalThis.fetch = async (at) => new Response('usual route: ' + at);
    const fallback = await fetchNative(url + '/fallback');
    results.push(await fallback.text());
    const github = await fetchNative('https://github.com/example');
    results.push(await github.text());
    console.log(JSON.stringify(results));
  `;
  const child = spawn(process.execPath, ["--input-type=module", "-e", script], { cwd: new URL("..", import.meta.url),
    env: { ...process.env, NODE_EXTRA_CA_CERTS: cert, STILLFAIL_DIRECT_DNS: `127.0.0.1:${dnsPort}` } });
  let stdout = "", stderr = "";
  child.stdout.on("data", (chunk) => { stdout += chunk; });
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  const [status] = await once(child, "exit");
  assert.equal(status, 0, stderr);
  assert.deepEqual(JSON.parse(stdout), [200, "artifact", 206, "a", 200, "artifact", `usual route: https://app.still.fail:${httpsPort}/fallback`, "usual route: https://github.com/example"]);
  assert.ok(queries.length > 0);
  assert.ok(queries.every((query) => query === "app.still.fail"));
  assert.deepEqual(requests.map(({ host, range, servername }) => ({ host, range, servername })), [
    { host: `app.still.fail:${httpsPort}`, range: undefined, servername: "app.still.fail" },
    { host: `app.still.fail:${httpsPort}`, range: "bytes=0-0", servername: "app.still.fail" },
    { host: `app.still.fail:${httpsPort}`, range: undefined, servername: "app.still.fail" },
    { host: `127.0.0.1:${httpsPort}`, range: undefined, servername: false },
  ]);
});
