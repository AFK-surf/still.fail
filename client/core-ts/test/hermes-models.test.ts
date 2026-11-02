import assert from "node:assert/strict";
import { test } from "node:test";
import { base, overview, started, stationReplies } from "./station-fixture.ts";
import { apply, call, subscribe, v } from "./helpers.ts";

test("Hermes models survive profile edits and reach the new-chat picker through the core", async () => {
  const profile = {
    id: "hm", name: "Hermes", runtime: "hermes", runtimes: ["hermes"], access: { kind: "env", key: "" },
    home: "/profiles/hm", homeExists: true, model: null, models: ["openai-api:local-model"], named: [] as string[], env: [], usedBy: [], loginCommand: "",
    check: { state: "ok", detail: "", checkedAt: 1, models: ["openai-api:local-model"] }, quota: null,
  };
  const raw = { ...overview, profiles: [profile] };
  const { host, core } = await started({ ...base(), "GET /overview": raw });
  try {
    const ui = core.connect(), values = new Map();
    subscribe(core, ui, 1, { topic: "overview", station: "ws/st" });
    subscribe(core, ui, 2, { topic: "newChat", scope: "ws" });
    await host.settle();
    assert.ok(host.emitted.some(([, m]) => m.id === 1 && "value" in m), JSON.stringify(host.emitted));
    apply(host, values);
    assert.equal(v(values, 1).profiles[0].canAddModel, true);
    assert.deepEqual(v(values, 1).profiles[0].available, ["openai-api:local-model"]);
    const writes: unknown[] = [];
    stationReplies(host, req => {
      if (req.method !== "PUT" || !req.url.endsWith("/profiles/hm")) return undefined;
      assert.ok(req.headers.some(([name, value]) => name === "stillfail-runtimes" && value.split(",").includes("hermes")));
      const input = JSON.parse(new TextDecoder().decode(req.body!)); writes.push(input);
      // (as the station has it: those named, then the rest its check found)
      profile.named = input.addModel ? [...profile.named, input.addModel] : input.models;
      profile.models = [...profile.named, ...profile.check.models.filter((m) => !profile.named.includes(m))];
      return structuredClone(raw);
    });
    call(core, ui, 4, "profile.addModel", { station: "ws/st", id: "hm", model: "custom:manual-model" });
    await host.settle(); apply(host, values);
    assert.deepEqual(writes, [{ addModel: "custom:manual-model" }]);
    assert.deepEqual(v(values, 1).profiles[0].models, ["custom:manual-model", "openai-api:local-model"]);
    assert.deepEqual(v(values, 1).profiles[0].added, ["custom:manual-model"], "named by hand, not listed: can be taken off");
    call(core, ui, 5, "newChat.pick", { scope: "ws", runtime: "hermes", model: "custom:manual-model" });
    await host.settle(); apply(host, values);
    assert.equal(v(values, 2).model.model, "custom:manual-model");
    assert.equal(v(values, 2).runtime, "hermes");
  } finally { core.close(); }
});
