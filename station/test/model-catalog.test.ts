// The model catalog (accounts/catalog.ts) as still.fail cloud says it, kept up to date by the models part
// (models/module.ts): what the prices and the image check read, kept across a restart, asked for again with its ETag.
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { facts, learn } from "../src/accounts/catalog.ts";
import { seesImages } from "../src/accounts/models.ts";
import { price, priceTable } from "../src/read/usage.ts";
import { ModelCatalog } from "../src/models/module.ts";

const MODELS = {
  "claude-haiku-5-5": { name: "Claude Haiku 5.5", input: ["text", "image"], cost: { input: 0.1, output: 0.5, cacheRead: 0.005 } },
  "glm-5.3": { input: ["text", "image"], context: 200_000 },
  "deepseek-v4-pro": { input: ["text"], cost: { input: 0.5, output: 2 } },
  "gpt-6-astra": { cost: { input: 12, output: 60, cacheRead: 1.2 } },
  broken: { input: "text", cost: { input: "free" } },
};

test("prices and the image check take the catalog's word, and the station's own tables where it says nothing", () => {
  try {
    assert.equal(price("claude-haiku-5-5"), null);
    assert.ok(!seesImages("glm-5.3"));
    assert.equal(learn(MODELS), 5);
    assert.deepEqual(price("anthropic/claude-haiku-5-5-20261001[1m]"), { input: 0.1, output: 0.5, cacheRead: 0.005 });
    // Newer than the station's table.
    assert.equal(price("gpt-6-astra")?.input, 12);
    // Not named: the table's. Named without a cache price: cached input at the input's.
    assert.equal(price("claude-opus-5-5")?.input, 4);
    assert.deepEqual(price("deepseek-v4-pro"), { input: 0.5, output: 2, cacheRead: 0.5 });
    assert.ok(seesImages("zai/glm-5.3"));
    assert.ok(!seesImages("deepseek-v4-pro"));
    // Checked by hand: sees images whatever the catalog says.
    assert.ok(seesImages("kimi-k3"));
    assert.deepEqual(facts("broken"), {});
    assert.equal(facts("glm-5.3")?.context, 200_000);
    // The usage page's table: the station's own and those its rows name.
    const rows = (priceTable("en", ["claude-haiku-5-5", null, "unknown-model"]) as any).rows;
    assert.ok(rows.some((r: any) => r.model === "claude-haiku-5-5" && r.input === 0.1 && r.cacheWrite === 0.125));
    assert.ok(rows.some((r: any) => r.model === "claude-opus-5-5"));
    assert.ok(!rows.some((r: any) => r.model === "unknown-model"));
  } finally {
    learn(null);
  }
});

test("the catalog is kept across a restart and asked for again with its ETag, a device's connecting at most once a minute", async () => {
  const file = join(mkdtempSync(join(tmpdir(), "model-catalog-")), "model-catalog.json");
  let now = 0;
  const asked: (string | null)[] = [];
  let answer = () => new Response(JSON.stringify({ models: MODELS }), { headers: { etag: '"one"' } });
  const get = async (url: string, init: RequestInit) => {
    assert.equal(url, "https://cloud.test/v1/models");
    asked.push((init.headers as Record<string, string>)["if-none-match"] ?? null);
    return answer();
  };
  try {
    const catalog = new ModelCatalog(file, () => "https://cloud.test", () => now, get);
    await catalog.refresh();
    assert.deepEqual(asked, [null]);
    assert.equal(price("claude-haiku-5-5")?.input, 0.1);
    assert.equal(JSON.parse(readFileSync(file, "utf8")).etag, '"one"');

    // Started again, offline: what it kept.
    learn(null);
    const again = new ModelCatalog(file, () => "https://cloud.test", () => now, get);
    assert.equal(price("claude-haiku-5-5")?.input, 0.1);
    answer = () => new Response(null, { status: 304 });
    await again.refresh();
    await again.refresh(true);
    now += 60_000;
    await again.refresh(true);
    assert.deepEqual(asked, [null, '"one"', '"one"']);
    assert.equal(price("claude-haiku-5-5")?.input, 0.1);

    // The cloud failing changes nothing; in no still.fail cloud, nothing is asked.
    answer = () => new Response("down", { status: 502 });
    await again.refresh();
    assert.equal(price("claude-haiku-5-5")?.input, 0.1);
    await new ModelCatalog(file, () => null, () => now, get).refresh();
    assert.equal(asked.length, 4);
  } finally {
    learn(null);
  }
});
