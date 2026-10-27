import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { createSocket } from "node:dgram";
import { spawnSync } from "node:child_process";
import { test } from "node:test";
import { bindStation, loadMesh } from "../src/mesh/native.ts";

const options = () => ({ secretKey: randomBytes(32), alpns: [Buffer.from("bind-test")], relayUrls: [], discovery: false });

test("a station keeps its configured UDP address across restarts and exchanges streams", async () => {
  const mesh = loadMesh();
  // Closing an endpoint can leave its socket held until GC; a station restart exits the process.
  const reservation = createSocket("udp4");
  await new Promise<void>((resolve) => reservation.bind(0, "127.0.0.1", resolve));
  const address = `127.0.0.1:${reservation.address().port}`;
  await assert.rejects(bindStation(mesh, options(), { STILLFAIL_MESH_BIND_ADDR: address }));
  await new Promise<void>((resolve) => reservation.close(() => resolve()));
  for (const congestion of ["cubic", "bbr"]) {
    const result = spawnSync(process.execPath, ["--input-type=module", "--eval", `
    import assert from "node:assert/strict";
    import { randomBytes } from "node:crypto";
    import { bindStation, loadMesh } from ${JSON.stringify(new URL("../src/mesh/native.ts", import.meta.url).href)};
    const mesh = loadMesh();
    const options = ${options.toString()};
    const address = ${JSON.stringify(address)};
    const server = await bindStation(mesh, { ...options(), congestion: ${JSON.stringify(congestion)} });
    const client = await mesh.bind(options());
    try {
      assert.ok(server.sockets().includes(address));
      const accepting = server.accept();
      const outgoing = await client.connect({ id: server.id(), ips: [address] }, Buffer.from("bind-test"));
      const incoming = await accepting;
      assert.ok(incoming);
      const stream = await outgoing.openBi();
      await stream.write(Buffer.from("direct"));
      await stream.finish();
      const received = await incoming.acceptBi();
      assert.ok(received);
      assert.equal((await received.read())?.toString(), "direct");
      assert.equal(outgoing.via(), "direct");
      outgoing.close(0, "test complete");
      incoming.close(0, "test complete");
    } finally {
      await Promise.all([server.close(), client.close()]);
    }
    `], { env: { ...process.env, STILLFAIL_MESH_BIND_ADDR: address }, encoding: "utf8", timeout: 20_000 });
    assert.equal(result.status, 0, result.stderr || String(result.error));
  }
});

test("an invalid explicit address fails instead of choosing an arbitrary port", async () => {
  await assert.rejects(bindStation(loadMesh(), options(), { STILLFAIL_MESH_BIND_ADDR: "not-an-address" }));
  await assert.rejects(bindStation(loadMesh(), options(), { STILLFAIL_MESH_BIND_ADDR: "" }));
});
