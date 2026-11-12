// feishu_api reads the same OpenAPI as the surface, but gives an agent local files for non-JSON answers.
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { basename, dirname, join } from "node:path";
import { test } from "node:test";
import { wall } from "../src/ops/fibers.ts";
import { FeishuSurface } from "../src/feishu/surface.ts";
import { FeishuThreads } from "../src/feishu/threads.ts";
import { feishuTools } from "../src/feishu/tool.ts";
import { FeishuClient } from "../src/feishu/web.ts";
import { FakeFeishu, RawAnswer } from "./feishu-fake.ts";
import { Rig } from "./hub-fakes.ts";

const resource = "/open-apis/im/v1/messages/om_other/resources/file_key";

async function setup() {
  const rig = new Rig();
  const fake = await FakeFeishu.start();
  const surface = new FeishuSurface({
    connect: "fs", appId: "cli_test", appSecret: "s", domain: "feishu",
    threads: new FeishuThreads(join(rig.dir, "threads.json")),
    client: new FeishuClient("cli_test", "s", "feishu", fake.base),
  });
  rig.edit((raw) => raw.connects.push({ id: "fs", kind: "feishu", feishu: { appId: "cli_test", appSecret: "s" }, bind: { runtime: "claude" } }));
  await rig.hub.shutdown();
  rig.hub = rig.newHub({ chats: (id) => (id === "fs" ? surface : undefined) });
  await rig.accept({ channel: "oc_g", threadTs: "om_a", ts: "om_a", user: "ou_ada", text: "@Bot 帮忙", addressed: true }, "fs");
  const key = "fs:oc_g:om_a";
  const tool = feishuTools(() => rig.hub, (id) => id === "fs")[0]!;
  return {
    fake,
    workspace: rig.session(key).workspace,
    call: (type = "file") => tool.run(key, { method: `GET ${resource}`, params: { type } }),
    close: async () => { await rig.close(); await surface.stop(); await fake.close(); },
  };
}

for (const { name, type, mime, bytes, extension } of [
  { name: "image", type: "image", mime: "image/jpeg", bytes: Buffer.from([0xff, 0xd8, 0xff, 0x00, 0x80, 0xfe]), extension: ".jpg" },
  { name: "PDF", type: "file", mime: "application/pdf", bytes: Buffer.from("%PDF-1.7\n\x00\xff", "latin1"), extension: ".pdf" },
  { name: "HTML", type: "file", mime: "text/html; charset=utf-8", bytes: Buffer.from("<!doctype html><p>你好</p>"), extension: ".html" },
]) {
  test(`feishu_api saves a ${name} response in the calling session's uploads`, async () => {
    const r = await setup();
    try {
      r.fake.answer(`GET ${resource}`, new RawAnswer(bytes, { "content-type": mime, "content-disposition": `attachment; filename="report${extension}"` }));
      const result = JSON.parse(await r.call(type));
      assert.equal(dirname(result.path), join(r.workspace, "uploads"));
      assert.ok(basename(result.path).endsWith(extension), result.path);
      assert.deepEqual({ content_type: result.content_type, size: result.size }, { content_type: mime, size: bytes.length });
      assert.deepEqual(await readFile(result.path), bytes);
      assert.deepEqual(r.fake.calls("GET", resource).map((c) => c.query), [{ type }]);
      const again = JSON.parse(await r.call(type));
      assert.notEqual(again.path, result.path, "a second download never replaces the first");
      assert.deepEqual(await readFile(again.path), bytes);
    } finally {
      await r.close();
    }
  });
}

test("feishu_api keeps Feishu JSON errors and non-JSON HTTP errors as errors", async () => {
  const r = await setup();
  try {
    r.fake.answer(`GET ${resource}`, { code: 230001, msg: "no permission" });
    await assert.rejects(r.call(), /230001 no permission/);
    r.fake.answer(`GET ${resource}`, new RawAnswer(Buffer.from("Forbidden"), { "content-type": "text/html" }, 403));
    await assert.rejects(r.call(), /403/);
    r.fake.answer(`GET ${resource}`, { code: 0, data: { value: 42 } });
    assert.deepEqual(JSON.parse(await r.call()), { code: 0, data: { value: 42 } });
  } finally {
    await r.close();
  }
});

test("feishu_api keeps a server-supplied filename inside uploads", async () => {
  const r = await setup();
  try {
    const bytes = Buffer.from("file");
    r.fake.answer(`GET ${resource}`, new RawAnswer(bytes, {
      "content-type": "application/octet-stream",
      "content-disposition": "attachment; filename*=UTF-8''..%2F%E6%8A%A5%E5%91%8A.pdf",
    }));
    const result = JSON.parse(await r.call());
    assert.equal(dirname(result.path), join(r.workspace, "uploads"));
    assert.ok(basename(result.path).endsWith(".._报告.pdf"), result.path);
    assert.deepEqual(await readFile(result.path), bytes);
  } finally {
    await r.close();
  }
});

test("feishu_api retries an expired token and a rate limit before saving the response", async (t) => {
  const r = await setup();
  const delays: number[] = [];
  t.mock.method(wall, "sleep", async (ms: number) => { delays.push(ms); });
  try {
    let tokens = 0;
    let calls = 0;
    r.fake.answer("POST /open-apis/auth/v3/tenant_access_token/internal", () => ({ code: 0, tenant_access_token: `token-${++tokens}`, expire: 7200 }));
    r.fake.answer(`GET ${resource}`, () => {
      calls++;
      if (calls === 1) return { code: 99991663, msg: "token expired" };
      if (calls === 2) return { code: 99991400, msg: "rate limited" };
      if (calls === 3) return new RawAnswer(Buffer.from("rate limited"), { "content-type": "text/plain", "retry-after": "2" }, 429);
      return new RawAnswer(Buffer.from("file"), { "content-type": "application/pdf" });
    });
    const result = JSON.parse(await r.call());
    assert.deepEqual(await readFile(result.path), Buffer.from("file"));
    assert.ok(result.path.endsWith(".pdf"), result.path);
    assert.deepEqual(r.fake.calls("GET", resource).map((c) => c.auth), ["token-1", "token-2", "token-2", "token-2"]);
    assert.deepEqual(delays, [1000, 2000]);
  } finally {
    await r.close();
  }
});
