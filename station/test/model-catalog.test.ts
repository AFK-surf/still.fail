// The model catalog (accounts/catalog.ts) as still.fail cloud says it, kept up to date by the models part
// (models/module.ts): what the prices and the image check read, kept across a restart, asked for again with its ETag.
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { facts, learn } from "../src/accounts/catalog.ts";
import { seesImages } from "../src/accounts/models.ts";
import { Readers } from "../src/read/pool.ts";
import { price, priceTable } from "../src/read/usage.ts";
import { ModelCatalog } from "../src/models/module.ts";
import { modelMakers } from "../src/api/overview.ts";
import { Store } from "../src/store/store.ts";

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

test("the overview says who made each model its profiles run, as the catalog says", () => {
  try {
    learn({
      "muse-spark-1.3": { name: "Muse Spark 1.3", maker: "meta", makerName: "Meta", family: "Muse" },
      "step-5-preview": { maker: "stepfun" },
      "claude-opus-5-5": { maker: "anthropic", makerName: "Anthropic", family: "Claude Opus" },
      odd: { maker: 3, family: "" },
    });
    const profiles = [{ models: ["muse-spark-1.3", "step-5-preview", "my-own-model"] }, { models: ["anthropic/claude-opus-5-5[1m]", "odd", "step-5-preview"] }, {}];
    assert.deepEqual(modelMakers(profiles), {
      "muse-spark-1.3": { maker: "meta", makerName: "Meta", family: "Muse" },
      "step-5-preview": { maker: "stepfun" },
      // However a profile spells it.
      "anthropic/claude-opus-5-5[1m]": { maker: "anthropic", makerName: "Anthropic", family: "Claude Opus" },
      // One the catalog does not name, or names no maker of: none (the clients go by its name).
    });
  } finally {
    learn(null);
  }
});

test("the catalog is kept across a restart and asked for again with its ETag, by the one the cloud says it changed to", async () => {
  const file = join(mkdtempSync(join(tmpdir(), "model-catalog-")), "model-catalog.json");
  const now = 0;
  const asked: (string | null)[] = [];
  let answer = () => new Response(JSON.stringify({ models: MODELS }), { headers: { etag: '"one"' } });
  const urls: string[] = [];
  const get = async (url: string, init: RequestInit) => {
    urls.push(url);
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
    // The cloud says it changed to the one held: nothing asked; to another, asked for by it.
    await again.refresh('"one"');
    await again.refresh('"two"');
    assert.deepEqual(asked, [null, '"one"', '"one"']);
    assert.deepEqual(urls.slice(1), ["https://cloud.test/v1/models", "https://cloud.test/v1/models?v=%22two%22"]);
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

test("models a catalog names that the one before did not are told, none the first time", async () => {
  const file = join(mkdtempSync(join(tmpdir(), "model-catalog-")), "model-catalog.json");
  let models: Record<string, unknown> = MODELS;
  let n = 0;
  const get = async () => new Response(JSON.stringify({ models }), { headers: { etag: `"${++n}"` } });
  const told: string[][] = [];
  try {
    const catalog = new ModelCatalog(file, () => "https://cloud.test", () => 0, get, (keys) => told.push(keys));
    await catalog.refresh();
    assert.deepEqual(told, []);
    models = { ...MODELS, "claude-fable-5-2": { maker: "anthropic" } };
    await catalog.refresh();
    await catalog.refresh();
    assert.deepEqual(told, [["claude-fable-5-2"]]);
  } finally {
    learn(null);
  }
});

test("tiered Antigravity model ids fall back to their base model in facts, price and priceTable", () => {
  try {
    // Without the catalog, the station's own table still prices tiered ids.
    assert.equal(price("claude-opus-5-5-medium")?.input, 4);
    assert.equal(price("anthropic/claude-opus-5-5-medium[1m]")?.input, 4);

    learn({
      "gemini-4-hydrogen": { name: "Gemini 4 Hydrogen", input: ["text", "image"], cost: { input: 1.5, output: 7.5, cacheRead: 0.075 } },
      "custom-model": { cost: { input: 1, output: 2 } },
      "custom-model-high": { cost: { input: 3, output: 6 } },
    });
    assert.equal(facts("gemini-4-hydrogen-high")?.name, "Gemini 4 Hydrogen");
    assert.deepEqual(price("google/gemini-4-hydrogen-high"), { input: 1.5, output: 7.5, cacheRead: 0.075 });
    // An exact catalog entry ending with a tier word wins over stripping.
    assert.deepEqual(price("custom-model-high"), { input: 3, output: 6, cacheRead: 3 });

    const rows = (priceTable("en", ["gemini-4-hydrogen-high", "claude-opus-5-5-medium"]) as any).rows;
    assert.ok(rows.some((r: any) => r.model === "gemini-4-hydrogen-high" && r.input === 1.5 && r.cacheRead === 0.075 && r.output === 7.5));
    assert.ok(rows.some((r: any) => r.model === "claude-opus-5-5-medium" && r.input === 4 && r.cacheWrite === 5));
  } finally {
    learn(null);
  }
});

test("reader workers see the main thread's model catalog and its updates when computing usage", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-catalog-worker-"));
  const store = Store.open(join(dir, "stillfail.db"));
  let readers: Readers | null = null;
  try {
    store.insertSession({ key: "s1", connect: "ember", runtime: "agy", profile: "agy", workspace: "/w", token: "s1", ws: "W", createdAt: 0, lastActiveAt: 0 });
    const owner = { turn: null, thread: null, person: "p", profile: "agy" };
    const call = (id: string, model: string) => ({
      id, at: 60_000, model, subagent: false, fast: false,
      input: 1_000_000, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 0, calls: 1, context: null, window: null,
    });
    store.recordUsage("/s1", { session: "s1", offset: 1, model: "gemini-4-hydrogen" }, "agy", [
      [call("c1", "gemini-4-hydrogen"), owner],
      [call("c2", "gemini-4-hydrogen-high"), owner],
      [call("c3", "claude-opus-5-5-medium"), owner],
    ]);
    store.db.exec("PRAGMA wal_checkpoint(TRUNCATE)");

    readers = new Readers(dir, 1);
    const readUsage = async () => JSON.parse(await readers!.read("usage", { from: "0", to: "120000", tz: "0", lang: "en", reading: false }, "en"));

    const before = await readUsage();
    assert.equal(before.rows.find((r: any) => r.model === "gemini-4-hydrogen").cost, null);
    assert.equal(before.rows.find((r: any) => r.model === "gemini-4-hydrogen-high").cost, null);
    assert.equal(before.rows.find((r: any) => r.model === "claude-opus-5-5-medium").cost, 4);

    // Populate the catalog on the main thread while the worker is already alive.
    learn({ "gemini-4-hydrogen": { cost: { input: 1.5, output: 7.5, cacheRead: 0.075 } } });
    const after = await readUsage();
    assert.equal(after.rows.find((r: any) => r.model === "gemini-4-hydrogen").cost, 1.5);
    assert.equal(after.rows.find((r: any) => r.model === "gemini-4-hydrogen-high").cost, 1.5);
    assert.ok(after.prices.rows.some((r: any) => r.model === "gemini-4-hydrogen-high" && r.input === 1.5 && r.output === 7.5));

    // Subsequent catalog updates also propagate to the kept worker.
    learn({ "gemini-4-hydrogen": { cost: { input: 2.5, output: 10, cacheRead: 0.1 } } });
    const updated = await readUsage();
    assert.equal(updated.rows.find((r: any) => r.model === "gemini-4-hydrogen").cost, 2.5);
    assert.equal(updated.rows.find((r: any) => r.model === "gemini-4-hydrogen-high").cost, 2.5);
  } finally {
    learn(null);
    readers?.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
