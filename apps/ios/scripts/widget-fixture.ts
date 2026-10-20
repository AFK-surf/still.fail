// Isolated simulator fixture: real native iroh peer + synthetic HTTP account API.
// Never imported or shipped by the app. Only binds loopback and serves fake data.
import { createServer } from "node:http";
import { randomBytes } from "node:crypto";
import { writeFileSync } from "node:fs";
import { loadAddon } from "../../../client/core-ts/src/hosts/node-iroh.ts";
import { ed25519 } from "../../../client/core-ts/node_modules/@noble/curves/ed25519.js";

const addon = loadAddon() as any;
if (!addon) throw new Error("STILLFAIL_MESH_NATIVE must point to the native test addon");
const utf8 = (s: string) => Buffer.from(s, "utf8");
const endpoint = await addon.bind({ secretKey: randomBytes(32), alpns: [utf8("stillfail/admin/1")], relayUrls: [], lookup: false, discovery: false });
const socket = (endpoint.sockets() as string[]).find((s) => !s.startsWith("["))!;
const ips = [`127.0.0.1:${socket.slice(socket.lastIndexOf(":") + 1)}`];
const device = Array.from(randomBytes(32));
let count = 2, reads = 0, refreshes = 0;
const server = createServer(async (req, res) => {
  const parts: Buffer[] = []; for await (const part of req) parts.push(part);
  const body = parts.length ? JSON.parse(Buffer.concat(parts).toString()) : {};
  let reply: unknown;
  if (req.url === "/test/update") { count = body.count; reply = { count }; }
  else if (req.url === "/test/state") reply = { count, reads, refreshes };
  else if (req.url === "/v1/auth/refresh" && req.headers.authorization === "Bearer fixture-refresh") {
    refreshes++;
    reply = { subject: "fixture", email: "fixture@example.invalid", name: "Fixture", access_token: "fixture-access-new", refresh_token: "fixture-refresh-new", expires_at: 4102444800 };
  } else if (req.headers.authorization !== "Bearer fixture-access-new") { res.statusCode = 401; reply = { error: "unauthorized" }; }
  else if (req.url === "/v1/me") reply = { user: { id: "fixture" }, relay_urls: [] };
  else if (req.url === "/v1/workspaces/fixture-w") reply = { id: "fixture-w", name: "Widget fixture", stations: [{ id: endpoint.id(), name: "Synthetic node" }] };
  else if (req.url === "/v1/workspaces/fixture-w/credential") {
    const proof = Buffer.from(body.proof, "hex"), base = Buffer.from(body.base, "hex");
    if (!ed25519.verify(proof, utf8(`stillfail-lock-endpoint/1\0fixture-w\0${body.device}`), base)) { res.statusCode = 403; reply = { error: "invalid_proof" }; }
    else reply = { credential: "widget-test-grant" };
  } else { res.statusCode = 404; reply = { error: "not_found" }; }
  res.setHeader("content-type", "application/json"); res.end(JSON.stringify(reply));
});
await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
const origin = `http://127.0.0.1:${(server.address() as any).port}`;
const config = { origin, ips, device, accounts: [{ sub: "fixture", email: "fixture@example.invalid", name: "Fixture", picture: "", access: "fixture-access-old", refresh: "fixture-refresh", access_expires: 1 }] };
writeFileSync(process.argv[2] ?? "/tmp/stillfail-widget-fixture.json", JSON.stringify(config));
console.log(JSON.stringify({ origin, station: endpoint.id(), ips }));
async function line(stream: any) {
  let all = ""; while (!all.includes("\n")) { const part = await stream.read(); if (!part) throw new Error("stream ended"); all += part.toString(); }
  return JSON.parse(all.slice(0, all.indexOf("\n")));
}
async function serve(conn: any) {
  const control = await conn.acceptBi();
  const hello = await line(control);
  if (hello.credential !== "widget-test-grant") throw new Error("wrong fixture credential");
  await control.write(utf8('{"ok":true}\n'));
  for (;;) {
    const stream = await conn.acceptBi(); if (!stream) return;
    const head = await line(stream);
    reads++;
    const now = Date.now();
    const rows = head.path === "/chats" ? Array.from({ length: count }, (_, i) => ({ id: `task-${i}`, session: `task-${i}`, title: `Independent task ${i + 1}`, createdAt: now, lastActiveAt: now, agents: [], last: { text: `updated to ${count}` } })) : [];
    await stream.write(utf8(JSON.stringify({ status: 200, headers: {} }) + "\n" + JSON.stringify(rows)));
    await stream.finish();
  }
}
for (;;) {
  const conn = await endpoint.accept(); if (!conn) break;
  void serve(conn).catch((error) => console.error("fixture connection:", String(error)));
}
