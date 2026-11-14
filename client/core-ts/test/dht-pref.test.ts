// Whether this device looks stations up in the Mainline DHT (prefs `dht`, prefs.ts `dhtOn`): on unless turned off,
// said on the `prefs` topic as kept, `off` the one value taken.
import assert from "node:assert/strict";
import { test } from "node:test";
import { apply, call, subscribe, v } from "./helpers.ts";
import { started } from "./station-fixture.ts";

test("the_dht_is_on_until_turned_off_on_this_device_and_off_is_the_one_value_taken", async () => {
  const { host, core } = await started();
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "prefs" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  assert.equal(v(values, 1).dht, undefined, "none kept: on");
  call(core, ui, 2, "prefs.set", { dht: "off" });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 1).dht, "off");
  call(core, ui, 3, "prefs.set", { dht: "on" });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 1).dht, "off", "a value other than off refused, what was kept stays");
  call(core, ui, 4, "prefs.set", { dht: null });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 1).dht, undefined, "taken away: on again");
  core.close();
});
