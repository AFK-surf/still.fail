import assert from "node:assert/strict";
import test from "node:test";
import { harness } from "./harness.ts";
import { catalog } from "../src/models.ts";

// GET /v1/models: models.dev's catalog as stations read it (src/models.ts).

/// models.dev as it answers, cut to two makers: a model's canonical entry (models.json) and the providers' (api.json),
/// one of them reselling the other's model at a price of its own.
const CANONICAL = {
  "anthropic/claude-opus-5-5": { name: "Claude Opus 5.5", reasoning: true, modalities: { input: ["text", "image", "pdf"], output: ["text"] }, limit: { context: 1_000_000, output: 128_000 } },
  "deepseek/deepseek-v4-pro": { name: "DeepSeek V4 Pro", reasoning: true, modalities: { input: ["text"], output: ["text"] }, limit: { context: 1_000_000, output: 384_000 } },
  "nowhere/odd": { name: "Odd", modalities: { input: "text" }, limit: { context: -1 } },
};
const PROVIDERS = {
  anthropic: { models: { "claude-opus-5-5": { reasoning_options: [{ type: "effort", values: ["low", "medium", "high", "xhigh", "max"] }], cost: { input: 4, output: 20, cache_read: 0.2, cache_write: 5 } } } },
  openrouter: { models: { "deepseek/deepseek-v4-pro": { cost: { input: 9, output: 9 } } } },
};

test("each model is keyed without its maker, with its maker's own prices and effort levels", () => {
  assert.deepEqual(catalog(CANONICAL, PROVIDERS), {
    "claude-opus-5-5": {
      name: "Claude Opus 5.5", input: ["text", "image", "pdf"], reasoning: true, context: 1_000_000, output: 128_000,
      efforts: ["low", "medium", "high", "xhigh", "max"], cost: { input: 4, output: 20, cacheRead: 0.2, cacheWrite: 5 },
    },
    // A reseller's price is what it charges, not the model's: none.
    "deepseek-v4-pro": { name: "DeepSeek V4 Pro", input: ["text"], reasoning: true, context: 1_000_000, output: 384_000 },
    // What is of no shape known is left out.
    odd: { name: "Odd" },
  });
  assert.deepEqual(catalog(null, null), {});
});

test("a model its maker sells under another name, or by its dated version, has that entry's prices", () => {
  const canonical = {
    "deepseek/deepseek-v4.1-flash-1017": { name: "DeepSeek V4.1 Flash 1017" },
    "deepseek/deepseek-v4.1-flash": { name: "DeepSeek V4.1 Flash" },
    "deepseek/deepseek-v4.1-flash-0910": { name: "DeepSeek V4.1 Flash 0910" },
    "cohere/command-a": { name: "Command A" },
    "meta/llama-5": { name: "Llama 5" },
  };
  const flash = { input: 0.15, output: 0.6, cache_read: 0.003 };
  const providers = {
    deepseek: { models: {
      "deepseek-flash": { canonical_model_id: "deepseek/deepseek-v4.1-flash-1017", cost: flash },
      "deepseek-v4-flash": { canonical_model_id: "deepseek/deepseek-v4.1-flash-1017", cost: flash },
    } },
    // Versions not dated, of other prices: not this model's.
    cohere: { models: { "command-a-plus-05-2026": { canonical_model_id: "cohere/command-a-plus-05-2026", cost: { input: 9, output: 9 } } } },
    openrouter: { models: { "meta/llama-5": { canonical_model_id: "meta/llama-5", cost: { input: 1, output: 1 } } } },
  };
  const priced = Object.fromEntries(Object.entries(catalog(canonical, providers)).map(([k, f]) => [k, f.cost ?? null]));
  const cost = { input: 0.15, output: 0.6, cacheRead: 0.003 };
  assert.deepEqual(priced, {
    "deepseek-v4.1-flash-1017": cost,
    "deepseek-v4.1-flash": cost,
    // Its maker sells it no longer.
    "deepseek-v4.1-flash-0910": null,
    "command-a": null,
    // Only resold: no list price of its maker's.
    "llama-5": null,
  });
  // Dated versions of different prices: none of them.
  const two = { deepseek: { models: { a: { canonical_model_id: "deepseek/deepseek-v4.1-flash-1017", cost: flash }, b: { canonical_model_id: "deepseek/deepseek-v4.1-flash-1120", cost: { input: 1, output: 1 } } } } };
  assert.equal(catalog({ "deepseek/deepseek-v4.1-flash": {} }, two)["deepseek-v4.1-flash"]!.cost, undefined);
});

test("the catalog is made once, and a station that has it is told so", async () => {
  const asked: string[] = [];
  const h = await harness({
    push: (request) => {
      asked.push(request.url);
      if (request.url === "https://models.dev/models.json") return { status: 200, body: JSON.stringify(CANONICAL) };
      if (request.url === "https://models.dev/api.json") return { status: 200, body: JSON.stringify(PROVIDERS) };
      return { status: 404 };
    },
  });
  try {
    const first = await h.fetch("/v1/models");
    assert.equal(first.status, 200);
    const etag = first.headers.get("etag");
    assert.ok(etag);
    const body = (await first.json()) as { models: Record<string, any> };
    assert.equal(body.models["claude-opus-5-5"].cost.input, 4);

    const again = await h.fetch("/v1/models", { headers: { "if-none-match": etag! } });
    assert.equal(again.status, 304);
    await again.arrayBuffer();
    const other = await h.fetch("/v1/models", { headers: { "if-none-match": '"else"' } });
    assert.deepEqual(await other.json(), body);
    // Made once: each source read once for the three asks.
    assert.deepEqual(asked.sort(), ["https://models.dev/api.json", "https://models.dev/models.json"]);
  } finally {
    await h.close();
  }
});
