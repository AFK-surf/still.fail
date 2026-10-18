// The station's modules as its members see them, and turned on or off by its owners and admins (api/routes/modules.ts):
// those still.fail makes listed whether on or not, one turned on written into config.json as its package, one turned
// off kept there off, a member who manages nothing refused.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { routes } from "../src/api/routes/modules.ts";
import type { Request } from "../src/api/request.ts";
import { ModuleSet } from "../src/modules/modules.ts";
import { ConfigFile } from "../src/ops/config.ts";

const owner = { sub: "o", email: "o@x", name: "O", role: "owner", workspace: "w", device: "d" };
const member = { ...owner, sub: "m", role: "member" };

function rig(t: { after: (f: () => void) => void }) {
  const data = mkdtempSync(join(tmpdir(), "modr-"));
  t.after(() => rmSync(data, { recursive: true, force: true }));
  const config = new ConfigFile(data);
  let changed = 0;
  const all = routes({ config, modules: new ModuleSet(data), changed: () => changed++ });
  const ask = async (who: typeof owner, method: string, path: string, body?: unknown) => {
    const route = all.find((r) => r.method === method && r.pattern.test(path))!;
    const r: Request = { method, path, query: [], headers: {}, body: Buffer.from(body === undefined ? "" : JSON.stringify(body)), viewer: who, lang: "en" };
    const a = await route.handle(r, route.pattern.exec(path)!.slice(1));
    return [a.status, JSON.parse(String(a.body))] as const;
  };
  return { config, ask, changed: () => changed };
}

test("still.fail's modules listed whether on or not; one turned on is its package in config.json, off kept off", async (t) => {
  const r = rig(t);
  const [, before] = await r.ask(member, "GET", "/modules");
  assert.deepEqual(before.modules, [{ id: "media", offered: true, enabled: false, installed: false, running: false, version: null }]);
  assert.equal((await r.ask(member, "PUT", "/modules/media", { enabled: true }))[0], 403);
  const [status, on] = await r.ask(owner, "PUT", "/modules/media", { enabled: true });
  assert.equal(status, 200);
  assert.equal(on.modules[0].enabled, true);
  assert.deepEqual(r.config.raw().modules, [{ id: "media", package: "media" }]);
  await r.ask(owner, "PUT", "/modules/media", { enabled: false });
  assert.deepEqual(r.config.raw().modules, [{ id: "media", package: "media", enabled: false }]);
  await r.ask(owner, "PUT", "/modules/media", { enabled: true });
  assert.deepEqual(r.config.raw().modules, [{ id: "media", package: "media" }]);
  assert.equal(r.changed(), 3);
  assert.equal((await r.ask(owner, "PUT", "/modules/nothing", { enabled: true }))[0], 404);
  assert.equal((await r.ask(owner, "PUT", "/modules/media", { enabled: "yes" }))[0], 400);
});
